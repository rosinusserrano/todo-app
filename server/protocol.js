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
//   BUMP      A new column, however optional. An older server drops what it
//             does not know, which is harmless; an older *client* does not -
//             it inserts pulled rows verbatim, so a column it has no column
//             for fails its whole merge and it stops receiving anything. (v13
//             `recur` and v14 `all_day` went out without a bump and had this
//             hole.) Bump, and list the column in COLUMN_SINCE in db.js with
//             the new number: clients that announce it get the column, older
//             ones keep working on everything else. MIN_CLIENT does not move.
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

// History:
//   2  The calendar_feeds table (subscribed calendars). A table a server does
//      not know fails the *whole* push in validatePayload, so a client must not
//      send it to a server that says 1 - and does not; it holds those rows back
//      until the server is updated. MIN_CLIENT stays 1: a protocol-1 client
//      simply never sends the table. Nor is it sent the table, or the
//      calendar_events.feed_uuid column: an older app inserts a pulled row
//      verbatim, and a column it lacks fails its whole merge (see COLUMN_SINCE
//      in db.js). From 2 on, a client says which protocol it speaks in the
//      body of /api/sync, and absent means 1.
//   3  The shopping list: `lists` and `list_items`, in TABLE_SINCE, so a client
//      below 3 is not sent them and a 3 client does not push them to a server
//      below 3. MIN_CLIENT stays 1.
//   4  Collections: `collections`, `collection_fields` and
//      `collection_entries`, in TABLE_SINCE on the same terms as 3.
//      MIN_CLIENT stays 1.
//   5  `workspaces.shortcuts` (a workspace's other names in a task title), in
//      COLUMN_SINCE: not sent to a client below 5, and kept when such a
//      client pushes the row back without it. MIN_CLIENT stays 1.
//   6  Voice notes: `audio` and `audio_ms` on `side_thoughts` and `tasks`, in
//      COLUMN_SINCE on 5's terms. The bytes go through /api/blobs, which an
//      older server answers with 404 - the client keeps them queued.
export const PROTOCOL = 6;
export const MIN_CLIENT = 1;
