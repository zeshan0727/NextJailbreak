const ALLOWED_DOMAINS = [
  "mzadqatar.com",
  "qatarliving.com",
  "qa.opensooq.com",
  "dubizzle.qa",
  "qatarsale.com",
  "facebook.com"
];

function cors() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET,OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Max-Age": "86400"
  };
}

function json(data, status = 200, extra = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      ...cors(),
      ...extra
    }
  });
}

async function sha256(value) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)]
    .map(byte => byte.toString(16).padStart(2, "0"))
    .join("");
}

function normalizeQuery(value) {
  return String(value || "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 100);
}

function tokens(value) {
  return normalizeQuery(value)
    .toLowerCase()
    .split(/[^\p{L}\p{N}]+/u)
    .filter(Boolean);
}

function marketplaceForUrl(raw) {
  let url;
  try {
    url = new URL(raw);
  } catch {
    return null;
  }

  const host = url.hostname.toLowerCase().replace(/^www\./, "");
  const path = decodeURIComponent(url.pathname).toLowerCase();

  if (host === "qatarliving.com" || host.endsWith(".qatarliving.com")) {
    if (/\/en\/classifieds\/items\/[^/]+-[0-9a-f]{8}\/?$/i.test(path)) {
      return "Qatar Living";
    }
    if (/\/en\/vehicles\/cars\/\d+_[^/]+\/?$/i.test(path)) {
      return "Qatar Living";
    }
    return null;
  }

  if (host === "mzadqatar.com" || host.endsWith(".mzadqatar.com")) {
    if (/\/en\/products\/[^/]*\d{6,}\/?$/i.test(path)) {
      return "Mzad Qatar";
    }
    return null;
  }

  if (host === "dubizzle.qa" || host.endsWith(".dubizzle.qa")) {
    if (/\/en\/ad\/[^/]*-id\d+\.html\/?$/i.test(path)) {
      return "Dubizzle Qatar";
    }
    return null;
  }

  if (host === "qatarsale.com" || host.endsWith(".qatarsale.com")) {
    if (/\/en\/product\/[^/]+-\d+\/?$/i.test(path)) {
      return "Qatar Sale";
    }
    return null;
  }

  if (host === "facebook.com" || host.endsWith(".facebook.com")) {
    if (/\/marketplace\/item\/\d+\/?$/i.test(path)) {
      return "Facebook Marketplace";
    }
    return null;
  }

  // OpenSooq often exposes category/model pages publicly instead of stable
  // individual ad URLs. Do not mislabel those as direct ads.
  return null;
}

function matchesQuery(listing, query) {
  const haystack = [
    listing.title || "",
    listing.snippet || "",
    listing.url || ""
  ].join(" ").toLowerCase();

  const queryTokens = tokens(query).filter(t => !["find","show","me","cheapest","cheap","lowest","highest","qatar","doha"].includes(t));
  if (!queryTokens.length) return true;

  const numeric = queryTokens.filter(t => /^\d+$/.test(t));
  if (numeric.some(t => !haystack.includes(t))) return false;

  const words = queryTokens.filter(t => !/^\d+$/.test(t));
  if (!words.length) return true;

  const hits = words.filter(t => haystack.includes(t)).length;
  return words.length <= 3 ? hits === words.length : hits >= words.length - 1;
}

function extractOutputText(payload) {
  for (const item of payload?.output || []) {
    if (item?.type !== "message") continue;
    for (const content of item?.content || []) {
      if (content?.type === "output_text" && typeof content.text === "string") {
        return content.text;
      }
    }
  }
  return "";
}

async function enforceRateLimit(request, env) {
  const ip = request.headers.get("CF-Connecting-IP") || "unknown";
  const ipHash = await sha256(`tipa-search:${ip}`);

  const recent = await env.RATE_DB.prepare(
    "SELECT COUNT(*) AS total FROM searches WHERE ip_hash = ? AND created_at >= datetime('now','-10 minutes')"
  ).bind(ipHash).first();

  if (Number(recent?.total || 0) >= 30) {
    return false;
  }

  await env.RATE_DB.prepare(
    "INSERT INTO searches (ip_hash, created_at) VALUES (?, datetime('now'))"
  ).bind(ipHash).run();

  return true;
}

async function searchMarketplaces(request, env) {
  if (!env.OPENAI_API_KEY) {
    return json({error: "Search backend is not configured."}, 503);
  }

  const requestUrl = new URL(request.url);
  const query = normalizeQuery(requestUrl.searchParams.get("q"));

  if (query.length < 2) {
    return json({error: "Search query is too short."}, 400);
  }

  const cache = caches.default;
  const cacheKey = new Request(
    `https://search.nextjailbreak.com/__tipa_cache?query=${encodeURIComponent(query.toLowerCase())}`
  );

  const cached = await cache.match(cacheKey);
  if (cached) {
    const headers = new Headers(cached.headers);
    headers.set("X-TIPA-Cache", "HIT");
    return new Response(cached.body, {status: cached.status, headers});
  }

  if (!(await enforceRateLimit(request, env))) {
    return json({error: "Too many searches. Please wait a few minutes."}, 429);
  }

  const schema = {
    type: "object",
    additionalProperties: false,
    required: ["query", "listings"],
    properties: {
      query: {type: "string"},
      listings: {
        type: "array",
        maxItems: 24,
        items: {
          type: "object",
          additionalProperties: false,
          required: ["title", "url", "source", "price_qar", "snippet"],
          properties: {
            title: {type: "string"},
            url: {type: "string"},
            source: {
              type: "string",
              enum: [
                "Mzad Qatar",
                "Qatar Living",
                "OpenSooq",
                "Dubizzle Qatar",
                "Qatar Sale",
                "Facebook Marketplace"
              ]
            },
            price_qar: {type: ["integer", "null"]},
            snippet: {type: "string"}
          }
        }
      }
    }
  };

  const prompt = `
Search the live public web for CURRENT Qatar marketplace listings matching the user's query.

User query: "${query}"

Requirements:
- You MUST use web search.
- Search only the allowed marketplace domains supplied by the tool.
- Return individual advertisement/listing pages only.
- Never return marketplace homepages, category pages, profile pages, search-result pages, or generic feeds.
- The URL must be the exact source listing URL you actually found. Never invent, reconstruct, or guess a URL.
- The title/page content must clearly match the requested product/model/year. Preserve important tokens such as iPhone X, Fold 5, Patrol 2012, storage size, model year, etc.
- Exclude accessories/parts when the query is for the main product unless the user explicitly asks for an accessory/part.
- price_qar must be the listing's stated QAR price. Use null when the listing price is not clearly stated.
- Prefer recently indexed/current listings and return up to 24 useful matches.
- If a marketplace only exposes a category/search page and not the individual ad URL, do not include that result.
`.trim();

  const body = {
    model: "gpt-5.6-luna",
    reasoning: {effort: "low"},
    tools: [
      {
        type: "web_search",
        filters: {allowed_domains: ALLOWED_DOMAINS},
        user_location: {
          type: "approximate",
          country: "QA",
          city: "Doha",
          region: "Doha",
          timezone: "Asia/Qatar"
        }
      }
    ],
    input: prompt,
    text: {
      format: {
        type: "json_schema",
        name: "tipa_marketplace_results",
        strict: true,
        schema
      }
    },
    max_output_tokens: 5000,
    store: false
  };

  let upstream;
  try {
    upstream = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${env.OPENAI_API_KEY}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify(body)
    });
  } catch {
    return json({error: "Search service is temporarily unavailable."}, 502);
  }

  if (!upstream.ok) {
    const detail = (await upstream.text()).slice(0, 500);
    return json({error: "Search provider error.", status: upstream.status, detail}, 502);
  }

  const payload = await upstream.json();
  const outputText = extractOutputText(payload);

  let parsed;
  try {
    parsed = JSON.parse(outputText);
  } catch {
    return json({error: "Search provider returned an invalid result."}, 502);
  }

  const seen = new Set();
  const listings = [];

  for (const item of Array.isArray(parsed?.listings) ? parsed.listings : []) {
    const source = marketplaceForUrl(item.url);
    if (!source) continue;
    if (!matchesQuery(item, query)) continue;

    let canonical;
    try {
      const u = new URL(item.url);
      u.hash = "";
      canonical = u.toString();
    } catch {
      continue;
    }

    const key = canonical.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);

    const price = Number.isInteger(item.price_qar) && item.price_qar > 0
      ? item.price_qar
      : null;

    listings.push({
      title: String(item.title || query).trim().slice(0, 180),
      url: canonical,
      source,
      price_qar: price,
      snippet: String(item.snippet || "").trim().slice(0, 500)
    });
  }

  const responsePayload = {
    query,
    listings,
    engine: "nextjailbreak-web-search-v1",
    searched_at: new Date().toISOString()
  };

  const response = json(responsePayload, 200, {
    "Cache-Control": "public, max-age=120"
  });

  if (listings.length > 0) {
    const cacheResponse = response.clone();
    cacheResponse.headers.set("Cache-Control", "public, max-age=600");
    await cache.put(cacheKey, cacheResponse);
  }

  return response;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, {status: 204, headers: cors()});
    }

    if (url.pathname === "/health") {
      return json({ok: true, service: "tipa-search", version: 1});
    }

    if (request.method === "GET" && url.pathname === "/api/tipa/search") {
      return searchMarketplaces(request, env);
    }

    return json({error: "Not found."}, 404);
  }
};
