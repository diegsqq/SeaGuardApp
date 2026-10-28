const functions = require('firebase-functions');
const admin = require('firebase-admin');
const fetch = (...args) => import('node-fetch').then(({ default: f }) => f(...args));

admin.initializeApp();

const jsonResponse = (res, status, payload) => res.status(status).json(payload);
const sanitizePhone = (phone) => (phone || '').toString().replace(/\s+/g, '');

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const handleCors = (req, res) => {
  res.set(corsHeaders);
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return true;
  }
  return false;
};

const safeTrim = (value, fallback = '') => {
  if (value === null || value === undefined) return fallback;
  return value.toString().trim() || fallback;
};

const fakeDecisionKeywords = [
  'fake',
  'invalid',
  'false',
  'fraud',
  'fraudulent',
];

const isFakeDecision = (data = {}) => {
  const combined = [
    data.status,
    data.actionStatus,
    data.decision,
    data.reviewStatus,
    data.moderationStatus,
    data.validationStatus,
  ]
    .map((value) => safeTrim(value).toLowerCase())
    .filter(Boolean)
    .join(' ');

  return fakeDecisionKeywords.some((keyword) => combined.includes(keyword));
};

const firstText = (data = {}, keys = [], fallback = '') => {
  for (const key of keys) {
    const value = safeTrim(data[key]);
    if (value) return value;
  }
  return fallback;
};

const lastUserMessage = (history = []) => {
  if (!Array.isArray(history)) return '';
  for (let i = history.length - 1; i >= 0; i -= 1) {
    const item = history[i];
    if (item && item.role === 'user' && item.content) {
      const text = item.content.toString().trim();
      if (text) return text;
    }
  }
  return '';
};

const bulletList = (items = []) =>
  items
    .filter((item) => safeTrim(item))
    .map((item) => `- ${safeTrim(item)}`)
    .join('\n');

const containsAny = (text, keywords = []) =>
  keywords.some((keyword) => safeTrim(keyword) && text.includes(keyword));

const inferMarineGroup = ({ name = '', scientificName = '', family = '', description = '', shareText = '' }) => {
  const combined = [name, scientificName, family, description, shareText]
    .filter((item) => safeTrim(item))
    .join(' ')
    .toLowerCase();

  const rayKeywords = [
    'ray',
    'stingray',
    'manta',
    'mobula',
    'eagle ray',
    'sawfish',
    'rajidae',
    'dasyatidae',
    'mobulidae',
    'myliobatidae',
    'pristidae',
    'rhinopteridae',
    'torpedinidae',
    'narcinidae',
  ];
  if (containsAny(combined, rayKeywords)) return 'ray';

  const sharkKeywords = [
    'shark',
    'thresher',
    'hammerhead',
    'mako',
    'dogfish',
    'catshark',
    'wobbegong',
    'nurse shark',
    'whale shark',
    'angel shark',
    'bull shark',
    'tiger shark',
    'reef shark',
    'basking shark',
    'alopias',
    'isurus',
    'lamna',
    'carcharhin',
    'sphyrna',
    'rhincodon',
    'orectolobus',
    'squalus',
    'alopiidae',
    'carcharhinidae',
    'lamnidae',
    'sphyrnidae',
    'rhincodontidae',
    'squalidae',
    'scyliorhinidae',
    'orectolobidae',
    'hexanchidae',
    'ginglymostomatidae',
    'hemiscylliidae',
    'heterodontidae',
  ];
  if (containsAny(combined, sharkKeywords)) return 'shark';

  return 'fish';
};

const buildAssistantAnswer = (question, history = []) => {
  const q = safeTrim(question) || lastUserMessage(history) || 'your topic';
  const lower = q.toLowerCase();

  const isEating = lower.includes('eat') || lower.includes('edible') || lower.includes('safe to eat');
  const isFishingSafety = lower.includes('safe') && (lower.includes('fish') || lower.includes('fishing'));
  const isWeather = lower.includes('weather') || lower.includes('wind') || lower.includes('wave') || lower.includes('tide');
  const wantsWhere = lower.includes('where') || lower.includes('location');

  const quick = [];
  if (isEating) {
    quick.push('Eating: favor smaller, fast-growing fish; clear eyes, firm flesh, clean smell; keep on ice.');
  }
  if (isFishingSafety || isWeather) {
    quick.push('On-water safety: winds under ~20 km/h, waves under ~1.5 m, avoid lightning/poor visibility.');
  }
  if (wantsWhere) {
    quick.push('Where to fish: pick sheltered spots with good visibility; avoid sewage outlets and recent algal blooms.');
  }
  if (quick.length === 0) {
    quick.push('Tip: share fish name + location + concern (eat/safety) for a sharper answer.');
  }

  const safety = [];
  safety.push('Check local advisories/bans before catching or eating.');
  safety.push("Wear a PFD, file a float plan, and don't fish alone in bad weather.");
  safety.push('Skip trips during lightning, very strong winds, or murky water with strong smell.');

  const handling = [];
  handling.push('For eating: gut, bleed, and chill quickly; cook to 63C/145F internal; trim dark/red meat to reduce contaminants.');
  handling.push('For reef fish in hot months, be cautious of ciguatera; avoid if there were recent blooms or fish kills.');

  const sections = [
    `Here's a quick answer for "${q}":`,
    bulletList(quick),
    '\nSafety checks:',
    bulletList(safety),
    '\nHandling & quality:',
    bulletList(handling),
    '\nWant better guidance? Add fish name, size, and your location.',
  ];

  return sections.filter(Boolean).join('\n');
};

