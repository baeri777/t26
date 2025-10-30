import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import { createServer } from 'http';
import { Server as SocketIOServer } from 'socket.io';
import pg from 'pg';
import Redis from 'redis';
import nodemailer from 'nodemailer';
import bcrypt from 'bcryptjs';

const app = express();
const server = createServer(app);
const io = new SocketIOServer(server, {
  cors: { origin: '*' }
});

const PORT = process.env.PORT ?? 3000;

const pool = new pg.Pool({
  host: process.env.PGHOST,
  user: process.env.PGUSER,
  password: process.env.PGPASSWORD,
  database: process.env.PGDATABASE,
  port: Number(process.env.PGPORT ?? 5432)
});

const redisClient = Redis.createClient({ url: process.env.REDIS_URL });
redisClient.on('error', (error) => console.error('Redis error', error));
await redisClient.connect();

const transporter = nodemailer.createTransport({
  service: process.env.AUTH_EMAIL_SERVICE,
  auth: {
    type: 'OAuth2',
    user: process.env.AUTH_EMAIL_FROM,
    clientId: process.env.AUTH_GOOGLE_CLIENT_ID,
    clientSecret: process.env.AUTH_GOOGLE_CLIENT_SECRET,
    refreshToken: process.env.AUTH_GOOGLE_REFRESH_TOKEN ?? 'define-me',
    accessToken: process.env.AUTH_GOOGLE_ACCESS_TOKEN ?? undefined
  }
});

app.use(cors());
app.use(express.json());

function parseBasicAuth(header) {
  if (!header || typeof header !== 'string') {
    return null;
  }
  const prefix = 'Basic ';
  if (!header.startsWith(prefix)) {
    return null;
  }
  const encoded = header.slice(prefix.length).trim();
  if (!encoded) {
    return null;
  }
  let decoded;
  try {
    decoded = Buffer.from(encoded, 'base64').toString('utf8');
  } catch {
    return null;
  }
  const separatorIndex = decoded.indexOf(':');
  if (separatorIndex === -1) {
    return null;
  }
  const email = decoded.slice(0, separatorIndex);
  const password = decoded.slice(separatorIndex + 1);
  if (!email || !password) {
    return null;
  }
  return { email, password };
}

async function requireConfigAuth(req, res, next) {
  const credentials = parseBasicAuth(req.headers.authorization);
  if (!credentials) {
    return res.status(401).json({ message: 'Authentication required' });
  }

  try {
    const { rows } = await pool.query(
      `SELECT id, email, password_hash
         FROM core.users
        WHERE email = $1
          AND is_active = TRUE
        LIMIT 1`,
      [credentials.email]
    );

    const user = rows[0];
    if (!user || !user.password_hash) {
      return res.status(401).json({ message: 'Invalid credentials' });
    }

    const isValid = await bcrypt.compare(credentials.password, user.password_hash);
    if (!isValid) {
      return res.status(401).json({ message: 'Invalid credentials' });
    }

    req.configUser = { id: user.id, email: user.email };
    return next();
  } catch (error) {
    console.error('Error during config authentication', error);
    return res.status(500).json({ message: 'Authentication failed' });
  }
}

app.get('/healthz', async (_req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ok' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ status: 'error', error: error.message });
  }
});

app.post('/auth/email', async (req, res) => {
  const { email } = req.body;
  if (!email) {
    return res.status(400).json({ message: 'email is required' });
  }

  const token = Math.random().toString(36).slice(2, 8).toUpperCase();
  await redisClient.set(`login:${email}`, token, { EX: 10 * 60 });

  try {
    await transporter.sendMail({
      to: email,
      from: process.env.AUTH_EMAIL_FROM,
      subject: 'Your sign-in token',
      text: `Your temporary login token is ${token}`
    });
  } catch (error) {
    console.error('Error sending email', error);
    return res.status(500).json({ message: 'Could not send email' });
  }

  res.json({ message: 'Token sent' });
});

app.post('/auth/verify', async (req, res) => {
  const { email, token } = req.body;
  if (!email || !token) {
    return res.status(400).json({ message: 'email and token are required' });
  }

  const stored = await redisClient.get(`login:${email}`);
  if (!stored || stored !== token) {
    return res.status(401).json({ message: 'Invalid token' });
  }

  await redisClient.del(`login:${email}`);

  try {
    const result = await pool.query(
      `INSERT INTO core.users (email) VALUES ($1)
       ON CONFLICT (email) DO UPDATE SET last_login = NOW()
       RETURNING id, email, display_name`,
      [email]
    );
    const user = result.rows[0];
    res.json({ user, token: 'placeholder-jwt' });
  } catch (error) {
    console.error('Database error', error);
    res.status(500).json({ message: 'Could not create user' });
  }
});

app.get('/config', requireConfigAuth, async (_req, res) => {
  try {
    const { rows } = await pool.query(
      `SELECT config_key AS key,
              config_value AS value,
              description,
              updated_at
         FROM core.config_entries
        ORDER BY config_key`
    );
    res.json(rows);
  } catch (error) {
    console.error('Error loading config entries', error);
    res.status(500).json({ message: 'Could not load configuration entries' });
  }
});

app.post('/config', requireConfigAuth, async (req, res) => {
  const { key, value, description } = req.body ?? {};
  if (!key) {
    return res.status(400).json({ message: 'key is required' });
  }
  if (value === undefined || value === null) {
    return res.status(400).json({ message: 'value is required' });
  }

  try {
    const { rows } = await pool.query(
      `INSERT INTO core.config_entries (config_key, config_value, description)
       VALUES ($1, $2, $3)
       ON CONFLICT (config_key)
       DO UPDATE SET config_value = EXCLUDED.config_value,
                     description = COALESCE(EXCLUDED.description, core.config_entries.description),
                     updated_at = NOW()
       RETURNING config_key AS key,
                 config_value AS value,
                 description,
                 updated_at`,
      [key, value, description ?? null]
    );
    const entry = rows[0];
    io.emit('config:updated', entry);
    res.json(entry);
  } catch (error) {
    console.error('Error persisting config entry', error);
    res.status(500).json({ message: 'Could not save configuration entry' });
  }
});

io.on('connection', (socket) => {
  console.log('Client connected', socket.id);
  socket.on('disconnect', () => console.log('Client disconnected', socket.id));
});

setInterval(() => {
  io.emit('notification', { message: `Server time ${new Date().toISOString()}` });
}, 15000);

server.listen(PORT, () => {
  console.log(`API listening on port ${PORT}`);
});
