// Live change hints, over Server-Sent Events.
//
// Sync is a poll, and a poll is a compromise: a minute of latency in exchange
// for not hammering a server that usually has nothing to say. This is the other
// half - the server telling a user's *other* devices that there is something
// worth fetching, so the poll only has to catch what the stream missed.
//
// The one rule that shapes the whole file: **a hint carries no rows.** The
// payload is a sequence number, and the client's only reaction is to run the
// sync it would have run anyway a minute later. That is what makes this purely
// additive - no merge rule, no conflict resolution and no tombstone handling
// moves here, there is no second way for data to arrive, and a device that
// never connects behaves exactly as it did before. It also means a dropped
// hint is not a lost write: it costs latency, nothing else, which is why
// reconnection needs no replay and no per-connection cursor.
//
// SSE rather than WebSockets because the traffic is one-directional and this is
// the direction: the client already has a way to talk to the server. It is
// plain HTTP, so it needs no new dependency, survives a reverse proxy that only
// speaks HTTP/1.1, and reconnects by making the request again.
//
// Streams are held per user, because that is the blast radius of a change. A
// second account on the same server shares the counter (see `meta.seq` in
// db.js) but must never learn that the counter moved.

/** userId -> Set of open connections. */
const streams = new Map();

/**
 * How often to write a keep-alive comment, in ms.
 *
 * Idle connections are what proxies and NAT tables reap, and an SSE connection
 * is idle by design - a user who is not editing anything produces no traffic
 * for hours. The comment is two bytes of nothing that both ends read as "still
 * here". 25s is comfortably inside the common 30-60s idle timeouts.
 */
const HEARTBEAT_MS = 25_000;

/**
 * Attach a client to its user's fan-out set.
 *
 * `deviceId` is what the device calls itself, and it is only ever used to
 * *exclude* that device from a broadcast its own push caused - see publish().
 * It is not a credential and is not trusted for anything: the user was already
 * established by the bearer token before this is reached, so the worst a lying
 * device id can do is cost its owner a redundant sync.
 *
 * @returns {() => void} detach, safe to call more than once
 */
export function subscribe(userId, deviceId, res) {
  // The response never completes, so nothing downstream may buffer it and
  // nothing may decide the socket is idle and reclaim it.
  res.writeHead(200, {
    'Content-Type': 'text/event-stream; charset=utf-8',
    'Cache-Control': 'no-cache, no-transform',
    Connection: 'keep-alive',
    // nginx buffers proxied responses by default, which turns a stream into a
    // response that arrives all at once, i.e. never. Caddy wants
    // `flush_interval -1` in its config instead - there is no header for it.
    'X-Accel-Buffering': 'no',
  });
  res.flushHeaders?.();

  // An open stream is not an idle socket, whatever the server's timeouts think.
  res.socket?.setTimeout?.(0);
  res.socket?.setNoDelay?.(true);

  const client = { res, deviceId };
  let set = streams.get(userId);
  if (!set) streams.set(userId, (set = new Set()));
  set.add(client);

  // Say hello immediately. It costs one line and it is what proves the whole
  // path works - through the proxy, through TLS - rather than leaving the
  // client to infer it from a silence it cannot tell apart from a broken pipe.
  write(res, 'ready', { ok: true });

  const beat = setInterval(() => {
    // A comment line: valid SSE, ignored by every parser, including ours.
    try {
      res.write(': ping\n\n');
    } catch {
      detach();
    }
  }, HEARTBEAT_MS);
  // Node keeps the process alive for pending timers; a heartbeat must not be
  // the reason the server will not shut down.
  beat.unref?.();

  let detached = false;
  function detach() {
    if (detached) return;
    detached = true;
    clearInterval(beat);
    const current = streams.get(userId);
    if (current) {
      current.delete(client);
      if (current.size === 0) streams.delete(userId);
    }
    try {
      res.end();
    } catch {
      // Already gone. Nothing here can fail in a way that matters.
    }
  }

  res.on('close', detach);
  res.on('error', detach);
  return detach;
}

/**
 * Tell a user's other devices that their account moved.
 *
 * `originDeviceId` is skipped: the device whose push caused this already has
 * the rows, and syncing it again would merge nothing. Skipping it is not what
 * makes this terminate, though - a sync that merges nothing publishes nothing,
 * so even a client that lies about its id cannot start a loop.
 *
 * @returns {number} how many connections were told
 */
export function publish(userId, cursor, originDeviceId = null) {
  const set = streams.get(userId);
  if (!set) return 0;

  let sent = 0;
  for (const client of [...set]) {
    if (originDeviceId && client.deviceId === originDeviceId) continue;
    if (write(client.res, 'changed', { cursor })) sent++;
  }
  return sent;
}

/** Open connections, for the console banner and the tests. */
export function connectionCount(userId = null) {
  if (userId != null) return streams.get(userId)?.size ?? 0;
  let n = 0;
  for (const set of streams.values()) n += set.size;
  return n;
}

/**
 * Close every stream. Only for tests and shutdown: an open SSE response keeps
 * the HTTP server's `close()` waiting forever otherwise.
 */
export function closeAll() {
  for (const set of [...streams.values()]) {
    for (const client of [...set]) {
      try {
        client.res.end();
      } catch {
        // Nothing to do about a socket that is already broken.
      }
    }
  }
  streams.clear();
}

function write(res, event, data) {
  try {
    res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
    return true;
  } catch {
    // A dead socket is normal - a phone went into a tunnel. The 'close'
    // handler does the bookkeeping; this just must not throw into a caller
    // that is in the middle of answering somebody else's request.
    return false;
  }
}