const buildFishAnswer = (payload = {}) => {
  const name = safeTrim(payload.englishName, 'this fish');
  const sci = safeTrim(payload.scientificName);
  const family = safeTrim(payload.family);
  const question = safeTrim(payload.question);
  const habitat = safeTrim(payload.habitat);
  const diet = safeTrim(payload.diet);
  const culinary = safeTrim(payload.culinary);
  const description = safeTrim(payload.description);
  const imageUrl = safeTrim(payload.imageUrl);
  const shareText = safeTrim(payload.shareText);

  const qLower = question.toLowerCase();
  const wantEat =
    qLower.includes('eat') || qLower.includes('edible') || qLower.includes('safe to eat');
  const wantHandle = qLower.includes('handle') || qLower.includes('prepare') || qLower.includes('cook');
  const wantBrief = qLower.includes('brief') || qLower.includes('summary') || qLower.includes('guide');
  const wantProtection = containsAny(qLower, [
    'endangered',
    'protected',
    'illegal',
    'conservation',
    'can i keep',
    'can we keep',
    'can i sell',
    'can we sell',
  ]);
  const asksIdentity = containsAny(qLower, [
    'what is this',
    'what is it',
    'what fish is this',
    'what species is this',
    'what species is it',
    'fish or shark',
    'shark or fish',
    'is this a shark',
    'is it a shark',
    'is this shark',
    'is it shark',
    'is this a fish',
    'is it a fish',
    'is this fish',
    'is it fish',
  ]);
  const marineGroup = inferMarineGroup({
    name,
    scientificName: sci,
    family,
    description,
    shareText,
  });

  if (asksIdentity && !wantEat && !wantHandle && !wantProtection && !wantBrief) {
    const speciesLine = sci ? `This appears to be ${name} (${sci}).` : `This appears to be ${name}.`;
    if (marineGroup === 'shark') {
      return `${speciesLine} It is a shark. Sharks are fish, so "shark" is the more precise answer.`;
    }
    if (marineGroup === 'ray') {
      return `${speciesLine} It is a ray, not a shark. Rays are fish and are closely related to sharks.`;
    }
    return `${speciesLine} It is a fish, not a shark.`;
  }

  if (wantProtection && !wantEat && !wantHandle && !wantBrief) {
    const riskNote =
      marineGroup === 'shark' || marineGroup === 'ray'
        ? 'Many sharks and rays have catch, landing, or size restrictions.'
        : 'Protection rules can still vary by species, size, season, and location.';
    return `${name} protection status cannot be confirmed from fallback data alone. ${riskNote} Check BFAR, DENR, and your local fishery rules before keeping, landing, or selling it.`;
  }

  const header = `Here's a concise guide on ${name}${sci ? ` (${sci})` : ''}:`;

  const profile = bulletList([
    description && description.length > 12 ? description : '',
    habitat ? `Habitat: ${habitat}` : '',
    diet ? `Diet: ${diet}` : '',
    culinary ? `Culinary: ${culinary}` : '',
  ]);

  const eating = bulletList([
    wantEat || wantHandle ? 'Eating safety: favor smaller fish; avoid if recent sewage spills, algal blooms, or fish kills.' : '',
    'Quality checks: clear eyes, firm flesh, clean smell; chill immediately after catch.',
    'Prep: gut, bleed, and keep on ice; cook to 63C/145F internal; trim dark/red meat to reduce contaminants.',
  ]);

  const fishing = bulletList([
    'Trip safety: aim for winds <~20 km/h, waves <~1.5 m; avoid lightning and poor visibility.',
    'If waters are murky with strong odor, skip harvesting until conditions improve.',
  ]);

  const extras = bulletList([
    imageUrl ? `Image reference: ${imageUrl}` : '',
    shareText ? `Summary: ${shareText}` : '',
  ]);

  const parts = [
    header,
    profile ? `\nProfile:\n${profile}` : '',
    `\nEating & handling:\n${eating}`,
    `\nFishing & conditions:\n${fishing}`,
    extras ? `\nRefs:\n${extras}` : '',
    question ? `\nYour question: ${question}` : '',
  ];

  return parts.filter((p) => safeTrim(p)).join('\n');
};

const getOpenAiKey = () => {
  const envKey = safeTrim(process.env.OPENAI_API_KEY);
  if (envKey) return envKey;
  try {
    const cfg = functions.config().openai || {};
    if (cfg.key) return safeTrim(cfg.key);
  } catch (_) {
    // ignore if not set
  }
  return '';
};

const getOpenAiModel = () => {
  const envModel = safeTrim(process.env.OPENAI_MODEL);
  if (envModel) return envModel;
  try {
    const cfg = functions.config().openai || {};
    if (cfg.model) return safeTrim(cfg.model);
  } catch (_) {
    // ignore if not set
  }
  return 'gpt-4o-mini';
};

const getOpenAiVisionModel = () => {
  const envModel = safeTrim(process.env.OPENAI_VISION_MODEL);
  if (envModel) return envModel;
  try {
    const cfg = functions.config().openai || {};
    if (cfg.vision_model) return safeTrim(cfg.vision_model);
  } catch (_) {
    // ignore if not set
  }
  return 'gpt-4o-mini';
};

const getOpenAiImageModel = () => {
  const envModel = safeTrim(process.env.OPENAI_IMAGE_MODEL);
  if (envModel) return envModel;
  try {
    const cfg = functions.config().openai || {};
    if (cfg.image_model) return safeTrim(cfg.image_model);
  } catch (_) {
    // ignore if not set
  }
  return 'gpt-image-1';
};

const getGeminiKey = () => {
  const envKey = safeTrim(process.env.GEMINI_API_KEY);
  if (envKey) return envKey;
  try {
    const cfg = functions.config().gemini || {};
    if (cfg.key) return safeTrim(cfg.key);
  } catch (_) {
    // ignore if not set
  }
  return '';
};

const getGeminiTextModel = () => {
  const envModel = safeTrim(process.env.GEMINI_TEXT_MODEL);
  if (envModel) return envModel;
  try {
    const cfg = functions.config().gemini || {};
    if (cfg.text_model) return safeTrim(cfg.text_model);
  } catch (_) {
    // ignore if not set
  }
  return 'gemini-1.5-flash';
};

const getGeminiVisionModel = () => {
  const envModel = safeTrim(process.env.GEMINI_VISION_MODEL);
  if (envModel) return envModel;
  try {
    const cfg = functions.config().gemini || {};
    if (cfg.vision_model) return safeTrim(cfg.vision_model);
  } catch (_) {
    // ignore if not set
  }
  return getGeminiTextModel();
};

