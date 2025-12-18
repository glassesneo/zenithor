# RenderContext Plugin

Core graphics subsystem and render pass lifecycle management for the Zenithor rendering pipeline.

## Purpose

Provides stable, platform-level graphics infrastructure that all rendering plugins can depend on without coupling to specific rendering features (2D/3D shapes, materials, etc.).

**Responsibilities**:
- Graphics subsystem initialization (`sokol.gfx` and `sokol.gl`)
- Render pass lifecycle (beginPass/endPass/commit)
- PassAction resource management
- Graphics backend selection and configuration

## Exported API

**Resource**: `PassAction` - Controls clear color and depth behavior
**Tags**: `Tags.PASS_BEGIN`, `Tags.PASS_END`, `Tags.PASS_COMMIT` - Stable ordering constraints

## Usage

```zig
const RenderContext = @import("render_context_plugin");

// Depend on render context
pub const Requires = .{RenderContext};

// Render within the pass
fn myRenderSystem() void {
    // Runs after PASS_BEGIN, before PASS_END
}

pub const systems = .{
    .main = &.{
        .{ .system = myRenderSystem, .stage = .render },
        // Automatically ordered by RenderContext's extreme priorities
    },
};
```

## Mutating Background Color

```zig
const RenderContext = @import("render_context_plugin");

fn setBackgroundColor(pass_action: ResourceMut(RenderContext.PassAction)) void {
    pass_action.value.colors[0].clear_value = .{ .r = 0.1, .g = 0.1, .b = 0.2, .a = 1.0 };
}
```

## System Guarantees

**Initialization Order** (`.first` stage in `.startup`):
- `initGraphics` runs FIRST (priority -32768) - initializes `sokol.gfx` and `sokol.gl`
- `initPassAction` runs after graphics initialization - sets default clear color

**Render Pass Lifecycle** (every frame):
- `beginPass` runs FIRST in `.render` stage (priority -32768, lowest)
- `endPass` runs LAST in `.render` stage (priority 32760, very high)
- `commit` runs FIRST in `.post_render` stage (priority -32768, lowest)
- All `.render` systems run inside valid render pass

**Shutdown Order** (`.last` stage in `.terminate`):
- `shutdownGraphics` runs in `.last` stage - shuts down `sokol.gl` then `sokol.gfx`
