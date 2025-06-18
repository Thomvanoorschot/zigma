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

        if (imgui.igBegin(title, &window.popen, imgui.ImGuiWindowFlags_None)) {
            const bids = orderbook.bids;
            const asks = orderbook.asks;

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

            const table_flags = imgui.ImGuiTableFlags_SizingFixedFit | imgui.ImGuiTableFlags_BordersInnerV | imgui.ImGuiTableFlags_RowBg;
            const text_buf_size = 64;
            var text_buf: [text_buf_size]u8 = undefined;

            const draw_list = imgui.igGetWindowDrawList();

            imgui.igPushStyleVarX(imgui.ImGuiStyleVar_CellPadding, 8.0);
            imgui.igPushStyleVarY(imgui.ImGuiStyleVar_CellPadding, 4.0);
            defer imgui.igPopStyleVar(2);

            if (imgui.igBeginTable("AsksTable", 3, table_flags, .{ .x = 0, .y = 0 }, 0)) {
                defer imgui.igEndTable();

                imgui.igTableSetupColumn("Price", imgui.ImGuiTableColumnFlags_WidthFixed, 120.0, 0);
                imgui.igTableSetupColumn("Size", imgui.ImGuiTableColumnFlags_WidthFixed, 120.0, 0);
                imgui.igTableSetupColumn("Total", imgui.ImGuiTableColumnFlags_WidthFixed, 120.0, 0);

                imgui.igTableHeadersRow();

                var total_ask_volume: f64 = 0;
                for (asks.items) |ask| {
                    total_ask_volume += ask.qty;
                }

                var remaining_ask_vol = total_ask_volume;
                for (asks.items, 0..) |_, i| {
                    const ask = asks.items[i];

                    imgui.igTableNextRow(imgui.ImGuiTableRowFlags_None, 0);

                    _ = imgui.igTableSetColumnIndex(0);
                    const price_fmt = formatPrice(ask.price, &text_buf);
                    imgui.igPushStyleColor_U32(imgui.ImGuiCol_Text, imgui.igGetColorU32_Vec4(imgui.ImVec4{ .x = 0.93, .y = 0.32, .z = 0.31, .w = 1.0 }));
                    imgui.igText(price_fmt.ptr);
                    imgui.igPopStyleColor(1);

                    _ = imgui.igTableSetColumnIndex(1);
                    const vol_fmt = formatVolume(ask.qty, &text_buf);
                    imgui.igText(vol_fmt.ptr);

                    _ = imgui.igTableSetColumnIndex(2);
                    const total_fmt = formatVolume(remaining_ask_vol, &text_buf);
                    imgui.igText(total_fmt.ptr);

                    const depth_ratio = remaining_ask_vol / max_vol;
                    if (depth_ratio > 0) {
                        var size_col_rect: imgui.ImRect = undefined;
                        var total_col_rect: imgui.ImRect = undefined;
                        imgui.igTableGetCellBgRect(&size_col_rect, imgui.igGetCurrentTable(), 1);
                        imgui.igTableGetCellBgRect(&total_col_rect, imgui.igGetCurrentTable(), 2);

                        const combined_width = total_col_rect.Max.x - size_col_rect.Min.x;
                        const bar_width = combined_width * @as(f32, @floatCast(depth_ratio));

                        const bar_start = imgui.ImVec2{ .x = total_col_rect.Max.x - bar_width, .y = size_col_rect.Min.y + 1 };
                        const bar_end = imgui.ImVec2{ .x = total_col_rect.Max.x, .y = total_col_rect.Max.y - 1 };

                        const ask_depth_color = imgui.igGetColorU32_Vec4(imgui.ImVec4{ .x = 0.93, .y = 0.32, .z = 0.31, .w = 0.25 });
                        imgui.ImDrawList_AddRectFilled(draw_list, bar_start, bar_end, ask_depth_color, 2.0, imgui.ImDrawFlags_None);
                    }

                    remaining_ask_vol -= ask.qty;
                }
            }

            imgui.igSpacing();
            imgui.igSeparator();

            const spread_val = if (asks.items.len > 0 and bids.items.len > 0)
                @abs(asks.items[0].price - bids.items[0].price)
            else
                0.0;
            const best_ask = if (asks.items.len > 0) asks.items[0].price else 0.0;
            const best_bid = if (bids.items.len > 0) bids.items[0].price else 0.0;
            const mid_price = if (best_ask > 0 and best_bid > 0) (best_ask + best_bid) / 2.0 else 0.0;

            if (best_ask > 0 and best_bid > 0) {
                const spread_text = formatSpread(spread_val, best_ask, &text_buf);
                const spread_pct = if (mid_price > 0) (spread_val / mid_price) * 100.0 else 0.0;

                imgui.igPushStyleColor_U32(imgui.ImGuiCol_Text, imgui.igGetColorU32_Vec4(imgui.ImVec4{ .x = 0.8, .y = 0.8, .z = 0.4, .w = 1.0 }));
                imgui.igText(spread_text.ptr);

                if (spread_pct > 0) {
                    const spread_pct_text = std.fmt.bufPrintZ(&text_buf, "({d:.4}%%)", .{spread_pct}) catch "ERR";
                    imgui.igSameLine(0, 5);
                    imgui.igText(spread_pct_text.ptr);
                }
                imgui.igPopStyleColor(1);
            } else {
                imgui.igPushStyleColor_U32(imgui.ImGuiCol_Text, imgui.igGetColorU32_Vec4(imgui.ImVec4{ .x = 0.6, .y = 0.6, .z = 0.6, .w = 1.0 }));
                imgui.igText("Spread: No data");
                imgui.igPopStyleColor(1);
            }

            imgui.igSeparator();
            imgui.igSpacing();

            if (imgui.igBeginTable("BidsTable", 3, table_flags, .{ .x = 0, .y = 0 }, 0)) {
                defer imgui.igEndTable();

                imgui.igTableSetupColumn("Price", imgui.ImGuiTableColumnFlags_WidthFixed, 120.0, 0);
                imgui.igTableSetupColumn("Size", imgui.ImGuiTableColumnFlags_WidthFixed, 120.0, 0);
                imgui.igTableSetupColumn("Total", imgui.ImGuiTableColumnFlags_WidthFixed, 120.0, 0);

                imgui.igTableHeadersRow();

                var bid_cum_vol: f64 = 0;
                for (bids.items) |bid| {
                    bid_cum_vol += bid.qty;

                    imgui.igTableNextRow(imgui.ImGuiTableRowFlags_None, 0);

                    _ = imgui.igTableSetColumnIndex(0);
                    const price_fmt = formatPrice(bid.price, &text_buf);
                    imgui.igPushStyleColor_U32(imgui.ImGuiCol_Text, imgui.igGetColorU32_Vec4(imgui.ImVec4{ .x = 0.15, .y = 0.65, .z = 0.60, .w = 1.0 }));
                    imgui.igText(price_fmt.ptr);
                    imgui.igPopStyleColor(1);

                    _ = imgui.igTableSetColumnIndex(1);
                    const vol_fmt = formatVolume(bid.qty, &text_buf);
                    imgui.igText(vol_fmt.ptr);

                    _ = imgui.igTableSetColumnIndex(2);
                    const total_fmt = formatVolume(bid_cum_vol, &text_buf);
                    imgui.igText(total_fmt.ptr);

                    const depth_ratio = bid_cum_vol / max_vol;
                    if (depth_ratio > 0) {
                        var size_col_rect: imgui.ImRect = undefined;
                        var total_col_rect: imgui.ImRect = undefined;
                        imgui.igTableGetCellBgRect(&size_col_rect, imgui.igGetCurrentTable(), 1);
                        imgui.igTableGetCellBgRect(&total_col_rect, imgui.igGetCurrentTable(), 2);

                        const combined_width = total_col_rect.Max.x - size_col_rect.Min.x;
                        const bar_width = combined_width * @as(f32, @floatCast(depth_ratio));

                        const bar_start = imgui.ImVec2{ .x = total_col_rect.Max.x - bar_width, .y = size_col_rect.Min.y + 1 };
                        const bar_end = imgui.ImVec2{ .x = total_col_rect.Max.x, .y = total_col_rect.Max.y - 1 };

                        const bid_depth_color = imgui.igGetColorU32_Vec4(imgui.ImVec4{ .x = 0.15, .y = 0.65, .z = 0.60, .w = 0.25 });
                        imgui.ImDrawList_AddRectFilled(draw_list, bar_start, bar_end, bid_depth_color, 2.0, imgui.ImDrawFlags_None);
                    }
                }
            }
        }
        imgui.igEnd();
    }
};

