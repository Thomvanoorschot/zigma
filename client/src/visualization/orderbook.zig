const std = @import("std");
const gui = @import("../gui.zig");
const plot = @import("../plot.zig");
const glfw = @import("zglfw");
const shared_models = @import("shared_models");
const wire = @import("wire");
const app = @import("app.zig");

const parseOrderbook = shared_models.parseOrderbook;

const Client = wire.Client;
const OrderBook = shared_models.OrderBook;
const PriceLevel = shared_models.PriceLevel;
const MessageTypes = app.MessageTypes;

var popen: bool = true;

const OrderbookWindow = struct {
    ticker: []const u8,
    open_message: [:0]u8,
    close_message: [:0]u8,
    popen: bool = false,
    orderbook: ?*const OrderBook = null,
};

pub const OrderbookWindows = struct {
    allocator: std.mem.Allocator,
    windows: ?std.StringHashMap(*OrderbookWindow) = null,
    tcp_client: ?*Client(MessageTypes) = null,
    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
    ) !*OrderbookWindows {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .windows = std.StringHashMap(*OrderbookWindow).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        var it = self.windows.?.valueIterator();
        while (it.next()) |window| {
            self.allocator.free(window.*.open_message);
            self.allocator.free(window.*.close_message);
            self.allocator.destroy(window.*);
        }
        self.windows.?.deinit();
    }

    pub fn openWindow(
        self: *Self,
        ticker: []const u8,
    ) !void {
        const window = try self.allocator.create(OrderbookWindow);
        const open_msg = std.fmt.allocPrintZ(self.allocator, "open_orderbook:{s}", .{ticker}) catch unreachable;
        const close_msg = std.fmt.allocPrintZ(self.allocator, "close_orderbook:{s}", .{ticker}) catch unreachable;
        window.* = .{
            .ticker = ticker,
            .open_message = open_msg,
            .close_message = close_msg,
            .popen = true,
        };
        try self.windows.?.put(ticker, window);
        self.tcp_client.?.write(open_msg);
    }

    pub fn orderbookCallback(
        self_: *anyopaque,
        payload: []const u8,
    ) anyerror!void {
        const self = @as(*Self, @ptrCast(@alignCast(self_)));
        const ob = parseOrderbook(self.allocator, payload) catch |err| {
            std.log.err("Failed to parse orderbook data: {s}", .{@errorName(err)});
            return error.FailedToParseOrderbook;
        };
        if (self.windows.?.get(ob.ticker)) |window| {
            if (window.popen) {
                window.orderbook = ob;
            } else {
                self.allocator.free(window.open_message);
                self.allocator.destroy(window);
                _ = self.windows.?.remove(ob.ticker);
                // TODO This is still dangling
                self.tcp_client.?.write(window.close_message);
            }
        } else {
            
        }
    }

    pub fn plot(self: *Self) !void {
        if (self.windows == null) {
            return;
        }

        var it = self.windows.?.valueIterator();
        while (it.next()) |window| {
            if (window.*.orderbook != null) {
                try plotOrderbookWindow(window.*);
            }
        }
    }

    fn plotOrderbookWindow(window: *OrderbookWindow) !void {
        var title_buf: [128]u8 = undefined;
        const orderbook = window.orderbook.?;
        const title = std.fmt.bufPrintZ(&title_buf, "Order Book - {s} ({s})", .{ orderbook.ticker, orderbook.exchange }) catch unreachable;

        if (popen and gui.begin(title, .{ .popen = &window.popen })) {
            defer gui.end();

            const bids = orderbook.bids;
            const asks = orderbook.asks;

            var max_vol: f64 = 0.0;
            for (bids.items) |bid| max_vol = @max(max_vol, bid[1]);
            for (asks.items) |ask| max_vol = @max(max_vol, ask[1]);

            if (max_vol > 0) {
                max_vol *= 1.05;
            } else {
                max_vol = 1.0;
            }

            const table_flags = gui.TableFlags{
                .borders = .{ .inner_v = true },
                .sizing = .fixed_fit,
                .row_bg = true,
            };

            const text_buf_size = 64;
            var text_buf: [text_buf_size]u8 = undefined;

            if (gui.beginTable("AsksTable", .{ .column = 2, .flags = table_flags })) {
                defer gui.endTable();

                gui.tableSetupColumn("Price", .{ .flags = .{ .width_fixed = true }, .init_width_or_height = 80.0 });
                gui.tableSetupColumn("Volume", .{ .flags = .{ .width_fixed = true }, .init_width_or_height = 80.0 });

                gui.tableNextRow(.{});
                _ = gui.tableSetColumnIndex(0);
                gui.textUnformattedColored(0xFF0000FF, "Asks");

                gui.tableHeadersRow();

                var ask_cum_vol: f64 = 0;
                for (asks.items, 0..) |_, i| {
                    const ask = asks.items[asks.items.len - 1 - i];
                    ask_cum_vol += ask[1];

                    gui.tableNextRow(.{});

                    _ = gui.tableSetColumnIndex(0);
                    const price_fmt = std.fmt.bufPrint(&text_buf, "{d:.2}", .{ask[0]}) catch "ERR";
                    // Colors are AABBGGRR
                    gui.textUnformattedColored(0xFF0000FF, price_fmt);

                    _ = gui.tableSetColumnIndex(1);
                    const vol_fmt = std.fmt.bufPrint(&text_buf, "{d:.3}", .{ask[1]}) catch "ERR";
                    gui.textUnformattedColored(0xFF0000FF, vol_fmt);
                }
            }

            gui.separator();
            const spread_val = if (asks.items.len > 0 and bids.items.len > 0) asks.items[0][0] - bids.items[0][0] else 0.0;
            const spread_text = std.fmt.bufPrint(&text_buf, "Spread: {d:.2}", .{spread_val}) catch "ERR SPREAD";
            gui.textUnformatted(spread_text);
            gui.separator();

            if (gui.beginTable("BidsTable", .{ .column = 2, .flags = table_flags })) {
                defer gui.endTable();

                gui.tableSetupColumn("Price", .{ .flags = .{ .width_fixed = true }, .init_width_or_height = 80.0 });
                gui.tableSetupColumn("Volume", .{ .flags = .{ .width_fixed = true }, .init_width_or_height = 80.0 });
                gui.tableNextRow(.{});
                _ = gui.tableSetColumnIndex(0);
                gui.textUnformattedColored(0xFF00FF00, "Bids");

                gui.tableHeadersRow();

                var bid_cum_vol: f64 = 0;
                for (bids.items) |bid| {
                    bid_cum_vol += bid[1];

                    gui.tableNextRow(.{});

                    _ = gui.tableSetColumnIndex(0);
                    const price_fmt = std.fmt.bufPrint(&text_buf, "{d:.2}", .{bid[0]}) catch "ERR";
                    gui.textUnformattedColored(0xFF00FF00, price_fmt);
                    _ = gui.tableSetColumnIndex(1);
                    const vol_fmt = std.fmt.bufPrint(&text_buf, "{d:.3}", .{bid[1]}) catch "ERR";
                    gui.textUnformattedColored(0xFF00FF00, vol_fmt);
                }
            }
        }
    }
};
