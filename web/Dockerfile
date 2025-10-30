FROM node:20-alpine AS builder
WORKDIR /app

ARG VITE_API_BASE_URL=http://localhost:3000
ENV VITE_API_BASE_URL=${VITE_API_BASE_URL}

COPY package.json ./
RUN npm install
COPY . .
RUN npm run build

FROM node:20-alpine
WORKDIR /app

ARG VITE_API_BASE_URL=http://localhost:3000
ENV NODE_ENV=production
ENV VITE_API_BASE_URL=${VITE_API_BASE_URL}

COPY package.json ./
RUN npm install
COPY --from=builder /app/dist ./dist
EXPOSE 4173
CMD ["npm", "run", "preview"]
