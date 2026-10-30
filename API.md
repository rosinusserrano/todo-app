# Todo Widget API: notifications, thoughts and todos from scripts

A script running anywhere can send the owner of a Todo Widget account:

- a **notification**: a push to every device that has notifications turned on,
- a **thought**: an entry in the side-thought pile,
- a **todo**: a task on one of the account's lists, or on one of its shelves.

Thoughts and todos sync to every device the account uses, the same as
anything typed in the app.

The API can only add things. A token cannot read, change or delete anything,
so a leaked one can at worst send unwanted notifications, thoughts and todos.
Revoke it in the app and nothing it sent before is removed.

## For an agent working in another project

Read the two variables from the project's environment, usually `.env`:

```sh
TODO_URL=https://todo.example.com   # the server, no trailing slash
TODO_TOKEN=...                      # an API token, see below
```

Then `POST` JSON to `$TODO_URL/api/notify`, `$TODO_URL/api/thought` or
`$TODO_URL/api/todo` with the header `Authorization: Bearer $TODO_TOKEN`.
Never print the token or commit it. If either variable is missing, ask the
person to create a token. Don't guess one.

## Getting a token

In the app: **Settings → API tokens → Manage → New token**. Give it a name
saying what will use it ("backup script", "ci"). The token is shown **once**,
because the server keeps only a hash of it. **Copy .env lines** copies both
`TODO_URL` and `TODO_TOKEN`, ready to paste.

Make one token per script or machine, so revoking one stops only that one.

## Requests

All three routes have the same shape:

- `POST` with `Content-Type: application/json`, a JSON object as the body.
- `Authorization: Bearer <token>`.
- They answer `200` with JSON on success, and `400 {"error": "..."}` for a
  request that cannot be carried out. A `400` never writes anything, and the
  error says what to fix.

### `POST /api/notify`: send a notification

Also reachable as `/api/notification`.

| Field | Type | |
| --- | --- | --- |
| `title` | string | Optional if `body` is given. Defaults to "Todo". Cut at 120 characters. |
| `body` | string | Optional if `title` is given. `message` is accepted as another name for it. Cut at 600 characters. |
| `tag` | string | Optional, at most 64 characters. A later notification with the same tag replaces the earlier one on the device instead of stacking. |

```sh
curl -sS "$TODO_URL/api/notify" \
  -H "Authorization: Bearer $TODO_TOKEN" -H "Content-Type: application/json" \
  -d '{"title": "Backup done", "body": "42 GB in 6 min", "tag": "backup"}'
```

```json
{"sent": 1, "subscriptions": 1}
```

`sent: 0` is still a success. It means no device has notifications turned on
yet (in the web app: Settings → Notifications). Retrying won't change that.
Only the web app receives pushes. The native desktop and phone apps don't.

### `POST /api/thought`: add a thought

| Field | Type | |
| --- | --- | --- |
| `text` | string | **Required.** At most 2000 characters. |
| `remind_at` | string | Optional. A reminder, as an ISO 8601 time **with a timezone**: `2026-11-02T09:00:00+01:00` or `2026-11-02T08:00:00Z`. |
| `notify` | boolean | Optional. `true` also sends a notification right away, titled "Thought". |

```sh
curl -sS "$TODO_URL/api/thought" \
  -H "Authorization: Bearer $TODO_TOKEN" -H "Content-Type: application/json" \
  -d '{"text": "Disk on nas01 at 85%", "notify": true}'
```

```json
{"ok": true, "id": "72a5b518-…", "text": "Disk on nas01 at 85%", "remind_at": null,
 "notified": {"sent": 1, "subscriptions": 1}}
```

`notified` is present only when `notify` was `true`. If the push fails, the
thought is still saved and the answer is still `200`.

### `POST /api/todo`: add a todo

| Field | Type | |
| --- | --- | --- |
| `text` | string | **Required.** The title, at most 2000 characters. `title` is accepted as another name for it. |
| `notes` | string | Optional. The long form, in Markdown. At most 20000 characters. |
| `workspace` | string | Optional. The workspace (list) to add it to, by name or by one of its `#shortcuts`, ignoring case. A project's name works too. **Left out: the first workspace.** |
| `shelf` | string | Optional. A shelf (parked group) in that workspace, by title, ignoring case. The todo is then parked there instead of on the list. |
| `remind_at` | string | Optional. A reminder, with a timezone, as for a thought. |
| `high_priority` | boolean | Optional. `true` flags it. |
| `notify` | boolean | Optional. `true` also sends a notification right away, titled with the workspace (and shelf). |

```sh
curl -sS "$TODO_URL/api/todo" \
  -H "Authorization: Bearer $TODO_TOKEN" -H "Content-Type: application/json" \
  -d '{"text": "Renew the TLS cert on web02", "workspace": "Work",
       "notes": "Expires **2026-11-14**.", "remind_at": "2026-11-10T09:00:00+01:00"}'
```

```json
{"ok": true, "id": "3df32c50-…", "text": "Renew the TLS cert on web02",
 "workspace": "Work", "remind_at": "2026-11-10T08:00:00.000Z"}
```

The todo goes to the end of the list. `shelf` appears in the answer when one
was given. A name that matches nothing is a `400` listing what does exist:

```json
{"error": "No workspace called \"Wrok\"", "workspaces": ["Home", "Work", "Rewrite"]}
```

```json
{"error": "No shelf called \"Someday\" in Work", "shelves": ["Ideas", "Backlog"]}
```

## Errors

| Status | Meaning | What to do |
| --- | --- | --- |
| `400` | The request is wrong: a missing `text`, a bad type, an unknown workspace or shelf, a `remind_at` without a timezone. | Fix the request using `error`. Don't retry it unchanged. |
| `401` | No token, or the token is unknown or revoked. | Ask for a new token. |
| `403` | The token is the wrong kind for this route, for example a notify-only token on `/api/todo`. | Use an API token from the app. |
| `5xx` / no answer | The server is down or restarting. | Retry later. Note that a retried thought or todo can arrive twice if the first attempt got through. |

## Examples

Python, standard library only:

```python
import json, os, urllib.request

def todo_api(route: str, payload: dict) -> dict:
    req = urllib.request.Request(
        f"{os.environ['TODO_URL']}/api/{route}",
        data=json.dumps(payload).encode(),
        headers={
            "Authorization": f"Bearer {os.environ['TODO_TOKEN']}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=15) as res:
        return json.load(res)

todo_api("notify", {"title": "Deploy finished", "body": "web02 is on v1.4.2"})
todo_api("thought", {"text": "Look into the slow query on /orders"})
todo_api("todo", {"text": "Rotate the S3 keys", "workspace": "Work", "high_priority": True})
```

Node 18 or newer:

```js
async function todoApi(route, payload) {
  const res = await fetch(`${process.env.TODO_URL}/api/${route}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${process.env.TODO_TOKEN}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });
  const body = await res.json();
  if (!res.ok) throw new Error(`todo api ${res.status}: ${body.error}`);
  return body;
}
```

A shell script with a `.env` beside it:

```sh
set -a; . ./.env; set +a
curl -fsS "$TODO_URL/api/notify" -H "Authorization: Bearer $TODO_TOKEN" \
  -H "Content-Type: application/json" -d "{\"title\": \"$(hostname)\", \"body\": \"nightly job done\"}"
```

---

*For whoever maintains the server:* these routes are `server/inbox.js` and
the `/api/notify` route in `server/index.js`. Inbox tokens are
`INBOX_SCOPE` in `server/users.js`. A change to a field or an answer belongs
in this file too.
