const std = @import("std");
const sparze = @import("sparze");
const Struct = std.builtin.Type.Struct;
const StructField = std.builtin.Type.StructField;

pub const AbstractPlugin = struct {
    vtable: *const VTable,
    instance: *anyopaque,
    allocator: std.mem.Allocator,
    const VTable = struct {
        buildFn: *const fn (*anyopaque, *sparze.World) anyerror!void,
        deinitFn: *const fn (*anyopaque) void,
    };

    pub fn build(self: AbstractPlugin, world: *sparze.World) !void {
        try self.vtable.buildFn(self.instance, world);
    }

    pub fn deinit(self: AbstractPlugin) void {
        self.vtable.deinitFn(self.instance);
    }

    pub fn init(comptime P: type, allocator: std.mem.Allocator) !AbstractPlugin {
        const PluginType = Plugin(P);
        const vtable = comptime VTable{
            .buildFn = struct {
                fn build(ptr: *anyopaque, world: *sparze.World) anyerror!void {
                    const self = castTo(PluginType, ptr);

                    // Automatic component registration
                    const ComponentsType = @TypeOf(self.components);
                    inline for (std.meta.fields(ComponentsType)) |field| {
                        // Get pointer to the actual field in the struct
                        const component_set_ptr = &@field(self.components, field.name);
                        const SetType = @TypeOf(@field(self.components, field.name));
                        const ComponentType = SetType.Component;
                        try world.registerComponent(ComponentType, component_set_ptr);
                    }

                    try P.build(world);
                }
            }.build,
            .deinitFn = struct {
                fn deinit(ptr: *anyopaque) void {
                    const self = castTo(PluginType, ptr);
                    const ComponentsType = @TypeOf(self.components);
                    inline for (std.meta.fields(ComponentsType)) |field| {
                        // Get pointer to the actual field in the struct
                        const component_set_ptr = &@field(self.components, field.name);
                        component_set_ptr.deinit();
                    }
                    self.allocator.destroy(self);
                }
            }.deinit,
        };

        const instance = try allocator.create(PluginType);
        instance.*.allocator = allocator;
        const ComponentsType = @TypeOf(instance.components);
        inline for (std.meta.fields(ComponentsType)) |field| {
            // Get pointer to the actual field in the struct
            const component_set_ptr = &@field(instance.components, field.name);
            const SetType = @TypeOf(@field(instance.components, field.name));
            const ComponentType = SetType.Component;

            component_set_ptr.* = sparze.SparseSet(ComponentType).init(allocator);
        }

        return .{
            .vtable = &vtable,
            .instance = instance,
            .allocator = allocator,
        };
    }

    fn castTo(comptime T: type, ptr: *anyopaque) *T {
        return @ptrCast(@alignCast(ptr));
    }
};

fn shortTypeName(comptime T: type) []const u8 {
    var iter = std.mem.splitBackwardsScalar(u8, @typeName(T), '.');
    return iter.first();
}

pub fn tupleToField(comptime types: anytype) [@typeInfo(@TypeOf(types)).@"struct".fields.len]StructField {
    const tuple_info = @typeInfo(@TypeOf(types)).@"struct";
    const tuple_len = tuple_info.fields.len;
    var result_fields: [tuple_len]StructField = undefined;

    for (types, 0..) |Component, i| {
        const type_name = shortTypeName(Component);
        const SparseSetType = sparze.SparseSet(Component);
        result_fields[i] = StructField{
            // .name = std.fmt.comptimePrint("{any}", .{i}),
            .name = type_name ++ "SparseSet",
            .type = SparseSetType,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(SparseSetType),
        };
    }
    return result_fields;
}

fn Plugin(comptime P: type) type {
    const BaseType = struct {
        allocator: std.mem.Allocator,
    };

    const base_info = @typeInfo(BaseType).@"struct";
    const base_fields = base_info.fields;
    var result_fields: [base_fields.len + 1]StructField = undefined;
    @memmove(result_fields[0..base_fields.len], base_fields);

    const Components = if (@hasDecl(P, "Components"))
        P.Components
    else
        .{};
    const components_fields = tupleToField(Components);
    const components_struct = Struct{
        .layout = .auto,
        .fields = &components_fields,
        .decls = &.{},
        .is_tuple = false,
    };

    const ComponentsType = @Type(.{ .@"struct" = components_struct });

    result_fields[base_fields.len] = StructField{
        .name = "components",
        .type = ComponentsType,
        .default_value_ptr = null,
        .is_comptime = false,
        .alignment = @alignOf(ComponentsType),
    };

    const result_struct = Struct{
        .layout = .auto,
        .fields = &result_fields,
        .decls = &.{},
        .is_tuple = false,
    };

    return @Type(.{ .@"struct" = result_struct });
}

test "Create plugins" {
    const Position = struct {
        x: f32,
        y: f32,
    };

    const Velocity = struct {
        x: f32,
        y: f32,
    };

    const ExamplePlugin = struct {
        pub const Components = .{ Position, Velocity };

        pub fn build(world: *sparze.World) !void {
            _ = world;
        }
    };

    const allocator = std.testing.allocator;

    var world = sparze.World.init(allocator);
    defer world.deinit();

    var plugin = try AbstractPlugin.init(ExamplePlugin, allocator);
    defer plugin.deinit();

    try plugin.build(&world);
}
