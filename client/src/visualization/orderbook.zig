const std = @import("std");

const zignite = @import("zignite");
const shared_models = @import("shared_models");
const imgui = zignite.imgui;
const plot = zignite.implot;
const glfw = zignite.glfw;

const parseOrderbook = shared_models.parseOrderbook;

const PriceLevel = shared_models.PriceLevel;
const OrderBook = shared_models.OrderBook;

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
        // try self.wss_client.?.write(open_msg);
    }

    pub fn updateOrderbook(self: *Self, ticker: []const u8, ob: *const OrderBook) !void {
        if (self.windows.?.get(ticker)) |window| {
            window.orderbook = ob;
        } else {
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

        if (window.popen and imgui.igBegin(title, &window.popen, imgui.ImGuiWindowFlags_None)) {
            defer imgui.igEnd();

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

            const table_flags = imgui.ImGuiTableFlags_RowBg | imgui.ImGuiTableFlags_BordersInnerV | imgui.ImGuiTableFlags_SizingFixedFit;

            const text_buf_size = 64;
            var text_buf: [text_buf_size]u8 = undefined;

            if (imgui.igBeginTable("AsksTable", 2, table_flags, .{ .x = 0, .y = 0 }, 0)) {
                defer imgui.igEndTable();

                imgui.igTableSetupColumn("Price", imgui.ImGuiTableColumnFlags_WidthFixed, 80.0, 0);
                imgui.igTableSetupColumn("Volume", imgui.ImGuiTableColumnFlags_WidthFixed, 80.0, 0);

                imgui.igTableNextRow(imgui.ImGuiTableRowFlags_None, 0);
                _ = imgui.igTableSetColumnIndex(0);
                imgui.igTextColored(imgui.ImVec4{ .x = 1, .y = 0, .z = 0, .w = 1 }, "Asks");

                imgui.igTableHeadersRow();

                var ask_cum_vol: f64 = 0;
                for (asks.items, 0..) |_, i| {
                    const ask = asks.items[asks.items.len - 1 - i];
                    ask_cum_vol += ask[1];

                    imgui.igTableNextRow(imgui.ImGuiTableRowFlags_None, 0);

                    _ = imgui.igTableSetColumnIndex(0);
                    const price_fmt = std.fmt.bufPrint(&text_buf, "{d:.2}", .{ask[0]}) catch "ERR";
                    imgui.igTextColored(imgui.ImVec4{ .x = 1, .y = 0, .z = 0, .w = 1 }, price_fmt.ptr);

                    _ = imgui.igTableSetColumnIndex(1);
                    const vol_fmt = std.fmt.bufPrint(&text_buf, "{d:.3}", .{ask[1]}) catch "ERR";
                    imgui.igTextColored(imgui.ImVec4{ .x = 1, .y = 0, .z = 0, .w = 1 }, vol_fmt.ptr);
                }
            }

            imgui.igSeparator();
            const spread_val = if (asks.items.len > 0 and bids.items.len > 0) asks.items[0][0] - bids.items[0][0] else 0.0;
            const spread_text = std.fmt.bufPrint(&text_buf, "Spread: {d:.2}", .{spread_val}) catch "ERR SPREAD";
            imgui.igText(spread_text.ptr);
            imgui.igSeparator();

            if (imgui.igBeginTable("BidsTable", 2, table_flags, .{ .x = 0, .y = 0 }, 0)) {
                defer imgui.igEndTable();

                imgui.igTableSetupColumn("Price", imgui.ImGuiTableColumnFlags_WidthFixed, 80.0, 0);
                imgui.igTableSetupColumn("Volume", imgui.ImGuiTableColumnFlags_WidthFixed, 80.0, 0);

                imgui.igTableNextRow(imgui.ImGuiTableRowFlags_None, 0);
                _ = imgui.igTableSetColumnIndex(0);
                imgui.igTextColored(imgui.ImVec4{ .x = 0, .y = 1, .z = 0, .w = 1 }, "Bids");

                imgui.igTableHeadersRow();

                var bid_cum_vol: f64 = 0;
                for (bids.items) |bid| {
                    bid_cum_vol += bid[1];

                    imgui.igTableNextRow(imgui.ImGuiTableRowFlags_None, 0);

                    _ = imgui.igTableSetColumnIndex(0);
                    const price_fmt = std.fmt.bufPrint(&text_buf, "{d:.2}", .{bid[0]}) catch "ERR";
                    imgui.igTextColored(imgui.ImVec4{ .x = 0, .y = 1, .z = 0, .w = 1 }, price_fmt.ptr);
                    _ = imgui.igTableSetColumnIndex(1);
                    const vol_fmt = std.fmt.bufPrint(&text_buf, "{d:.3}", .{bid[1]}) catch "ERR";
                    imgui.igTextColored(imgui.ImVec4{ .x = 0, .y = 1, .z = 0, .w = 1 }, vol_fmt.ptr);
                }
            }
        }
    }
};
