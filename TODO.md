## Centralized Sokol Initialization - COMPLETED

All tasks have been successfully implemented and verified.

### Summary

Centralized all `sokol.*.setup()` and `sokol.*.shutdown()` calls in `src/core/application.zig` to ensure clear initialization order and ownership. Plugins no longer manage Sokol module lifecycle.

### Changes Made

**1. Core Application (`src/core/application.zig`):**
- Added centralized `sokol.time.setup()` and `sokol.imgui.setup()` in `appInit()` (lines 291-307)
- Added centralized `sokol.imgui.shutdown()` in `appCleanup()` (lines 308-321)
- Documented initialization order with comments explaining dependencies

**2. Time Plugin (`plugins/time/src/root.zig`):**
- Removed `init()` function and its `sokol.time.setup()` call
- Removed startup system registration for `init()`
- Added comment: "sokol.time is initialized centrally in src/core/application.zig"

**3. Debug Plugin (`plugins/debug/src/root.zig`):**
- Removed duplicate `sokol.time.setup()` call from `initDebugState()` (line 80)
- Added comment explaining central initialization

**4. ImGui Plugin (`plugins/imgui/src/root.zig`):**
- Removed `init()` function with `sokol.imgui.setup()` call
- Removed `deinit()` function with `sokol.imgui.shutdown()` call
- Removed startup and terminate system registrations
- Added comments explaining central initialization and shutdown

**5. Documentation (`CLAUDE.md`):**
- Added "Sokol Module Initialization" section (after "Entry Point Flow")
- Documented initialization order and dependencies
- Documented shutdown order (reverse of initialization)
- Documented plugin assumptions and rationale

### Verification

✅ Unit tests pass: `zig build test`
✅ Native examples build: `demo_window`, `demo_2d`, `demo_imgui`, `demo_time`, `demo_debug`
✅ WebAssembly examples build: `zig build examples -Dtarget=wasm32-emscripten`
✅ Native example runs successfully: `demo_window` launches and displays

### Benefits Achieved

- **No duplicate initialization**: Prevents conflicts from multiple plugins initializing the same module
- **Explicit ordering**: Dependencies (ImGui → GL/GFX) are clear and documented
- **Single source of truth**: All Sokol lifecycle management in one place
- **Simplified plugins**: Plugins focus on game logic without managing low-level initialization

---

### Original Investigation and Planning

Goal: Centralize all `sokol.*.setup()` and `sokol.*.shutdown()` calls in `src/core/application.zig` so initialization order and ownership are clear.

Investigation summary
- Current setup call locations (found via repo search):
  - `src/core/application.zig:291` — `sokol.gfx.setup()` (already centralized)
  - `src/core/application.zig:295` — `sokol.gl.setup()` (already centralized)
  - `plugins/time/src/root.zig:40` — `sokol.time.setup()` (time plugin startup system)
  - `plugins/debug/src/root.zig:80` — `sokol.time.setup()` (debug plugin lazy init)
  - `plugins/imgui/src/root.zig:35` — `sokol.imgui.setup()` (imgui plugin startup system)

Risks & notes
- Order matters: `sokol.gfx.setup()` / `sokol.gl.setup()` must run before modules that rely on GL/GFX (e.g. `sokol.imgui.setup()`). Current flow is: register plugin systems during `Plugin.build()` (compile-time), then `sokol.gfx.setup()` + `sokol.gl.setup()` in `appInit`, and only after that do startup systems run — so plugin setup calls happen safely in startup systems currently.
- Duplicate setup calls exist (e.g., `sokol.time.setup()` in both Time plugin and Debug plugin). Duplicate or out-of-order calls could cause reinitialization bugs if a `setup()` function is not idempotent.
- Plugins currently call `sokol.*.setup()` inside startup systems or lazy initialization functions; centralizing reduces duplication and makes ordering explicit.
- Some modules may not require explicit shutdown, but `sokol.imgui.shutdown()` is currently invoked in the ImGui plugin's terminate system and `sokol.gl.shutdown()`/`sokol.gfx.shutdown()` are invoked centrally in `appCleanup`. Decide whether shutdown should also be centralized to maintain symmetry.

