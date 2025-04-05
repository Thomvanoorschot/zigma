const std = @import("std");
const sokol = @import("sokol");
const imgui = @import("imgui");

const OrderBookEntry = struct {
    price: f64,
    volume: f64,
};

const DEPTH = 10;
const CENTER_PRICE = 100.0;
const PRICE_STEP = 0.5;
const MAX_VOLUME = 20.0;

var seed: u32 = 12345;
fn lcg() f64 {
    seed = seed *% 1103515245 +% 12345;
    return @as(f64, @floatFromInt(seed % 1000)) / 1000.0;
}

fn generateDummyData(allocator: std.mem.Allocator) ![2][]OrderBookEntry {
    var bids = try allocator.alloc(OrderBookEntry, DEPTH);
    errdefer allocator.free(bids);
    var asks = try allocator.alloc(OrderBookEntry, DEPTH);
    errdefer allocator.free(asks);

    for (0..DEPTH) |i| {
        const price_offset = @as(f64, @floatFromInt(i + 1)) * PRICE_STEP;
        bids[i] = .{
            .price = CENTER_PRICE - price_offset,
            .volume = lcg() * MAX_VOLUME + 1.0,
        };
        asks[i] = .{
            .price = CENTER_PRICE + price_offset,
            .volume = lcg() * MAX_VOLUME + 1.0,
        };
    }

    return .{ bids, asks };
}

fn drawVolumeBar(draw_list: *imgui.ImDrawList, p_min: imgui.ImVec2, p_max: imgui.ImVec2, volume_fraction: f32, color: u32, is_ask: bool) void {
    const width = p_max.x - p_min.x;
    const bar_width = width * volume_fraction;
    var bar_p_min: imgui.ImVec2 = undefined;
    var bar_p_max: imgui.ImVec2 = undefined;

    if (is_ask) {
        bar_p_min = p_min;
        bar_p_max = imgui.ImVec2{ .x = p_min.x + bar_width, .y = p_max.y };
    } else {
        bar_p_min = imgui.ImVec2{ .x = p_max.x - bar_width, .y = p_min.y };
        bar_p_max = p_max;
    }
    const padding: f32 = 1.0;
    bar_p_min.x += padding;
    bar_p_min.y += padding;
    bar_p_max.x -= padding;
    bar_p_max.y -= padding;

    if (bar_p_max.x > bar_p_min.x and bar_p_max.y > bar_p_min.y) {
        imgui.ImDrawList_AddRectFilled(draw_list, bar_p_min, bar_p_max, color, 0.0, 0);
    }
}

