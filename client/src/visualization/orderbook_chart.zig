const std = @import("std");
const zgui = @import("zgui");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const gl = zopengl.bindings;
const shared_models = @import("shared_models");

const OrderBook = shared_models.OrderBook;
const PriceLevel = shared_models.PriceLevel;

fn drawVolumeBar(
    draw_list: zgui.DrawList,
    p_min: [2]f32,
    p_max: [2]f32,
    volume_fraction: f32,
    color: u32,
    is_ask: bool,
) void {
    const width = p_max[0] - p_min[0];
    const bar_width = width * volume_fraction;
    var bar_p_min: [2]f32 = undefined;
    var bar_p_max: [2]f32 = undefined;

    if (is_ask) {
        bar_p_min = p_min;
        bar_p_max = .{ p_min[0] + bar_width, p_max[1] };
    } else {
        bar_p_min = .{ p_max[0] - bar_width, p_min[1] };
        bar_p_max = p_max;
    }
    const padding: f32 = 1.0;
    bar_p_min[0] += padding;
    bar_p_min[1] += padding;
    bar_p_max[0] -= padding;
    bar_p_max[1] -= padding;

    if (bar_p_max[0] > bar_p_min[0] and bar_p_max[1] > bar_p_min[1]) {
        draw_list.addRectFilled(.{
            .pmin = bar_p_min,
            .pmax = bar_p_max,
            .col = color,
            .rounding = 0.0,
            .flags = .{},
        });
    }
}

pub fn plotOrderbookWindow(orderbook: *const OrderBook) !void {
    zgui.setNextWindowSize(.{ .w = 400, .h = 600, .cond = .first_use_ever });

    var title_buf: [128]u8 = undefined;
    const title = std.fmt.bufPrintZ(&title_buf, "Order Book - {s} ({s})", .{ orderbook.ticker, orderbook.exchange }) catch unreachable;

    if (zgui.begin(title, .{})) {
        defer zgui.end();

        const bids = orderbook.bids;
        const asks = orderbook.asks;

        var max_vol: f64 = 0.0;
        for (bids) |bid| max_vol = @max(max_vol, bid.qty);
        for (asks) |ask| max_vol = @max(max_vol, ask.qty);

        if (max_vol > 0) {
            max_vol *= 1.05;
        } else {
            max_vol = 1.0;
        }

        const table_flags = zgui.TableFlags{
            .borders = .{ .inner_v = true },
            .sizing = .fixed_fit,
            .row_bg = true,
        };

        const text_buf_size = 64;
        var text_buf: [text_buf_size]u8 = undefined;

        if (zgui.beginTable("AsksTable", .{ .column = 3, .flags = table_flags })) {
            defer zgui.endTable();

            zgui.tableSetupColumn("Price", .{ .flags = .{ .width_fixed = true }, .init_width_or_height = 80.0 });
            zgui.tableSetupColumn("Volume", .{ .flags = .{ .width_fixed = true }, .init_width_or_height = 80.0 });
            zgui.tableSetupColumn("Bar", .{ .flags = .{ .width_stretch = true } });
            zgui.tableHeadersRow();

            const ask_color = zgui.colorConvertFloat4ToU32([_]f32{ 1.0, 0.2, 0.2, 0.4 });

            var ask_cum_vol: f64 = 0;
            var i: usize = asks.len;
            while (i > 0) : (i -= 1) {
                const index = i - 1;
                const ask = asks[index];
                ask_cum_vol += ask.qty;

                zgui.tableNextRow(.{});

                _ = zgui.tableSetColumnIndex(0);
                const price_fmt = std.fmt.bufPrint(&text_buf, "{d:.2}", .{ask.price}) catch "ERR";
                zgui.textUnformatted(price_fmt);

                _ = zgui.tableSetColumnIndex(1);
                const vol_fmt = std.fmt.bufPrint(&text_buf, "{d:.3}", .{ask.qty}) catch "ERR";
                zgui.textUnformatted(vol_fmt);

                _ = zgui.tableSetColumnIndex(2);
                const draw_list = zgui.getWindowDrawList();
                const cell_p_min = zgui.getCursorScreenPos();
                const content_region_avail = zgui.getContentRegionAvail();
                const cell_p_max: [2]f32 = .{
                    cell_p_min[0] + content_region_avail[0],
                    cell_p_min[1] + zgui.getTextLineHeight() + zgui.getStyle().frame_padding[1] * 2,
                };
                const vol_fraction = @as(f32, @floatCast(ask.qty / max_vol));
                drawVolumeBar(draw_list, cell_p_min, cell_p_max, vol_fraction, ask_color, true);
                zgui.dummy(.{ .w = 0, .h = zgui.getTextLineHeight() });
            }
        }

        zgui.separator();
        const spread_val = if (asks.len > 0 and bids.len > 0) asks[0].price - bids[0].price else 0.0;
        const spread_text = std.fmt.bufPrint(&text_buf, "Spread: {d:.2}", .{spread_val}) catch "ERR SPREAD";
        zgui.textUnformatted(spread_text);
        zgui.separator();

        if (zgui.beginTable("BidsTable", .{ .column = 3, .flags = table_flags })) {
            defer zgui.endTable();

            zgui.tableSetupColumn("Price", .{ .flags = .{ .width_fixed = true }, .init_width_or_height = 80.0 });
            zgui.tableSetupColumn("Volume", .{ .flags = .{ .width_fixed = true }, .init_width_or_height = 80.0 });
            zgui.tableSetupColumn("Bar", .{ .flags = .{ .width_stretch = true } });

            const bid_color = zgui.colorConvertFloat4ToU32([_]f32{ 0.2, 1.0, 0.2, 0.4 });

            var bid_cum_vol: f64 = 0;
            for (bids) |bid| {
                bid_cum_vol += bid.qty;

                zgui.tableNextRow(.{});

                _ = zgui.tableSetColumnIndex(0);
                const price_fmt = std.fmt.bufPrint(&text_buf, "{d:.2}", .{bid.price}) catch "ERR";
                zgui.textUnformatted(price_fmt);

                _ = zgui.tableSetColumnIndex(1);
                const vol_fmt = std.fmt.bufPrint(&text_buf, "{d:.3}", .{bid.qty}) catch "ERR";
                zgui.textUnformatted(vol_fmt);

                _ = zgui.tableSetColumnIndex(2);
                const draw_list = zgui.getWindowDrawList();
                const cell_p_min = zgui.getCursorScreenPos();
                const content_region_avail = zgui.getContentRegionAvail();
                const cell_p_max: [2]f32 = .{
                    cell_p_min[0] + content_region_avail[0],
                    cell_p_min[1] + zgui.getTextLineHeight() + zgui.getStyle().frame_padding[1] * 2,
                };
                const vol_fraction = @as(f32, @floatCast(bid.qty / max_vol));
                drawVolumeBar(draw_list, cell_p_min, cell_p_max, vol_fraction, bid_color, false);
                zgui.dummy(.{ .w = 0, .h = zgui.getTextLineHeight() });
            }
        }
    }
}
