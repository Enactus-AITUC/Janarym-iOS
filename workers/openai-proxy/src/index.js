function jsonError(message, status = 500) {
  return Response.json({ error: { message } }, { status });
}

function readOutputText(data) {
  if (typeof data?.output_text === "string" && data.output_text) {
    return data.output_text;
  }

  const parts = data?.output ?? [];
  const texts = [];
  for (const item of parts) {
    for (const content of item?.content ?? []) {
      if (content?.type === "output_text" && typeof content.text === "string") {
        texts.push(content.text);
      }
    }
  }
  return texts.join(" ").trim();
}

function bytesToBase64(bytes) {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

async function transcribeAudio({ audioFile, language, model, apiKey }) {
  const form = new FormData();
  form.append("file", audioFile, audioFile.name || "speech.m4a");
  form.append("model", model);
  form.append("language", language);

  const response = await fetch("https://api.openai.com/v1/audio/transcriptions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
    },
    body: form,
  });

  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(data?.error?.message || `Transcription failed with HTTP ${response.status}`);
  }

  return typeof data?.text === "string" ? data.text.trim() : "";
}

async function generateAnswer({ transcript, imageBase64, prompt, responseModel, apiKey }) {
  const content = [{ type: "input_text", text: transcript }];

  if (imageBase64) {
    content.push({
      type: "input_image",
      image_url: `data:image/jpeg;base64,${imageBase64}`,
    });
  }

  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: responseModel,
      instructions: prompt,
      max_output_tokens: 220,
      input: [{ role: "user", content }],
    }),
  });

  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(data?.error?.message || `Response generation failed with HTTP ${response.status}`);
  }

  const text = readOutputText(data);
  if (!text) {
    throw new Error("OpenAI response did not include output text");
  }

  return text;
}

async function synthesizeSpeech({ text, voice, ttsModel, apiKey }) {
  const response = await fetch("https://api.openai.com/v1/audio/speech", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: ttsModel,
      voice,
      response_format: "mp3",
      input: text,
    }),
  });

  if (!response.ok) {
    const data = await response.json().catch(() => ({}));
    throw new Error(data?.error?.message || `Speech synthesis failed with HTTP ${response.status}`);
  }

  const bytes = new Uint8Array(await response.arrayBuffer());
  return bytesToBase64(bytes);
}

export default {
  async fetch(request, env) {
    if (request.method !== "POST") {
      return jsonError("Method not allowed", 405);
    }

    if (!env.OPENAI_API_KEY) {
      return jsonError("OPENAI_API_KEY is not configured", 500);
    }

    try {
      const form = await request.formData();
      const audioFile = form.get("audio");
      const imageFile = form.get("image");

      if (!(audioFile instanceof File)) {
        return jsonError("Missing audio file", 400);
      }

      const language = String(form.get("language") || "ru");
      const voice = String(form.get("voice") || "cedar");
      const prompt = String(form.get("prompt") || "");
      const transcriptionModel = String(form.get("transcription_model") || "gpt-4o-transcribe");
      const responseModel = String(form.get("response_model") || "gpt-4.1-mini");
      const ttsModel = String(form.get("tts_model") || "gpt-4o-mini-tts");

      const transcript = await transcribeAudio({
        audioFile,
        language,
        model: transcriptionModel,
        apiKey: env.OPENAI_API_KEY,
      });
      if (!transcript) {
        return jsonError("Transcription is empty", 422);
      }

      let imageBase64 = "";
      if (imageFile instanceof File) {
        const imageBytes = new Uint8Array(await imageFile.arrayBuffer());
        imageBase64 = bytesToBase64(imageBytes);
      }

      const responseText = await generateAnswer({
        transcript,
        imageBase64,
        prompt,
        responseModel,
        apiKey: env.OPENAI_API_KEY,
      });

      const audioBase64 = await synthesizeSpeech({
        text: responseText,
        voice,
        ttsModel,
        apiKey: env.OPENAI_API_KEY,
      });

      return Response.json({
        transcript,
        response_text: responseText,
        audio_base64: audioBase64,
        audio_mime_type: "audio/mpeg",
      });
    } catch (error) {
      return jsonError(error instanceof Error ? error.message : "Unknown proxy error", 500);
    }
  },
};