pub fn plotOrderbookWindow(allocator: std.mem.Allocator) !void {
    if (!imgui.igIsWindowDocked()) {
        imgui.igSetNextWindowSize(.{ .x = 400, .y = 600 }, imgui.ImGuiCond_FirstUseEver);
    }

    if (imgui.igBegin("Order Book Table", null, imgui.ImGuiWindowFlags_None)) {
        defer imgui.igEnd();

        const data = try generateDummyData(allocator);
        defer allocator.free(data[0]);
        defer allocator.free(data[1]);
        const bids = data[0];
        const asks = data[1];

        var max_vol: f64 = 0.0;
        for (bids) |bid| max_vol = @max(max_vol, bid.volume);
        for (asks) |ask| max_vol = @max(max_vol, ask.volume);
        if (max_vol > 0) {
            max_vol *= 1.05;
        } else {
            max_vol = 1.0;
        }

        const table_flags: imgui.ImGuiTableFlags =
            imgui.ImGuiTableFlags_BordersInnerV |
            imgui.ImGuiTableFlags_SizingFixedFit |
            imgui.ImGuiTableFlags_RowBg;

        const text_buf_size = 64;
        var text_buf: [text_buf_size]u8 = undefined;

        if (imgui.igBeginTable("AsksTable", 3, table_flags, .{ .x = 0, .y = 0 }, 0)) {
            defer imgui.igEndTable();

            imgui.igTableSetupColumn("Price", imgui.ImGuiTableColumnFlags_WidthFixed, 80.0, 0);
            imgui.igTableSetupColumn("Volume", imgui.ImGuiTableColumnFlags_WidthFixed, 80.0, 0);
            imgui.igTableSetupColumn("Bar", imgui.ImGuiTableColumnFlags_WidthStretch, 0.0, 0);
            imgui.igTableHeadersRow();

            const ask_color = imgui.igGetColorU32_Vec4(.{ .x = 1.0, .y = 0.2, .z = 0.2, .w = 0.4 });

            var ask_cum_vol: f64 = 0;
            var i: usize = asks.len;
            while (i > 0) : (i -= 1) {
                const index = i - 1;
                const ask = asks[index];
                ask_cum_vol += ask.volume;

                imgui.igTableNextRow(0, 0);

                _ = imgui.igTableSetColumnIndex(0);
                const price_fmt = std.fmt.bufPrint(&text_buf, "{d:.2}", .{ask.price}) catch "ERR";
                imgui.igText(price_fmt.ptr);

                _ = imgui.igTableSetColumnIndex(1);
                const vol_fmt = std.fmt.bufPrint(&text_buf, "{d:.3}", .{ask.volume}) catch "ERR";
                imgui.igText(vol_fmt.ptr);

                _ = imgui.igTableSetColumnIndex(2);
                const draw_list = imgui.igGetWindowDrawList();
                var cell_p_min: imgui.ImVec2 = undefined;
                imgui.igGetCursorScreenPos(&cell_p_min);
                var content_region_avail: imgui.ImVec2 = undefined;
                imgui.igGetContentRegionAvail(&content_region_avail);
                const cell_p_max = imgui.ImVec2{
                    .x = cell_p_min.x + content_region_avail.x,
                    .y = cell_p_min.y + imgui.igGetTextLineHeight() + imgui.igGetStyle().*.FramePadding.y * 2,
                };
                const vol_fraction = @as(f32, @floatCast(ask.volume / max_vol));
                drawVolumeBar(draw_list, cell_p_min, cell_p_max, vol_fraction, ask_color, true);
                imgui.igDummy(.{ .x = 0, .y = imgui.igGetTextLineHeight() });
            }
        }

        imgui.igSeparator();
        const spread_text = std.fmt.bufPrint(&text_buf, "Spread: {d:.2}", .{if (asks.len > 0 and bids.len > 0) asks[0].price - bids[0].price else 0.0}) catch "ERR SPREAD";
        imgui.igText(spread_text.ptr);
        imgui.igSeparator();

        if (imgui.igBeginTable("BidsTable", 3, table_flags, .{ .x = 0, .y = 0 }, 0)) {
            defer imgui.igEndTable();

            imgui.igTableSetupColumn("Price", imgui.ImGuiTableColumnFlags_WidthFixed, 80.0, 0);
            imgui.igTableSetupColumn("Volume", imgui.ImGuiTableColumnFlags_WidthFixed, 80.0, 0);
            imgui.igTableSetupColumn("Bar", imgui.ImGuiTableColumnFlags_WidthStretch, 0.0, 0);

            const bid_color = imgui.igGetColorU32_Vec4(.{ .x = 0.2, .y = 1.0, .z = 0.2, .w = 0.4 });

            var bid_cum_vol: f64 = 0;
            for (bids) |bid| {
                bid_cum_vol += bid.volume;

                imgui.igTableNextRow(0, 0);

                _ = imgui.igTableSetColumnIndex(0);
                const price_fmt = std.fmt.bufPrint(&text_buf, "{d:.2}", .{bid.price}) catch "ERR";
                imgui.igText(price_fmt.ptr);

                _ = imgui.igTableSetColumnIndex(1);
                const vol_fmt = std.fmt.bufPrint(&text_buf, "{d:.3}", .{bid.volume}) catch "ERR";
                imgui.igText(vol_fmt.ptr);

                _ = imgui.igTableSetColumnIndex(2);
                const draw_list = imgui.igGetWindowDrawList();
                var cell_p_min: imgui.ImVec2 = undefined;
                imgui.igGetCursorScreenPos(&cell_p_min);
                var content_region_avail: imgui.ImVec2 = undefined;
                imgui.igGetContentRegionAvail(&content_region_avail);
                const cell_p_max = imgui.ImVec2{
                    .x = cell_p_min.x + content_region_avail.x,
                    .y = cell_p_min.y + imgui.igGetTextLineHeight() + imgui.igGetStyle().*.FramePadding.y * 2,
                };
                const vol_fraction = @as(f32, @floatCast(bid.volume / max_vol));
                drawVolumeBar(draw_list, cell_p_min, cell_p_max, vol_fraction, bid_color, false);
                imgui.igDummy(.{ .x = 0, .y = imgui.igGetTextLineHeight() });
            }
        }
    }
}
