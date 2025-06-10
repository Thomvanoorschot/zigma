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
        previous_open: bool = true,
        initial_pos: imgui.ImVec2,
        pos_set: bool = false,
        context: *anyopaque,
        on_close: *const fn (context: *anyopaque, window: *Window(IMPL)) anyerror!void,

        const Self = @This();

        pub fn init(
            allocator: std.mem.Allocator,
            impl: IMPL,
            context: *anyopaque,
            on_close: *const fn (context: *anyopaque, window: *Window(IMPL)) anyerror!void,
            options: WindowOptions,
        ) !*Self {
            const self = try allocator.create(Self);
            self.* = .{
                .impl = impl,
                .initial_pos = options.initial_pos,
                .context = context,
                .on_close = on_close,
            };
            return self;
        }
        pub fn render(self: *Self) !void {
            if (self.previous_open != self.popen) {
                try self.on_close(self.context, self);
                return;
            }
            self.previous_open = self.popen;
            try self.impl.render(self);
        }
    };
}
