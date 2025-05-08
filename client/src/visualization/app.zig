const std = @import("std");
const glfw = @import("zglfw");
const zgpu = @import("zgpu");
const gui = @import("../gui.zig");
const plot = @import("../plot.zig");
const xev = @import("xev");
const orderbook_chart = @import("orderbook_chart.zig");
const ohlc_chart = @import("ohlc_chart.zig");
const shared_models = @import("shared_models");
const xevtcp = @import("xevtcp");

const Client = xevtcp.Client;
const wgpu = zgpu.wgpu;
const OrderBook = shared_models.OrderBook;
const PriceLevel = shared_models.PriceLevel;
const parseOrderbook = shared_models.parseOrderbook;
const plotOrderbookWindow = orderbook_chart.plotOrderbookWindow;
const OHLCList = shared_models.OHLCList;
const OHLC = shared_models.OHLC;
const parseOHLCList = shared_models.parseOHLCList;
const TCP = xev.TCP;
const plotOHLCListWindow = ohlc_chart.plotOHLCListWindow;

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

    orderbooks: ?std.StringHashMap(*const OrderBook) = null,
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

        _ = width;
        _ = height;
        glfw.windowHint(.client_api, .no_api);
        const window = try glfw.Window.create(1920, 1080, title, null);
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
        const tcp_client = try Client(
            MessageTypes,
        ).init(
            allocator,
            loop,
            .{
                .server_addr = try std.net.Address.parseIp4("127.0.0.1", 8081),
            },
            .{
                .orderbook = orderbookCallback,
                .ohlc = ohlcCallback,
            },
            self,
        );

        self.* = Self{
            .allocator = allocator,
            .loop = loop,
            .window = window,
            .gctx = gctx,
            .tcp_client = tcp_client,
            .orderbooks = std.StringHashMap(*const OrderBook).init(allocator),
            .last_fps_update_time = glfw.getTime(),
        };

        return self;
    }

    pub fn start(self: *Self) void {
        // while (true) {
        //     self.renderFrame();
        // }
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

 
        var fps_buf: [16]u8 = undefined;
        const fps_text = try std.fmt.bufPrint(&fps_buf, "FPS: {d:.1}", .{self.current_fps});
        const draw_list = gui.getBackgroundDrawList();
        draw_list.addTextVec2(.{ 10, 10 }, 0xFF00FF00, fps_text);

        if (self.ohlc_list) |ohlc_list| {
            try plotOHLCListWindow(self.allocator, ohlc_list);
        }
        if (self.orderbooks) |orderbooks| {
            var it = orderbooks.valueIterator();
            while (it.next()) |orderbook| {
                try plotOrderbookWindow(orderbook.*);
            }
        }

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

    pub fn orderbookCallback(
        self_: ?*anyopaque,
        payload: []const u8,
    ) anyerror!void {
        const self = @as(*Self, @ptrCast(@alignCast(self_)));
        const ob = parseOrderbook(self.allocator, payload) catch |err| {
            std.log.err("Failed to parse orderbook data: {s}", .{@errorName(err)});
            return error.FailedToParseOrderbook;
        };
        try self.orderbooks.?.put(ob.ticker, ob);
    }

    pub fn orderbookTestCallback(
        self_: ?*anyopaque,
        payload: []const u8,
    ) anyerror!void {
        const self = @as(*Self, @ptrCast(@alignCast(self_)));
        _ = self;
        std.debug.print("orderbookTestCallback: {s}\n", .{payload});
    }
};
