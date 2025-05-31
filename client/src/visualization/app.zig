const std = @import("std");
const sd = @import("../wasm/shared_data.zig");
const zignite = @import("zignite");

const imgui = zignite.imgui;
const websocket = zignite.websocket;
const SharedData = sd.SharedData;

pub const App = struct {
    allocator: std.mem.Allocator,
    shared_data: *SharedData,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator, shared_data: *SharedData) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .shared_data = shared_data,
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }

    pub fn render(self: *Self) !void {
        try self.renderMenu();
        try self.shared_data.orderbook_windows.plot();
    }

    fn renderMenu(self: *Self) !void {
        const tickers = [_][]const u8{ "ETH/USD", "BTC/USD", "XRP/USD", "DOGE/USD", "SUI/USD", "USDC/USD", "SOL/USD", "PEPE/USD", "ADA/USD", "WIF/USD", "EUR/USD", "FARTCOIN/USD", "AVAX/USD", "LTC/USD", "XLM/USD", "TRUMP/USD" };
        if (imgui.igBeginMainMenuBar()) {
            defer imgui.igEndMainMenuBar();
            if (imgui.igBeginMenu("Orderbook", true)) {
                for (tickers) |ticker| {
                    const c_str = try std.fmt.allocPrintZ(self.allocator, "{s}\r\n", .{ticker});
                    defer self.allocator.free(c_str);
                    if (imgui.igMenuItem_Bool(c_str, null, false, true)) {
                        try self.shared_data.orderbook_windows.openWindow(ticker);
                    }
                }
                imgui.igEndMenu();
            }
        }
    }
};
