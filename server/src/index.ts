import http from 'node:http';
import { WebSocketServer } from 'ws';
import { RoomRegistry } from './roomRegistry.js';
import { attachSignaling } from './signaling.js';

export interface BubbleServerOptions {
  port?: number;
  host?: string;
}

function escapeHtml(value: string): string {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function renderInviteHtml(code: string, roomName: string): string {
  const safeCode = escapeHtml(code);
  const safeName = escapeHtml(roomName);
  const deepLink = `bubble://join?code=${encodeURIComponent(code)}`;

  return `<!DOCTYPE html>
<html lang="it">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${safeName} · Bubble</title>
  <meta property="og:title" content="Unisciti a ${safeName} su Bubble" />
  <meta property="og:description" content="Intimacy in a noisy world. Tocca per entrare nella stanza vocale #${safeCode}." />
  <meta property="og:type" content="website" />
  <style>
    body {
      margin: 0;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif;
      background: radial-gradient(circle at 30% 20%, #24124d 0%, #090b16 65%, #04050a 100%);
      color: #f8f7ff;
      padding: 24px;
    }
    .card {
      max-width: 380px;
      width: 100%;
      background: rgba(255, 255, 255, 0.06);
      border: 1px solid rgba(255, 255, 255, 0.14);
      border-radius: 28px;
      padding: 28px 24px;
      text-align: center;
      backdrop-filter: blur(24px);
    }
    .orb {
      width: 84px;
      height: 84px;
      margin: 0 auto 18px;
      border-radius: 50%;
      background: radial-gradient(circle at 32% 30%, rgba(255,255,255,0.75), rgba(168,125,255,0.45) 45%, rgba(92,52,200,0.2) 100%);
      box-shadow: 0 0 40px rgba(154, 107, 255, 0.45);
    }
    h1 { font-size: 22px; font-weight: 600; margin: 0 0 8px; }
    p { font-size: 14px; color: rgba(240, 238, 255, 0.72); margin: 0 0 20px; line-height: 1.5; }
    .code {
      display: inline-block;
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 24px;
      letter-spacing: 0.24em;
      padding: 10px 18px;
      border-radius: 14px;
      background: rgba(255, 255, 255, 0.08);
      margin-bottom: 20px;
    }
    .btn {
      display: block;
      width: 100%;
      box-sizing: border-box;
      padding: 14px 18px;
      border-radius: 16px;
      text-decoration: none;
      color: #ffffff;
      font-weight: 600;
      background: linear-gradient(135deg, #7c4dff 0%, #c04dff 100%);
      box-shadow: 0 10px 28px rgba(124, 77, 255, 0.35);
    }
  </style>
</head>
<body>
  <main class="card">
    <div class="orb"></div>
    <h1>${safeName}</h1>
    <p>Sei stato invitato a entrare in una Bubble privata. Se hai già l'app installata, toccando il pulsante entrerai nel gruppo.</p>
    <div class="code">${safeCode}</div>
    <a class="btn" href="${deepLink}">Apri in Bubble</a>
  </main>
  <script>
    setTimeout(function () { window.location.href = ${JSON.stringify(deepLink)}; }, 150);
  </script>
</body>
</html>`;
}

export function createBubbleServer() {
  const registry = new RoomRegistry();
  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url ?? '/', `http://${req.headers.host ?? 'localhost'}`);

    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

    if (req.method === 'OPTIONS') {
      res.writeHead(204);
      res.end();
      return;
    }

    if (req.method === 'GET' && url.pathname === '/health') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: true, ...registry.stats() }));
      return;
    }

    if (req.method === 'GET' && url.pathname.startsWith('/join/')) {
      const code = url.pathname.slice('/join/'.length).replace(/\D/g, '').slice(0, 6);
      if (code.length !== 6) {
        res.writeHead(400, { 'Content-Type': 'text/plain; charset=utf-8' });
        res.end('Codice stanza non valido');
        return;
      }
      const room = registry.getRoom(code);
      const roomName = url.searchParams.get('name') || room?.name || `Bubble #${code}`;
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(renderInviteHtml(code, roomName));
      return;
    }

    if (req.method === 'POST' && url.pathname === '/api/rooms') {
      let body = '';
      for await (const chunk of req) {
        body += chunk;
        if (body.length > 16_384) {
          res.writeHead(413, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'payload_too_large' }));
          return;
        }
      }
      try {
        const data = JSON.parse(body) as { code?: string; name?: string };
        const code = (data.code ?? '').replace(/\D/g, '').slice(0, 6);
        if (code.length !== 6) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'invalid_code' }));
          return;
        }
        const room = registry.upsertRoom(code, (data.name ?? '').slice(0, 60));
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: true, room }));
      } catch {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'invalid_json' }));
      }
      return;
    }

    if (req.method === 'GET' && url.pathname.startsWith('/api/rooms/')) {
      const code = url.pathname.slice('/api/rooms/'.length).replace(/\D/g, '').slice(0, 6);
      const room = registry.getRoom(code);
      if (!room) {
        res.writeHead(404, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'not_found' }));
        return;
      }
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ room, activePeers: registry.getLivePeers(code).length }));
      return;
    }

    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'not_found' }));
  });

  const wss = new WebSocketServer({ server, path: '/ws' });
  const stopHeartbeat = attachSignaling(wss, registry);

  server.on('close', () => {
    stopHeartbeat();
    wss.close();
  });

  return { server, wss, registry };
}

export function startBubbleServer(options: BubbleServerOptions = {}) {
  const port = options.port ?? Number(process.env.PORT ?? 8787);
  const host = options.host ?? process.env.HOST ?? '0.0.0.0';
  const instance = createBubbleServer();
  instance.server.listen(port, host, () => {
    console.log(`[Bubble2 Server] Listening on http://${host}:${port} (ws path /ws)`);
  });
  return instance;
}

const isEntrypoint = process.argv[1]?.endsWith('index.js') || process.argv[1]?.endsWith('index.ts');
if (isEntrypoint) {
  startBubbleServer();
}
