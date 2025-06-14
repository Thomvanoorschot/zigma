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

            var max_vol: f64 = 0.0;
            for (bids.items) |bid| max_vol = @max(max_vol, bid.qty);
            for (asks.items) |ask| max_vol = @max(max_vol, ask.qty);

            if (max_vol > 0) {
                max_vol *= 1.05;
            } else {
                max_vol = 1.0;
            }

            const table_flags = imgui.ImGuiTableFlags_BordersInnerV | imgui.ImGuiTableFlags_SizingFixedFit;
            const text_buf_size = 64;
            var text_buf: [text_buf_size]u8 = undefined;

            const draw_list = imgui.igGetWindowDrawList();

            if (imgui.igBeginTable("AsksTable", 3, table_flags, .{ .x = 0, .y = 0 }, 0)) {
                defer imgui.igEndTable();

                imgui.igTableSetupColumn("Price", imgui.ImGuiTableColumnFlags_WidthFixed, 80.0, 0);
                imgui.igTableSetupColumn("Size", imgui.ImGuiTableColumnFlags_WidthFixed, 80.0, 0);
                imgui.igTableSetupColumn("Total", imgui.ImGuiTableColumnFlags_WidthFixed, 100.0, 0);

                imgui.igTableHeadersRow();

                var ask_cum_vol: f64 = 0;
                for (asks.items, 0..) |_, i| {
                    const ask = asks.items[asks.items.len - 1 - i];
                    ask_cum_vol += ask.qty;

                    imgui.igTableNextRow(imgui.ImGuiTableRowFlags_None, 0);

                    const depth_ratio = ask.qty / max_vol;
                    if (depth_ratio > 0) {
                        var rect_col0: imgui.ImRect = undefined;
                        var rect_col2: imgui.ImRect = undefined;
                        imgui.igTableGetCellBgRect(&rect_col0, imgui.igGetCurrentTable(), 0);
                        imgui.igTableGetCellBgRect(&rect_col2, imgui.igGetCurrentTable(), 2);

                        const full_row_min = imgui.ImVec2{ .x = rect_col0.Min.x, .y = rect_col0.Min.y };
                        const full_row_max = imgui.ImVec2{ .x = rect_col2.Max.x, .y = rect_col0.Max.y };

                        const bar_width = (full_row_max.x - full_row_min.x) * @as(f32, @floatCast(depth_ratio));
                        const bar_max = imgui.ImVec2{ .x = full_row_max.x - bar_width, .y = full_row_max.y };

                        const ask_depth_color = imgui.igGetColorU32_Vec4(imgui.ImVec4{ .x = 0.8, .y = 0.2, .z = 0.2, .w = 0.3 });
                        imgui.ImDrawList_AddRectFilled(draw_list, bar_max, full_row_max, ask_depth_color, 0.0, imgui.ImDrawFlags_None);
                    }

                    _ = imgui.igTableSetColumnIndex(0);
                    const price_fmt = std.fmt.bufPrintZ(&text_buf, "{d:.2}", .{ask.price}) catch "ERR";
                    imgui.igTextColored(imgui.ImVec4{ .x = 1, .y = 0, .z = 0, .w = 1 }, price_fmt.ptr);

                    _ = imgui.igTableSetColumnIndex(1);
                    const vol_fmt = std.fmt.bufPrintZ(&text_buf, "{d:.3}", .{ask.qty}) catch "ERR";
                    imgui.igText(vol_fmt.ptr);

                    _ = imgui.igTableSetColumnIndex(2);
                    const total_fmt = std.fmt.bufPrintZ(&text_buf, "{d:.2}", .{ask_cum_vol * ask.price}) catch "ERR";
                    imgui.igText(total_fmt.ptr);
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

                    const depth_ratio = bid.qty / max_vol;
                    if (depth_ratio > 0) {
                        var rect_col0: imgui.ImRect = undefined;
                        var rect_col2: imgui.ImRect = undefined;
                        imgui.igTableGetCellBgRect(&rect_col0, imgui.igGetCurrentTable(), 0);
                        imgui.igTableGetCellBgRect(&rect_col2, imgui.igGetCurrentTable(), 2);

                        const full_row_min = imgui.ImVec2{ .x = rect_col0.Min.x, .y = rect_col0.Min.y };
                        const full_row_max = imgui.ImVec2{ .x = rect_col2.Max.x, .y = rect_col0.Max.y };

                        const bar_width = (full_row_max.x - full_row_min.x) * @as(f32, @floatCast(depth_ratio));
                        const bar_max = imgui.ImVec2{ .x = full_row_max.x - bar_width, .y = full_row_max.y };

                        const bid_depth_color = imgui.igGetColorU32_Vec4(imgui.ImVec4{ .x = 0.2, .y = 0.8, .z = 0.2, .w = 0.3 });
                        imgui.ImDrawList_AddRectFilled(draw_list, bar_max, full_row_max, bid_depth_color, 0.0, imgui.ImDrawFlags_None);
                    }

                    _ = imgui.igTableSetColumnIndex(0);
                    const price_fmt = std.fmt.bufPrintZ(&text_buf, "{d:.2}", .{bid.price}) catch "ERR";
                    imgui.igTextColored(imgui.ImVec4{ .x = 0, .y = 1, .z = 0, .w = 1 }, price_fmt.ptr);

                    _ = imgui.igTableSetColumnIndex(1);
                    const vol_fmt = std.fmt.bufPrintZ(&text_buf, "{d:.3}", .{bid.qty}) catch "ERR";
                    imgui.igText(vol_fmt.ptr);

                    _ = imgui.igTableSetColumnIndex(2);
                    const total_fmt = std.fmt.bufPrintZ(&text_buf, "{d:.2}", .{bid_cum_vol * bid.price}) catch "ERR";
                    imgui.igText(total_fmt.ptr);
                }
            }
        }
    }
};
