const std = @import("std");
const skgui = @import("skgui");

const sokol = skgui.sokol;
const imp = skgui.implot;
const ig = skgui.imgui;

const slog = sokol.log;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;

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
        imp.ImPlot_ShowDemoWindow(null);

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
        _ = imp.ImPlot_CreateContext();

        var io: *ig.ImGuiIO = @ptrCast(ig.igGetIO());
        io.ConfigFlags |= ig.ImGuiConfigFlags_NavEnableKeyboard;
        io.ConfigFlags |= ig.ImGuiConfigFlags_DockingEnable;
        io.FontGlobalScale = 1.0 / io.DisplayFramebufferScale.y;

        State.pass_action.colors[0] = .{
            .load_action = .CLEAR,
            .clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
        };
    }

    export fn sCleanup() void {
        imp.ImPlot_DestroyContext(null);
        sokol.imgui.shutdown();
        sg.shutdown();
    }

    export fn sEvent(ev: [*c]const sapp.Event) void {
        _ = sokol.imgui.handleEvent(ev.*);
    }
};