const normalizeGeminiModelPath = (model) => {
  const cleaned = safeTrim(model);
  if (!cleaned) return 'models/gemini-1.5-flash';
  return cleaned.startsWith('models/') ? cleaned : `models/${cleaned}`;
};

const geminiGenerateContentUrl = (model, apiKey) =>
  `https://generativelanguage.googleapis.com/v1beta/${normalizeGeminiModelPath(model)}:generateContent?key=${encodeURIComponent(apiKey)}`;

const getVertexProjectId = () => {
  const explicit = safeTrim(
    process.env.GOOGLE_CLOUD_PROJECT || process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT,
  );
  if (explicit) return explicit;

  try {
    const appProject = safeTrim(admin.app().options.projectId);
    if (appProject) return appProject;
  } catch (_) {
    // ignore
  }

  return '';
};

const getVertexLocation = () => {
  const envLocation = safeTrim(process.env.VERTEX_LOCATION);
  if (envLocation) return envLocation;
  try {
    const cfg = functions.config().vertex || {};
    if (cfg.location) return safeTrim(cfg.location);
  } catch (_) {
    // ignore if not set
  }
  return 'us-central1';
};

const getVertexImagenModel = () => {
  const envModel = safeTrim(process.env.VERTEX_IMAGEN_MODEL);
  if (envModel) return envModel;
  try {
    const cfg = functions.config().vertex || {};
    if (cfg.imagen_model) return safeTrim(cfg.imagen_model);
  } catch (_) {
    // ignore if not set
  }
  return 'imagen-4.0-fast-generate-001';
};

let _vertexToken = '';
let _vertexTokenExpiryMs = 0;

const getVertexAccessToken = async () => {
  const now = Date.now();
  if (_vertexToken && _vertexTokenExpiryMs > now + 30 * 1000) {
    return _vertexToken;
  }

  const tokenInfo = await admin.credential.applicationDefault().getAccessToken();
  const token = safeTrim(tokenInfo && tokenInfo.access_token);
  if (!token) {
    throw new Error('Unable to obtain GCP access token for Vertex AI');
  }

  const expiresIn = Number(tokenInfo && tokenInfo.expires_in);
  const ttlMs = Number.isFinite(expiresIn) && expiresIn > 0 ? expiresIn * 1000 : 4 * 60 * 1000;
  _vertexToken = token;
  _vertexTokenExpiryMs = now + ttlMs;
  return token;
};

const buildFishIllustrationPrompt = (payload = {}) => {
  const englishName = safeTrim(payload.englishName, 'a marine fish');
  const scientificName = safeTrim(payload.scientificName);
  const habitat = safeTrim(payload.habitat);
  const localName = safeTrim(payload.localName);
  const description = safeTrim(payload.description);
  const requestedStyle = safeTrim(payload.style, 'underwater natural-history illustration');

  const identity = [englishName, scientificName ? `(${scientificName})` : ''].filter(Boolean).join(' ');
  const details = [
    habitat ? `Natural habitat: ${habitat}.` : '',
    localName ? `Also known locally as ${localName}.` : '',
    description ? `Distinctive traits: ${description}.` : '',
  ]
    .filter(Boolean)
    .join(' ');

  return [
    `Create a ${requestedStyle} of ${identity}.`,
    'Focus on realistic fish anatomy, accurate proportions, and ocean context.',
    details,
    'No people, no text, no logos, no watermark, no frame.',
    'Single-subject composition, high detail, soft natural lighting.',
  ]
    .filter(Boolean)
    .join(' ');
};

const callVertexImagen = async ({ prompt, negativePrompt = '' }) => {
  const projectId = getVertexProjectId();
  if (!projectId) {
    throw new Error('Missing project id for Vertex AI');
  }

  const location = getVertexLocation();
  const model = getVertexImagenModel();
  const token = await getVertexAccessToken();
  const endpoint =
    `https://${location}-aiplatform.googleapis.com/v1/projects/${projectId}/locations/${location}` +
    `/publishers/google/models/${model}:predict`;

  const body = {
    instances: [{ prompt: safeTrim(prompt) }],
    parameters: {
      sampleCount: 1,
      outputOptions: {
        mimeType: 'image/jpeg',
        compressionQuality: 78,
      },
    },
  };

  const cleanedNegative = safeTrim(negativePrompt);
  if (cleanedNegative) {
    body.parameters.negativePrompt = cleanedNegative;
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 30000);
  try {
    const resp = await fetch(endpoint, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });

    const raw = await resp.text();
    let data;
    try {
      data = JSON.parse(raw);
    } catch (_) {
      data = { raw };
    }

    if (!resp.ok) {
      throw new Error(`Vertex Imagen HTTP ${resp.status}: ${JSON.stringify(data)}`);
    }

    const prediction = Array.isArray(data.predictions) ? data.predictions[0] : null;
    const imageBase64 = safeTrim(prediction && prediction.bytesBase64Encoded);
    const mimeType = safeTrim(prediction && prediction.mimeType, 'image/jpeg');

    if (!imageBase64) {
      throw new Error(`Vertex Imagen returned no image bytes: ${JSON.stringify(data)}`);
    }

    return {
      imageBase64,
      mimeType,
      model,
      location,
    };
  } finally {
    clearTimeout(timeout);
  }
};

const callOpenAi = async ({ question, history = [], systemPrompt, temperature = 0.6, maxTokens = 360 }) => {
  const apiKey = getOpenAiKey();
  if (!apiKey) return null;

  const messages = [];
  if (systemPrompt) {
    messages.push({ role: 'system', content: systemPrompt });
  }

  const trimmedHistory = Array.isArray(history) ? history.slice(-6) : [];
  for (const item of trimmedHistory) {
    if (item && item.role && item.content) {
      messages.push({ role: item.role, content: safeTrim(item.content) });
    }
  }

  messages.push({ role: 'user', content: safeTrim(question) });

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 15000);
  try {
    const resp = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: getOpenAiModel(),
        temperature,
        max_tokens: maxTokens,
        messages,
      }),
      signal: controller.signal,
    });

    const text = await resp.text();
    let data;
    try {
      data = JSON.parse(text);
    } catch (_) {
      data = { raw: text };
    }

    if (!resp.ok) {
      functions.logger.warn('OpenAI call failed', { status: resp.status, data });
      return null;
    }

    const choice = data.choices && data.choices[0];
    const answer = choice && choice.message && choice.message.content;
    if (answer && safeTrim(answer)) return safeTrim(answer);
    return null;
  } catch (e) {
    functions.logger.warn('OpenAI call error', e);
    return null;
  } finally {
    clearTimeout(timeout);
  }
};

