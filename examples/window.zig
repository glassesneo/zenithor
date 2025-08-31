const zenithor = @import("zenithor");

pub fn main() !void {
    var app = zenithor.Application.init();
    app.run();
}
