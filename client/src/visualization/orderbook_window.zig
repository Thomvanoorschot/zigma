const std = @import("std");
const zignite = @import("zignite");
const shared_models = @import("shared_models");
const wdw = @import("window.zig");
const sd = @import("../wasm/shared_data.zig");

const Window = wdw.Window;
const imgui = zignite.imgui;
const plot = zignite.implot;
const glfw = zignite.glfw;
const websocket = zignite.websocket;
const SharedData = sd.SharedData;
const OrderBook = shared_models.Orderbook;
const Orderbook = shared_models.Orderbook;

pub const OrderbookWindow = struct {
    ticker: []const u8,
    shared_data: *SharedData,
    const Self = @This();

    pub fn init(ticker: []const u8, shared_data: *SharedData) Self {
        return .{
            .ticker = ticker,
            .shared_data = shared_data,
        };
    }

    pub fn render(self: *Self, window: *Window(Self)) !void {
        const orderbook = self.shared_data.orderbooks.get(self.ticker) orelse return;

        var title_buf: [128]u8 = undefined;
        const title = std.fmt.bufPrintZ(&title_buf, "Order Book - {s} ({s})", .{ self.ticker, orderbook.exchange.Owned.str }) catch unreachable;

        if (!window.pos_set) {
            imgui.igSetNextWindowPos(window.initial_pos, imgui.ImGuiCond_FirstUseEver, imgui.ImVec2{ .x = 0, .y = 0 });
            window.pos_set = true;
        }

        if (window.popen and imgui.igBegin(title, &window.popen, imgui.ImGuiWindowFlags_None)) {
            defer imgui.igEnd();

            const bids = orderbook.bids;
            const asks = orderbook.asks;

            // Calculate max cumulative volume for proper scaling
            var max_vol: f64 = 0.0;
            var temp_cum: f64 = 0.0;
            for (bids.items) |bid| {
                temp_cum += bid.qty;
                max_vol = @max(max_vol, temp_cum);
            }
            temp_cum = 0.0;
            for (asks.items) |ask| {
                temp_cum += ask.qty;
                max_vol = @max(max_vol, temp_cum);
            }

            if (max_vol > 0) {
                max_vol *= 1.05;
            } else {
                max_vol = 1.0;
            }

            const table_flags = imgui.ImGuiTableFlags_SizingFixedFit;
            const text_buf_size = 64;
            var text_buf: [text_buf_size]u8 = undefined;

            const draw_list = imgui.igGetWindowDrawList();

            if (imgui.igBeginTable("AsksTable", 3, table_flags, .{ .x = 0, .y = 0 }, 0)) {
                defer imgui.igEndTable();

                imgui.igTableSetupColumn("Price", imgui.ImGuiTableColumnFlags_WidthFixed, 80.0, 0);
                imgui.igTableSetupColumn("Size", imgui.ImGuiTableColumnFlags_WidthFixed, 80.0, 0);
                imgui.igTableSetupColumn("Total", imgui.ImGuiTableColumnFlags_WidthFixed, 100.0, 0);

                imgui.igTableHeadersRow();

                // Calculate total ask volume first
                var total_ask_volume: f64 = 0;
                for (asks.items) |ask| {
                    total_ask_volume += ask.qty;
                }

                var remaining_ask_vol = total_ask_volume;
                for (asks.items, 0..) |_, i| {
                    const ask = asks.items[asks.items.len - 1 - i];

                    imgui.igTableNextRow(imgui.ImGuiTableRowFlags_None, 0);

                    // Use remaining volume (largest at top, smallest at bottom)
                    const depth_ratio = remaining_ask_vol / max_vol;
                    if (depth_ratio > 0) {
                        var total_col_rect: imgui.ImRect = undefined;
                        imgui.igTableGetCellBgRect(&total_col_rect, imgui.igGetCurrentTable(), 2);

                        const total_col_width = total_col_rect.Max.x - total_col_rect.Min.x;
                        const bar_width = total_col_width * @as(f32, @floatCast(depth_ratio));

                        const bar_start = imgui.ImVec2{ .x = total_col_rect.Max.x - bar_width, .y = total_col_rect.Min.y };
                        const bar_end = imgui.ImVec2{ .x = total_col_rect.Max.x, .y = total_col_rect.Max.y };

                        const ask_depth_color = imgui.igGetColorU32_Vec4(imgui.ImVec4{ .x = 0.8, .y = 0.2, .z = 0.2, .w = 0.4 });
                        imgui.ImDrawList_AddRectFilled(draw_list, bar_start, bar_end, ask_depth_color, 0.0, imgui.ImDrawFlags_None);
                    }

                    _ = imgui.igTableSetColumnIndex(0);
                    const price_fmt = std.fmt.bufPrintZ(&text_buf, "{d:.2}", .{ask.price}) catch "ERR";
                    imgui.igTextColored(imgui.ImVec4{ .x = 1, .y = 0, .z = 0, .w = 1 }, price_fmt.ptr);

                    _ = imgui.igTableSetColumnIndex(1);
                    const vol_fmt = std.fmt.bufPrintZ(&text_buf, "{d:.2}", .{ask.qty}) catch "ERR";
                    imgui.igText(vol_fmt.ptr);

                    _ = imgui.igTableSetColumnIndex(2);
                    // Show individual cumulative volume (not remaining volume)
                    const individual_cum_vol = total_ask_volume - remaining_ask_vol + ask.qty;
                    const total_fmt = std.fmt.bufPrintZ(&text_buf, "{d:.8}", .{individual_cum_vol}) catch "ERR";
                    imgui.igText(total_fmt.ptr);

                    // Subtract this ask's volume for next iteration
                    remaining_ask_vol -= ask.qty;
                }
            }

            imgui.igSeparator();
            const spread_val = if (asks.items.len > 0 and bids.items.len > 0) asks.items[0].price - bids.items[0].price else 0.0;
            const spread_text = std.fmt.bufPrintZ(&text_buf, "Spread: {d:.2}", .{spread_val}) catch "ERR";
            imgui.igText(spread_text.ptr);
            imgui.igSeparator();

            if (imgui.igBeginTable("BidsTable", 3, table_flags, .{ .x = 0, .y = 0 }, 0)) {
                defer imgui.igEndTable();

                imgui.igTableSetupColumn("Price", imgui.ImGuiTableColumnFlags_WidthFixed, 80.0, 0);
                imgui.igTableSetupColumn("Size", imgui.ImGuiTableColumnFlags_WidthFixed, 80.0, 0);
                imgui.igTableSetupColumn("Total", imgui.ImGuiTableColumnFlags_WidthFixed, 100.0, 0);

                imgui.igTableHeadersRow();

                var bid_cum_vol: f64 = 0;
                for (bids.items) |bid| {
                    bid_cum_vol += bid.qty;

                    imgui.igTableNextRow(imgui.ImGuiTableRowFlags_None, 0);

                    // Use cumulative volume for bar sizing (creates the slope effect)
                    const depth_ratio = bid_cum_vol / max_vol;
                    if (depth_ratio > 0) {
                        var total_col_rect: imgui.ImRect = undefined;
                        imgui.igTableGetCellBgRect(&total_col_rect, imgui.igGetCurrentTable(), 2);

                        const total_col_width = total_col_rect.Max.x - total_col_rect.Min.x;
                        const bar_width = total_col_width * @as(f32, @floatCast(depth_ratio));

                        const bar_start = imgui.ImVec2{ .x = total_col_rect.Max.x - bar_width, .y = total_col_rect.Min.y };
                        const bar_end = imgui.ImVec2{ .x = total_col_rect.Max.x, .y = total_col_rect.Max.y };

                        const bid_depth_color = imgui.igGetColorU32_Vec4(imgui.ImVec4{ .x = 0.2, .y = 0.8, .z = 0.2, .w = 0.4 });
                        imgui.ImDrawList_AddRectFilled(draw_list, bar_start, bar_end, bid_depth_color, 0.0, imgui.ImDrawFlags_None);
                    }

                    _ = imgui.igTableSetColumnIndex(0);
                    const price_fmt = std.fmt.bufPrintZ(&text_buf, "{d:.2}", .{bid.price}) catch "ERR";
                    imgui.igTextColored(imgui.ImVec4{ .x = 0, .y = 1, .z = 0, .w = 1 }, price_fmt.ptr);

                    _ = imgui.igTableSetColumnIndex(1);
                    const vol_fmt = std.fmt.bufPrintZ(&text_buf, "{d:.2}", .{bid.qty}) catch "ERR";
                    imgui.igText(vol_fmt.ptr);

                    _ = imgui.igTableSetColumnIndex(2);
                    const total_fmt = std.fmt.bufPrintZ(&text_buf, "{d:.8}", .{bid.qty}) catch "ERR";
                    imgui.igText(total_fmt.ptr);
                }
            }
        }
    }
};
