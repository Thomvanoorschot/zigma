const std = @import("std");
const gui = @import("../gui.zig");
const plot = @import("../plot.zig");
const glfw = @import("zglfw");
const shared_models = @import("shared_models");
const zul = @import("zul");

const DateTime = zul.DateTime;
const OHLC = shared_models.OHLC;
const DrawList = gui.DrawList;

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

    // const half_width: f64 = if (ohlc_list.len > 1)
    //     (xs[1] - xs[0]) * 0.25
    // else
    //     0.25;

    const bull_col: [4]f32 = .{ 0.0, 1.0, 0.0, 1.0 }; // Green
    const bear_col: [4]f32 = .{ 1.0, 0.0, 0.0, 1.0 }; // Red

    plot.setupAxis(.x1, .{
        .label = "Time",
        .flags = .{
            .auto_fit = true,
            .range_fit = true,
        },
    }); // Setup default X axis
    plot.setupAxis(.y1, .{
        .label = "$",
        .flags = .{
            .auto_fit = true,
            .range_fit = true,
        },
    });

    const time_padding: f64 = 60 * 60;
    const min_time = xs[0];
    const max_time = xs[xs.len - 1];

    plot.setupAxisLimits(.x1, .{ .min = min_time - (time_padding), .max = max_time + (time_padding) });
    // plot.setupAxisLimits(.y1, .{ .min = 84000, .max = 86000 });
    plot.setupAxisScale(.x1, .time);
    plot.setupAxisLimitsConstraints(.x1, min_time - time_padding, max_time + time_padding);

    const min_zoom_span: f64 = 60 * 15;
    const max_zoom_span: f64 = if (ohlc_list.len > 1)
        max_time - min_time + (2 * time_padding)
    else
        time_padding * 2;

    plot.setupAxisZoomConstraints(.x1, min_zoom_span, max_zoom_span);

    plot.setupAxisFormat(.y1, "$%.0f");
    plot.setupLegend(.{ .south = true, .west = true }, .{});
    plot.setupFinish();
    // Render data

    // if (plot.beginItem("Candlestick2")) {
    //     defer plot.endItem();

    if (plot.fitThisFrame()) {
        for (0..ohlc_list.len) |i| {
            plot.fitPoint(plot.PlotPoint{ .x = xs[i], .y = ohlc_list[i].low });
            plot.fitPoint(plot.PlotPoint{ .x = xs[i], .y = ohlc_list[i].high });
        }
    }

    for (ohlc_list, 0..) |ohlc, i| {
        const color = if (ohlc.close > ohlc.open) bull_col else bear_col;

        // Draw wicks
        plot.pushPlotStyleColor_Vec4(.line, color);
        plot.plotLine("", f64, .{
            .xv = &[_]f64{ xs[i], xs[i] },
            .yv = &[_]f64{ ohlc.low, ohlc.high },
        });
        // plot.popStyleColor(1);

        // Draw body
        // const bottom = @min(ohlc.open, ohlc.close);
        // const top = @max(ohlc.open, ohlc.close);

        plot.pushPlotStyleVar_Float(.line_weight, 5.0);
        // plot.pushStyleColor_Vec4(.line, color);

        plot.plotLine("", f64, .{
            .xv = &[_]f64{ xs[i], xs[i] },
            .yv = &[_]f64{ ohlc.open, ohlc.close },
        });

        plot.popPlotStyleColor(1);
        plot.popPlotStyleVar(1);

        // const open_pos = plot.plotToPixels(xs[i] - half_width, ohlc.open);
        // const close_pos = plot.plotToPixels(xs[i] + half_width, ohlc.close);
    }
    // }
}

pub fn plotOHLCListWindow(allocator: std.mem.Allocator, ohlc_list: []const OHLC) !void {
    if (ohlc_list.len == 0) {
        // Handle empty list case if needed, maybe show a message
        return;
    }

    var title_buf: [128]u8 = undefined;
    const title = std.fmt.bufPrintZ(&title_buf, "OHLC - {s}", .{ohlc_list[0].symbol}) catch unreachable;

    if (gui.begin(title, .{})) {
        defer gui.end();

        if (plot.beginPlot(
            "Candlestick",
            .{ .h = -1 },
        )) {
            plot.getStyle().use_local_time = true;

            defer plot.endPlot(); // Ensure endPlot is always called

            // Keep plotCandlestick commented out for now
            try plotCandlestick(
                allocator,
                ohlc_list,
            );
        }
    }
}
