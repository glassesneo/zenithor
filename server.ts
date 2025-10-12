import { serveDir } from "jsr:@std/http@1";

const fsRoot = Deno.args[0] ?? "./zig-out/web";

Deno.serve({ port: 8000 }, (req) => {
  return serveDir(req, { fsRoot });
});

console.log("🚀 Server running at http://localhost:8000");
