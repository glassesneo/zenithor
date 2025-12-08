const application_module = @import("core/application.zig");
pub const run = application_module.run;

const system_module = @import("core/system.zig");
pub const Stage = system_module.Stage;
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
