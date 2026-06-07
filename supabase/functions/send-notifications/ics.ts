// iCalendar (.ics) generation + branded email HTML + "add to calendar" links.
// Kept separate from index.ts so the pure functions are unit-testable with `deno test`.

const PRODID = "-//214 Pickle//Booking//EN";
export const CAL_LOCATION = "214 Pickle";
export const CAL_SUMMARY = "Pickleball at 214 Pickle";

function pad(n: number): string {
  return n < 10 ? "0" + n : String(n);
}

/** UTC basic format: YYYYMMDDTHHMMSSZ (used by .ics and Google Calendar links). */
export function formatICSDate(d: Date): string {
  return (
    String(d.getUTCFullYear()) +
    pad(d.getUTCMonth() + 1) +
    pad(d.getUTCDate()) +
    "T" +
    pad(d.getUTCHours()) +
    pad(d.getUTCMinutes()) +
    pad(d.getUTCSeconds()) +
    "Z"
  );
}

/** Escape a value for an iCalendar TEXT field (RFC 5545 §3.3.11). */
export function icsEscape(s: string): string {
  return s
    .replace(/\\/g, "\\\\")
    .replace(/;/g, "\\;")
    .replace(/,/g, "\\,")
    .replace(/\r?\n/g, "\\n");
}

/** Fold a content line to <=75 octets with CRLF + space continuation (RFC 5545 §3.1). */
export function foldICSLine(line: string): string {
  const enc = new TextEncoder();
  if (enc.encode(line).length <= 75) return line;
  const out: string[] = [];
  let current = "";
  let first = true;
  for (const ch of line) {
    // Continuation lines carry a leading space, so reserve a byte for it.
    const limit = first ? 75 : 74;
    if (enc.encode(current + ch).length > limit) {
      out.push(current);
      current = ch;
      first = false;
    } else {
      current += ch;
    }
  }
  out.push(current);
  return out.join("\r\n ");
}

export interface ICSParams {
  uid: string;
  method: "PUBLISH" | "CANCEL";
  sequence: number;
  start: Date;
  end: Date;
  summary: string;
  location: string;
  description: string;
  cancelled?: boolean;
}

/** Build a complete VCALENDAR string (CRLF line endings). */
export function buildICS(p: ICSParams): string {
  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    `PRODID:${PRODID}`,
    "CALSCALE:GREGORIAN",
    `METHOD:${p.method}`,
    "BEGIN:VEVENT",
    foldICSLine(`UID:${p.uid}`),
    `DTSTAMP:${formatICSDate(new Date())}`,
    `DTSTART:${formatICSDate(p.start)}`,
    `DTEND:${formatICSDate(p.end)}`,
    foldICSLine(`SUMMARY:${icsEscape(p.summary)}`),
    foldICSLine(`LOCATION:${icsEscape(p.location)}`),
    foldICSLine(`DESCRIPTION:${icsEscape(p.description)}`),
    `STATUS:${p.cancelled ? "CANCELLED" : "CONFIRMED"}`,
    `SEQUENCE:${p.sequence}`,
    "END:VEVENT",
    "END:VCALENDAR",
  ];
  return lines.join("\r\n") + "\r\n";
}

/** UTF-8 safe base64 (for the Resend attachment content). */
export function toBase64(s: string): string {
  return btoa(String.fromCharCode(...new TextEncoder().encode(s)));
}

export function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/** Google Calendar "add event" template URL. */
export function buildGoogleCalUrl(
  start: Date,
  end: Date,
  title: string,
  details: string,
  location: string,
): string {
  const params = new URLSearchParams({
    action: "TEMPLATE",
    text: title,
    dates: `${formatICSDate(start)}/${formatICSDate(end)}`,
    details,
    location,
  });
  return `https://calendar.google.com/calendar/render?${params.toString()}`;
}

/** Outlook (Microsoft 365) deep-link compose URL. */
export function buildOutlookUrl(
  start: Date,
  end: Date,
  title: string,
  body: string,
  location: string,
): string {
  const params = new URLSearchParams({
    path: "/calendar/action/compose",
    rru: "addevent",
    subject: title,
    startdt: start.toISOString(),
    enddt: end.toISOString(),
    body,
    location,
  });
  return `https://outlook.office.com/calendar/0/deeplink/compose?${params.toString()}`;
}

export interface CalendarLinks {
  google: string;
  outlook: string;
}

/** Branded, email-client-safe HTML body. `addToCalendar` adds the calendar buttons. */
export function buildEmailHtml(
  title: string,
  body: string,
  addToCalendar?: CalendarLinks,
): string {
  const accent = "#7AC143";
  const safeTitle = escapeHtml(title);
  const safeBody = escapeHtml(body);

  const calendarBlock = addToCalendar
    ? `
        <tr><td style="padding-top:8px;">
          <p style="margin:0 0 10px 0;font-size:14px;color:#444;">Add this game to your calendar:</p>
          <a href="${addToCalendar.google}" style="display:inline-block;margin:0 8px 8px 0;padding:10px 16px;background:${accent};color:#000;text-decoration:none;border-radius:8px;font-weight:600;font-size:14px;">Google Calendar</a>
          <a href="${addToCalendar.outlook}" style="display:inline-block;margin:0 8px 8px 0;padding:10px 16px;background:${accent};color:#000;text-decoration:none;border-radius:8px;font-weight:600;font-size:14px;">Outlook</a>
          <p style="margin:6px 0 0 0;font-size:12px;color:#888;">Apple Calendar &amp; other apps: open the attached <strong>invite.ics</strong> file.</p>
        </td></tr>`
    : "";

  return `<!DOCTYPE html>
<html><body style="margin:0;padding:0;background:#f4f4f4;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f4f4;padding:24px 0;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;background:#ffffff;border-radius:12px;overflow:hidden;">
        <tr><td style="background:#000000;padding:20px 24px;">
          <span style="color:${accent};font-size:20px;font-weight:700;">214 Pickle</span>
        </td></tr>
        <tr><td style="padding:24px;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
            <tr><td>
              <h1 style="margin:0 0 12px 0;font-size:18px;color:#111;">${safeTitle}</h1>
              <p style="margin:0 0 16px 0;font-size:15px;line-height:1.5;color:#333;">${safeBody}</p>
            </td></tr>
            ${calendarBlock}
          </table>
        </td></tr>
        <tr><td style="padding:16px 24px;border-top:1px solid #eee;">
          <p style="margin:0;font-size:12px;color:#999;">214 Pickle · times shown in Toronto time</p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>`;
}
