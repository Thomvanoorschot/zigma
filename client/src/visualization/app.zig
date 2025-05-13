const std = @import("std");
const glfw = @import("zglfw");
const zgpu = @import("zgpu");
const gui = @import("../gui.zig");
const plot = @import("../plot.zig");
const xev = @import("xev");
const ob = @import("orderbook.zig");
const ohlc_chart = @import("ohlc_chart.zig");
const shared_models = @import("shared_models");
const wire = @import("wire");

const Client = wire.Client;
const TCP = xev.TCP;
const wgpu = zgpu.wgpu;

const OrderBook = shared_models.OrderBook;
const PriceLevel = shared_models.PriceLevel;
const OHLCList = shared_models.OHLCList;
const OHLC = shared_models.OHLC;
const parseOHLCList = shared_models.parseOHLCList;
const plotOHLCListWindow = ohlc_chart.plotOHLCListWindow;
const OrderbookPlots = ob.OrderbookWindows;
const orderbookCallback = ob.OrderbookWindows.orderbookCallback;

pub const MessageTypes = enum {
    orderbook,
    ohlc,
};

pub const App = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    loop: *xev.Loop,
    window: *glfw.Window,
    gctx: *zgpu.GraphicsContext,
    render_frame_completion: xev.Completion = undefined,

    orderbook_plots: *OrderbookPlots,
    ohlc_list: ?[]OHLC = null,
    tcp_client: Client(MessageTypes),

    last_fps_update_time: f64 = 0.0,
    frame_count_since_last_update: u32 = 0,
    current_fps: f32 = 0.0,
    pub fn init(
        allocator: std.mem.Allocator,
        loop: *xev.Loop,
        comptime title: [:0]const u8,
        comptime width: i32,
        comptime height: i32,
    ) !*Self {
        try glfw.init();

        glfw.windowHint(.client_api, .no_api);
        const window = try glfw.Window.create(width, height, title, null);
        // window.setSizeLimits(450, 800, -1, -1);
        glfw.makeContextCurrent(window);

        const gctx = try zgpu.GraphicsContext.create(
            allocator,
            .{
                .window = window,
                .fn_getTime = @ptrCast(&glfw.getTime),
                .fn_getFramebufferSize = @ptrCast(&glfw.Window.getFramebufferSize),
                .fn_getCocoaWindow = @ptrCast(&glfw.getCocoaWindow),
            },
            .{},
        );

        gui.init(allocator);
        gui.backend.init(
            window,
            gctx.device,
            @intFromEnum(zgpu.GraphicsContext.swapchain_format),
            @intFromEnum(wgpu.TextureFormat.undef),
        );

        // const scale_factor = scale_factor: {
        //     const scale = window.getContentScale();
        //     break :scale_factor @max(scale[0], scale[1]);
        // };
        // gui.getStyle().scaleAllSizes(scale_factor);
        plot.init();

        const self = try allocator.create(Self);

        const orderbook_plots = try OrderbookPlots.init(allocator);
        const tcp_client = try Client(
            MessageTypes,
        ).init(
            allocator,
            loop,
            .{
                .server_addr = try std.net.Address.parseIp4("127.0.0.1", 8081),
            },
            .{
                .orderbook = .{
                    .context = @ptrCast(orderbook_plots),
                    .cb = orderbookCallback,
                },
                .ohlc = .{
                    // TODO: This is still incorrect
                    .context = self,
                    .cb = ohlcCallback,
                },
            },
            self,
        );
        self.* = Self{
            .allocator = allocator,
            .loop = loop,
            .window = window,
            .gctx = gctx,
            .tcp_client = tcp_client,
            .orderbook_plots = orderbook_plots,
            .last_fps_update_time = glfw.getTime(),
        };
        orderbook_plots.tcp_client = &self.tcp_client;

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
                app.renderFrame() catch unreachable;
                if (!app.window.shouldClose() and app.window.getKey(.escape) != .press) {
                    l.timer(c, 16, ud, inner);
                    return .disarm;
                }
                app.deinit();
                return .disarm;
            }
        }.inner;
        self.loop.timer(&self.render_frame_completion, 16, @ptrCast(self), callback);
        self.tcp_client.connect();
        self.tcp_client.startReading();
    }

    pub fn deinit(self: *Self) void {
        self.loop.deinit();
        self.gctx.destroy(self.allocator);
        gui.backend.deinit();
        plot.deinit();
        glfw.terminate();
        self.window.destroy();
    }

    pub fn renderFrame(self: *Self) !void {
        glfw.pollEvents();

        const current_time = glfw.getTime();
        self.frame_count_since_last_update += 1;
        const delta_time = current_time - self.last_fps_update_time;

        if (delta_time >= 1.0) {
            self.current_fps = @as(f32, @floatFromInt(self.frame_count_since_last_update)) / @as(f32, @floatCast(delta_time));
            self.frame_count_since_last_update = 0;
            self.last_fps_update_time = current_time;
        }

        gui.backend.newFrame(
            self.gctx.swapchain_descriptor.width,
            self.gctx.swapchain_descriptor.height,
        );

        const tickers = [_][]const u8{ "ETH/USD", "BTC/USD", "XRP/USD", "DOGE/USD", "SUI/USD", "USDC/USD", "SOL/USD", "PEPE/USD", "ADA/USD", "WIF/USD", "EUR/USD", "FARTCOIN/USD", "AVAX/USD", "LTC/USD", "XLM/USD", "TRUMP/USD" };
        if (gui.beginMainMenuBar()) {
            defer gui.endMainMenuBar();
            if (gui.beginMenu("Orderbook", true)) {
                for (tickers) |ticker| {
                    const c_str = try std.fmt.allocPrintZ(self.allocator, "{s}\r\n", .{ticker});
                    defer self.allocator.free(c_str);
                    if (gui.menuItem(c_str, .{})) {
                        try self.orderbook_plots.openWindow(ticker);
                    }
                }
                gui.endMenu();
            }
        }

        var fps_buf: [16]u8 = undefined;
        const fps_text = try std.fmt.bufPrint(&fps_buf, "FPS: {d:.1}", .{self.current_fps});
        const draw_list = gui.getBackgroundDrawList();
        // const screen_width: f32 = @floatFromInt(self.gctx.swapchain_descriptor.width);
        const padding: f32 = 10.0;

        // const fps_pos_x = screen_width - padding;
        const fps_pos_y = padding * 2;

        draw_list.addTextVec2(.{ 1600, fps_pos_y }, 0xFF00FF00, fps_text);

        if (self.ohlc_list) |ohlc_list| {
            try plotOHLCListWindow(self.allocator, ohlc_list);
        }
        try self.orderbook_plots.plot();

        const swapchain_texv = self.gctx.swapchain.getCurrentTextureView();
        defer swapchain_texv.release();

        const commands = commands: {
            const encoder = self.gctx.device.createCommandEncoder(null);
            defer encoder.release();
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

        self.gctx.submit(&.{commands});
        _ = self.gctx.present();
    }

    pub fn ohlcCallback(
        self_: ?*anyopaque,
        payload: []const u8,
    ) anyerror!void {
        const self = @as(*Self, @ptrCast(@alignCast(self_)));
        const ohlc_list = parseOHLCList(self.allocator, payload) catch |err| {
            std.log.err("Failed to parse ohlc data: {s}", .{@errorName(err)});
            return error.FailedToParseOHLC;
        };
        self.ohlc_list = ohlc_list;
    }
};
