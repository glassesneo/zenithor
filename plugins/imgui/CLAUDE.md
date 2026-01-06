# ImGui Plugin

Dear ImGui integration for debug UI and tools.

## Build Options

```bash
-Dimgui-docking    # Enable docking features (optional)
```

## Exported API

Provides `ig` namespace (cimgui or cimgui_docking) and wrapper functions:

**Windows**: `begin()`, `end()`, `setNextWindowPos()`, `setNextWindowSize()`
**Layout**: `separator()`, `spacing()`, `sameLine()`, `indent()`, `unindent()`
**Text**: `text()`, `textFmt()`, `textColored()`, `textColoredFmt()`, `textWrapped()`, `bulletText()`, `bulletTextFmt()`
**Widgets**: `button()`, `sliderFloat()`, `sliderInt()`

Full C API available through `ImGui.ig.*` for advanced usage.

## Usage

```zig
const ImGui = @import("imgui_plugin");

const zenithor = @import("zenithor");
const Resource = zenithor.Resource;
const Time = @import("time_plugin").Time;

fn debugUI(time: Resource(Time)) !void {
    if (ImGui.begin("Debug", null, .None)) {
        ImGui.textFmt("FPS: {d:.1}", .{time.value.fps});
        if (ImGui.button("Reset")) {
            // Handle reset
        }
    }
    ImGui.end();
}
```

## Implementation

- Depends on Renderer plugin for render pass lifecycle
- Frame setup in `.first` stage
- Rendering in `.render` stage with high priority (1000) to render after 3D content
- Event handler processes input automatically
- Docking enabled via `ConfigFlags_DockingEnable` when `-Dimgui-docking` used

## Documentation

- **@docs/PLUGIN_DEVELOPMENT.md** - Creating custom plugins
- [Dear ImGui API](https://github.com/ocornut/imgui) - Full C++ API reference