const callGeminiText = async ({
  question,
  history = [],
  systemPrompt,
  temperature = 0.6,
  maxTokens = 360,
}) => {
  const apiKey = getGeminiKey();
  if (!apiKey) return null;

  const contents = [];
  const trimmedHistory = Array.isArray(history) ? history.slice(-6) : [];
  for (const item of trimmedHistory) {
    const role = safeTrim(item && item.role).toLowerCase();
    const content = safeTrim(item && item.content);
    if (!content) continue;
    contents.push({
      role: role === 'user' ? 'user' : 'model',
      parts: [{ text: content }],
    });
  }

  contents.push({
    role: 'user',
    parts: [{ text: safeTrim(question) }],
  });

  const body = {
    contents,
    generationConfig: {
      temperature,
      maxOutputTokens: maxTokens,
    },
  };
  if (safeTrim(systemPrompt)) {
    body.systemInstruction = { parts: [{ text: safeTrim(systemPrompt) }] };
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 15000);
  try {
    const resp = await fetch(
      geminiGenerateContentUrl(getGeminiTextModel(), apiKey),
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
        signal: controller.signal,
      },
    );

    const text = await resp.text();
    let data;
    try {
      data = JSON.parse(text);
    } catch (_) {
      data = { raw: text };
    }

    if (!resp.ok) {
      functions.logger.warn('Gemini text call failed', { status: resp.status, data });
      return null;
    }

    const candidates = Array.isArray(data.candidates) ? data.candidates : [];
    for (const candidate of candidates) {
      const parts = candidate?.content?.parts;
      if (!Array.isArray(parts)) continue;
      const joined = parts
        .map((p) => safeTrim(p && p.text))
        .filter(Boolean)
        .join('\n')
        .trim();
      if (joined) return joined;
    }
    return null;
  } catch (e) {
    functions.logger.warn('Gemini text call error', e);
    return null;
  } finally {
    clearTimeout(timeout);
  }
};

const normalizeName = (value) =>
  safeTrim(value)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();

const bestCandidateMatch = (rawSpecies, candidates = []) => {
  const speciesNorm = normalizeName(rawSpecies);
  if (!speciesNorm || !Array.isArray(candidates) || !candidates.length) return '';

  let exact = '';
  for (const candidate of candidates) {
    const cNorm = normalizeName(candidate);
    if (!cNorm) continue;
    if (cNorm === speciesNorm) {
      exact = safeTrim(candidate);
      break;
    }
  }
  if (exact) return exact;

  const speciesTokens = new Set(speciesNorm.split(' ').filter((t) => t.length >= 3));
  if (!speciesTokens.size) return '';

  let best = '';
  let bestScore = 0;
  for (const candidate of candidates) {
    const cleaned = safeTrim(candidate);
    const cNorm = normalizeName(cleaned);
    if (!cNorm) continue;
    const cTokens = new Set(cNorm.split(' ').filter((t) => t.length >= 3));
    if (!cTokens.size) continue;

    let overlap = 0;
    for (const token of cTokens) {
      if (speciesTokens.has(token)) overlap += 1;
    }
    if (!overlap) continue;

    const score = overlap / cTokens.size;
    if (score > bestScore) {
      bestScore = score;
      best = cleaned;
    }
  }

  return bestScore >= 0.5 ? best : '';
};

const parseJsonSafe = (text) => {
  const raw = safeTrim(text);
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch (_) {
    const first = raw.indexOf('{');
    const last = raw.lastIndexOf('}');
    if (first >= 0 && last > first) {
      try {
        return JSON.parse(raw.slice(first, last + 1));
      } catch (_) {
        return null;
      }
    }
    return null;
  }
};

