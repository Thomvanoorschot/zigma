const std = @import("std");
const sd = @import("../wasm/shared_data.zig");
const zignite = @import("zignite");
const shared_models = @import("shared_models");
const wg = @import("window_group.zig");
const ob_window = @import("orderbook_window.zig");
const mnu = @import("menu.zig");

const imgui = zignite.imgui;
const websocket = zignite.websocket;
const SharedData = sd.SharedData;
const Orderbook = shared_models.Orderbook;
const OrderbookWindow = ob_window.OrderbookWindow;
const WindowGroup = wg.WindowGroup;
const Menu = mnu.Menu;

pub const App = struct {
    allocator: std.mem.Allocator,
    shared_data: *SharedData,
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
    }
    pub fn onOpenOrderbook(self_: *anyopaque, ticker: []const u8) !void {
        const self = @as(*Self, @ptrCast(@alignCast(self_)));
        if (self.shared_data.open_socket) |open_socket| {
            var open_msg_buf: [25]u8 = undefined;
            const open_msg = try std.fmt.bufPrintZ(&open_msg_buf, "open_orderbook:{s}", .{ticker});
            _ = websocket.sendText(open_socket, open_msg);
        }
        const ob = try self.allocator.create(Orderbook);
        try self.shared_data.orderbooks.put(ticker, ob);
        try self.orderbook_windows.openWindow(OrderbookWindow.init(ob));
    }
};