Recommendation
- Centralize module setup and shutdown calls in `src/core/application.zig` (appInit and appCleanup).
- Remove `sokol.*.setup()` calls from plugins (Time, ImGui, Debug), and remove `sokol.imgui.shutdown()` from ImGui plugin. Plugins should assume the module runtime is already initialized by the application.
- Ensure ordering in `appInit`:
  1. `sokol.gfx.setup()` and `sokol.gl.setup()` (already present)
  2. `sokol.time.setup()` (time needs to be ready before time-using systems)
  3. `sokol.imgui.setup()` (after GL/GFX)
  4. Any other sokol modules in the future
- For conditional setup (only call `sokol.imgui.setup()` if ImGui plugin is present), implement a small compile-time check in `run()` using `comptime` presence of plugin (e.g. check if any plugin has `Components` tuple containing `imgui` types or more explicitly detect the ImGui plugin type when known). If compile-time detection is awkward, call setup unconditionally if it is safe, or gate it behind a `build` flag.
- Centralize shutdown similarly in `appCleanup`, calling module-specific shutdowns in reverse order of initialization.

Implementation tasks (to-do)
1. Audit occurrences of sokol setup/shutdown
   - Files: `src/core/application.zig:291`, `src/core/application.zig:295`, `plugins/time/src/root.zig:40`, `plugins/debug/src/root.zig:80`, `plugins/imgui/src/root.zig:35`
   - Acceptance: list of file locations confirmed and added to change set.

2. Add centralized setup calls in `src/core/application.zig`
   - Add calls to `sokol.time.setup()` and `sokol.imgui.setup()` in `appInit` after `sokol.gfx.setup()` & `sokol.gl.setup()` and before `App.world.beginFrame()` and running startup systems.
   - If possible, gate `sokol.imgui.setup()` behind a `comptime` check detecting the ImGui plugin.
   - Acceptance: `appInit` contains all required `sokol.*.setup()` calls and ordering is documented in code comments.

3. Remove `sokol.*.setup()` calls from plugins
   - Time plugin: remove `sokol.time.setup()` from `plugins/time/src/root.zig` (init system will no longer call it).
   - Debug plugin: remove `sokol.time.setup()` from `plugins/debug/src/root.zig` `initDebugState` (assume time already initialized).
   - ImGui plugin: remove `sokol.imgui.setup()` from `plugins/imgui/src/root.zig` `init()` and rely on central setup.
   - Acceptance: plugins no longer call `sokol.*.setup()`.

4. Centralize shutdown calls
   - Move `sokol.imgui.shutdown()` out of `plugins/imgui` terminate system and call it (plus any other module-specific shutdowns) from `appCleanup` in `src/core/application.zig`, in reverse order of setup.
   - Acceptance: `appCleanup` calls module shutdowns and plugins do not call module shutdowns themselves.

5. Update plugins' init/cleanup semantics and docs
   - Add comments to plugin source indicating that sokol initialization is handled by the application.
   - Update `CLAUDE.md` or README to document centralization policy.
   - Acceptance: docs updated and plugin files contain explanatory comments.

6. Testing & verification
   - Run native examples: `zig build run-demo_window`, `zig build run-demo_2d` and web dev server for wasm examples as needed to verify behavior.
   - Verify ImGui windows render, time and debug metrics work, and no crashes occur at startup/shutdown.
   - Acceptance: examples run without regressions; if regressions occur, revert or add guarding logic.

7. Optional: Add compile-time detection for plugin-specific setup
   - Implement `comptime` detection in `run(comptime user_plugins)` to call module setup only when corresponding plugin is present (recommended if you want minimal/no-op module initialization).
   - Acceptance: conditional setup works and prevents unnecessary module initialization.

Rollback plan
- Keep a branch with the changes; if odd runtime behavior appears, revert plugin setup removals and re-evaluate order or idempotency.

Estimated risk and effort
- Risk: Low–Medium. Most work is refactoring initialization calls and should be safe if ordering is preserved. The main hazard is calling `setup()` multiple times or too early/late; thorough testing of examples mitigates risk.
- Effort: Small (1–3 hours) to implement and test across examples.

If you want, I can implement the TODO plan now: remove plugin setup calls and centralize them in `src/core/application.zig`, and run quick build/test steps. Reply with "Yes, implement" to proceed or ask for adjustments to the task list.
