const std = @import("std");

const zignite = @import("zignite");
const shared_models = @import("shared_models");
const wdw = @import("window.zig");

const Window = wdw.Window;
const imgui = zignite.imgui;
const plot = zignite.implot;
const glfw = zignite.glfw;
const websocket = zignite.websocket;

const OrderBook = shared_models.Orderbook;
const Orderbook = shared_models.Orderbook;

pub const OrderbookWindow = struct {
    orderbook: *Orderbook,
    const Self = @This();

    pub fn init(orderbook: *Orderbook) Self {
        return .{
            .orderbook = orderbook,
        };
    }

    pub fn render(self: *Self, window: *Window(Self)) !void {
        if (self.orderbook.ticker.isEmpty()) {
            return;
        }
        const orderbook = self.orderbook;

        var title_buf: [128]u8 = undefined;
        const title = std.fmt.bufPrintZ(&title_buf, "Order Book - {s} ({s})", .{ orderbook.ticker.Owned.str, orderbook.exchange.Owned.str }) catch unreachable;

        if (!window.pos_set) {
            imgui.igSetNextWindowPos(window.initial_pos, imgui.ImGuiCond_FirstUseEver, imgui.ImVec2{ .x = 0, .y = 0 });
            window.pos_set = true;
        }

        if (window.popen and imgui.igBegin(title, &window.popen, imgui.ImGuiWindowFlags_None)) {
            defer imgui.igEnd();

            const bids = orderbook.bids;
            const asks = orderbook.asks;

            var max_vol: f64 = 0.0;
            for (bids.items) |bid| max_vol = @max(max_vol, bid.qty);
            for (asks.items) |ask| max_vol = @max(max_vol, ask.qty);

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
                    ask_cum_vol += ask.qty;

                    imgui.igTableNextRow(imgui.ImGuiTableRowFlags_None, 0);

                    _ = imgui.igTableSetColumnIndex(0);
                    const price_fmt = std.fmt.bufPrintZ(&text_buf, "{d:.2}", .{ask.price}) catch "ERR";
                    imgui.igTextColored(imgui.ImVec4{ .x = 1, .y = 0, .z = 0, .w = 1 }, price_fmt.ptr);

                    _ = imgui.igTableSetColumnIndex(1);
                    const vol_fmt = std.fmt.bufPrintZ(&text_buf, "{d:.3}", .{ask.qty}) catch "ERR";
                    imgui.igTextColored(imgui.ImVec4{ .x = 1, .y = 0, .z = 0, .w = 1 }, vol_fmt.ptr);
                }
            }

            imgui.igSeparator();
            const spread_val = if (asks.items.len > 0 and bids.items.len > 0) asks.items[0].price - bids.items[0].price else 0.0;
            const spread_text = std.fmt.bufPrintZ(&text_buf, "Spread: {d:.2}", .{spread_val}) catch "ERR";
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
                    bid_cum_vol += bid.qty;

                    imgui.igTableNextRow(imgui.ImGuiTableRowFlags_None, 0);

                    _ = imgui.igTableSetColumnIndex(0);
                    const price_fmt = std.fmt.bufPrintZ(&text_buf, "{d:.2}", .{bid.price}) catch "ERR";
                    imgui.igTextColored(imgui.ImVec4{ .x = 0, .y = 1, .z = 0, .w = 1 }, price_fmt.ptr);
                    _ = imgui.igTableSetColumnIndex(1);
                    const vol_fmt = std.fmt.bufPrintZ(&text_buf, "{d:.3}", .{bid.qty}) catch "ERR";
                    imgui.igTextColored(imgui.ImVec4{ .x = 0, .y = 1, .z = 0, .w = 1 }, vol_fmt.ptr);
                }
            }
        }
    }
};

// const OrderbookWindow = struct {
//     ticker: []const u8,
//     open_message: [:0]u8,
//     close_message: [:0]u8,
//     popen: bool = false,
//     orderbook: ?OrderBook = null,
//     initial_pos: imgui.ImVec2,
//     pos_set: bool = false,
// };

// pub const OrderbookWindows = struct {
//     allocator: std.mem.Allocator,
//     windows: ?std.StringHashMap(*OrderbookWindow) = null,
//     open_socket: websocket.WebSocket,
//     next_window_offset: u32 = 0,
//     const Self = @This();

