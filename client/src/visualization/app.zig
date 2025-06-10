const std = @import("std");
const sd = @import("../wasm/shared_data.zig");
const zignite = @import("zignite");
const shared_models = @import("shared_models");
const wg = @import("window_group.zig");
const ob_window = @import("orderbook_window.zig");
const mnu = @import("menu.zig");
const wdw = @import("window.zig");
const ohlc_wdw = @import("ohlc_window.zig");

const imgui = zignite.imgui;
const websocket = zignite.websocket;
const SharedData = sd.SharedData;
const Orderbook = shared_models.Orderbook;
const OrderbookWindow = ob_window.OrderbookWindow;
const WindowGroup = wg.WindowGroup;
const Menu = mnu.Menu;
const Window = wdw.Window;
const OHLCWindow = ohlc_wdw.OHLCWindow;

const StdOut = @TypeOf(std.io.getStdOut().writer());
const StdErr = @TypeOf(std.io.getStdErr().writer());

pub const App = struct {
    allocator: std.mem.Allocator,
    shared_data: *SharedData,
    open_socket: ?websocket.WebSocket = null,
    std_out: StdOut = std.io.getStdOut().writer(),
    std_err: StdErr = std.io.getStdErr().writer(),
    menu: Menu,
    orderbook_windows: *WindowGroup(OrderbookWindow),

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator, shared_data: *SharedData) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .shared_data = shared_data,
            .menu = try Menu.init(
                allocator,
                self,
                onOpenOrderbook,
            ),
            .orderbook_windows = try WindowGroup(OrderbookWindow).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }

    pub fn render(self: *Self) !void {
        try self.menu.render();
        for (self.orderbook_windows.windows.items) |window| {
            try window.render();
        }
        var ohlc_window = OHLCWindow.init();
        try ohlc_window.render();
    }
    pub fn onOpenOrderbook(self_: *anyopaque, ticker: []const u8) !void {
        const self = @as(*Self, @ptrCast(@alignCast(self_)));
        if (self.open_socket == null) {
            return;
        }
        // Send open message to server
        var open_msg_buf: [25]u8 = undefined;
        const open_msg = try std.fmt.bufPrintZ(&open_msg_buf, "open_orderbook:{s}", .{ticker});
        _ = websocket.sendText(self.open_socket.?, open_msg);

        // Create orderbook for shared data, not really a fan of this and should probably be changed to something more elegant
        const ob = try self.allocator.create(Orderbook);
        errdefer self.allocator.destroy(ob);

        try self.shared_data.orderbooks.put(ticker, ob);
        errdefer _ = self.shared_data.orderbooks.remove(ticker);

        // Open window
        try self.orderbook_windows.openWindow(
            OrderbookWindow.init(ob),
            self,
            onCloseOrderbook,
        );
    }
    pub fn onCloseOrderbook(self_: *anyopaque, window: *Window(OrderbookWindow)) !void {
        const self = @as(*Self, @ptrCast(@alignCast(self_)));
        const ticker = window.impl.orderbook.ticker.Owned.str;

        // Send close message to server
        var close_msg_buf: [26]u8 = undefined;
        const close_msg = try std.fmt.bufPrintZ(&close_msg_buf, "close_orderbook:{s}", .{ticker});
        _ = websocket.sendText(self.open_socket.?, close_msg);

        // Remove orderbook from shared data
        if (self.shared_data.orderbooks.fetchRemove(ticker)) |kv| {
            self.allocator.destroy(kv.value);
        } else {
            return error.OrderbookNotFound;
        }

        // Remove window
        self.orderbook_windows.removeWindow(window);
    }

    pub fn onWebsocketOpenCallback(self_: *anyopaque, open_socket: websocket.WebSocket) !bool {
        const self = @as(*Self, @ptrCast(@alignCast(self_)));
        self.open_socket = open_socket;
        return true;
    }
    pub fn onWebsocketMessageCallback(self_: *anyopaque, message: []const u8) !bool {
        const self = @as(*Self, @ptrCast(@alignCast(self_)));

        const ws_message = shared_models.WsMessage.decode(message, self.allocator) catch |err| {
            try self.std_out.print("Failed {any}\n", .{err});
            return true;
        };
        if (ws_message.message) |msg| {
            switch (msg) {
                .orderbook => |orderbook| {
                    const ob = self.shared_data.orderbooks.get(orderbook.ticker.Owned.str);
                    if (ob) |o| {
                        o.* = orderbook;
                        return true;
                    }
                },
                else => {
                    return error.UnknownMessageType;
                },
            }
        }
        return true;
    }
    pub fn onWebsocketErrorCallback(self_: *anyopaque) !bool {
        const self = @as(*Self, @ptrCast(@alignCast(self_)));
        try self.std_err.print("WebSocket error\n", .{});
        return true;
    }
    pub fn onWebsocketCloseCallback(self_: *anyopaque, code: u16, reason: []const u8) !bool {
        const self = @as(*Self, @ptrCast(@alignCast(self_)));
        try self.std_out.print("WebSocket closed: {d} {s}\n", .{ code, reason });
        return true;
    }
};
