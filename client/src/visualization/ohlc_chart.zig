const std = @import("std");
const zgui = @import("zgui");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const gl = zopengl.bindings;
const shared_models = @import("shared_models");

const OHLC = shared_models.OHLC;

const plot = zgui.plot;
const DrawList = zgui.DrawList;

// fn parseFloatTimestamp(_: std.mem.Allocator, timestamp_str: []const u8) !f32 {
//     // TODO: Implement robust timestamp parsing based on your actual format
//     // Assuming Unix timestamp as string for now
//     _ = timestamp_str;
//     return 1712982000;
//     // return std.fmt.parseFloat(f64, timestamp_str);
// }

fn plotCandlestick(
    _: [:0]const u8,
    ohlc_list: []const OHLC,
    allocator: std.mem.Allocator,
    tooltip: bool,
    width_percent: f32,
    bull_col: u32,
    bear_col: u32,
) !void {
    if (ohlc_list.len == 0) return;

    const draw_list = zgui.getWindowDrawList();
    // Convert timestamps to f64 for plotting
    var xs = try allocator.alloc(f32, ohlc_list.len);
    defer allocator.free(xs);
    for (ohlc_list, 0..) |_, i| {
        // xs[i] = try parseFloatTimestamp(allocator, ohlc.timestamp);
        xs[i] = @as(f32, @floatFromInt(i));
    }

    // Calculate width based on time difference if possible
    const half_width: f32 = if (ohlc_list.len > 1)
        (xs[1] - xs[0]) * width_percent * 0.5
    else
        width_percent * 0.5; // Fallback for single data point

    // TODO: Implement tooltip logic similar to C++ example
    _ = tooltip; // Suppress unused warning for now

    // Begin plot item
    // if (zgui.begin(label_id, .{})) {
    //     defer zgui.end();

    // Override legend icon color (optional)
    // plot.getCurrentItem().?.color = zgui.colorConvertFloat4ToU32(.{ 0.25, 0.25, 0.25, 1.0 });

    // Fit data if requested
    // if (plot.fitThisFrame()) {
    //     for (ohlc_list, 0..) |ohlc, i| {
    //         plot.fitPoint(.{ .x = xs[i], .y = ohlc.low });
    //         plot.fitPoint(.{ .x = xs[i], .y = ohlc.high });
    //     }
    // }
    // plot.plotBars("GOOGL", f64, .{
    //     .xv = &.{
    //         0.1,
    //     },
    //     .yv = &.{
    //         0.1,
    //     },
    //     .bar_size = 0.1,
    // });
    // _ = draw_list;
    // _ = bull_col;
    // _ = bear_col;
    // Render data
    for (ohlc_list, 0..) |ohlc, i| {
        // Ensure coordinates are ordered correctly for the rectangle
        const open_y = @max(ohlc.open, ohlc.close);
        const close_y = @min(ohlc.open, ohlc.close);

        const open_pos = .{ xs[i] - half_width, open_y };
        const close_pos = .{ xs[i] + half_width, close_y };
        const low_pos = .{ xs[i], ohlc.low };
        const high_pos = .{ xs[i], ohlc.high };

        const color = if (ohlc.open > ohlc.close) bear_col else bull_col;
        // const color_u32 = zgui.colorConvertFloat4ToU32(color);

        draw_list.addCircle(.{ .p = .{ 2000000000, 6000000000000 }, .r = 30, .col = 0xff_00_00_ff, .thickness = 11 });

        // Draw wick (high-low line)
        draw_list.addLine(.{ .p1 = low_pos, .p2 = high_pos, .col = color, .thickness = 100.0 });

        // Draw body (open-close rectangle)
        draw_list.addRectFilled(.{ .pmin = close_pos, .pmax = open_pos, .col = color });
    }
}

pub fn plotOHLCListWindow(_: std.mem.Allocator, ohlc_list: []const OHLC) !void {
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
            .{},
        )) {
            defer plot.endPlot();

            // Setup axes - assuming time on X and price on Y
            plot.setupAxis(.x1, .{ .flags = .{} });
            plot.setupAxis(.y1, .{ .label = "$", .flags = .{ .auto_fit = true } });

            const draw_list = plot.getPlotDrawList();
            std.debug.print("draw_list: {any}\n", .{draw_list});
            // Define colors
            // const bull_col: u32 = zgui.colorConvertFloat4ToU32(.{ 0.0, 1.0, 0.0, 1.0 }); // Green
            // const bear_col: u32 = zgui.colorConvertFloat4ToU32(.{ 1.0, 0.0, 0.0, 1.0 }); // Red



            // TODO Needs PlotToPixels, also fix the candlestick plotting
            draw_list.addCircle(.{
                .p = .{ 100, 100 }, // Example position
                .r = 30,
                .col = 0xff_00_ff_ff, // Magenta, fully opaque
                .thickness = 5,
            });
            draw_list.addRectFilled(.{ .pmin = .{ 100, 100 }, .pmax = .{ 200, 200 }, .col = 0xff_00_00_ff });

            // Plot the candlesticks
            // try plotCandlestick("GOOGL", ohlc_list, allocator, true, 0.25, bull_col, bear_col);
        }
    }
}
