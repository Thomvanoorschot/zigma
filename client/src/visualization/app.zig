const std = @import("std");
const sokol = @import("sokol");
const implot = @import("implot");
const imgui = @import("imgui");
const orderbook_chart = @import("orderbook_chart.zig");
const sapp = sokol.app;
const sg = sokol.gfx;
const slog = sokol.log;
const sglue = sokol.glue;
const plotOrderbookWindow = orderbook_chart.plotOrderbookWindow;

const State = struct {
    var pass_action: sg.PassAction = .{};
};

pub const App = struct {
    pub fn init(width: i32, height: i32, title: [:0]const u8) void {
        sapp.run(.{
            .init_cb = sInit,
            .frame_cb = sFrame,
            .cleanup_cb = sCleanup,
            .event_cb = sEvent,
            .width = width,
            .height = height,
            .window_title = title,
            .icon = .{ .sokol_default = true },
            .logger = .{ .func = slog.func },
        });
    }
    export fn sFrame() void {
        const new_frame: sokol.imgui.FrameDesc = .{
            .width = sapp.width(),
            .height = sapp.height(),
            .delta_time = sapp.frameDuration(),
            .dpi_scale = sapp.dpiScale(),
        };
        sokol.imgui.newFrame(new_frame);

        // Render windows
        // if (State.actor_manager) |manager| {
        //     candlestick_chart.plotCandlestickWindow(manager);
        // }
        plotOrderbookWindow(std.heap.page_allocator) catch unreachable;
        // _ = implot.ImPlot_ShowDemoWindow(null);

        sg.beginPass(.{ .action = State.pass_action, .swapchain = sglue.swapchain() });
        sokol.imgui.render();
        sg.endPass();
        sg.commit();
    }

    export fn sInit() void {
        sg.setup(.{
            .environment = sglue.environment(),
            .logger = .{ .func = slog.func },
        });

        const desc: sokol.imgui.Desc = .{};
        sokol.imgui.setup(desc);
        _ = implot.ImPlot_CreateContext();

        var io: *imgui.ImGuiIO = @ptrCast(imgui.igGetIO());
        io.ConfigFlags |= imgui.ImGuiConfigFlags_NavEnableKeyboard;
        io.ConfigFlags |= imgui.ImGuiConfigFlags_DockingEnable;
        io.FontGlobalScale = 1.0 / io.DisplayFramebufferScale.y;

        State.pass_action.colors[0] = .{
            .load_action = .CLEAR,
            .clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
        };
    }

    export fn sCleanup() void {
        _ = implot.ImPlot_DestroyContext(null);
        sokol.imgui.shutdown();
        sg.shutdown();
    }

    export fn sEvent(ev: [*c]const sapp.Event) void {
        _ = sokol.imgui.handleEvent(ev.*);
    }
};
