# Supabase Email Notifications Research

## Scope
Email notifications for this app (booking created/cancelled/reminders), using Supabase-native components.

## Primary Sources
- Send emails from Edge Functions (Resend):
  - https://supabase.com/docs/guides/functions/examples/send-emails
- Auth email templates:
  - https://supabase.com/docs/guides/auth/auth-email-templates
- Send Email Hook (custom provider for auth mail):
  - https://supabase.com/docs/guides/auth/auth-hooks/send-email-hook

## Option A (Recommended): Edge Function + External Email API (Resend/SendGrid)

## Verified docs pattern (Resend)
From Supabase guide:
```bash
supabase functions new resend
```

```ts
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY')

const handler = async (_request: Request): Promise<Response> => {
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${RESEND_API_KEY}`,
    },
    body: JSON.stringify({
      from: 'onboarding@resend.dev',
      to: 'delivered@resend.dev',
      subject: 'hello world',
      html: '<strong>it works!</strong>',
    }),
  })

  const data = await res.json()

  return new Response(JSON.stringify(data), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  })
}

Deno.serve(handler)
```

## Deploy pattern from docs
```bash
supabase start
supabase functions serve --no-verify-jwt --env-file .env
supabase functions deploy resend --no-verify-jwt
```

## How this maps to pickleball app
- Trigger source: booking insert/update/cancel events.
- Trigger mechanism: DB trigger -> `notifications` row, or DB webhook -> Edge Function.
- Edge Function composes booking email and calls provider API.
- Persist delivery result in `notifications` table (`pending` -> `sent`/`failed`).

## SendGrid adaptation
Supabase guide is Resend-specific, but architecture is identical for SendGrid:
- Keep API key in Edge Function secrets.
- Call SendGrid REST API from function.
- Preserve same retry/logging model.

## Option B: Supabase Auth Email Templates (Auth Events)

This is best for:
- signup confirmation
- password reset
- magic link
- security notifications

Not ideal for booking business events by itself.

### Verified template variables
From `auth-email-templates` docs, available template fields include:
- `{{ .ConfirmationURL }}`
- `{{ .Token }}`
- `{{ .TokenHash }}`
- `{{ .SiteURL }}`
- `{{ .RedirectTo }}`
- `{{ .Data }}`

### Management API pattern (docs)
```bash
curl -X PATCH "https://api.supabase.com/v1/projects/$PROJECT_REF/config/auth" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{ ...mailer_templates... }'
```

## Option C: Send Email Hook (Replace Supabase Auth Sender)

Use when you want your own provider for auth emails too.

From docs:
- Send Email Hook replaces built-in auth email sending.
- Hook payload includes `user` + `email_data` (token, redirect, action type, etc.).

This is useful if you want one provider stack for both:
- Auth emails
- Booking emails

## Recommended Implementation for This App
1. Keep Supabase Auth templates for signup/reset baseline.
2. Implement booking emails via Edge Function + provider API (Resend first).
3. Store outbound attempts/results in `notifications` for observability.
4. Add retry strategy (e.g., scheduled retry for transient failures).

## Practical Gotchas (from docs + implementation constraints)
- Store provider keys in Supabase Function Secrets, not source files.
- If auth email links are pre-fetched by email clients, token links can be consumed early; templates docs recommend OTP or custom confirmation links in this case.
- Disable tracking/link rewriting at provider level if it breaks confirmation links.
