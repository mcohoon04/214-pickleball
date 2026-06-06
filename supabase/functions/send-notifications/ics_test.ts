// deno test --allow-none supabase/functions/send-notifications/ics_test.ts
import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildEmailHtml,
  buildGoogleCalUrl,
  buildICS,
  buildOutlookUrl,
  escapeHtml,
  foldICSLine,
  formatICSDate,
  icsEscape,
  toBase64,
} from "./ics.ts";

Deno.test("formatICSDate -> UTC basic format", () => {
  const d = new Date("2026-06-07T14:30:00Z");
  assertEquals(formatICSDate(d), "20260607T143000Z");
});

Deno.test("icsEscape escapes , ; \\ and newlines", () => {
  assertEquals(icsEscape("a,b;c\\d\ne"), "a\\,b\\;c\\\\d\\ne");
});

Deno.test("escapeHtml escapes entities", () => {
  assertEquals(escapeHtml(`<b>"&'`), "&lt;b&gt;&quot;&amp;&#39;");
});

Deno.test("buildICS PUBLISH has required structure", () => {
  const ics = buildICS({
    uid: "abc-123@214-pickle.com",
    method: "PUBLISH",
    sequence: 0,
    start: new Date("2026-06-07T14:00:00Z"),
    end: new Date("2026-06-07T14:30:00Z"),
    summary: "Pickleball at 214 Pickle",
    location: "214 Pickle",
    description: "Players: Alice, Bob, Dave (guest)",
  });
  // CRLF line endings
  assert(ics.includes("\r\n"), "must use CRLF");
  assertStringIncludes(ics, "BEGIN:VCALENDAR");
  assertStringIncludes(ics, "METHOD:PUBLISH");
  assertStringIncludes(ics, "UID:abc-123@214-pickle.com");
  assertStringIncludes(ics, "DTSTART:20260607T140000Z");
  assertStringIncludes(ics, "DTEND:20260607T143000Z");
  assertStringIncludes(ics, "STATUS:CONFIRMED");
  assertStringIncludes(ics, "SEQUENCE:0");
  // comma in DESCRIPTION must be escaped
  assertStringIncludes(ics, "Players: Alice\\, Bob\\, Dave (guest)");
  assert(ics.trimEnd().endsWith("END:VCALENDAR"));
});

Deno.test("buildICS CANCEL marks the event cancelled", () => {
  const ics = buildICS({
    uid: "abc-123@214-pickle.com",
    method: "CANCEL",
    sequence: 1,
    start: new Date("2026-06-07T14:00:00Z"),
    end: new Date("2026-06-07T14:30:00Z"),
    summary: "Pickleball at 214 Pickle",
    location: "214 Pickle",
    description: "Cancelled",
    cancelled: true,
  });
  assertStringIncludes(ics, "METHOD:CANCEL");
  assertStringIncludes(ics, "STATUS:CANCELLED");
  assertStringIncludes(ics, "SEQUENCE:1");
});

Deno.test("foldICSLine keeps each physical line <= 75 octets", () => {
  const long = "DESCRIPTION:" + "x".repeat(200);
  const folded = foldICSLine(long);
  const physical = folded.split("\r\n");
  assert(physical.length > 1, "should fold");
  for (const [i, line] of physical.entries()) {
    const bytes = new TextEncoder().encode(line).length;
    assert(bytes <= 75, `line ${i} is ${bytes} octets`);
    if (i > 0) assert(line.startsWith(" "), "continuation must start with a space");
  }
  // Unfolding restores the original.
  const unfolded = folded.replace(/\r\n /g, "");
  assertEquals(unfolded, long);
});

Deno.test("buildGoogleCalUrl includes basic-format dates", () => {
  const url = buildGoogleCalUrl(
    new Date("2026-06-07T14:00:00Z"),
    new Date("2026-06-07T14:30:00Z"),
    "Pickleball at 214 Pickle",
    "Players: Alice, Bob",
    "214 Pickle",
  );
  assertStringIncludes(url, "calendar.google.com");
  assertStringIncludes(url, "dates=20260607T140000Z%2F20260607T143000Z");
  assertStringIncludes(url, "action=TEMPLATE");
});

Deno.test("buildOutlookUrl includes ISO dates", () => {
  const url = buildOutlookUrl(
    new Date("2026-06-07T14:00:00Z"),
    new Date("2026-06-07T14:30:00Z"),
    "Pickleball at 214 Pickle",
    "Players: Alice, Bob",
    "214 Pickle",
  );
  assertStringIncludes(url, "outlook.office.com");
  assertStringIncludes(url, "startdt=2026-06-07T14%3A00%3A00.000Z");
  assertStringIncludes(url, "rru=addevent");
});

Deno.test("toBase64 round-trips UTF-8", () => {
  const s = "Players: Café, Søren";
  const decoded = new TextDecoder().decode(
    Uint8Array.from(atob(toBase64(s)), (c) => c.charCodeAt(0)),
  );
  assertEquals(decoded, s);
});

Deno.test("buildEmailHtml escapes body and adds calendar buttons", () => {
  const html = buildEmailHtml("New booking", "<script>alert(1)</script> Dave & Bob", {
    google: "https://g",
    outlook: "https://o",
  });
  assertStringIncludes(html, "&lt;script&gt;");
  assert(!html.includes("<script>alert"), "must not contain raw script tag");
  assertStringIncludes(html, "https://g");
  assertStringIncludes(html, "https://o");
  assertStringIncludes(html, "invite.ics");
});

Deno.test("buildEmailHtml without calendar links omits buttons", () => {
  const html = buildEmailHtml("Cancelled", "A game was cancelled.");
  assert(!html.includes("Add this game to your calendar"));
});
