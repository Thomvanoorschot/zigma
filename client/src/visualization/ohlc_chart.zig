const std = @import("std");
const zgui = @import("zgui");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const shared_models = @import("shared_models");
const zul = @import("zul");

const DateTime = zul.DateTime;
const gl = zopengl.bindings;
const OHLC = shared_models.OHLC;
const plot = zgui.plot;
const DrawList = zgui.DrawList;

fn plotCandlestick(
    allocator: std.mem.Allocator,
    ohlc_list: []const OHLC,
) !void {
    if (ohlc_list.len == 0) return;

    var xs = try allocator.alloc(f64, ohlc_list.len);
    defer allocator.free(xs);

    for (ohlc_list, 0..) |ohlc, i| {
        const dt = try DateTime.parse(ohlc.timestamp, .rfc3339);
        xs[i] = @as(f64, @floatFromInt(dt.unix(.seconds)));
    }

    const half_width: f64 = if (ohlc_list.len > 1)
        (xs[1] - xs[0]) * 0.25
    else
        0.25;

    const bull_col: u32 = zgui.colorConvertFloat4ToU32(.{ 0.0, 1.0, 0.0, 1.0 }); // Green
    const bear_col: u32 = zgui.colorConvertFloat4ToU32(.{ 1.0, 0.0, 0.0, 1.0 }); // Red

    plot.setupAxis(.x1, .{
        .label = "Time",
        .flags = .{
            // .auto_fit = true,
            // .range_fit = true,
        },
    }); // Setup default X axis
    plot.setupAxis(.y1, .{
        .label = "$",
        .flags = .{
            // .auto_fit = true,
            // .range_fit = true,
        },
    });

    const time_padding: f64 = 60 * 60;
    const min_time = xs[0];
    const max_time = xs[xs.len - 1];

    zgui.plot.setupAxisLimits(.x1, .{ .min = min_time - (time_padding), .max = max_time + (time_padding) });
    zgui.plot.setupAxisLimits(.y1, .{ .min = 84000, .max = 86000 });
    zgui.plot.setupAxisScale(.x1, .time);
    
    zgui.plot.setupAxisLimitsConstraints(.x1, min_time - time_padding, max_time + time_padding);

    const min_zoom_span: f64 = 60 * 15;
    const max_zoom_span: f64 = if (ohlc_list.len > 1)
        max_time - min_time + (2 * time_padding)
    else
        time_padding * 2;

    zgui.plot.setupAxisZoomConstraints(.x1, min_zoom_span, max_zoom_span);

    zgui.plot.setupAxisFormat(.y1, "$%.0f");
    zgui.plot.setupLegend(.{ .south = true, .west = true }, .{});
    zgui.plot.setupFinish();
    // Render data
    const draw_list = plot.getPlotDrawList();

    std.debug.print("time: {d} ohlc: {s} {d} {d} {d} {d}\n", .{ xs[ohlc_list.len - 1], ohlc_list[ohlc_list.len - 1].symbol, ohlc_list[ohlc_list.len - 1].open, ohlc_list[ohlc_list.len - 1].close, ohlc_list[ohlc_list.len - 1].low, ohlc_list[ohlc_list.len - 1].high });
    if (plot.beginItem("Candlestick")) {
        defer plot.endItem();
        for (ohlc_list, 0..) |ohlc, i| {

            const color = if (ohlc.open > ohlc.close) bear_col else bull_col;

            const open_pos = plot.plotToPixels(xs[i] - half_width, ohlc.open);
            const close_pos = plot.plotToPixels(xs[i] + half_width, ohlc.close);

            const low_pos = plot.plotToPixels(xs[i], ohlc.low);
            const high_pos = plot.plotToPixels(xs[i], ohlc.high);

            draw_list.addLine(.{
                .p1 = low_pos,
                .p2 = high_pos,
                .col = color,
                .thickness = 10.0,
            });
            draw_list.addRectFilled(.{
                .pmin = open_pos,
                .pmax = close_pos,
                .col = color,
            });
        }
    }
}

pub fn plotOHLCListWindow(allocator: std.mem.Allocator, ohlc_list: []const OHLC) !void {
    if (ohlc_list.len == 0) {
        // Handle empty list case if needed, maybe show a message
        return;
    }

    zgui.setNextWindowSize(.{ .w = 800, .h = 600, .cond = .first_use_ever });

    var title_buf: [128]u8 = undefined;
    const title = std.fmt.bufPrintZ(&title_buf, "OHLC - {s}", .{ohlc_list[0].symbol}) catch unreachable;

    if (zgui.begin(title, .{})) {
        defer zgui.end();

        if (plot.beginPlot(
            "Candlestick",
            .{ .h = -1 },
        )) {
            defer plot.endPlot(); // Ensure endPlot is always called

            // Keep plotCandlestick commented out for now
            try plotCandlestick(
                allocator,
                ohlc_list,
            );
        }
    }
}
