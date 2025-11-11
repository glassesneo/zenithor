import { serveDir } from "jsr:@std/http@1";

const fsRoot = Deno.args[0] ?? "./zig-out/web";
const PORT = 8000;
const HOT_RELOAD_PATH = "/__hot-reload";
const API_EXAMPLES_PATH = "/__api/examples";

// Simplified HTML template
const HTML_TEMPLATE = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Zenithor Examples</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      background: #f5f5f5;
      padding: 20px;
    }
    .container {
      max-width: 700px;
      margin: 0 auto;
      background: white;
      border-radius: 8px;
      border: 1px solid #ddd;
      overflow: hidden;
    }
    .header {
      padding: 24px;
      border-bottom: 1px solid #eee;
    }
    .header h1 {
      font-size: 24px;
      color: #333;
      margin-bottom: 4px;
    }
    .header p {
      font-size: 14px;
      color: #666;
    }
    .examples {
      padding: 16px;
    }
    .example-item {
      display: flex;
      align-items: center;
      padding: 12px;
      border-bottom: 1px solid #f0f0f0;
      text-decoration: none;
      color: inherit;
      transition: background 0.1s;
    }
    .example-item:hover {
      background: #f9f9f9;
    }
    .example-item:last-child {
      border-bottom: none;
    }
    .example-name {
      flex: 1;
      color: #0066cc;
      font-weight: 500;
    }
    .example-size {
      font-size: 13px;
      color: #999;
      padding: 2px 8px;
      background: #f5f5f5;
      border-radius: 3px;
    }
    .empty {
      padding: 48px 24px;
      text-align: center;
      color: #666;
    }
    .empty h2 {
      font-size: 18px;
      margin: 12px 0;
      color: #333;
    }
    .empty code {
      background: #f5f5f5;
      padding: 2px 6px;
      border-radius: 3px;
      font-family: monospace;
      font-size: 13px;
    }
    .footer {
      padding: 12px 24px;
      background: #f9f9f9;
      border-top: 1px solid #eee;
      text-align: center;
      font-size: 13px;
      color: #666;
    }
    .hot-reload {
      display: inline-flex;
      align-items: center;
      gap: 6px;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>Zenithor Examples</h1>
      <p>Choose an example to run</p>
    </div>
    <div class="examples" id="examples"></div>
    <div class="footer">
      <span class="hot-reload">🔥 Hot Reload Active</span>
    </div>
  </div>
  <script>
    async function loadExamples() {
      try {
        const response = await fetch("/__api/examples");
        const examples = await response.json();
        const container = document.getElementById("examples");

        if (examples.length === 0) {
          container.innerHTML = \`
            <div class="empty">
              <div>📦</div>
              <h2>No examples found</h2>
              <p>Build examples with: <code>zig build examples -Dtarget=wasm32-emscripten</code></p>
            </div>
          \`;
        } else {
          container.innerHTML = examples.map(ex => \`
            <a href="\${ex.htmlPath}" class="example-item">
              <span class="example-name">▶ \${ex.name}</span>
              <span class="example-size">\${ex.wasmSize}</span>
            </a>
          \`).join("");
        }
      } catch (error) {
        console.error("Failed to load examples:", error);
        document.getElementById("examples").innerHTML = \`
          <div class="empty">
            <div>⚠️</div>
            <h2>Failed to load examples</h2>
            <p>Check the console for errors</p>
          </div>
        \`;
      }
    }
    loadExamples();
  </script>
</body>
</html>
`;

// WebSocket connections for hot reload
const wsConnections = new Set<WebSocket>();

function isBuildFile(path: string): boolean {
  return path.endsWith(".html") || path.endsWith(".wasm");
}

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
  const watcher = Deno.watchFs([fsRoot], { recursive: true });
  (async () => {
    for await (const event of watcher) {
      if (event.paths.some(isBuildFile)) {
        const changed = event.paths.find(isBuildFile) || "file";
        const fileType = changed.split(".").pop()?.toUpperCase() ?? "FILE";
        console.log(`📦 ${fileType} changed — notifying clients`);
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

interface ExampleInfo {
  name: string;
  htmlPath: string;
  wasmSize: number;
}

async function getAvailableExamples(): Promise<ExampleInfo[]> {
  const examples: ExampleInfo[] = [];

  try {
    for await (const entry of Deno.readDir(fsRoot)) {
      if (entry.isFile && entry.name.endsWith(".html")) {
        const name = entry.name.replace(".html", "");
        const wasmPath = `${fsRoot}/${name}.wasm`;

        try {
          const wasmStat = await Deno.stat(wasmPath);
          examples.push({
            name,
            htmlPath: `/${entry.name}`,
            wasmSize: wasmStat.size,
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
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

async function serveHandler(req: Request): Promise<Response> {
  const url = new URL(req.url, `http://${req.headers.get("host")}`);

  // Hot reload WebSocket
  if (url.pathname === HOT_RELOAD_PATH) {
    return handleWebSocket(req);
  }

  // API endpoint for examples
  if (url.pathname === API_EXAMPLES_PATH) {
    const examples = await getAvailableExamples();
    const formattedExamples = examples.map(ex => ({
      name: ex.name,
      htmlPath: ex.htmlPath,
      wasmSize: formatBytes(ex.wasmSize),
    }));

    return new Response(JSON.stringify(formattedExamples), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  }

  // Serve landing page at root
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

    // Add no-cache for WASM files to avoid caching issues
    if (url.pathname.endsWith(".wasm")) {
      headers.set("cache-control", "no-cache");
    }

    return new Response(bodyBytes, {
      status: 200,
      headers,
    });
  }

  // Add no-cache for WASM files
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
startFileWatcher();
Deno.serve({ port: PORT }, serveHandler);

console.log(`🚀 Server running at http://localhost:${PORT}`);
console.log(`🔥 Hot reload enabled for HTML and WASM files`);