const callOpenAiFishVision = async ({
  imageDataUrl,
  extraImageDataUrls = [],
  candidateSpecies = [],
  localHints = [],
}) => {
  const apiKey = getOpenAiKey();
  const imageUrl = safeTrim(imageDataUrl);
  if (!apiKey || !imageUrl) return null;

  const candidates = Array.isArray(candidateSpecies)
    ? candidateSpecies.map((c) => safeTrim(c)).filter(Boolean).slice(0, 120)
    : [];
  const hints = Array.isArray(localHints)
    ? localHints
        .map((hint) => {
          const label = safeTrim(hint?.label || hint?.species);
          const confidence = Number(hint?.confidence);
          if (!label) return '';
          if (Number.isFinite(confidence)) return `${label} (${confidence.toFixed(2)})`;
          return label;
        })
        .filter(Boolean)
        .slice(0, 5)
    : [];
  const candidateBlock = candidates.length
    ? candidates.join(', ')
    : 'No candidate list provided.';
  const hintBlock = hints.length ? hints.join(', ') : 'No local hints provided.';

  const systemPrompt =
    'You are a fish species identifier for a marine app. You may receive multiple images of the same fish. Return strict JSON only.';
  const userPrompt = [
    'Identify the fish species in this image set.',
    'You may receive a full photo plus tighter crops of the same fish.',
    'Prefer scientific species names.',
    'Use body shape, fin layout, tail shape, head profile, mouth position, and color pattern.',
    'Only return a species when the visual evidence is strong and consistent across the images.',
    'Treat local hints as weak hints only. Ignore them when the images disagree.',
    'If candidate species are provided, choose the single best match from that list.',
    'If uncertain or not a fish, set species to "Unknown sea creature".',
    'Return JSON with exactly: {"species":"...", "confidence":0-1, "reason":"short"}',
    `Candidates: ${candidateBlock}`,
    `Local hints: ${hintBlock}`,
  ].join('\n');

  const extraImages = Array.isArray(extraImageDataUrls)
    ? extraImageDataUrls.map((url) => safeTrim(url)).filter(Boolean).slice(0, 2)
    : [];
  const content = [
    { type: 'text', text: userPrompt },
    { type: 'image_url', image_url: { url: imageUrl } },
    ...extraImages.map((url) => ({ type: 'image_url', image_url: { url } })),
  ];

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 22000);
  try {
    const resp = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: getOpenAiVisionModel(),
        temperature: 0.1,
        max_tokens: 220,
        response_format: { type: 'json_object' },
        messages: [
          { role: 'system', content: systemPrompt },
          {
            role: 'user',
            content,
          },
        ],
      }),
      signal: controller.signal,
    });

    const raw = await resp.text();
    let data;
    try {
      data = JSON.parse(raw);
    } catch (_) {
      data = { raw };
    }
    if (!resp.ok) {
      functions.logger.warn('OpenAI fish vision failed', { status: resp.status, data });
      return null;
    }

    const choice = data.choices && data.choices[0];
    const text = choice && choice.message && choice.message.content;
    const parsed = parseJsonSafe(text);
    if (!parsed || typeof parsed !== 'object') return null;

    const rawSpecies = safeTrim(parsed.species || parsed.label || parsed.scientificName);
    const confidenceRaw = Number(parsed.confidence);
    const boundedConfidence = Number.isFinite(confidenceRaw)
      ? Math.max(0, Math.min(1, confidenceRaw))
      : 0.35;

    if (!rawSpecies) return null;
    if (rawSpecies.toLowerCase().startsWith('unknown')) {
      return { species: 'Unknown sea creature', confidence: boundedConfidence };
    }

    const matched = bestCandidateMatch(rawSpecies, candidates);
    if (candidates.length && !matched) {
      return { species: 'Unknown sea creature', confidence: boundedConfidence };
    }
    const species = matched || rawSpecies;
    return { species, confidence: boundedConfidence };
  } catch (e) {
    functions.logger.warn('OpenAI fish vision error', e);
    return null;
  } finally {
    clearTimeout(timeout);
  }
};

const callGeminiFishVision = async ({
  imageBase64,
  mimeType = 'image/jpeg',
  additionalImagesBase64 = [],
  candidateSpecies = [],
  localHints = [],
}) => {
  const apiKey = getGeminiKey();
  const imageData = safeTrim(imageBase64);
  if (!apiKey || !imageData) return null;

  const candidates = Array.isArray(candidateSpecies)
    ? candidateSpecies.map((c) => safeTrim(c)).filter(Boolean).slice(0, 120)
    : [];
  const hints = Array.isArray(localHints)
    ? localHints
        .map((hint) => {
          const label = safeTrim(hint?.label || hint?.species);
          const confidence = Number(hint?.confidence);
          if (!label) return '';
          if (Number.isFinite(confidence)) return `${label} (${confidence.toFixed(2)})`;
          return label;
        })
        .filter(Boolean)
        .slice(0, 5)
    : [];
  const candidateBlock = candidates.length
    ? candidates.join(', ')
    : 'No candidate list provided.';
  const hintBlock = hints.length ? hints.join(', ') : 'No local hints provided.';

  const userPrompt = [
    'Identify the fish species in this image set.',
    'You may receive a full photo plus tighter crops of the same fish.',
    'Prefer scientific species names.',
    'Use body shape, fin layout, tail shape, head profile, mouth position, and color pattern.',
    'Only return a species when the visual evidence is strong and consistent across the images.',
    'Treat local hints as weak hints only. Ignore them when the images disagree.',
    'If candidate species are provided, choose exactly one best match from that list.',
    'If uncertain or not a fish, return "Unknown sea creature".',
    'Return JSON only with: {"species":"...", "confidence":0-1, "reason":"short"}',
    `Candidates: ${candidateBlock}`,
    `Local hints: ${hintBlock}`,
  ].join('\n');

  const extraImages = Array.isArray(additionalImagesBase64)
    ? additionalImagesBase64.map((item) => safeTrim(item)).filter(Boolean).slice(0, 2)
    : [];
  const imageParts = [
    { inlineData: { mimeType: safeTrim(mimeType, 'image/jpeg'), data: imageData } },
    ...extraImages.map((data) => ({
      inlineData: { mimeType: safeTrim(mimeType, 'image/jpeg'), data },
    })),
  ];

  const body = {
    systemInstruction: {
      parts: [{
        text: 'You are a marine species identifier. You may receive multiple images of the same fish. Return strict JSON only.',
      }],
    },
    contents: [
      {
        role: 'user',
        parts: [
          { text: userPrompt },
          ...imageParts,
        ],
      },
    ],
    generationConfig: {
      temperature: 0.1,
      maxOutputTokens: 220,
      responseMimeType: 'application/json',
    },
  };

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 22000);
  try {
    const resp = await fetch(
      geminiGenerateContentUrl(getGeminiVisionModel(), apiKey),
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
        signal: controller.signal,
      },
    );

    const raw = await resp.text();
    let data;
    try {
      data = JSON.parse(raw);
    } catch (_) {
      data = { raw };
    }
    if (!resp.ok) {
      functions.logger.warn('Gemini fish vision failed', { status: resp.status, data });
      return null;
    }

    const candidatesOut = Array.isArray(data.candidates) ? data.candidates : [];
    let text = '';
    for (const candidate of candidatesOut) {
      const parts = candidate?.content?.parts;
      if (!Array.isArray(parts)) continue;
      text = parts.map((p) => safeTrim(p && p.text)).filter(Boolean).join('\n').trim();
      if (text) break;
    }
    const parsed = parseJsonSafe(text);
    if (!parsed || typeof parsed !== 'object') return null;

    const rawSpecies = safeTrim(parsed.species || parsed.label || parsed.scientificName);
    const confidenceRaw = Number(parsed.confidence);
    const boundedConfidence = Number.isFinite(confidenceRaw)
      ? Math.max(0, Math.min(1, confidenceRaw))
      : 0.35;

    if (!rawSpecies) return null;
    if (rawSpecies.toLowerCase().startsWith('unknown')) {
      return { species: 'Unknown sea creature', confidence: boundedConfidence };
    }

    const matched = bestCandidateMatch(rawSpecies, candidates);
    if (candidates.length && !matched) {
      return { species: 'Unknown sea creature', confidence: boundedConfidence };
    }
    const species = matched || rawSpecies;
    return { species, confidence: boundedConfidence };
  } catch (e) {
    functions.logger.warn('Gemini fish vision error', e);
    return null;
  } finally {
    clearTimeout(timeout);
  }
};

