const std = @import("std");
const gui = @import("../gui.zig");
const plot = @import("../plot.zig");
const glfw = @import("zglfw");
const shared_models = @import("shared_models");

const OrderBook = shared_models.OrderBook;
const PriceLevel = shared_models.PriceLevel;

pub fn plotOrderbookWindow(orderbook: *const OrderBook) !void {
    var title_buf: [128]u8 = undefined;
    const title = std.fmt.bufPrintZ(&title_buf, "Order Book - {s} ({s})", .{ orderbook.ticker, orderbook.exchange }) catch unreachable;

    if (gui.begin(title, .{})) {
        defer gui.end();

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
                ask_cum_vol += ask.qty;

                gui.tableNextRow(.{});

                _ = gui.tableSetColumnIndex(0);
                const price_fmt = std.fmt.bufPrint(&text_buf, "{d:.2}", .{ask.price}) catch "ERR";
                // Colors are AABBGGRR
                gui.textUnformattedColored(0xFF0000FF, price_fmt);

                _ = gui.tableSetColumnIndex(1);
                const vol_fmt = std.fmt.bufPrint(&text_buf, "{d:.3}", .{ask.qty}) catch "ERR";
                gui.textUnformattedColored(0xFF0000FF, vol_fmt);
            }
        }

        gui.separator();
        const spread_val = if (asks.items.len > 0 and bids.items.len > 0) asks.items[0].price - bids.items[0].price else 0.0;
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
                bid_cum_vol += bid.qty;

                gui.tableNextRow(.{});

                _ = gui.tableSetColumnIndex(0);
                const price_fmt = std.fmt.bufPrint(&text_buf, "{d:.2}", .{bid.price}) catch "ERR";
                gui.textUnformattedColored(0xFF00FF00, price_fmt);
                _ = gui.tableSetColumnIndex(1);
                const vol_fmt = std.fmt.bufPrint(&text_buf, "{d:.3}", .{bid.qty}) catch "ERR";
                gui.textUnformattedColored(0xFF00FF00, vol_fmt);
            }
        }
    }
}
