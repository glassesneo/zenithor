import { serveDir } from "jsr:@std/http@1";

const fsRoot = Deno.args[0] ?? "./zig-out/web";
const PORT = 8000;
const HOT_RELOAD_PATH = "/__hot-reload";
const API_EXAMPLES_PATH = "/__api/examples";
const ASSETS_PATH = "/__assets";

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

interface ExampleInfo {
  name: string;
  htmlPath: string;
  wasmSize: number;
  lastModified: Date;
}

async function getAvailableExamples(): Promise<ExampleInfo[]> {
  const examples: ExampleInfo[] = [];
  
  try {
    for await (const entry of Deno.readDir(fsRoot)) {
      if (entry.isFile && entry.name.endsWith(".html")) {
        const name = entry.name.replace(".html", "");
        const htmlPath = `${fsRoot}/${entry.name}`;
        const wasmPath = `${fsRoot}/${name}.wasm`;
        
        try {
          const wasmStat = await Deno.stat(wasmPath);
          const htmlStat = await Deno.stat(htmlPath);
          
          examples.push({
            name,
            htmlPath: `/${entry.name}`,
            wasmSize: wasmStat.size,
            lastModified: htmlStat.mtime ?? new Date(),
          });
        } catch {
          // Skip if wasm file doesn't exist
        }
      }
    }
  } catch (error) {
    console.error("Error reading examples directory:", error);
  }
  
  return examples.sort((a, b) => a.name.localeCompare(b.name));
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

function formatDate(date: Date): string {
  return date.toLocaleString("en-US", {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

async function serveAsset(pathname: string): Promise<Response | null> {
  const assetMap: Record<string, { path: string; contentType: string }> = {
    "/style.css": { path: "./server/style.css", contentType: "text/css" },
    "/index.js": { path: "./server/index.js", contentType: "application/javascript" },
  };

  const asset = assetMap[pathname];
  if (!asset) return null;

  try {
    const content = await Deno.readTextFile(asset.path);
    return new Response(content, {
      status: 200,
      headers: { "content-type": asset.contentType },
    });
  } catch {
    return new Response("Not Found", { status: 404 });
  }
}

async function serveHandler(req: Request): Promise<Response> {
  const url = new URL(req.url, `http://${req.headers.get("host")}`);

  if (url.pathname === HOT_RELOAD_PATH) {
    return handleWebSocket(req);
  }

  // Serve API endpoint for examples data
  if (url.pathname === API_EXAMPLES_PATH) {
    const examples = await getAvailableExamples();
    const formattedExamples = examples.map(ex => ({
      name: ex.name,
      htmlPath: ex.htmlPath,
      wasmSize: formatBytes(ex.wasmSize),
      lastModified: formatDate(ex.lastModified),
    }));
    
    return new Response(JSON.stringify(formattedExamples), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  }

  // Serve static assets (CSS, JS)
  if (url.pathname.startsWith(ASSETS_PATH)) {
    const assetPath = url.pathname.replace(ASSETS_PATH, "");
    const response = await serveAsset(assetPath);
    if (response) return response;
  }

  // Serve custom index page at root
  if (url.pathname === "/") {
    try {
      const html = await Deno.readTextFile("./server/index.html");
      return new Response(html, {
        status: 200,
        headers: { "content-type": "text/html; charset=utf-8" },
      });
    } catch {
      return new Response("Index page not found", { status: 404 });
    }
  }

  // Serve example files with hot reload injection
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
      status: 200,
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
