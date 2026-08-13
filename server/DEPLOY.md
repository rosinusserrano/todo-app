# Running the sync server for real

The quick version — `npm run server` on a laptop for a LAN — is in the
[README](../README.md). This is the rest: a box that stays up, TLS, and
Keycloak.

---

## Ubuntu / Debian, with systemd

```sh
git clone https://github.com/rosinusserrano/todo-app.git
cd todo-app
sudo ./server/install-server.sh
```

Idempotent — run it again to upgrade. It never overwrites the database or
`/etc/todo-sync.env`, so an upgrade cannot lose data or reset your settings.

| | |
| --- | --- |
| Install dir | `/opt/todo-sync` (copied out of the clone, so `git pull` cannot swap code under a live process) |
| Data | `/var/lib/todo-sync/` — database and bootstrap secret, `0700`, owned by `todosync` |
| Config | `/etc/todo-sync.env` |
| Service | `todo-sync.service`, running as the unprivileged `todosync` user |

```sh
sudo systemctl status todo-sync
sudo journalctl -u todo-sync -f
sudo systemctl restart todo-sync        # after editing the env file
```

### Getting the first token

```sh
sudo journalctl -u todo-sync -n 40 --no-pager | grep -i token
```

Then, per device:

```sh
sudo -u todosync TODO_SYNC_DB=/var/lib/todo-sync/sync.db \
  node /opt/todo-sync/server/tokens.js add "Marco's phone"
```

`list` and `revoke <id>` too. All of it works against the running server — WAL
allows the second writer and the server reads the tokens table per request, so
issuing and revoking take effect without a restart.

---

## TLS

**Do not expose this over plain HTTP.** Authentication is a bearer token in a
header; anything on the path can read it and then is you.

The installer defaults `TODO_SYNC_HOST=127.0.0.1` so the server is not reachable
from outside until you have put something in front of it. With Caddy, the whole
job is two lines:

```caddyfile
todo.example.com {
    reverse_proxy 127.0.0.1:8787 {
        # Instant sync is an event stream on /api/events: a response that
        # deliberately never ends. Caddy buffers proxied responses by default,
        # which turns that into a response that never arrives — sync still
        # works, it just silently falls back to polling once a minute.
        # -1 means flush immediately.
        flush_interval -1
    }
}
```

Or nginx with certbot:

```nginx
server {
    listen 443 ssl;
    server_name todo.example.com;

    ssl_certificate     /etc/letsencrypt/live/todo.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/todo.example.com/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:8787;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Attachment metadata pushes can be chunky.
        client_max_body_size 16m;

        # Instant sync (/api/events) is a response that never ends. Without
        # these, nginx buffers it forever and the app quietly falls back to
        # polling once a minute; the read timeout would then cut the
        # connection between keep-alives.
        proxy_buffering off;
        proxy_cache off;
        proxy_http_version 1.1;
        proxy_read_timeout 1h;
    }
}
```

Then point the app at `https://todo.example.com` — no port.

### LAN only

If the box never leaves your network, set `TODO_SYNC_HOST=0.0.0.0`, open the
port, and accept that the traffic is unencrypted on your own LAN:

```sh
sudo ufw allow 8787/tcp
```

---

## Keycloak

With SSO configured, devices sign in with your existing identity provider
instead of a pasted token. The server still runs no login flow of its own: the
app gets an access token from Keycloak and presents it, and the server verifies
the signature against Keycloak's published keys.

Device tokens keep working alongside it. That is deliberate — the CLI is what
fixes a server nobody can log in to.

### 1. Create the client

In the Keycloak admin console, in your realm:

1. **Clients → Create client**
   - Client type: **OpenID Connect**
   - Client ID: `todo-widget`
