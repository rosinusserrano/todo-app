// The version of what the client and the server say to each other.
//
// Not the app's version and not the server's: those move on every release, and
// almost every release leaves the wire exactly as it was. This number is the
// wire itself, so "are these two compatible" has an answer that does not need a
// table of releases to look it up in.
//
// ---------------------------------------------------------------------------
// When to bump PROTOCOL
//
// Only when an older client talking to this server would be *wrong*, not merely
// behind. The distinction is the whole value of the number:
//
//   no bump   A new optional column (v13 `recur`, v14 `all_day`). An older
//             server drops what it does not know and an older client ignores
//             what it was not expecting; both keep working on everything else.
//             The fix for a dropped column is deploying, not refusing to sync.
//   no bump   A new endpoint the client can live without (`/api/events` was
//             exactly this - a 404 turns instant sync off and the poll carries
//             on).
//   BUMP      A required field, a renamed one, a field whose meaning changed, a
//             different conflict rule, an endpoint the client cannot work
//             without, or anything that makes an older client write a row this
//             server would store incorrectly.
//
// ---------------------------------------------------------------------------
// When to bump MIN_CLIENT
//
// Separately, and much more rarely: it is the oldest client this server will
// still serve. Raising it *cuts devices off* until they update, so it is for
// the case where continuing to accept an old client means accepting damage -
// not for tidiness. A client older than this is told to update the app; a
// server older than the client's floor is told to update the server. Two
// directions, two sentences, because either side can be the old one.
//
// A peer that sends neither number is protocol 1 by definition: 1 is what the
// wire was on the day the number was invented, which is what keeps this from
// being a flag day for every server already running.

export const PROTOCOL = 1;
export const MIN_CLIENT = 1;