fn formatPrice(price: f64, buf: []u8) []const u8 {
    return if (price >= 1000.0)
        std.fmt.bufPrintZ(buf, "{d:>12.2}", .{price}) catch "ERR"
    else if (price >= 100.0)
        std.fmt.bufPrintZ(buf, "{d:>12.3}", .{price}) catch "ERR"
    else if (price >= 10.0)
        std.fmt.bufPrintZ(buf, "{d:>12.4}", .{price}) catch "ERR"
    else if (price >= 1.0)
        std.fmt.bufPrintZ(buf, "{d:>12.5}", .{price}) catch "ERR"
    else if (price >= 0.1)
        std.fmt.bufPrintZ(buf, "{d:>12.6}", .{price}) catch "ERR"
    else if (price >= 0.01)
        std.fmt.bufPrintZ(buf, "{d:>12.7}", .{price}) catch "ERR"
    else if (price >= 0.001)
        std.fmt.bufPrintZ(buf, "{d:>12.8}", .{price}) catch "ERR"
    else if (price >= 0.0001)
        std.fmt.bufPrintZ(buf, "{d:>12.9}", .{price}) catch "ERR"
    else
        std.fmt.bufPrintZ(buf, "{d:>12.10}", .{price}) catch "ERR";
}

fn formatVolume(volume: f64, buf: []u8) []const u8 {
    return if (volume >= 1000000.0)
        std.fmt.bufPrintZ(buf, "{d:>12.0}", .{volume}) catch "ERR"
    else if (volume >= 100000.0)
        std.fmt.bufPrintZ(buf, "{d:>12.1}", .{volume}) catch "ERR"
    else if (volume >= 1000.0)
        std.fmt.bufPrintZ(buf, "{d:>12.2}", .{volume}) catch "ERR"
    else
        std.fmt.bufPrintZ(buf, "{d:>12.2}", .{volume}) catch "ERR";
}

