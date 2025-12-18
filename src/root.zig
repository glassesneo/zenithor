//! Zenithor public API surface.
//!
//! **Ubiquitous Language**: Plugin System, World Construction, System Ordering, ECS, Plugin Dependency
//!
//! This module re-exports the core APIs for building Zenithor applications:
//! - Application lifecycle (`run`)
//! - System scheduling (`Stage`, `SystemConfig`)
//! - Builtin components (`Transform`, `Color`, `Rotation`, `Scale`)
//! - Sparze ECS types (`Entity`, `Query`, `Resource`, `EventWriter`, etc.)
//!
//! Most types are re-exports from Sparze or core modules.
//!
//! **See Also**:
//! - docs/APPLICATION_LIFECYCLE.md - Detailed `zenithor.run()` flow
//! - docs/SYSTEM_ORDERING.md - System execution order and constraints
//! - docs/PLUGIN_DEVELOPMENT.md - Creating plugins step-by-step

const application_module = @import("core/application.zig");

/// Main entry point for Zenithor applications.
///
/// **Ubiquitous Language**: Application Lifecycle, Plugin Expansion, Event Handlers, World Construction
///
/// Initializes the engine, expands plugin dependencies, constructs the ECS World,
/// and runs the main loop (startup → frames → terminate).
///
/// **Critical constraints**:
/// - Core initializes `sokol.gfx`, `sokol.gl`, and `sokol.time` centrally
/// - Subsystem plugins may initialize their own modules (e.g., `imgui_plugin` → `sokol.imgui`)
/// - Event handlers must have signature `fn(sokol.app.Event, world: anytype) void|!void`
/// - Errors in event handlers are caught and enqueued as `BuiltinPlugin.EventLoopError`
/// - Errors in systems are caught and enqueued as `BuiltinPlugin.GameLoopError`
///
/// **Allocator/lifetime model**:
/// - Single arena allocator per application
/// - Native: pass base allocator via `zenithor.run(..., .{ .allocator = your_allocator })`
/// - WASM: uses `std.heap.c_allocator`, heap-allocates `AppState` (never freed until tab close)
///
/// **Plugin contract** (`pub const systems`):
/// - `.startup = &.{...}` - Systems run once on initialization
/// - `.main = &.{...}` - Systems run every frame
/// - `.terminate = &.{...}` - Systems run once on shutdown
/// - `.event_handlers = &.{...}` - Sokol event handlers
///
/// **See Also**: docs/APPLICATION_LIFECYCLE.md
pub const run = application_module.run;

const system_module = @import("core/system.zig");

/// Frame execution stages (fixed order).
///
/// **Ubiquitous Language**: Frame Stages, Render Submit, Post-Process
///
/// Systems run in stage order every frame:
/// ```
/// .first → .pre_update → .update → .post_update →
/// .pre_render → .render → .render_submit → .post_render →
/// .last → .post_process
/// ```
///
/// Stage ordering is **fixed**. System order **within a stage** is configurable
/// via priority, tags, and before/after constraints.
///
/// **Common stage usage**:
/// - `.first` - Early setup (Time update, ImGui frame start)
/// - `.update` - Main game logic (movement, AI, physics)
/// - `.render` - Drawing operations (2D shapes, 3D meshes)
/// - `.render_submit` - Batch submission (Graphics flush, ImGui render)
/// - `.last` - Late cleanup (Input reset, frame counters)
///
/// **See Also**: docs/SYSTEM_ORDERING.md
pub const Stage = system_module.Stage;

/// Optional configuration for system ordering within a stage.
///
/// **Ubiquitous Language**: System Ordering, Priority, Tags, Constraints, Before/After
///
/// Controls system execution order via:
/// - `priority: i16 = 0` - Lower values run first (stable sort)
/// - `tags: []const []const u8 = &.{}` - Tag this system for constraint references
/// - `before: []const []const u8 = &.{}` - Run before all systems with these tags
/// - `after: []const []const u8 = &.{}` - Run after all systems with these tags
///
/// **Ordering resolution** (within each stage):
/// 1. Registration order (plugin expansion order + declaration order)
/// 2. Stable priority sort (lower values first)
/// 3. Constraint resolution (topological sort preserving priority groups)
///
/// **Validation** (Debug/ReleaseSafe only):
/// - Missing tags → panic during `finalize()`
/// - Circular constraints → panic during `finalize()`
/// - ReleaseFast/ReleaseSmall: validation skipped for performance
///
/// **See Also**: docs/SYSTEM_ORDERING.md
pub const SystemConfig = system_module.SystemConfig;

// Core engine exports
pub const BuiltinPlugin = @import("core/builtin.zig");
pub const Transform = BuiltinPlugin.Transform;
pub const Rotation = BuiltinPlugin.Rotation;
pub const Scale = BuiltinPlugin.Scale;
pub const Color = BuiltinPlugin.Color;

const sparze = @import("sparze");
pub const Entity = sparze.Entity;
pub const SingleQuery = sparze.SingleQuery;
pub const Query = sparze.Query;
pub const SingleTag = sparze.SingleTag;
pub const TagQuery = sparze.TagQuery;
pub const Group = sparze.Group;
pub const Resource = sparze.Resource;
pub const ResourceMut = sparze.ResourceMut;
pub const EventWriter = sparze.EventWriter;
pub const EventReader = sparze.EventReader;

test {
    std.testing.refAllDecls(@This());
}

const std = @import("std");