const callOpenAiImage = async ({ prompt, size = '1024x1024', quality = 'medium' }) => {
  const apiKey = getOpenAiKey();
  if (!apiKey) {
    throw new Error('Missing OPENAI_API_KEY for image generation');
  }

  const model = getOpenAiImageModel();
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 45000);
  try {
    const resp = await fetch('https://api.openai.com/v1/images/generations', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model,
        prompt: safeTrim(prompt),
        size: safeTrim(size, '1024x1024'),
        quality: safeTrim(quality, 'medium'),
        response_format: 'b64_json',
        n: 1,
      }),
      signal: controller.signal,
    });

    const raw = await resp.text();
    let data;
    try {
      data = JSON.parse(raw);
    } catch (_) {
      data = { raw };
    }

    if (!resp.ok) {
      throw new Error(`OpenAI image HTTP ${resp.status}: ${JSON.stringify(data)}`);
    }

    const first = Array.isArray(data.data) ? data.data[0] : null;
    let imageBase64 = safeTrim(
      first && (first.b64_json || first.imageBase64 || first.base64),
    );
    const mimeType = safeTrim(
      first && (first.mime_type || first.mimeType),
      'image/png',
    );

    if (!imageBase64) {
      const imageUrl = safeTrim(first && (first.url || first.imageUrl || first.image_url));
      if (!imageUrl) {
        throw new Error(`OpenAI image response missing base64 payload: ${JSON.stringify(data)}`);
      }

      let downloaded;
      try {
        downloaded = await fetch(imageUrl);
      } catch (e) {
        throw new Error(`OpenAI image url fetch failed: ${String(e)}`);
      }
      if (!downloaded.ok) {
        throw new Error(`OpenAI image url HTTP ${downloaded.status}`);
      }

      const arrayBuffer = await downloaded.arrayBuffer();
      const bytes = Buffer.from(arrayBuffer);
      if (!bytes.length) {
        throw new Error('OpenAI image url returned empty body');
      }
      imageBase64 = bytes.toString('base64');
    }

    return {
      imageBase64,
      mimeType,
      model,
      location: 'openai',
      source: 'openai-image',
    };
  } finally {
    clearTimeout(timeout);
  }
};

const getInfobipConfig = () => {
  const cfg = functions.config().infobip || {};
  const { baseurl, apikey, application_id, message_id } = cfg;
  if (!baseurl || !apikey || !application_id || !message_id) {
    throw new Error('Missing Infobip config: baseurl, apikey, application_id, message_id are required');
  }
  return {
    baseUrl: baseurl,
    apiKey: apikey,
    applicationId: application_id,
    messageId: message_id,
  };
};

exports.prepareGoogleEmailVerification = functions.https.onCall(async (_data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'You must be signed in to verify your email.',
    );
  }

  const uid = context.auth.uid;
  const user = await admin.auth().getUser(uid);
  const hasGoogleProvider = user.providerData.some(
    (provider) => provider.providerId === 'google.com',
  );

  if (!hasGoogleProvider) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'This verification reset is only available for Google sign-in accounts.',
    );
  }

  await admin.auth().updateUser(uid, { emailVerified: false });
  await admin.firestore().collection('users').doc(uid).set({
    email_verified: false,
    email_confirmation_required: true,
    email_verification_started_at: admin.firestore.FieldValue.serverTimestamp(),
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  return { ok: true };
});

exports.sendOtp = functions.https.onRequest(async (req, res) => {
  try {
    if (req.method !== 'POST') {
      return jsonResponse(res, 405, { error: 'POST only' });
    }

    const { phone, applicationId, messageId } = req.body || {};
    if (!phone) return jsonResponse(res, 400, { error: 'phone required' });

    const cfg = getInfobipConfig();
    const url = `https://${cfg.baseUrl}/2fa/2/pin`;
    const payload = {
      applicationId: applicationId || cfg.applicationId,
      messageId: messageId || cfg.messageId,
      to: sanitizePhone(phone),
    };

    const r = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: `App ${cfg.apiKey}`,
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: JSON.stringify(payload),
    });

    const text = await r.text();
    let data;
    try {
      data = JSON.parse(text);
    } catch (_) {
      data = { raw: text };
    }

    if (!r.ok) {
      functions.logger.error('Infobip send failed', { status: r.status, data });
      return jsonResponse(res, r.status, { error: 'Infobip send failed', details: data });
    }

    const pinId = data.pinId || data.pinID || data['pinId'];
    if (!pinId) {
      return jsonResponse(res, 500, { error: 'pinId missing from Infobip response', details: data });
    }

    return jsonResponse(res, 200, { pinId, infobip: data });
  } catch (e) {
    functions.logger.error('sendOtp error', e);
    return jsonResponse(res, 500, { error: 'Server error', details: String(e) });
  }
});

