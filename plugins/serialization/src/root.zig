const std = @import("std");
const sparze = @import("sparze");
const builtin = @import("builtin");

const is_debug = builtin.mode == .Debug;

const SingleQuery = sparze.SingleQuery;
const Query = sparze.Query;
const Resource = sparze.Resource;
const ResourceMut = sparze.ResourceMut;
const zenithor = @import("zenithor");
const Stage = zenithor.Stage;
const Transform = zenithor.Transform;
const Color = zenithor.Color;

/// Save file resource containing metadata about the save
pub const SaveFile = struct {
    path: [256:0]u8 = [_:0]u8{0} ** 256,
    len: usize = 0,
    timestamp: i128 = 0,
    checksum_valid: bool = false,

    pub fn getPath(self: *const SaveFile) []const u8 {
        return self.path[0..self.len];
    }

    pub fn getPathZ(self: *const SaveFile) [:0]const u8 {
        // For C APIs that need null-terminated strings
        if (is_debug) {
            std.debug.assert(self.path[self.len] == 0);
        }
        return self.path[0..self.len :0];
    }
};

pub const Resources = .{SaveFile};
pub const Events = .{};
pub const Components = .{};

/// Save game system - uses Commands API only
pub fn saveGame(
    commands: anytype,
    save_file: ResourceMut(SaveFile),
) !void {
    const path = save_file.value.getPath();
    if (path.len == 0) return;

    std.debug.print("💾 Saving game to: {s}\n", .{path});

    try commands.serializeToFile(path);

    // Update metadata
    const file = std.fs.cwd().openFile(path, .{}) catch return;
    defer file.close();
    const stat = file.stat() catch return;
    save_file.value.timestamp = stat.mtime;
    save_file.value.checksum_valid = true;

    std.debug.print("✅ Save complete!\n", .{});
}

/// Load game system - uses Commands API only
pub fn loadGame(
    commands: anytype,
    save_file: ResourceMut(SaveFile),
) !void {
    const path = save_file.value.getPath();
    if (path.len == 0) return;

    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        std.debug.print("❌ Save file not found: {s}\n", .{@errorName(err)});
        return;
    };
    defer file.close();

    std.debug.print("📂 Loading game from: {s}\n", .{path});

    try commands.deserializeFromFile(path);

    // Update metadata
    const stat = file.stat() catch return;
    save_file.value.timestamp = stat.mtime;
    save_file.value.checksum_valid = true;

    std.debug.print("✅ Load complete!\n", .{});
}

fn init(commands: anytype) void {
    // Initialize resources with defaults
    const save_filename = "savegame.spze";
    var save_path: SaveFile = .{};

    // Copy filename into path buffer
    for (save_filename, 0..) |c, i| {
        save_path.path[i] = c;
    }
    save_path.len = save_filename.len;

    commands.setResource(SaveFile, save_path);

    std.debug.print("SerializationPlugin: Save/Load systems available\n", .{});
    std.debug.print("Default save path: {s}\n", .{save_path.getPath()});
}

// Declarative system registration
pub const systems = .{
    .startup = &.{
        .{ .system = init, .stage = .first },
    },
};
