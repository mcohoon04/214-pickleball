// deno test --allow-net supabase/functions/send-notifications/rules_test.ts
import {
  assert,
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  apnsExpiration,
  BATCH_SIZE,
  fetchWithTimeout,
  isCronRequest,
  reminderSkipReason,
  RUN_BUDGET_MS,
  SEND_TIMEOUT_MS,
} from "./rules.ts";

const NOW = new Date("2026-10-20T11:02:00Z");
const PLAYER = "11111111-1111-1111-1111-111111111111";
const OTHER = "22222222-2222-2222-2222-222222222222";

// --- isCronRequest ---

const SECRET = "s3cr3t-value-for-tests";
const req = (method: string, secret?: string) =>
  new Request("http://localhost/send-notifications", {
    method,
    headers: secret === undefined ? {} : { "x-cron-secret": secret },
  });

Deno.test("isCronRequest -> accepts POST with the cron secret", () => {
  assert(isCronRequest(req("POST", SECRET), SECRET));
});

Deno.test("isCronRequest -> rejects a missing secret header", () => {
  assert(!isCronRequest(req("POST"), SECRET));
});

Deno.test("isCronRequest -> rejects a wrong secret", () => {
  assert(!isCronRequest(req("POST", "s3cr3t-value-for-testz"), SECRET));
  assert(!isCronRequest(req("POST", "short"), SECRET));
});

Deno.test("isCronRequest -> rejects non-POST methods", () => {
  assert(!isCronRequest(req("GET", SECRET), SECRET));
});

Deno.test("isCronRequest -> fails closed when CRON_SECRET is not configured", () => {
  assert(!isCronRequest(req("POST", ""), undefined));
  assert(!isCronRequest(req("POST", ""), ""));
});

// --- run budget ---

Deno.test("a worst-case batch (every send times out) fits the 150s Free-plan limit", () => {
  const FREE_PLAN_WALL_CLOCK_MS = 150_000;
  assert(RUN_BUDGET_MS + SEND_TIMEOUT_MS < FREE_PLAN_WALL_CLOCK_MS);
  assert(BATCH_SIZE * SEND_TIMEOUT_MS <= RUN_BUDGET_MS);
});

// --- apnsExpiration ---

Deno.test("apnsExpiration -> game start as UNIX seconds", () => {
  assertEquals(apnsExpiration("2026-10-20T12:00:00+00:00"), "1792497600");
});

// --- reminderSkipReason ---

const reminder = { type: "booking_reminder", user_id: PLAYER };
const activeBooking = {
  starts_at: "2026-10-20T12:00:00Z",
  status: "active",
  player_ids: [PLAYER, OTHER],
};

Deno.test("reminderSkipReason -> null for a reminder that still applies", () => {
  assertEquals(reminderSkipReason(reminder, activeBooking, NOW), null);
});

Deno.test("reminderSkipReason -> null for non-reminder types", () => {
  const created = { type: "booking_created", user_id: PLAYER };
  assertEquals(reminderSkipReason(created, undefined, NOW), null);
});

Deno.test("reminderSkipReason -> skips when booking is gone", () => {
  assertEquals(reminderSkipReason(reminder, undefined, NOW), "Booking not found");
});

Deno.test("reminderSkipReason -> skips cancelled bookings", () => {
  const cancelled = { ...activeBooking, status: "cancelled" };
  assertEquals(reminderSkipReason(reminder, cancelled, NOW), "Booking cancelled");
});

Deno.test("reminderSkipReason -> skips once the game has started", () => {
  const started = { ...activeBooking, starts_at: "2026-10-20T11:02:00Z" };
  assertEquals(reminderSkipReason(reminder, started, NOW), "Game already started");
});

Deno.test("reminderSkipReason -> skips players no longer on the booking", () => {
  const left = { ...activeBooking, player_ids: [OTHER] };
  assertEquals(reminderSkipReason(reminder, left, NOW), "No longer on booking");
});

// --- fetchWithTimeout ---

Deno.test("fetchWithTimeout -> rejects when the server never answers", async () => {
  const hang = Promise.withResolvers<void>();
  const server = Deno.serve({ port: 0, onListen() {} }, async () => {
    await hang.promise;
    return new Response("late");
  });
  try {
    await assertRejects(() =>
      fetchWithTimeout(`http://localhost:${server.addr.port}/`, {}, 100)
    );
  } finally {
    hang.resolve();
    await server.shutdown();
  }
});

Deno.test("fetchWithTimeout -> returns the response when the server answers", async () => {
  const server = Deno.serve({ port: 0, onListen() {} }, () => new Response("ok"));
  try {
    const res = await fetchWithTimeout(`http://localhost:${server.addr.port}/`, {}, 2000);
    assertEquals(await res.text(), "ok");
  } finally {
    await server.shutdown();
  }
});
