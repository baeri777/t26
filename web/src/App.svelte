<script>
  import { onMount } from 'svelte';

  const apiBase = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:3000';

  let email = '';
  let token = '';
  let user = null;
  let socketStatus = 'disconnected';
  let notifications = [];
  let activeTab = 'auth';

  let configEntries = [];
  let hasLoadedConfig = false;
  let configLoading = false;
  let configMessage = '';
  let configError = '';
  let configForm = { key: '', value: '', description: '' };
  let configCredentials = { email: 'admin@example.com', password: '' };
  let configAuthHeader = '';
  let configAuthenticated = false;
  let configAuthError = '';

  onMount(async () => {
    const { io } = await import('socket.io-client');
    const socket = io(apiBase);
    socket.on('connect', () => (socketStatus = 'connected'));
    socket.on('disconnect', () => (socketStatus = 'disconnected'));
    socket.on('notification', (payload) => {
      notifications = [payload, ...notifications].slice(0, 20);
    });
    socket.on('config:updated', (entry) => {
      upsertConfigEntry({
        ...entry,
        description: entry.description ?? '',
        valueDraft: entry.value,
        descriptionDraft: entry.description ?? ''
      });
    });
  });

  async function requestToken() {
    await fetch(`${apiBase}/auth/email`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email })
    });
  }

  async function verifyToken() {
    const response = await fetch(`${apiBase}/auth/verify`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, token })
    });
    if (response.ok) {
      user = await response.json();
    }
  }

  function setActiveTab(tab) {
    activeTab = tab;
    if (tab === 'config' && configAuthenticated && !hasLoadedConfig) {
      loadConfig();
    }
  }

  async function loadConfig() {
    if (!configAuthHeader) {
      configAuthError = 'Bitte zuerst mit den Konfigurations-Zugangsdaten anmelden.';
      configError = '';
      return;
    }
    configLoading = true;
    configError = '';
    configMessage = '';
    try {
      const response = await fetch(`${apiBase}/config`, {
        headers: {
          Authorization: configAuthHeader
        }
      });
      if (response.status === 401) {
        throw new Error('Ungültige Zugangsdaten für den Konfigurationsbereich.');
      }
      if (!response.ok) {
        throw new Error('Server returned an error while loading config entries');
      }
      const rows = await response.json();
      configEntries = rows.map((row) => ({
        ...row,
        description: row.description ?? '',
        valueDraft: row.value,
        descriptionDraft: row.description ?? ''
      }));
      hasLoadedConfig = true;
    } catch (error) {
      console.error(error);
      configError = error.message ?? 'Unknown error loading configuration';
      if (error.message?.toLowerCase().includes('ungültige')) {
        configAuthError = error.message;
        configAuthenticated = false;
        configAuthHeader = '';
        hasLoadedConfig = false;
        configEntries = [];
        configCredentials = { ...configCredentials, password: '' };
      }
    } finally {
      configLoading = false;
    }
  }

  function upsertConfigEntry(entry) {
    const index = configEntries.findIndex((item) => item.key === entry.key);
    if (index === -1) {
      configEntries = [entry, ...configEntries];
    } else {
      const updated = [...configEntries];
      updated[index] = {
        ...updated[index],
        ...entry,
        valueDraft: entry.value,
        descriptionDraft: entry.description ?? ''
      };
      configEntries = updated;
    }
  }

  async function saveConfigEntry(key, value, description) {
    configError = '';
    configMessage = '';
    if (!configAuthHeader) {
      configAuthError = 'Bitte zuerst mit den Konfigurations-Zugangsdaten anmelden.';
      configError = '';
      return;
    }
    try {
      const response = await fetch(`${apiBase}/config`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: configAuthHeader
        },
        body: JSON.stringify({ key, value, description })
      });
      if (!response.ok) {
        const payload = await response.json().catch(() => ({}));
        throw new Error(payload.message ?? 'Could not save configuration entry');
      }
      const entry = await response.json();
      configMessage = `Saved configuration for ${entry.key}`;
      upsertConfigEntry({
        ...entry,
        description: entry.description ?? '',
        valueDraft: entry.value,
        descriptionDraft: entry.description ?? ''
      });
    } catch (error) {
      console.error(error);
      configError = error.message ?? 'Unknown error saving configuration';
    }
  }

  async function submitConfigForm(event) {
    event.preventDefault();
    if (!configForm.key || !configForm.value) {
      configError = 'Key and value are required.';
      return;
    }
    await saveConfigEntry(configForm.key, configForm.value, configForm.description);
    if (!configError) {
      configForm = { key: '', value: '', description: '' };
    }
  }

  async function saveExistingEntry(entry) {
    await saveConfigEntry(entry.key, entry.valueDraft, entry.descriptionDraft);
  }

  function signOutConfig() {
    configAuthHeader = '';
    configAuthenticated = false;
    configAuthError = '';
    configMessage = '';
    configEntries = [];
    hasLoadedConfig = false;
    configCredentials = { ...configCredentials, password: '' };
  }

  async function submitConfigAuth(event) {
    event.preventDefault();
    configAuthError = '';
    configError = '';
    configMessage = '';
    if (!configCredentials.email || !configCredentials.password) {
      configAuthError = 'E-Mail und Passwort sind erforderlich.';
      return;
    }
    try {
      configAuthHeader = `Basic ${btoa(`${configCredentials.email}:${configCredentials.password}`)}`;
      configAuthenticated = true;
      hasLoadedConfig = false;
      await loadConfig();
      if (!configError) {
        configAuthError = '';
      }
    } catch (error) {
      console.error(error);
      configAuthError = 'Die Zugangsdaten konnten nicht verarbeitet werden.';
      configAuthHeader = '';
      configAuthenticated = false;
    }
  }
