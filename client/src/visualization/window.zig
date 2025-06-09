const std = @import("std");
const zignite = @import("zignite");
const imgui = zignite.imgui;

pub const WindowOptions = struct {
    initial_pos: imgui.ImVec2 = .{ .x = 0, .y = 0 },
};

pub fn Window(comptime IMPL: type) type {
    comptime {
        if (!@hasDecl(IMPL, "render")) {
            @compileError("Implementation must implement 'render' method.");
        }
    }
    return struct {
        impl: IMPL,
        popen: bool = true,
        initial_pos: imgui.ImVec2,
        pos_set: bool = false,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, impl: IMPL, options: WindowOptions) !*Self {
            const self = try allocator.create(Self);
            self.* = .{
                .impl = impl,
                .initial_pos = options.initial_pos,
            };
            return self;
        }
        pub fn render(self: *Self) !void {
            try self.impl.render(self);
        }
    };
}
