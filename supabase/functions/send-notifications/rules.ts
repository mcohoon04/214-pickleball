// Pure rules for the notification worker (kept separate so they can be unit-tested
// without booting the Deno.serve handler in index.ts).

// Claiming (incl. recovery of rows a dead run left "processing") lives in the
// claim_notifications() SQL function; these bound how long one run can take.

// Never let one slow APNs/Resend call hang the whole run.
export const SEND_TIMEOUT_MS = 10_000;

// Rows claimed per run. Even if every send times out, the batch stays inside
// RUN_BUDGET_MS, which leaves headroom under the 150s Free-plan wall clock.
export const BATCH_SIZE = 10;

// Stop starting new sends after this long and hand the rest back to the queue.
export const RUN_BUDGET_MS = 100_000;

export interface ReminderBooking {
  starts_at: string;
  status: string;
  player_ids: string[];
}

/**
 * Reason a reminder should not be sent anymore, or null to send it.
 * Non-reminder notifications always send.
 */
export function reminderSkipReason(
  notif: { type: string; user_id: string },
  booking: ReminderBooking | undefined,
  now: Date
): string | null {
  if (notif.type !== "booking_reminder") return null;
  if (!booking) return "Booking not found";
  if (booking.status !== "active") return "Booking cancelled";
  if (new Date(booking.starts_at) <= now) return "Game already started";
  if (!booking.player_ids.includes(notif.user_id)) return "No longer on booking";
  return null;
}

export function fetchWithTimeout(
  url: string,
  init: RequestInit,
  ms: number = SEND_TIMEOUT_MS
): Promise<Response> {
  return fetch(url, { ...init, signal: AbortSignal.timeout(ms) });
}

/** APNs `apns-expiration`: drop an undelivered reminder once the game starts. */
export function apnsExpiration(startsAt: string): string {
  return String(Math.floor(new Date(startsAt).getTime() / 1000));
}
