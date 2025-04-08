const std = @import("std");
const zgui = @import("zgui");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const xev = @import("xev");
const orderbook_chart = @import("orderbook_chart.zig");
const plotOrderbookWindow = orderbook_chart.plotOrderbookWindow;
const gl = zopengl.bindings;
const TCP = xev.TCP;

pub const App = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    loop: *xev.Loop,
    window: *glfw.Window,
    render_frame_completion: xev.Completion = undefined,

    socket: TCP,
    server_addr: std.net.Address,
    connect_completion: xev.Completion = undefined,
    read_completion: xev.Completion = undefined,
    read_buf: [1024]u8 = undefined,
    pub fn init(
        allocator: std.mem.Allocator,
        loop: *xev.Loop,
        comptime title: [:0]const u8,
        comptime width: i32,
        comptime height: i32,
    ) !*Self {
        try glfw.init();

        const gl_major = 4;
        const gl_minor = 0;
        glfw.windowHint(.context_version_major, gl_major);
        glfw.windowHint(.context_version_minor, gl_minor);
        glfw.windowHint(.opengl_profile, .opengl_core_profile);
        glfw.windowHint(.opengl_forward_compat, true);
        glfw.windowHint(.client_api, .opengl_api);
        glfw.windowHint(.doublebuffer, true);

        const window = try glfw.Window.create(width, height, title, null);
        window.setSizeLimits(width, height, -1, -1);

        glfw.makeContextCurrent(window);
        glfw.swapInterval(1);

        try zopengl.loadCoreProfile(glfw.getProcAddress, gl_major, gl_minor);

        zgui.init(allocator);

        const scale_factor = scale_factor: {
            const scale = window.getContentScale();
            break :scale_factor @max(scale[0], scale[1]);
        };
        zgui.getStyle().scaleAllSizes(scale_factor);

        zgui.backend.init(window);

        zgui.plot.init();

        const self = try allocator.create(Self);
        const server_addr = try std.net.Address.parseIp4("127.0.0.1", 8081);
        self.* = Self{
            .allocator = allocator,
            .loop = loop,
            .window = window,
            .socket = try TCP.init(server_addr),
            .server_addr = server_addr,
        };
        return self;
    }

    pub fn start(self: *Self) void {
        const callback = struct {
            fn inner(
                ud: ?*anyopaque,
                l: *xev.Loop,
                c: *xev.Completion,
                _: xev.Result,
            ) xev.CallbackAction {
                var app = @as(*Self, @ptrCast(@alignCast(ud.?)));
                app.renderFrame();
                if (!app.window.shouldClose() and app.window.getKey(.escape) != .press) {
                    l.timer(c, 16, ud, inner);
                    return .disarm;
                }
                app.deinit();
                return .disarm;
            }
        }.inner;
        self.loop.timer(&self.render_frame_completion, 0, @ptrCast(self), callback);
        self.socket.connect(self.loop, &self.connect_completion, self.server_addr, Self, self, connectCallback);
    }

    pub fn deinit(self: *Self) void {
        self.loop.deinit();
        zgui.backend.deinit();
        zgui.deinit();
        zgui.plot.deinit();
        glfw.terminate();
        self.window.destroy();
    }

    pub fn renderFrame(self: *Self) void {
        glfw.pollEvents();

        gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0, 0, 0, 1.0 });

        const fb_size = self.window.getFramebufferSize();

        zgui.backend.newFrame(@intCast(fb_size[0]), @intCast(fb_size[1]));

        if (zgui.begin("My window", .{})) {
            if (zgui.button("Press me!", .{ .w = 200.0 })) {
                std.debug.print("Button pressed\n", .{});
            }
        }
        zgui.end();
        zgui.showDemoWindow(null);
        zgui.plot.showDemoWindow(null);

        zgui.backend.draw();

        self.window.swapBuffers();
    }

    fn connectCallback(
        self_: ?*Self,
        l: *xev.Loop,
        c: *xev.Completion,
        _: TCP,
        r: xev.ConnectError!void,
    ) xev.CallbackAction {
        const self = self_.?;

        r catch |err| {
            std.debug.print("Callback error: {s}\n", .{@errorName(err)});
            return .disarm;
        };

        std.debug.print("Connected to server\n", .{});

        self.socket.write(l, c, .{ .slice = "Connection: keep-alive\r\nstart" }, Self, self, writeCallback);
        return .disarm;
    }

    fn writeCallback(
        self_: ?*Self,
        l: *xev.Loop,
        _: *xev.Completion,
        _: TCP,
        _: xev.WriteBuffer,
        r: xev.WriteError!usize,
    ) xev.CallbackAction {
        const self = self_.?;
        _ = r catch |err| {
            std.debug.print("Callback error: {s}\n", .{@errorName(err)});
            return .disarm;
        };
        std.debug.print("Wrote to server\n", .{});

        self.socket.read(l, &self.read_completion, .{ .slice = &self.read_buf }, Self, self, readCallback);

        return .disarm;
    }

    fn readCallback(
        self_: ?*Self,
        l: *xev.Loop,
        c: *xev.Completion,
        _: TCP,
        buf: xev.ReadBuffer,
        r: xev.ReadError!usize,
    ) xev.CallbackAction {
        const self = self_.?;
        const n = r catch |err| {
            std.debug.print("Read error: {s}\n", .{@errorName(err)});
            return .disarm;
        };

        const received_data = buf.slice[0..n];
        std.debug.print("Received data: {s}\n", .{received_data});

        self.socket.read(l, c, .{ .slice = &self.read_buf }, Self, self, readCallback);
        return .disarm;
    }
};
