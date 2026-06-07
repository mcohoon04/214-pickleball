import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";
import {
  buildEmailHtml,
  buildGoogleCalUrl,
  buildICS,
  buildOutlookUrl,
  CAL_LOCATION,
  CAL_SUMMARY,
  toBase64,
} from "./ics.ts";

// --- APNs JWT helpers ---

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

function base64url(data: Uint8Array): string {
  return btoa(String.fromCharCode(...data))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function base64urlEncode(obj: Record<string, unknown>): string {
  return base64url(new TextEncoder().encode(JSON.stringify(obj)));
}

let cachedApnsKey: CryptoKey | null = null;
let cachedApnsToken: string | null = null;
let apnsTokenCreatedAt = 0;
const APNS_TOKEN_TTL = 50 * 60 * 1000; // 50 min

async function getApnsKey(): Promise<CryptoKey> {
  if (cachedApnsKey) return cachedApnsKey;
  const pem = Deno.env.get("APNS_P8_KEY")!;
  const keyData = pemToArrayBuffer(pem);
  cachedApnsKey = await crypto.subtle.importKey(
    "pkcs8",
    keyData,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"]
  );
  return cachedApnsKey;
}

async function getApnsToken(): Promise<string> {
  if (cachedApnsToken && Date.now() - apnsTokenCreatedAt < APNS_TOKEN_TTL) {
    return cachedApnsToken;
  }
  const key = await getApnsKey();
  const keyId = Deno.env.get("APNS_KEY_ID")!;
  const teamId = Deno.env.get("APNS_TEAM_ID")!;
  const header = base64urlEncode({ alg: "ES256", kid: keyId });
  const claims = base64urlEncode({
    iss: teamId,
    iat: Math.floor(Date.now() / 1000),
  });
  const unsigned = `${header}.${claims}`;
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(unsigned)
  );
  cachedApnsToken = `${unsigned}.${base64url(new Uint8Array(sig))}`;
  apnsTokenCreatedAt = Date.now();
  return cachedApnsToken;
}

// --- Send push via APNs ---

