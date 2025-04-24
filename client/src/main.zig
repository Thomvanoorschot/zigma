const std = @import("std");
const xev = @import("xev");
const Loop = xev.Loop;
// const App = @import("visualization/app.zig").App;
const window_title = "zigma_client";
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const gl = zopengl.bindings;
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
    glfw.windowHint(.context_version_major, gl_major);
    glfw.windowHint(.context_version_minor, gl_minor);
    glfw.windowHint(.opengl_profile, .opengl_core_profile);
    glfw.windowHint(.opengl_forward_compat, true);
    glfw.windowHint(.client_api, .opengl_api);
    glfw.windowHint(.doublebuffer, true);
    try zopengl.loadCoreProfile(glfw.getProcAddress, gl_major, gl_minor);

    const gl_version_ptr = gl.getString(gl.VERSION);
    const glsl_version_ptr = gl.getString(gl.SHADING_LANGUAGE_VERSION);

    if (gl_version_ptr) |ptr| {
        // Assuming ptr is null-terminated, which gl.getString should return
        const gl_version = std.mem.sliceTo(ptr, 0);
        std.debug.print("Actual OpenGL Version: {s}\n", .{gl_version});
    } else {
        std.debug.print("Failed to get OpenGL Version string\n", .{});
    }

    if (glsl_version_ptr) |ptr| {
        // Assuming ptr is null-terminated
        const glsl_version = std.mem.sliceTo(ptr, 0);
        std.debug.print("Actual GLSL Version: {s}\n", .{glsl_version});
    } else {
        std.debug.print("Failed to get GLSL Version string\n", .{});
    }

    gui.init(allocator);
    gui.backend.init(window);
    defer gui.backend.deinit();
    while (!window.shouldClose()) {
        glfw.pollEvents();

        // gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0, 0, 0, 1.0 });

        gl.clear(gl.COLOR_BUFFER_BIT);

        const fb_size = window.getFramebufferSize();
        gui.backend.newFrame(@intCast(fb_size[0]), @intCast(fb_size[1]));

        if (gui.begin("My window", .{})) {
            if (gui.button("Press me!", .{ .w = 200.0 })) {
                std.debug.print("Button pressed\n", .{});
            }
        }
        gui.end();
        gui.showDemoWindow(null);
        gui.backend.draw();

        window.swapBuffers();
    }
}