//     pub fn init(
//         allocator: std.mem.Allocator,
//         open_socket: websocket.WebSocket,
//     ) !*OrderbookWindows {
//         const self = try allocator.create(Self);
//         self.* = .{
//             .allocator = allocator,
//             .windows = std.StringHashMap(*OrderbookWindow).init(allocator),
//             .open_socket = open_socket,
//         };
//         return self;
//     }

//     pub fn deinit(self: *Self) void {
//         var it = self.windows.?.valueIterator();
//         while (it.next()) |window| {
//             self.allocator.free(window.*.open_message);
//             self.allocator.free(window.*.close_message);
//             self.allocator.destroy(window.*);
//         }
//         self.windows.?.deinit();
//     }

//     pub fn openWindow(
//         self: *Self,
//         ticker: []const u8,
//     ) !void {
//         const window = try self.allocator.create(OrderbookWindow);
//         const open_msg = try std.fmt.allocPrintZ(self.allocator, "open_orderbook:{s}", .{ticker});
//         const close_msg = try std.fmt.allocPrintZ(self.allocator, "close_orderbook:{s}", .{ticker});

//         const offset: f32 = @floatFromInt(self.next_window_offset * 30);
//         const initial_x: f32 = 50.0 + offset;
//         const initial_y: f32 = 100.0 + offset;

//         window.* = .{
//             .ticker = ticker,
//             .open_message = open_msg,
//             .close_message = close_msg,
//             .popen = true,
//             .initial_pos = imgui.ImVec2{ .x = initial_x, .y = initial_y },
//             .pos_set = false,
//         };

//         try self.windows.?.put(ticker, window);
//         self.next_window_offset += 1;
//         _ = websocket.sendText(self.open_socket, open_msg);
//     }

//     pub fn updateOrderbook(self: *Self, ob: OrderBook) !void {
//         if (self.windows.?.get(ob.ticker.Owned.str)) |window| {
//             if (window.popen) {
//                 window.orderbook = ob;
//             } else {
//                 _ = websocket.sendText(self.open_socket, window.close_message);

//                 _ = self.windows.?.remove(ob.ticker.Owned.str);

//                 self.allocator.free(window.open_message);
//                 self.allocator.free(window.close_message);
//                 self.allocator.destroy(window);
//                 ob.deinit();

//                 if (self.next_window_offset > 0) {
//                     self.next_window_offset -= 1;
//                 }
//             }
//         } else {
//             ob.deinit();
//         }
//     }

//     pub fn plot(self: *Self) !void {
//         if (self.windows == null) {
//             return;
//         }

//         var it = self.windows.?.valueIterator();
//         while (it.next()) |window| {
//             if (window.*.orderbook != null) {
//                 // try plotOrderbookWindow(window.*);
//             }
//         }
//     }

//     fn plotOrderbookWindow(window: *OrderbookWindow) !void {
//         var title_buf: [128]u8 = undefined;
//         const orderbook = window.orderbook.?;
//         const title = std.fmt.bufPrintZ(&title_buf, "Order Book - {s} ({s})", .{ orderbook.ticker.Owned.str, orderbook.exchange.Owned.str }) catch unreachable;

//         if (!window.pos_set) {
//             imgui.igSetNextWindowPos(window.initial_pos, imgui.ImGuiCond_FirstUseEver, imgui.ImVec2{ .x = 0, .y = 0 });
//             window.pos_set = true;
//         }

//         if (window.popen and imgui.igBegin(title, &window.popen, imgui.ImGuiWindowFlags_None)) {
//             defer imgui.igEnd();

//             const bids = orderbook.bids;
//             const asks = orderbook.asks;

//             var max_vol: f64 = 0.0;
//             for (bids.items) |bid| max_vol = @max(max_vol, bid.qty);
//             for (asks.items) |ask| max_vol = @max(max_vol, ask.qty);

//             if (max_vol > 0) {
//                 max_vol *= 1.05;
//             } else {
//                 max_vol = 1.0;
//             }

//             const table_flags = imgui.ImGuiTableFlags_RowBg | imgui.ImGuiTableFlags_BordersInnerV | imgui.ImGuiTableFlags_SizingFixedFit;