exports.verifyOtp = functions.https.onRequest(async (req, res) => {
  try {
    if (req.method !== 'POST') {
      return jsonResponse(res, 405, { error: 'POST only' });
    }

    const { pinId, code, phone } = req.body || {};
    if (!pinId || !code) return jsonResponse(res, 400, { error: 'pinId and code required' });

    const cfg = getInfobipConfig();
    const url = `https://${cfg.baseUrl}/2fa/2/pin/${encodeURIComponent(pinId)}/verify`;

    const r = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: `App ${cfg.apiKey}`,
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: JSON.stringify({ pin: String(code) }),
    });

    const text = await r.text();
    let data;
    try {
      data = JSON.parse(text);
    } catch (_) {
      data = { raw: text };
    }

    if (!r.ok) {
      functions.logger.warn('Infobip verify failed', { status: r.status, data });
      return jsonResponse(res, r.status, { error: 'Infobip verify failed', details: data });
    }

    const verified = data.verified === true || data.pinVerified === true || data.status === 'VERIFIED';
    if (!verified) {
      return jsonResponse(res, 401, { verified: false, infobip: data });
    }

    const msisdn = sanitizePhone(data.msisdn || data.to || phone || '');
    const uid = msisdn ? `infobip:${msisdn}` : `infobip:${pinId}`;

    await admin.auth().getUser(uid).catch(() => admin.auth().createUser({ uid, phoneNumber: msisdn || undefined }));
    const customToken = await admin.auth().createCustomToken(uid);

    return jsonResponse(res, 200, { verified: true, customToken, infobip: data });
  } catch (e) {
    functions.logger.error('verifyOtp error', e);
    return jsonResponse(res, 500, { error: 'Server error', details: String(e) });
  }
});

exports.issueFakeSightingViolation = functions.firestore
  .document('sightings/{sightingId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};
    const sightingId = context.params.sightingId;

    if (!isFakeDecision(after)) return null;
    if (after.violationIssued === true && safeTrim(after.violationId)) return null;
    if (isFakeDecision(before) && before.violationIssued === true) return null;

    const uid = firstText(after, ['userId', 'uid', 'reportedBy', 'submittedBy']);
    if (!uid) {
      functions.logger.warn('Fake sighting has no user id', { sightingId });
      return null;
    }

    const species = firstText(after, ['species', 'title', 'speciesName'], 'Marine sighting');
    const location = firstText(after, ['location', 'address'], 'Unknown location');
    const reporterName = firstText(after, ['reporterName', 'reporter', 'displayName', 'username'], 'Unknown reporter');
    const violationId = `${uid}_${sightingId}_fake_sighting`;
    const db = admin.firestore();
    const violationRef = db.collection('violations').doc(violationId);
    const userRef = db.collection('users').doc(uid);
    const sightingRef = change.after.ref;
    const notificationRef = db.collection('notifications').doc();
    const now = admin.firestore.FieldValue.serverTimestamp();

    await db.runTransaction(async (transaction) => {
      const existing = await transaction.get(violationRef);

      if (!existing.exists) {
        transaction.set(violationRef, {
          uid,
          userId: uid,
          reporterName,
          sightingId,
          reportId: sightingId,
          species,
          location,
          type: 'fake_sighting',
          category: 'log_sighting',
          title: 'Fake Log Sighting',
          description: 'Marine log sighting was marked fake or invalid by BFAR review.',
          status: 'active',
          severity: 'warning',
          createdAt: now,
        });

        transaction.set(
          userRef,
          {
            violationCount: admin.firestore.FieldValue.increment(1),
            fakeSightingViolationCount: admin.firestore.FieldValue.increment(1),
            lastViolationAt: now,
            accountStanding: 'warning',
          },
          { merge: true },
        );
      }

      transaction.update(sightingRef, {
        violationIssued: true,
        violationId,
        violationType: 'fake_sighting',
        violationIssuedAt: now,
      });

      transaction.set(notificationRef, {
        targetUserId: uid,
        title: 'Fake log sighting violation issued',
        message: `Your log sighting "${species}" at ${location} was marked fake or invalid by BFAR. A violation was added to your account.`,
        type: 'sighting_violation',
        category: 'violation',
        violationType: 'fake_sighting',
        sightingId,
        violationId,
        timestamp: now,
        isRead: false,
      });
    });

    return null;
  });

// Lightweight AI endpoints to avoid 404s when the external AI service is unavailable.
const aiAssistantHandler = functions.https.onRequest(async (req, res) => {
  if (handleCors(req, res)) return;
  try {
    if (req.method !== 'POST') {
      return jsonResponse(res, 405, { error: 'POST only' });
    }

    const { question, history } = req.body || {};
    const openAiAnswer = await callOpenAi({
      question: question || 'general help',
      history,
      systemPrompt:
        'You are a concise marine safety and fish knowledge assistant. Keep answers short (under 120 words), practical, and specific to fishing, fish safety, or handling. If unsure, say what extra info you need.',
      temperature: 0.55,
      maxTokens: 320,
    });
    const geminiAnswer = openAiAnswer
      ? null
      : await callGeminiText({
          question: question || 'general help',
          history,
          systemPrompt:
            'You are a concise marine safety and fish knowledge assistant. Keep answers short (under 120 words), practical, and specific to fishing, fish safety, or handling. If unsure, say what extra info you need.',
          temperature: 0.55,
          maxTokens: 320,
        });
    const answer = openAiAnswer || geminiAnswer || buildAssistantAnswer(question, history);
    return jsonResponse(res, 200, {
      answer,
      source: openAiAnswer ? 'openai' : geminiAnswer ? 'gemini' : 'fallback',
    });
  } catch (e) {
    functions.logger.error('ai-assistant error', e);
    return jsonResponse(res, 500, { error: 'Assistant failed', details: String(e) });
  }
});

