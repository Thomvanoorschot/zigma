const std = @import("std");
const zignite = @import("zignite");
const imgui = zignite.imgui;

const tickers = [_][]const u8{
    "ETH/USD",
    "BTC/USD",
    "XRP/USD",
    "DOGE/USD",
    "SUI/USD",
    "USDC/USD",
    "SOL/USD",
    "PEPE/USD",
    "ADA/USD",
    "WIF/USD",
    "EUR/USD",
    "FARTCOIN/USD",
    "AVAX/USD",
    "LTC/USD",
    "XLM/USD",
    "TRUMP/USD",
};
pub const Menu = struct {
    allocator: std.mem.Allocator,
    callback_context: *anyopaque,
    on_open_orderbook: *const fn (context: *anyopaque, ticker: []const u8) anyerror!void,
    on_open_ohlc: *const fn (context: *anyopaque, ticker: []const u8) anyerror!void,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        callback_context: *anyopaque,
        on_open_orderbook: *const fn (
            context: *anyopaque,
            ticker: []const u8,
        ) anyerror!void,
        on_open_ohlc: *const fn (
            context: *anyopaque,
            ticker: []const u8,
        ) anyerror!void,
    ) !Self {
        return .{
            .allocator = allocator,
            .callback_context = callback_context,
            .on_open_orderbook = on_open_orderbook,
            .on_open_ohlc = on_open_ohlc,
        };
    }
    pub fn render(self: *Self) !void {
        if (imgui.igBeginMainMenuBar()) {
            defer imgui.igEndMainMenuBar();
            if (imgui.igBeginMenu("Orderbook", true)) {
                for (tickers) |ticker| {
                    const c_str = try std.fmt.allocPrintZ(self.allocator, "{s}\r\n", .{ticker});
                    defer self.allocator.free(c_str);
                    if (imgui.igMenuItem_Bool(c_str, null, false, true)) {
                        try self.on_open_orderbook(self.callback_context, ticker);
                    }
                }
                imgui.igEndMenu();
            }
            if (imgui.igBeginMenu("OHLC", true)) {
                for (tickers) |ticker| {
                    const c_str = try std.fmt.allocPrintZ(self.allocator, "{s}\r\n", .{ticker});
                    defer self.allocator.free(c_str);
                    if (imgui.igMenuItem_Bool(c_str, null, false, true)) {
                        try self.on_open_ohlc(self.callback_context, ticker);
                    }
                }
                imgui.igEndMenu();
            }
        }
    }
};
