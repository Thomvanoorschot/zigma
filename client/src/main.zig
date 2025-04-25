const std = @import("std");
const xev = @import("xev");
const Loop = xev.Loop;
// const App = @import("visualization/app.zig").App;
const window_title = "zigma_client";
const glfw = @import("zglfw");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const gui = @import("gui.zig");
const plot = @import("plot.zig");
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

var gctx: *zgpu.GraphicsContext = undefined;

fn testGlfw() !void {
    var allocator_state = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = allocator_state.allocator();
    try glfw.init();
    defer glfw.terminate();

    glfw.windowHint(.client_api, .no_api);
    const window = try glfw.Window.create(1920, 1080, "test", null);
    defer window.destroy();
    // window.setSizeLimits(400, 400, -1, -1);

    gctx = try zgpu.GraphicsContext.create(
        allocator,
        .{
            .window = window,
            .fn_getTime = @ptrCast(&glfw.getTime),
            .fn_getFramebufferSize = @ptrCast(&glfw.Window.getFramebufferSize),
            // .fn_getWin32Window = @ptrCast(&glfw.getWin32Window),
            // .fn_getX11Display = @ptrCast(&glfw.getX11Display),
            // .fn_getX11Window = @ptrCast(&glfw.getX11Window),
            // .fn_getWaylandDisplay = @ptrCast(&glfw.getWaylandDisplay),
            // .fn_getWaylandSurface = @ptrCast(&glfw.getWaylandWindow),
            .fn_getCocoaWindow = @ptrCast(&glfw.getCocoaWindow),
        },
        .{},
    );
    defer gctx.destroy(allocator);

    gui.init(allocator);
    gui.backend.init(
        window,
        gctx.device,
        @intFromEnum(zgpu.GraphicsContext.swapchain_format),
        @intFromEnum(wgpu.TextureFormat.undef),
    );
    defer gui.backend.deinit();

    const scale_factor = scale_factor: {
        const scale = window.getContentScale();
        break :scale_factor @max(scale[0], scale[1]);
    };
    gui.getStyle().scaleAllSizes(scale_factor);

    plot.init();
    defer plot.deinit();

    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        glfw.pollEvents();

        gui.backend.newFrame(
            gctx.swapchain_descriptor.width,
            gctx.swapchain_descriptor.height,
        );

        if (gui.begin("My window", .{})) {
            if (gui.button("Press me!", .{ .w = 200.0 })) {
                std.debug.print("Button pressed\n", .{});
            }
        }
        gui.end();
        gui.showDemoWindow(null);
        plot.showDemoWindow(null);

        const swapchain_texv = gctx.swapchain.getCurrentTextureView();
        defer swapchain_texv.release();

        const commands = commands: {
            const encoder = gctx.device.createCommandEncoder(null);
            defer encoder.release();

            // GUI pass
            {
                const pass = zgpu.beginRenderPassSimple(
                    encoder,
                    .load,
                    swapchain_texv,
                    null,
                    null,
                    null,
                );
                defer zgpu.endReleasePass(pass);
                gui.backend.draw(pass);
            }

            break :commands encoder.finish(null);
        };
        defer commands.release();

        gctx.submit(&.{commands});
        _ = gctx.present();
    }
}
