const zenithor = @import("zenithor");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    var app = zenithor.Application.init(allocator);
    try app.run();
}

const std = @import("std");
