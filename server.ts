import { serveDir } from "jsr:@std/http@1";

const fsRoot = Deno.args[0] ?? "./zig-out/web";
const PORT = 8000;
const HOT_RELOAD_PATH = "/__hot-reload";

// Store WebSocket connections for hot reload notifications
const wsConnections = new Set<WebSocket>();

function isBuildFile(path: string) {
  return path.endsWith(".html") || path.endsWith(".wasm");
}

function broadcastReload() {
  for (const ws of wsConnections) {
    try {
      ws.send(JSON.stringify({ type: "reload" }));
    } catch {
      wsConnections.delete(ws);
    }
  }
}

function startFileWatcher() {
  const watcher = Deno.watchFs([fsRoot], { recursive: true });
  (async () => {
    for await (const event of watcher) {
      if (event.paths.some(isBuildFile)) {
        const changed = event.paths.find(isBuildFile) || "file";
        const fileType = changed.split(".").pop()?.toUpperCase() ?? "FILE";
        console.log(`📦 ${fileType} changed — notifying clients`);
        broadcastReload();
      }
    }
  })();
}

function handleWebSocket(req: Request): Response {
  if (req.headers.get("upgrade") !== "websocket") {
    return new Response("Not a websocket request", { status: 400 });
  }

  const { socket, response } = Deno.upgradeWebSocket(req);
  wsConnections.add(socket);

  socket.onopen = () => console.log("✅ Hot-reload client connected");
  socket.onclose = () => {
    wsConnections.delete(socket);
    console.log("❌ Hot-reload client disconnected");
  };
  socket.onerror = (err) => {
    console.error("WebSocket error:", err);
    wsConnections.delete(socket);
  };

  return response;
}

function createHotReloadScript() {
  return `
<script>
(function() {
  let reloading = false;
  const proto = (location.protocol === 'https:') ? 'wss:' : 'ws:';
  const wsUrl = proto + '//' + location.host + '${HOT_RELOAD_PATH}';
  function connect() {
    if (reloading) return;
    const ws = new WebSocket(wsUrl);
    ws.onopen = () => console.log('[Hot Reload] connected');
    ws.onmessage = (ev) => {
      try {
        const data = JSON.parse(ev.data);
        if (data.type === 'reload') {
          console.log('[Hot Reload] reload triggered');
          reloading = true;
          location.reload();
        }
      } catch (e) {
        console.error('[Hot Reload] invalid message', e);
      }
    };
    ws.onclose = () => {
      console.log('[Hot Reload] disconnected, reconnect in 1s');
      setTimeout(connect, 1000);
    };
    ws.onerror = (err) => console.error('[Hot Reload] error', err);
  }
  connect();
})();
</script>
`;
}

function injectHotReload(html: string) {
  const script = createHotReloadScript();
  if (html.includes("</body>")) {
    return html.replace("</body>", `${script}</body>`);
  }
  return html + script;
}

async function serveHandler(req: Request): Promise<Response> {
  const url = new URL(req.url, `http://${req.headers.get("host")}`);

  if (url.pathname === HOT_RELOAD_PATH) {
    return handleWebSocket(req);
  }

  const response = await serveDir(req, { fsRoot });

  const contentType = response.headers.get("content-type") ?? "";
  if (response.status === 200 && contentType.includes("text/html")) {
    const originalText = await response.text();
    const modified = injectHotReload(originalText);

    const headers = new Headers(response.headers);
    const enc = new TextEncoder();
    const bodyBytes = enc.encode(modified);
    headers.set("content-length", String(bodyBytes.length));

    return new Response(bodyBytes, {
      status: response.status,
      headers,
    });
  }

  return response;
}

// Start services
startFileWatcher();
Deno.serve({ port: PORT }, serveHandler);

console.log(`🚀 Server running at http://localhost:${PORT}`);
console.log("🔥 Hot reload enabled for HTML and WASM files");
