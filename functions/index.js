const admin = require("firebase-admin");
const { onRequest } = require("firebase-functions/v2/https");

admin.initializeApp();

exports.createOpenAIRealtimeSession = onRequest(
  {
    cors: false,
    region: "us-central1",
    memory: "256MiB",
    timeoutSeconds: 30,
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: { message: "Method not allowed" } });
      return;
    }

    const authHeader = req.get("Authorization") || "";
    if (!authHeader.startsWith("Bearer ")) {
      res.status(401).json({ error: { message: "Missing Firebase bearer token" } });
      return;
    }

    const firebaseToken = authHeader.slice("Bearer ".length).trim();
    try {
      await admin.auth().verifyIdToken(firebaseToken);
    } catch (error) {
      res.status(401).json({ error: { message: "Invalid Firebase token" } });
      return;
    }

    const openAIKey = process.env.OPENAI_API_KEY;
    if (!openAIKey) {
      res.status(500).json({ error: { message: "OPENAI_API_KEY is not configured" } });
      return;
    }

    const body = req.body && typeof req.body === "object" ? req.body : {};
    const model = typeof body.model === "string" && body.model ? body.model : "gpt-realtime";
    const voice = typeof body.voice === "string" && body.voice ? body.voice : "cedar";
    const language = typeof body.language === "string" && body.language ? body.language : "ru";

    const sessionPayload = {
      session: {
        type: "realtime",
        model,
        voice,
        modalities: ["audio"],
        input_audio_format: "pcm16",
        output_audio_format: "pcm16",
        input_audio_noise_reduction: { type: "near_field" },
        input_audio_transcription: {
          model: "gpt-4o-transcribe",
          language,
        },
      },
    };

    const response = await fetch("https://api.openai.com/v1/realtime/client_secrets", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${openAIKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(sessionPayload),
    });

    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      const message =
        data?.error?.message ||
        data?.message ||
        `OpenAI session creation failed with HTTP ${response.status}`;
      res.status(response.status).json({ error: { message } });
      return;
    }

    const clientSecret = data?.client_secret?.value;
    const expiresAt = data?.client_secret?.expires_at;
    if (!clientSecret || !expiresAt) {
      res.status(502).json({ error: { message: "OpenAI response did not include a client secret" } });
      return;
    }

    res.status(200).json({
      client_secret: clientSecret,
      expires_at: expiresAt,
      model,
    });
  }
);