//             const text_buf_size = 64;
//             var text_buf: [text_buf_size]u8 = undefined;

//             if (imgui.igBeginTable("AsksTable", 2, table_flags, .{ .x = 0, .y = 0 }, 0)) {
//                 defer imgui.igEndTable();

//                 imgui.igTableSetupColumn("Price", imgui.ImGuiTableColumnFlags_WidthFixed, 80.0, 0);
//                 imgui.igTableSetupColumn("Volume", imgui.ImGuiTableColumnFlags_WidthFixed, 80.0, 0);

//                 imgui.igTableNextRow(imgui.ImGuiTableRowFlags_None, 0);
//                 _ = imgui.igTableSetColumnIndex(0);
//                 imgui.igTextColored(imgui.ImVec4{ .x = 1, .y = 0, .z = 0, .w = 1 }, "Asks");

//                 imgui.igTableHeadersRow();

//                 var ask_cum_vol: f64 = 0;
//                 for (asks.items, 0..) |_, i| {
//                     const ask = asks.items[asks.items.len - 1 - i];
//                     ask_cum_vol += ask.qty;

//                     imgui.igTableNextRow(imgui.ImGuiTableRowFlags_None, 0);

//                     _ = imgui.igTableSetColumnIndex(0);
//                     const price_fmt = std.fmt.bufPrintZ(&text_buf, "{d:.2}", .{ask.price}) catch "ERR";
//                     imgui.igTextColored(imgui.ImVec4{ .x = 1, .y = 0, .z = 0, .w = 1 }, price_fmt.ptr);

//                     _ = imgui.igTableSetColumnIndex(1);
//                     const vol_fmt = std.fmt.bufPrintZ(&text_buf, "{d:.3}", .{ask.qty}) catch "ERR";
//                     imgui.igTextColored(imgui.ImVec4{ .x = 1, .y = 0, .z = 0, .w = 1 }, vol_fmt.ptr);
//                 }
//             }

//             imgui.igSeparator();
//             const spread_val = if (asks.items.len > 0 and bids.items.len > 0) asks.items[0].price - bids.items[0].price else 0.0;
//             const spread_text = std.fmt.bufPrintZ(&text_buf, "Spread: {d:.2}", .{spread_val}) catch "ERR";
//             imgui.igText(spread_text.ptr);
//             imgui.igSeparator();

//             if (imgui.igBeginTable("BidsTable", 2, table_flags, .{ .x = 0, .y = 0 }, 0)) {
//                 defer imgui.igEndTable();

//                 imgui.igTableSetupColumn("Price", imgui.ImGuiTableColumnFlags_WidthFixed, 80.0, 0);
//                 imgui.igTableSetupColumn("Volume", imgui.ImGuiTableColumnFlags_WidthFixed, 80.0, 0);

//                 imgui.igTableNextRow(imgui.ImGuiTableRowFlags_None, 0);
//                 _ = imgui.igTableSetColumnIndex(0);
//                 imgui.igTextColored(imgui.ImVec4{ .x = 0, .y = 1, .z = 0, .w = 1 }, "Bids");

//                 imgui.igTableHeadersRow();

//                 var bid_cum_vol: f64 = 0;
//                 for (bids.items) |bid| {
//                     bid_cum_vol += bid.qty;

//                     imgui.igTableNextRow(imgui.ImGuiTableRowFlags_None, 0);

//                     _ = imgui.igTableSetColumnIndex(0);
//                     const price_fmt = std.fmt.bufPrintZ(&text_buf, "{d:.2}", .{bid.price}) catch "ERR";
//                     imgui.igTextColored(imgui.ImVec4{ .x = 0, .y = 1, .z = 0, .w = 1 }, price_fmt.ptr);
//                     _ = imgui.igTableSetColumnIndex(1);
//                     const vol_fmt = std.fmt.bufPrintZ(&text_buf, "{d:.3}", .{bid.qty}) catch "ERR";
//                     imgui.igTextColored(imgui.ImVec4{ .x = 0, .y = 1, .z = 0, .w = 1 }, vol_fmt.ptr);
//                 }
//             }
//         }
//     }
// };
