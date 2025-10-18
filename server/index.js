// Fetch and display available examples
async function loadExamples() {
  try {
    const response = await fetch("/__api/examples");
    const examples = await response.json();

    const container = document.getElementById("examples");

    if (examples.length === 0) {
      container.innerHTML = `
        <div class="empty">
          <div class="empty-icon">📦</div>
          <h2>No examples found</h2>
          <p>Build examples with: <code>zig build examples-web -Dtarget=wasm32-emscripten</code></p>
        </div>
      `;
    } else {
      container.innerHTML = examples.map((ex) => `
        <a href="${ex.htmlPath}" class="example-card">
          <div class="example-title">${ex.name}</div>
          <div class="example-meta">
            <span><span class="badge">${ex.wasmSize}</span></span>
            <span>📅 ${ex.lastModified}</span>
          </div>
        </a>
      `).join("");
    }
  } catch (error) {
    console.error("Failed to load examples:", error);
    document.getElementById("examples").innerHTML = `
      <div class="empty">
        <div class="empty-icon">⚠️</div>
        <h2>Failed to load examples</h2>
        <p>Please check the console for errors.</p>
      </div>
    `;
  }
}

// Load examples when page loads
loadExamples();
