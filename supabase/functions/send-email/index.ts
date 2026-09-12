import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const RESEND_API_KEY = Deno.env.get("9f837ac2843340e08318d2108f46a93d79e4fc392b49d440fad4b90d0f627097")!;

serve(async (req) => {
  try {
    const { email, code } = await req.json();

    const resp = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: "no-reply@yourverifieddomain.com",
        to: email,
        subject: "كود التحقق",
        html: `<p>رمز التحقق الخاص بك هو: <b>${code}</b></p>`,
      }),
    });

    if (!resp.ok) {
      const err = await resp.text();
      return new Response(
        JSON.stringify({ error: err }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    return new Response(
      JSON.stringify({ success: true }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(
      JSON.stringify({ error: e.message }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
