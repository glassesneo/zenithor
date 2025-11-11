import { serveDir } from "jsr:@std/http@1";

// Parse CLI arguments
const gameName = Deno.args.find(arg => !arg.startsWith("--"));
const portArg = Deno.args.find(arg => arg.startsWith("--port="));
const PORT = portArg ? parseInt(portArg.split("=")[1]) : 8000;

if (!gameName) {
  console.error("Usage: deno run --allow-net --allow-read shell.ts <game-name> [--port=8000]");
  console.error("Example: deno run --allow-net --allow-read shell.ts demo_2d");
  Deno.exit(1);
}

const fsRoot = "./zig-out/web";
const HOT_RELOAD_PATH = "/__hot-reload";

// Validate game exists
const gameHtmlPath = `${fsRoot}/${gameName}.html`;
const gameWasmPath = `${fsRoot}/${gameName}.wasm`;

try {
  await Deno.stat(gameHtmlPath);
  await Deno.stat(gameWasmPath);
} catch {
  console.error(`❌ Game "${gameName}" not found in ${fsRoot}/`);
  console.error("\nAvailable games:");

  try {
    for await (const entry of Deno.readDir(fsRoot)) {
      if (entry.isFile && entry.name.endsWith(".html")) {
        const name = entry.name.replace(".html", "");
        console.error(`  - ${name}`);
      }
    }
  } catch {
    console.error("  (Unable to read directory)");
  }

  Deno.exit(1);
}

// WebSocket connections for hot reload
const wsConnections = new Set<WebSocket>();

function broadcastReload(): void {
  for (const ws of wsConnections) {
    try {
      ws.send(JSON.stringify({ type: "reload" }));
    } catch {
      wsConnections.delete(ws);
    }
  }
}

function startFileWatcher(): void {
  const watcher = Deno.watchFs([gameHtmlPath, gameWasmPath]);
  (async () => {
    for await (const event of watcher) {
      if (event.kind === "modify" || event.kind === "create") {
        const fileName = event.paths[0]?.split("/").pop() ?? "file";
        console.log(`📦 ${fileName} changed — reloading`);
        setTimeout(() => broadcastReload(), 200); // Delay to avoid race conditions
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

function createHotReloadScript(): string {
  return `
<script>
(function() {
  let reloading = false;
  const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
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

function injectHotReload(html: string): string {
  const script = createHotReloadScript();
  if (html.includes("</body>")) {
    return html.replace("</body>", `${script}</body>`);
  }
  return html + script;
}

async function serveHandler(req: Request): Promise<Response> {
  const url = new URL(req.url, `http://${req.headers.get("host")}`);

  // Hot reload WebSocket
  if (url.pathname === HOT_RELOAD_PATH) {
    return handleWebSocket(req);
  }

  // Serve game HTML at root
  if (url.pathname === "/") {
    try {
      const html = await Deno.readTextFile(gameHtmlPath);
      return new Response(injectHotReload(html), {
        status: 200,
        headers: { "content-type": "text/html; charset=utf-8" },
      });
    } catch (error) {
      return new Response(`Error loading game: ${error}`, { status: 500 });
    }
  }

  // Serve all other files (wasm, js, etc.)
  const response = await serveDir(req, { fsRoot });

  // Add no-cache for WASM files to avoid caching issues
  if (url.pathname.endsWith(".wasm")) {
    const headers = new Headers(response.headers);
    headers.set("cache-control", "no-cache");
    return new Response(response.body, {
      status: response.status,
      headers,
    });
  }

  return response;
}

// Start server
try {
  startFileWatcher();
  Deno.serve({ port: PORT }, serveHandler);

  console.log(`🎮 ${gameName} → http://localhost:${PORT}`);
  console.log(`🔥 Hot reload enabled`);
} catch (error) {
  if (error instanceof Error && error.message.includes("address in use")) {
    console.error(`❌ Port ${PORT} is already in use. Try: --port=${PORT + 1}`);
    Deno.exit(1);
  }
  throw error;
}
