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
const ClientMessage = shared_models.ClientMessage;
const ManagedString = shared_models.ManagedString;

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
    ohlc_window: *WindowGroup(OHLCWindow),

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
                onOpenOHLC,
            ),
            .orderbook_windows = try WindowGroup(OrderbookWindow).init(allocator),
            .ohlc_window = try WindowGroup(OHLCWindow).init(allocator),
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
        for (self.ohlc_window.windows.items) |window| {
            try window.render();
        }
    }
    pub fn onOpenOrderbook(self_: *anyopaque, ticker: []const u8) !void {
        const self = @as(*Self, @ptrCast(@alignCast(self_)));
        if (self.open_socket == null) {
            return;
        }
        for (self.orderbook_windows.windows.items) |window| {
            if (std.mem.eql(u8, window.impl.ticker, ticker)) {
                return;
            }
        }

        const msg_bytes = try ClientMessage.encode(ClientMessage{
            .message = .{ .subscribe = .{
                .ticker = try ManagedString.copy(ticker, self.allocator),
                .subscription_type = .ORDERBOOK,
            } },
        }, self.allocator);
        _ = websocket.sendBinary(self.open_socket.?, msg_bytes);
        defer self.allocator.free(msg_bytes);

        try self.orderbook_windows.openWindow(
            OrderbookWindow.init(ticker, self.shared_data),
            self,
            onCloseOrderbook,
        );
    }
    pub fn onCloseOrderbook(self_: *anyopaque, window: *Window(OrderbookWindow)) !void {
        const self = @as(*Self, @ptrCast(@alignCast(self_)));
        const ticker = window.impl.ticker;

        const msg_bytes = try ClientMessage.encode(ClientMessage{
            .message = .{ .unsubscribe = .{
                .ticker = try ManagedString.copy(ticker, self.allocator),
                .subscription_type = .ORDERBOOK,
            } },
        }, self.allocator);
        _ = websocket.sendBinary(self.open_socket.?, msg_bytes);
        defer self.allocator.free(msg_bytes);

        if (self.shared_data.orderbooks.fetchRemove(ticker)) |kv| {
            kv.value.deinit();
        } else {
            return error.OrderbookNotFound;
        }

        self.orderbook_windows.removeWindow(window);
    }

    pub fn onOpenOHLC(self_: *anyopaque, ticker: []const u8) !void {
        const self = @as(*Self, @ptrCast(@alignCast(self_)));

        for (self.ohlc_window.windows.items) |window| {
            if (std.mem.eql(u8, window.impl.ticker, ticker)) {
                return;
            }
        }

        const msg_bytes = try ClientMessage.encode(ClientMessage{
            .message = .{ .subscribe = .{
                .ticker = try ManagedString.copy(ticker, self.allocator),
                .subscription_type = .OHLC,
            } },
        }, self.allocator);

        _ = websocket.sendBinary(self.open_socket.?, msg_bytes);
        defer self.allocator.free(msg_bytes);

        try self.ohlc_window.openWindow(
            OHLCWindow.init(ticker, self.shared_data),
            self,
            onCloseOHLC,
        );
    }
    pub fn onCloseOHLC(self_: *anyopaque, window: *Window(OHLCWindow)) !void {
        const self = @as(*Self, @ptrCast(@alignCast(self_)));
        self.ohlc_window.removeWindow(window);
    }

    pub fn onWebsocketOpenCallback(self_: *anyopaque, open_socket: websocket.WebSocket) !bool {
        const self = @as(*Self, @ptrCast(@alignCast(self_)));
        self.open_socket = open_socket;
        return true;
    }
    pub fn onWebsocketMessageCallback(self_: *anyopaque, message: []const u8) !bool {
        const self = @as(*Self, @ptrCast(@alignCast(self_)));

        const ws_message = shared_models.ServerMessage.decode(message, self.allocator) catch |err| {
            try self.std_out.print("Failed {any}\n", .{err});
            return true;
        };
        if (ws_message.message) |msg| {
            switch (msg) {
                .orderbook => |orderbook| {
                    if (self.shared_data.orderbooks.fetchRemove(orderbook.ticker.Owned.str)) |kv| {
                        kv.value.deinit();
                    }
                    try self.shared_data.orderbooks.put(orderbook.ticker.Owned.str, orderbook);
                    return true;
                },
                .ohlc => |ohlc| {
                    if (ohlc.ohlc.items.len == 0) {
                        return true;
                    }
                    if (self.shared_data.ohlc.fetchRemove(ohlc.ticker.Owned.str)) |kv| {
                        kv.value.deinit();
                    }
                    try self.shared_data.ohlc.put(ohlc.ticker.Owned.str, ohlc);
                    return true;
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
