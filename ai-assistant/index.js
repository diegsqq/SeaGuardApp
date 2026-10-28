"use strict";
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");
const MODEL = "gemini-1.5-flash";

function geminiUrl(model) {
  return `https://generativelanguage.googleapis.com/v1/models/${model}:generateContent`;
}

exports.askGeminiCallable = onCall({ secrets: [GEMINI_API_KEY] }, async (request) => {
  const data = request.data || {};
  const prompt = String(data.prompt || "").trim();
  const context = String(data.context || "").trim();

  if (!prompt) {
    throw new HttpsError("invalid-argument", "Missing prompt.");
  }

  const systemStyle =
    "You are a helpful marine biology assistant for a fish identification app. " +
    "Answer clearly in simple terms. If unsure, say you are unsure. " +
    "Do not invent scientific facts.";

  const fullPrompt =
    `${systemStyle}\n\n` +
    (context ? `Fish details:\n${context}\n\n` : "") +
    `User question: ${prompt}`;

  const res = await fetch(geminiUrl(MODEL), {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-goog-api-key": GEMINI_API_KEY.value(),
    },
    body: JSON.stringify({
      contents: [
        {
          role: "user",
          parts: [{ text: fullPrompt }],
        },
      ],
    }),
  });

  const raw = await res.text();
  if (!res.ok) {
    throw new HttpsError("internal", `Gemini error ${res.status}: ${raw}`);
  }

  const json = JSON.parse(raw);
  const parts = json?.candidates?.[0]?.content?.parts || [];
  const answer =
    parts.map((p) => p.text || "").join("").trim() || "No response.";

  // 👇 PROOF for debugging
  return {
    answer,
    modelUsed: MODEL,
    function: "askGeminiCallable",
  };
});
