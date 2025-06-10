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
