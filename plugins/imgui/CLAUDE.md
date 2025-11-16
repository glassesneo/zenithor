# ImGui Plugin

Dear ImGui integration for debug UI and tools.

## Build Options

- `-Dimgui-docking` - Enable docking features (optional)

## Exported API

Provides `ig` namespace (`cimgui` or `cimgui_docking` based on build option) and wrapper functions:

**Window Management**
```zig
begin(name: [:0]const u8, open: ?*bool, flags: ImGuiWindowFlags) bool
end() void
```

**Layout**
```zig
separator(), spacing(), sameLine()
indent(), unindent()
```

**Text**
```zig
text(content: [:0]const u8)
textFmt(comptime fmt: []const u8, args: anytype)
textColored(color: ImVec4, content: [:0]const u8)
textColoredFmt(color: ImVec4, comptime fmt: []const u8, args: anytype)
textWrapped(content: [:0]const u8)
bulletText(content: [:0]const u8)
bulletTextFmt(comptime fmt: []const u8, args: anytype)
```

**Widgets**
```zig
button(label: [:0]const u8) bool
sliderFloat(label: [:0]const u8, value: *f32, min: f32, max: f32) bool
sliderInt(label: [:0]const u8, value: *i32, min: i32, max: i32) bool
```

**Window Positioning**
```zig
setNextWindowPos(pos: ImVec2, cond: ImGuiCond)
setNextWindowSize(size: ImVec2, cond: ImGuiCond)
```

## Usage

```zig
const ImGui = @import("imgui_plugin");

fn debugUI(time: Resource(Time)) !void {
    if (ImGui.begin("Debug", null, .None)) {
        ImGui.textFmt("FPS: {d:.1}", .{time.value.fps});
        ImGui.textFmt("Frame: {}", .{time.value.frame_count});

        if (ImGui.button("Reset")) {
            // Handle reset
        }
    }
    ImGui.end();
}

// Register in plugin build()
registry.registerSystem(debugUI, .update);
```

## Implementation Notes

- Frame setup runs in `.first` stage
- Rendering runs in `.render_submit` stage
- Event handler automatically processes input
- Docking enabled via `ConfigFlags_DockingEnable` when `-Dimgui-docking` used
- Full C API available through `ImGui.ig.*` for advanced usage
