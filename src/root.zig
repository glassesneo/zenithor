//! Zenithor public API surface.
//!
//! **Ubiquitous Language**: Plugin System, World Construction, System Ordering, ECS, Plugin Dependency
//!
//! This module re-exports the core APIs for building Zenithor applications:
//! - Application lifecycle (`run`)
//! - Platform abstraction (window, cursor, clipboard)
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
/// - Core manages app loop and plugin orchestration only
/// - Plugins initialize their own subsystems (`render_context` → `sokol.gfx/gl`, `time_plugin` → `sokol.time`, `imgui_plugin` → `sokol.imgui`)
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
/// **Ubiquitous Language**: Frame Stages, Post-Process
///
/// Systems run in stage order every frame:
/// ```
/// .first → .pre_update → .update → .post_update →
/// .pre_render → .render → .post_render → .last → .post_process
/// ```
///
/// Stage ordering is **fixed**. System order **within a stage** is configurable
/// via priority, tags, and before/after constraints.
///
/// **Common stage usage**:
/// - `.first` - Early setup (Time update, ImGui frame start)
/// - `.update` - Main game logic (movement, AI, physics)
/// - `.render` - Drawing operations (2D shapes, 3D meshes, ImGui render)
/// - `.post_render` - Render finalization (Pass commit)
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

// =============================================================================
// PLATFORM ABSTRACTION LAYER
// =============================================================================
// Stateless functions for window, cursor, clipboard, and application control.
// These wrap the underlying platform layer so users never need to import sokol.

/// Mouse cursor types for `setCursor()`.
pub const Cursor = application_module.Cursor;

// Window functions
pub const windowWidth = application_module.windowWidth;
pub const windowHeight = application_module.windowHeight;
pub const windowWidthF = application_module.windowWidthF;
pub const windowHeightF = application_module.windowHeightF;
pub const dpiScale = application_module.dpiScale;
pub const isHighDpi = application_module.isHighDpi;
pub const isFullscreen = application_module.isFullscreen;
pub const toggleFullscreen = application_module.toggleFullscreen;
pub const setWindowTitle = application_module.setWindowTitle;

// Cursor functions
pub const showCursor = application_module.showCursor;
pub const isCursorVisible = application_module.isCursorVisible;
pub const lockCursor = application_module.lockCursor;
pub const isCursorLocked = application_module.isCursorLocked;
pub const setCursor = application_module.setCursor;
pub const getCursor = application_module.getCursor;
pub const captureCursor = application_module.captureCursor;

// Clipboard functions
pub const setClipboard = application_module.setClipboard;
pub const getClipboard = application_module.getClipboard;

// Application lifecycle functions
pub const requestQuit = application_module.requestQuit;
pub const cancelQuit = application_module.cancelQuit;
pub const quit = application_module.quit;
pub const frameCount = application_module.frameCount;
pub const frameDuration = application_module.frameDuration;

// Mobile/virtual keyboard functions
pub const showKeyboard = application_module.showKeyboard;
pub const isKeyboardVisible = application_module.isKeyboardVisible;

// File drop functions
pub const getDroppedFileCount = application_module.getDroppedFileCount;
pub const getDroppedFilePath = application_module.getDroppedFilePath;

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