fn formatSpread(spread: f64, best_ask: f64, buf: []u8) []const u8 {
    if (spread == 0.0) {
        return std.fmt.bufPrintZ(buf, "Spread: 0", .{}) catch "ERR";
    }

    return if (best_ask >= 1000.0)
        std.fmt.bufPrintZ(buf, "Spread: {d:.2}", .{spread}) catch "ERR"
    else if (best_ask >= 100.0)
        std.fmt.bufPrintZ(buf, "Spread: {d:.3}", .{spread}) catch "ERR"
    else if (best_ask >= 10.0)
        std.fmt.bufPrintZ(buf, "Spread: {d:.4}", .{spread}) catch "ERR"
    else if (best_ask >= 1.0)
        std.fmt.bufPrintZ(buf, "Spread: {d:.5}", .{spread}) catch "ERR"
    else if (best_ask >= 0.1)
        std.fmt.bufPrintZ(buf, "Spread: {d:.6}", .{spread}) catch "ERR"
    else if (best_ask >= 0.01)
        std.fmt.bufPrintZ(buf, "Spread: {d:.7}", .{spread}) catch "ERR"
    else if (best_ask >= 0.001)
        std.fmt.bufPrintZ(buf, "Spread: {d:.8}", .{spread}) catch "ERR"
    else if (best_ask >= 0.0001)
        std.fmt.bufPrintZ(buf, "Spread: {d:.9}", .{spread}) catch "ERR"
    else if (best_ask >= 0.00001)
        std.fmt.bufPrintZ(buf, "Spread: {d:.10}", .{spread}) catch "ERR"
    else
        std.fmt.bufPrintZ(buf, "Spread: {d:.12}", .{spread}) catch "ERR";
}
