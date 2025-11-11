import { serveDir } from "jsr:@std/http@1";

const fsRoot = Deno.args[0] ?? "./zig-out/web";
const PORT = 8000;
const HOT_RELOAD_PATH = "/__hot-reload";
const API_EXAMPLES_PATH = "/__api/examples";
const ASSETS_PATH = "/__assets";

// Inlined assets
const HTML_TEMPLATE = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Zenithor Examples</title>
  <link rel="stylesheet" href="/__assets/style.css">
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>Zenithor Examples</h1>
      <p>Choose an example to run</p>
    </div>
    <div class="examples" id="examples">
      <!-- Examples will be injected here -->
    </div>
    <div class="footer">
      <span class="hot-reload">Hot Reload Active</span>
    </div>
  </div>
  <script src="/__assets/index.js"></script>
</body>
</html>
`;

const CSS_CONTENT = `* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 20px;
}

.container {
  background: white;
  border-radius: 16px;
  box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
  max-width: 800px;
  width: 100%;
  overflow: hidden;
}

.header {
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: white;
  padding: 32px;
  text-align: center;
}

.header h1 {
  font-size: 32px;
  font-weight: 700;
  margin-bottom: 8px;
}

.header p {
  font-size: 16px;
  opacity: 0.9;
}

.examples {
  padding: 24px;
}

.example-card {
  border: 2px solid #e5e7eb;
  border-radius: 12px;
  padding: 20px;
  margin-bottom: 16px;
  transition: all 0.2s;
  text-decoration: none;
  display: block;
  color: inherit;
}

.example-card:hover {
  border-color: #667eea;
  box-shadow: 0 4px 12px rgba(102, 126, 234, 0.15);
  transform: translateY(-2px);
}

.example-title {
  font-size: 20px;
  font-weight: 600;
  color: #1f2937;
  margin-bottom: 8px;
  display: flex;
  align-items: center;
  gap: 8px;
}

.example-title::before {
  content: "▶";
  color: #667eea;
  font-size: 14px;
}

.example-meta {
  display: flex;
  gap: 16px;
  font-size: 14px;
  color: #6b7280;
}

.example-meta span {
  display: flex;
  align-items: center;
  gap: 4px;
}

.badge {
  background: #f3f4f6;
  padding: 4px 8px;
  border-radius: 4px;
  font-weight: 500;
}

.empty {
  text-align: center;
  padding: 48px 24px;
  color: #6b7280;
}

.empty-icon {
  font-size: 48px;
  margin-bottom: 16px;
}

.empty h2 {
  font-size: 20px;
  margin-bottom: 12px;
  color: #374151;
}

.empty p {
  line-height: 1.6;
}

.empty code {
  background: #f3f4f6;
  padding: 2px 6px;
  border-radius: 4px;
  font-family: 'Courier New', monospace;
  font-size: 13px;
  color: #667eea;
}

.footer {
  padding: 16px 24px;
  background: #f9fafb;
  border-top: 1px solid #e5e7eb;
  text-align: center;
  font-size: 14px;
  color: #6b7280;
}

.hot-reload {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  background: #dcfce7;
  color: #166534;
  padding: 4px 12px;
  border-radius: 12px;
  font-weight: 500;
}

.hot-reload::before {
  content: "🔥";
  font-size: 12px;
}
`;

const JS_CONTENT = `// Fetch and display available examples
async function loadExamples() {
  try {
    const response = await fetch("/__api/examples");
    const examples = await response.json();

    const container = document.getElementById("examples");

    if (examples.length === 0) {
      container.innerHTML = \`
        <div class="empty">
          <div class="empty-icon">📦</div>
          <h2>No examples found</h2>
          <p>Build examples with: <code>zig build examples-web -Dtarget=wasm32-emscripten</code></p>
        </div>
      \`;
    } else {
      container.innerHTML = examples.map((ex) => \`
        <a href="\${ex.htmlPath}" class="example-card">
          <div class="example-title">\${ex.name}</div>
          <div class="example-meta">
            <span><span class="badge">\${ex.wasmSize}</span></span>
            <span>📅 \${ex.lastModified}</span>
          </div>
        </a>
      \`).join("");
    }
  } catch (error) {
    console.error("Failed to load examples:", error);
    document.getElementById("examples").innerHTML = \`
      <div class="empty">
        <div class="empty-icon">⚠️</div>
        <h2>Failed to load examples</h2>
        <p>Please check the console for errors.</p>
      </div>
    \`;
  }
}

// Load examples when page loads
loadExamples();
`;

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

function serveAsset(pathname: string): Response | null {
  const assetMap: Record<string, { content: string; contentType: string }> = {
    "/style.css": { content: CSS_CONTENT, contentType: "text/css" },
    "/index.js": { content: JS_CONTENT, contentType: "application/javascript" },
  };

  const asset = assetMap[pathname];
  if (!asset) return null;

  return new Response(asset.content, {
    status: 200,
    headers: { "content-type": asset.contentType },
  });
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

  // Serve static assets (CSS, JS) from memory
  if (url.pathname.startsWith(ASSETS_PATH)) {
    const assetPath = url.pathname.replace(ASSETS_PATH, "");
    const response = serveAsset(assetPath);
    if (response) return response;
  }

  // Serve custom index page at root from memory
  if (url.pathname === "/") {
    return new Response(HTML_TEMPLATE, {
      status: 200,
      headers: { "content-type": "text/html; charset=utf-8" },
    });
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