const aiAskFishHandler = functions.https.onRequest(async (req, res) => {
  if (handleCors(req, res)) return;
  try {
    if (req.method !== 'POST') {
      return jsonResponse(res, 405, { error: 'POST only' });
    }

    const payload = req.body || {};
    const {
      question = 'fish question',
      englishName,
      scientificName,
      localName,
      family,
      habitat,
      diet,
      culinary,
      description,
      imageUrl,
      shareText,
      history,
    } = payload;

    const context = `
Fish: ${safeTrim(englishName, 'Unknown')}
Scientific: ${safeTrim(scientificName)}
Local: ${safeTrim(localName)}
Family: ${safeTrim(family)}
Habitat: ${safeTrim(habitat)}
Diet: ${safeTrim(diet)}
Culinary: ${safeTrim(culinary)}
Description: ${safeTrim(description)}
Image: ${safeTrim(imageUrl)}
Share: ${safeTrim(shareText)}
`.trim();

    const systemPrompt =
      'You are a concise fisheries assistant. Answer the user\'s exact question in the first sentence using the provided context. If the species is a shark or ray, say explicitly that sharks and rays are fish. Do not invent conservation or legal status; say when you are unsure. Keep answers brief (<140 words), practical, and include safety or handling advice only when relevant.';

    const openAiAnswer = await callOpenAi({
      question: `${safeTrim(question)}\n\nContext:\n${context}`,
      history,
      systemPrompt,
      temperature: 0.5,
      maxTokens: 360,
    });
    const geminiAnswer = openAiAnswer
      ? null
      : await callGeminiText({
          question: `${safeTrim(question)}\n\nContext:\n${context}`,
          history,
          systemPrompt,
          temperature: 0.5,
          maxTokens: 360,
        });

    const answer = openAiAnswer || geminiAnswer || buildFishAnswer(payload);
    return jsonResponse(res, 200, {
      answer,
      source: openAiAnswer ? 'openai' : geminiAnswer ? 'gemini' : 'fallback',
    });
  } catch (e) {
    functions.logger.error('ai-ask-fish error', e);
    return jsonResponse(res, 500, { error: 'Fish assistant failed', details: String(e) });
  }
});

const aiDetectFishHandler = functions.https.onRequest(async (req, res) => {
  if (handleCors(req, res)) return;
  try {
    if (req.method !== 'POST') {
      return jsonResponse(res, 405, { error: 'POST only' });
    }

    const payload = req.body || {};
    let imageBase64 = safeTrim(payload.imageBase64 || payload.base64 || payload.image || '');
    const candidateSpecies = Array.isArray(payload.candidateSpecies) ? payload.candidateSpecies : [];
    const localHints = Array.isArray(payload.localHints) ? payload.localHints : [];
    const additionalImagesBase64 = Array.isArray(payload.additionalImagesBase64)
      ? payload.additionalImagesBase64.map((item) => safeTrim(item)).filter(Boolean).slice(0, 2)
      : [];
    let mimeType = safeTrim(payload.mimeType, 'image/jpeg');

    if (imageBase64.startsWith('data:')) {
      const commaIdx = imageBase64.indexOf(',');
      const header = commaIdx > 0 ? imageBase64.slice(0, commaIdx) : '';
      const body = commaIdx > 0 ? imageBase64.slice(commaIdx + 1) : '';
      if (header.includes('image/')) {
        mimeType = safeTrim(
          header.replace('data:', '').replace(';base64', ''),
          'image/jpeg',
        );
      }
      imageBase64 = body;
    }

    if (!imageBase64) {
      return jsonResponse(res, 400, { error: 'imageBase64 required' });
    }
    if (imageBase64.length > 4000000) {
      return jsonResponse(res, 413, { error: 'Image payload too large' });
    }

    const imageDataUrl = `data:${mimeType};base64,${imageBase64}`;
    const extraImageDataUrls = additionalImagesBase64.map(
      (item) => `data:${mimeType};base64,${item}`,
    );
    const openAiVisionResult = await callOpenAiFishVision({
      imageDataUrl,
      extraImageDataUrls,
      candidateSpecies,
      localHints,
    });
    const geminiVisionResult = openAiVisionResult
      ? null
      : await callGeminiFishVision({
          imageBase64,
          mimeType,
          additionalImagesBase64,
          candidateSpecies,
          localHints,
        });
    const visionResult = openAiVisionResult || geminiVisionResult;

    if (visionResult && safeTrim(visionResult.species)) {
      return jsonResponse(res, 200, {
        species: safeTrim(visionResult.species),
        confidence: Number(visionResult.confidence || 0),
        source: openAiVisionResult ? 'openai-vision' : 'gemini-vision',
      });
    }

    return jsonResponse(res, 200, {
      species: 'Unknown sea creature',
      confidence: 0,
      source: 'fallback',
    });
  } catch (e) {
    functions.logger.error('ai-detect-fish error', e);
    return jsonResponse(res, 500, { error: 'Fish detection failed', details: String(e) });
  }
});

const aiGenerateFishImageHandler = functions.https.onRequest(async (req, res) => {
  if (handleCors(req, res)) return;
  try {
    if (req.method !== 'POST') {
      return jsonResponse(res, 405, { error: 'POST only' });
    }

    const payload = req.body || {};
    const prompt = safeTrim(payload.prompt) || buildFishIllustrationPrompt(payload);
    const negativePrompt =
      safeTrim(payload.negativePrompt) ||
      'text, logo, watermark, signature, blurry, distorted anatomy, extra fins';
    const size = safeTrim(payload.size, '1024x1024');
    const quality = safeTrim(payload.quality, 'medium');
    let generated;

    try {
      generated = await callVertexImagen({ prompt, negativePrompt });
      generated.source = 'vertex-imagen';
    } catch (vertexError) {
      functions.logger.warn('Vertex image generation failed, trying OpenAI image fallback', {
        error: String(vertexError),
      });
      generated = await callOpenAiImage({ prompt, size, quality });
    }

    return jsonResponse(res, 200, {
      imageBase64: generated.imageBase64,
      mimeType: generated.mimeType,
      source: safeTrim(generated.source, 'vertex-imagen'),
      model: generated.model,
      location: generated.location,
      prompt,
    });
  } catch (e) {
    functions.logger.error('ai-generate-fish-image error', e);
    return jsonResponse(res, 500, {
      error: 'Fish image generation failed',
      details: String(e),
    });
  }
});

// Export using nested keys so generated entrypoints match hyphenated function IDs (ai-assistant, ai-ask-fish).
exports.ai = {
  assistant: aiAssistantHandler,
  ask: {
    fish: aiAskFishHandler,
  },
  detect: {
    fish: aiDetectFishHandler,
  },
  generate: {
    fish: {
      image: aiGenerateFishImageHandler,
    },
  },
};

// Also export flat names for app compatibility.
exports.aiAssistant = aiAssistantHandler;
exports.aiAskFish = aiAskFishHandler;
exports.aiDetectFish = aiDetectFishHandler;
exports.aiGenerateFishImage = aiGenerateFishImageHandler;
