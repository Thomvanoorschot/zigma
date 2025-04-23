const std = @import("std");
const xev = @import("xev");
const Loop = xev.Loop;
// const App = @import("visualization/app.zig").App;
const window_title = "zigma_client";
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const gl = zopengl.bindings;
const backend =  @import("backend_glfw_opengl.zig");
const gui = @import("gui.zig");
pub fn main() !void {
    var loop = try Loop.init(.{});
    defer loop.deinit();
    // var allocator_state = std.heap.GeneralPurposeAllocator(.{}){};
    // const allocator = allocator_state.allocator();

    // var app = try App.init(
    //     allocator,
    //     &loop,
    //     window_title,
    //     1920,
    //     1080,
    // );
    // app.start();

    try testGlfw();
    // try loop.run(.until_done);
}

fn testGlfw() !void {
    var allocator_state = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = allocator_state.allocator();
    try glfw.init();
    defer glfw.terminate();

    const window = try glfw.Window.create(1920, 1080, "test", null);
    defer window.destroy();

    glfw.makeContextCurrent(window);
    glfw.swapInterval(1);

    const gl_major = 4;
    const gl_minor = 0;
    try zopengl.loadCoreProfile(glfw.getProcAddress, gl_major, gl_minor);


    gui.init(allocator);
    while (!window.shouldClose()) {
        glfw.pollEvents();

        // gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0, 0, 0, 1.0 });

        const fb_size = window.getFramebufferSize();
        backend.newFrame(@intCast(fb_size[0]), @intCast(fb_size[1]));
        // zgui.backend.newFrame(@intCast(fb_size[0]), @intCast(fb_size[1]));

        // if (zgui.begin("My window", .{})) {
        //     if (zgui.button("Press me!", .{ .w = 200.0 })) {
        //         std.debug.print("Button pressed\n", .{});
        //     }
        // }
        // zgui.end();
        // zgui.showDemoWindow(null);
        // zgui.plot.showDemoWindow(null);

        // if (self.orderbook) |ob| {
        //     plotOrderbookWindow(ob) catch unreachable;
        // }

        // if (self.ohlc_list) |ohlc_list| {
        //     plotOHLCListWindow(self.allocator, ohlc_list) catch unreachable;
        // }

        // zgui.backend.draw();

        // window.swapBuffers();
    }
}
