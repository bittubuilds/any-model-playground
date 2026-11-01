// Tiny CORS proxy for providers that block direct browser calls (OpenAI, Mistral, DeepSeek, xAI...).
// No dependencies. Node 18+.
//
//   node proxy.mjs            -> http://localhost:8787
//   PORT=9000 node proxy.mjs
//
// Usage in the playground's Base URL field:
//   http://localhost:8787/https://api.openai.com/v1
// The playground then appends /chat/completions and the proxy forwards the whole
// path as the upstream URL, streaming the response back untouched.

import http from 'node:http';

const PORT = process.env.PORT || 8787;

const CORS = {
  'access-control-allow-origin': '*',
  'access-control-allow-headers': '*',
  'access-control-allow-methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS',
  'access-control-expose-headers': '*',
  'access-control-max-age': '86400'
};

const SKIP_HEADERS = new Set([
  'host', 'connection', 'content-length', 'origin', 'referer',
  'accept-encoding', 'transfer-encoding', 'keep-alive', 'upgrade'
]);

const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') {
    res.writeHead(204, CORS);
    return res.end();
  }

  if (req.url === '/' || req.url === '/health') {
    res.writeHead(200, { ...CORS, 'content-type': 'text/plain' });
    return res.end('proxy ok');
  }

  let target;
  try {
    target = decodeURIComponent(req.url.slice(1));
  } catch {
    target = req.url.slice(1);
  }

  if (!/^https?:\/\//i.test(target)) {
    res.writeHead(400, { ...CORS, 'content-type': 'application/json' });
    return res.end(JSON.stringify({ error: 'Path must be the full upstream URL, e.g. /https://api.openai.com/v1/chat/completions' }));
  }

  let body = '';
  for await (const chunk of req) body += chunk;

  const headers = {};
  for (const [k, v] of Object.entries(req.headers)) {
    if (SKIP_HEADERS.has(k)) continue;
    headers[k] = v;
  }

  try {
    const upstream = await fetch(target, {
      method: req.method,
      headers,
      body: (req.method === 'GET' || req.method === 'HEAD') ? undefined : body
    });

    res.writeHead(upstream.status, {
      ...CORS,
      'content-type': upstream.headers.get('content-type') || 'application/octet-stream',
      'cache-control': 'no-store'
    });

    if (upstream.body) {
      const reader = upstream.body.getReader();
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        res.write(Buffer.from(value));
      }
    }
    res.end();
  } catch (e) {
    if (!res.headersSent) {
      res.writeHead(502, { ...CORS, 'content-type': 'application/json' });
      res.end(JSON.stringify({ error: String(e && e.message ? e.message : e) }));
    } else {
      res.end();
    }
  }
});

server.listen(PORT, () => {
  console.log('CORS proxy listening on http://localhost:' + PORT);
  console.log('Example base URL: http://localhost:' + PORT + '/https://api.openai.com/v1');
});