async function sendPush(
  deviceToken: string,
  title: string,
  body: string
): Promise<{ success: boolean; status: number; error?: string }> {
  const bundleId = Deno.env.get("APNS_BUNDLE_ID")!;
  const sandbox = Deno.env.get("APNS_SANDBOX") === "true";
  const host = sandbox
    ? "api.development.push.apple.com"
    : "api.push.apple.com";
  const jwt = await getApnsToken();

  const res = await fetch(`https://${host}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": bundleId,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      aps: { alert: { title, body }, sound: "default" },
    }),
  });

  if (res.status === 200) return { success: true, status: 200 };
  const err = await res.json().catch(() => ({}));
  return {
    success: false,
    status: res.status,
    error: (err as Record<string, string>).reason ?? "unknown",
  };
}

// --- Calendar invite (.ics) for a booking email ---

interface CalendarAttachment {
  icsContent: string;
  method: "PUBLISH" | "CANCEL";
  links?: { google: string; outlook: string };
}

/**
 * Build the .ics + "add to calendar" links for a booking notification email.
 * Returns undefined if the booking can't be found. Never throws — the email
 * must go out even if calendar generation fails.
 */
async function buildCalendarForBooking(
  supabase: SupabaseClient,
  bookingId: string,
  type: string
): Promise<CalendarAttachment | undefined> {
  const { data: booking } = await supabase
    .from("bookings")
    .select("id, starts_at, ends_at")
    .eq("id", bookingId)
    .maybeSingle();
  if (!booking) return undefined;

  // Participant names: real players (by profile) + guests (by guest_name).
  const { data: bps } = await supabase
    .from("booking_players")
    .select("player_id, guest_name")
    .eq("booking_id", bookingId);

  const rows = bps ?? [];
  const realIds = rows
    .filter((p: { player_id: string | null }) => p.player_id)
    .map((p: { player_id: string }) => p.player_id);

  const nameById: Record<string, string> = {};
  if (realIds.length > 0) {
    const { data: profs } = await supabase
      .from("profiles")
      .select("id, display_name")
      .in("id", realIds);
    for (const p of profs ?? []) nameById[p.id] = p.display_name;
  }

  const names = rows.map((p: { player_id: string | null; guest_name: string | null }) =>
    p.player_id ? nameById[p.player_id] ?? "Player" : `${p.guest_name} (guest)`
  );

  const start = new Date(booking.starts_at);
  const end = new Date(booking.ends_at);
  const description = names.length ? `Players: ${names.join(", ")}` : "Pickleball game";
  const isCancel = type === "booking_cancelled";
  const method: "PUBLISH" | "CANCEL" = isCancel ? "CANCEL" : "PUBLISH";

  const icsContent = buildICS({
    uid: `${bookingId}@214-pickle.com`,
    method,
    sequence: isCancel ? 1 : 0,
    start,
    end,
    summary: CAL_SUMMARY,
    location: CAL_LOCATION,
    description: isCancel ? "This pickleball game was cancelled." : description,
    cancelled: isCancel,
  });

  const links = isCancel
    ? undefined
    : {
        google: buildGoogleCalUrl(start, end, CAL_SUMMARY, description, CAL_LOCATION),
        outlook: buildOutlookUrl(start, end, CAL_SUMMARY, description, CAL_LOCATION),
      };

  return { icsContent, method, links };
}

// --- Send email via Resend ---

async function sendEmail(
  to: string,
  subject: string,
  body: string,
  calendar?: CalendarAttachment
): Promise<{ success: boolean; id?: string; error?: string }> {
  const apiKey = Deno.env.get("RESEND_API_KEY")!;
  const fromEmail =
    Deno.env.get("RESEND_FROM_EMAIL") ?? "noreply@send.214-pickle.com";

  const payload: Record<string, unknown> = {
    from: fromEmail,
    to,
    subject,
    html: buildEmailHtml(subject, body, calendar?.links),
  };

  if (calendar) {
    payload.attachments = [
      {
        filename: "invite.ics",
        content: toBase64(calendar.icsContent),
        content_type: `text/calendar; charset=utf-8; method=${calendar.method}`,
      },
    ];
  }

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify(payload),
  });

  const data = await res.json();
  if (res.ok) return { success: true, id: data.id };
  return { success: false, error: data.message ?? "unknown" };
}

// --- Main handler ---

Deno.serve(async (_req: Request) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  // Fetch pending notifications ready to send
  const { data: notifications, error: fetchErr } = await supabase
    .from("notifications")
    .select("*")
    .in("status", ["pending", "failed"])
    .lte("scheduled_for", new Date().toISOString())
    .lt("retry_count", 3)
    .order("scheduled_for", { ascending: true })
    .limit(50);

  if (fetchErr) {
    return new Response(JSON.stringify({ error: fetchErr.message }), {
      status: 500,
    });
  }

  if (!notifications || notifications.length === 0) {
    return new Response(JSON.stringify({ processed: 0 }), { status: 200 });
  }

  // Mark as processing
  const ids = notifications.map((n: { id: string }) => n.id);
  await supabase.from("notifications").update({ status: "processing" }).in("id", ids);

  let sent = 0;
  let failed = 0;

  for (const notif of notifications) {
    let success = false;
    let errorMsg = "";
    let providerId = "";

    try {
      if (notif.channel === "push") {
        // Get device token from profiles
        const { data: profile } = await supabase
          .from("profiles")
          .select("apns_device_token")
          .eq("id", notif.user_id)
          .single();

        const token = profile?.apns_device_token;
        if (!token) {
          errorMsg = "No device token";
        } else {
          const result = await sendPush(token, notif.title, notif.body);
          success = result.success;
          if (!success) {
            errorMsg = result.error ?? `HTTP ${result.status}`;
            // Handle 410 Unregistered — clear device token
            if (result.status === 410) {
              await supabase
                .from("profiles")
                .update({ apns_device_token: null })
                .eq("id", notif.user_id);
            }
          }
        }
      } else if (notif.channel === "email") {
        // Get user email from auth.users via admin API
        const { data: userData } = await supabase.auth.admin.getUserById(
          notif.user_id
        );
        const email = userData?.user?.email;
        if (!email) {
          errorMsg = "No email address";
        } else {
          // Attach a calendar invite (.ics) for booking created/cancelled emails.
          let calendar: CalendarAttachment | undefined;
          if (
            notif.booking_id &&
            (notif.type === "booking_created" || notif.type === "booking_cancelled")
          ) {
            try {
              calendar = await buildCalendarForBooking(
                supabase,
                notif.booking_id,
                notif.type
              );
            } catch (_e) {
              calendar = undefined; // never block the email on calendar build failure
            }
          }
          const result = await sendEmail(email, notif.title, notif.body, calendar);
          success = result.success;
          providerId = result.id ?? "";
          if (!success) errorMsg = result.error ?? "unknown";
        }
      }
    } catch (e) {
      errorMsg = e instanceof Error ? e.message : "unknown error";
    }

    if (success) {
      await supabase
        .from("notifications")
        .update({
          status: "sent",
          sent_at: new Date().toISOString(),
          provider_message_id: providerId || null,
        })
        .eq("id", notif.id);
      sent++;
    } else {
      await supabase
        .from("notifications")
        .update({
          status: "failed",
          error_message: errorMsg,
          retry_count: (notif.retry_count ?? 0) + 1,
        })
        .eq("id", notif.id);
      failed++;
    }
  }

  return new Response(
    JSON.stringify({ processed: notifications.length, sent, failed }),
    { status: 200, headers: { "Content-Type": "application/json" } }
  );
});