2. **Capability config**
   - Client authentication: **Off** (this is a public client — a desktop and
     mobile app cannot keep a secret, and pretending otherwise just puts one in
     everybody's binary)
   - Authentication flow: tick **OAuth 2.0 Device Authorization Grant**
   - Standard flow and Direct access grants can both be **off**
3. Save.

No redirect URI is needed. The device grant does not use one, which is the main
reason it was chosen: no custom URL scheme, no loopback listener, no
per-platform deep-link plumbing, and the same flow works identically on Windows,
iOS and Android.

### 2. Create the admin role

**Realm roles → Create role → `todo-admin`**, then assign it to yourself
(**Users → *you* → Role mapping**).

Anyone holding that realm role is an admin of the sync server. The role is read
from the token on **every** request, so granting or revoking it in Keycloak
takes effect on the next sync — there is nothing to change on the server.

### 3. Point the server at it

In `/etc/todo-sync.env`:

```sh
TODO_OIDC_ISSUER=https://keycloak.example.com/realms/home
TODO_OIDC_CLIENT_ID=todo-widget
TODO_OIDC_ADMIN_ROLE=todo-admin
```

```sh
sudo systemctl restart todo-sync
curl -s https://todo.example.com/api/auth/config | jq
```

That should report `"mode": "oidc"` and echo the endpoints it found. If it
returns 503, the server is up but cannot reach Keycloak — check the issuer URL
first; it must match the `iss` claim **exactly**, including the `/realms/<name>`
part.

### 4. Move your existing account onto SSO — do this before signing in

If the server has been running on the bootstrap secret, all your rows belong to
the user `local`. The first SSO login would find no account for that Keycloak
identity, create a **new, empty one**, and correctly show you nothing.

Link first:

```sh
# The <sub> is the user's ID in the Keycloak admin console:
#   Users -> the person -> the "ID" field (a UUID).
sudo -u todosync TODO_SYNC_DB=/var/lib/todo-sync/sync.db \
  node /opt/todo-sync/server/tokens.js link local 8f14e45f-ce4a-...
```

Now signing in with that Keycloak user lands on the account your data is
already in. `unlink <user-id>` detaches it again; both leave rows and device
tokens untouched.

If you already signed in and got a stray empty account, `unlink` it (or delete
it) and then link `local` — the identity cannot be attached to two accounts at
once, and the CLI refuses rather than silently moving it.

### 5. Sign in from the app

**Settings → Sync**, enter the address, press **Connect**, then **Sign in with
your account**. The browser opens at your login page; approve it and the app
takes over, refreshing on its own.

New people need nothing from you: their account is created the first time they
sign in. Who is *allowed* to sign in is a Keycloak question — see the note under
"Logging in with Google".

### Logging in on more than one device

Expected, and the point of the whole thing: sign in on Windows and on the phone
as the same Keycloak user and both land on the same account with the same
tasks. Each device runs its own sign-in and holds its own tokens — those are
per-device credentials — but the account is chosen by the `sub` claim, which is
the same person's regardless of which device or which browser approved it.

Signing out on one device does not touch the others.

### Logging in with Google

If your realm brokers Google (or any other identity provider), nothing here
changes. The sync server only ever talks to Keycloak and only ever reads
Keycloak's own `sub`, which is stable no matter how the person authenticated to
Keycloak. Everyone who logs in that way gets their own account on the sync
server automatically.

Worth knowing: that means **anyone who can authenticate to the `todo-widget`
client gets an account**. If your Keycloak allows self-registration through
Google, so does your sync server. Restrict it in Keycloak — client-level
authorization, a required role, or an identity-provider mapper — which is where
that policy belongs.

### How accounts map

- Identity is the token's `sub` claim, never the email address. An address
  changing hands in your directory must not hand over the account with it.
- An account is created the first time someone signs in. If you do not want
  that, restrict who can reach the `todo-widget` client in Keycloak — that
  policy belongs in the identity provider, not in a todo app.
- The display name and the admin role are refreshed from the token on every
  request: while SSO is on, the directory is the authority on both.

### Cutting someone off

Disabling the user in Keycloak stops the refresh, and their access token
expires within minutes.

To cut an account off from this end immediately — the server cannot un-issue a
Keycloak token — block it locally:

```sh
sudo -u todosync TODO_SYNC_DB=/var/lib/todo-sync/sync.db \
  node -e "
    import('/opt/todo-sync/server/users.js').then(async (u) => {
      const { default: D } = await import('better-sqlite3');
      const db = new D(process.env.TODO_SYNC_DB);
      u.setBlocked(db, 'the-user-id', true);
    })"
```

Blocking is checked on every request for both credential kinds, and it deletes
nothing — unblocking restores the account and its rows intact.

---

## Backups

Everything is one SQLite file. Stop the service or use the online backup API;
copying a live WAL database with `cp` can capture a torn state.

```sh
sudo -u todosync sqlite3 /var/lib/todo-sync/sync.db \
  ".backup '/var/backups/todo-sync-$(date +%F).db'"
```

The server is not the source of truth — every device holds a full local copy —
but restoring from a backup is still much less annoying than asking six devices
to re-push.

---

## Upgrading

```sh
cd todo-app && git pull
sudo ./server/install-server.sh
```

The schema migrates itself on open (`addColumn` in `db.js`). Client and server
versions may differ: unknown fields are dropped rather than rejected, so an
older server stays usable against a newer app, and a column the server does not
have yet syncs as null until it is upgraded.