</script>

<main>
  <h1>TRP Modular App Shell</h1>
  <p>Socket status: {socketStatus}</p>

  <nav class="tabs">
    <button class:active={activeTab === 'auth'} on:click={() => setActiveTab('auth')}>Auth</button>
    <button class:active={activeTab === 'config'} on:click={() => setActiveTab('config')}>Config</button>
  </nav>

  {#if activeTab === 'auth'}
    {#if user}
      <section>
        <h2>Welcome {user.user.email}</h2>
        <pre>{JSON.stringify(user, null, 2)}</pre>
      </section>
    {:else}
      <section>
        <h2>Email sign-in</h2>
        <form on:submit|preventDefault={requestToken}>
          <label>
            Email
            <input type="email" bind:value={email} required />
          </label>
          <button type="submit">Send token</button>
        </form>
        <form on:submit|preventDefault={verifyToken}>
          <label>
            Token
            <input bind:value={token} required />
          </label>
          <button type="submit">Verify</button>
        </form>
      </section>
    {/if}
  {:else if activeTab === 'config'}
    <section>
      <h2>Configuration</h2>
      <p>Manage dynamic settings such as Google mailbox credentials via key/value pairs.</p>
      {#if !configAuthenticated}
        <form class="config-form" on:submit={submitConfigAuth}>
          <div>
            <label>
              Admin email
              <input bind:value={configCredentials.email} type="email" placeholder="admin@example.com" required />
            </label>
          </div>
          <div>
            <label>
              Password
              <input bind:value={configCredentials.password} type="password" placeholder="ChangeMeNow!" required />
            </label>
          </div>
          <button type="submit">Authenticate</button>
          {#if configAuthError}
            <p class="error">{configAuthError}</p>
          {/if}
        </form>
      {:else}
        <div class="config-auth-status">
          <p>
            Signed in as <strong>{configCredentials.email}</strong>.
            <button type="button" class="link-button" on:click={signOutConfig}>Sign out</button>
          </p>
        </div>

        <form class="config-form" on:submit={submitConfigForm}>
          <div>
            <label>
              Key
              <input bind:value={configForm.key} placeholder="AUTH_EMAIL_FROM" required />
            </label>
          </div>
          <div>
            <label>
              Value
              <input bind:value={configForm.value} placeholder="noreply@example.com" required />
            </label>
          </div>
          <div>
            <label>
              Description
              <input bind:value={configForm.description} placeholder="Optional context" />
            </label>
          </div>
          <button type="submit">Save entry</button>
        </form>

        {#if configLoading}
          <p>Loading configuration…</p>
        {/if}
        {#if configError}
          <p class="error">{configError}</p>
        {/if}
        {#if configMessage}
          <p class="success">{configMessage}</p>
        {/if}

        {#if configEntries.length > 0}
          <table class="config-table">
            <thead>
              <tr>
                <th>Key</th>
                <th>Value</th>
                <th>Description</th>
                <th>Last updated</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {#each configEntries as entry (entry.key)}
                <tr>
                  <td class="config-key">{entry.key}</td>
                  <td>
                    <input bind:value={entry.valueDraft} class="table-input" />
                  </td>
                  <td>
                    <input bind:value={entry.descriptionDraft} class="table-input" />
                  </td>
                  <td>{entry.updated_at ? new Date(entry.updated_at).toLocaleString() : '—'}</td>
                  <td>
                    <button type="button" on:click={() => saveExistingEntry(entry)}>Save</button>
                  </td>
                </tr>
              {/each}
            </tbody>
          </table>
        {:else if hasLoadedConfig && !configLoading}
          <p>No configuration entries yet.</p>
        {/if}
      {/if}
    </section>
  {/if}

  <section>
    <h2>Notifications</h2>
    {#if notifications.length === 0}
      <p>No notifications yet.</p>
    {:else}
      <ul>
        {#each notifications as notification}
          <li>{notification.message}</li>
        {/each}
      </ul>
    {/if}
  </section>
</main>

<style>
  main {
    max-width: 50rem;
    margin: 0 auto;
    padding: 2rem;
    font-family: system-ui, sans-serif;
  }

  .tabs {
    display: flex;
    gap: 0.5rem;
    margin-bottom: 1.5rem;
  }

  .tabs button {
    padding: 0.5rem 1rem;
    border: 1px solid #cbd5f5;
    background: white;
    border-radius: 999px;
    cursor: pointer;
  }

  .tabs button.active {
    background: #4f46e5;
    color: white;
    border-color: #4f46e5;
  }

  form {
    margin-bottom: 1rem;
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }

  .config-form {
    border: 1px solid #e5e7eb;
    padding: 1rem;
    border-radius: 0.5rem;
    margin-bottom: 1.5rem;
  }

  .config-auth-status {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 1rem;
  }

  .link-button {
    margin-left: 0.5rem;
    padding: 0;
    background: none;
    border: none;
    color: #4f46e5;
    cursor: pointer;
    text-decoration: underline;
  }

  input {
    padding: 0.5rem;
    border: 1px solid #ccc;
    border-radius: 4px;
  }

  button {
    padding: 0.5rem;
    border: none;
    background: #4f46e5;
    color: white;
    border-radius: 4px;
    cursor: pointer;
  }

  .config-table {
    width: 100%;
    border-collapse: collapse;
    margin-top: 1rem;
  }

  .config-table th,
  .config-table td {
    border: 1px solid #e5e7eb;
    padding: 0.5rem;
    text-align: left;
  }

  .config-key {
    font-family: monospace;
    font-weight: 600;
  }

  .table-input {
    width: 100%;
  }

  .error {
    color: #b91c1c;
  }

  .success {
    color: #047857;
  }
</style>
