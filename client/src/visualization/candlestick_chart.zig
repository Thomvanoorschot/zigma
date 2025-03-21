const std = @import("std");
const skgui = @import("skgui");
const actor_manager = @import("../../actor/core/manager.zig");
const candlestick_collector = @import("../../actor/impl/actor/candlestick_collector.zig");
const candlestick = @import("../../market/candlestick.zig");
const datetime = @import("../../core/utils/datetime.zig");

const imp = skgui.implot;
const ig = skgui.imgui;
const ActorManager = actor_manager.ActorManager;
const CandlestickCollectorActor = candlestick_collector.CandlestickCollectorActor;
const Candlestick = candlestick.Candlestick;
pub const CandlestickData = struct {
    time: []const f64,
    open: []const f64,
    high: []const f64,
    low: []const f64,
    close: []const f64,
};

pub const CandlestickStyle = struct {
    bull_color: ig.ImVec4 = .{ .x = 0.0, .y = 1.0, .z = 0.0, .w = 1.0 }, // green
    bear_color: ig.ImVec4 = .{ .x = 1.0, .y = 0.0, .z = 0.0, .w = 1.0 }, // red
    width_percent: f32 = 0.35,
    show_tooltip: bool = true,
};

pub fn plotCandlestickWindow(manager: *ActorManager) void {
    // Set initial window size and position
    if (!ig.igIsWindowDocked()) {
        ig.igSetNextWindowSize(.{ .x = 800, .y = 600 }, ig.ImGuiCond_FirstUseEver);
    }

    if (ig.igBegin("Candlestick Chart", null, ig.ImGuiWindowFlags_None)) {
        defer ig.igEnd();

        if (imp.ImPlot_BeginPlot("OHLC Data", .{ .x = -1, .y = -1 }, imp.ImPlotFlags_NoBoxSelect)) {
            defer imp.ImPlot_EndPlot();

            if (manager.get_actor("collector", CandlestickCollectorActor)) |collector| {
                const candlesticks = collector.context.getCandlesticks();
                if (candlesticks.len > 0) {
                    // Setup axes with AutoFit flags
                    imp.ImPlot_SetupAxis(imp.ImAxis_X1, "Time", imp.ImPlotAxisFlags_AutoFit);
                    imp.ImPlot_SetupAxis(imp.ImAxis_Y1, "Price", imp.ImPlotAxisFlags_AutoFit);
                    imp.ImPlot_SetupAxisScale_PlotScale(imp.ImAxis_X1, imp.ImPlotScale_Time);

                    plotCandlestick(
                        "Candlesticks",
                        candlesticks,
                        .{}, // Use default style
                    );
                }
            }
        }
    }
}

fn plotCandlestick(
    label_id: [*:0]const u8,
    candlesticks: []const Candlestick,
    style: CandlestickStyle,
) void {
    const count = candlesticks.len;
    const draw_list = imp.ImPlot_GetPlotDrawList();

    // Calculate width based on average spacing between points
    var avg_spacing: f64 = 0;
    if (count > 1) {
        for (1..count) |i| {
            avg_spacing += @as(f64, @floatFromInt(candlesticks[i].time - candlesticks[i - 1].time));
        }
        avg_spacing /= @as(f64, @floatFromInt(count - 1));
    }
    const half_width = if (count > 1)
        avg_spacing * style.width_percent * 0.5
    else
        style.width_percent;

    // Handle tooltip
    if (imp.ImPlot_IsPlotHovered() and style.show_tooltip) {
        var mouse_point: imp.ImPlotPoint = undefined;
        imp.ImPlot_GetPlotMousePos(&mouse_point, imp.ImAxis_X1, imp.ImAxis_Y1);

        // Binary search for closest point
        var left: usize = 0;
        var right: usize = count - 1;
        var closest_idx: usize = 0;
        var min_dist: f64 = std.math.inf(f64);

        while (left <= right) {
            const mid = left + (right - left) / 2;
            const time_f64 = @as(f64, @floatFromInt(candlesticks[mid].time));
            const dist = @abs(time_f64 - mouse_point.x);

            if (dist < min_dist) {
                min_dist = dist;
                closest_idx = mid;
            }

            if (time_f64 < mouse_point.x) {
                if (mid == right) break;
                left = mid + 1;
            } else if (time_f64 > mouse_point.x) {
                if (mid == 0) break;
                right = mid - 1;
            } else {
                break;
            }
        }

        if (min_dist < avg_spacing * 0.5) {
            const stick = candlesticks[closest_idx];
            const time_f64 = @as(f64, @floatFromInt(stick.time));

            var tool_l_pos: imp.ImVec2 = undefined;
            var tool_r_pos: imp.ImVec2 = undefined;
            imp.ImPlot_PlotToPixels_double(&tool_l_pos, time_f64 - half_width * 1.5, mouse_point.y, imp.ImAxis_X1, imp.ImAxis_Y1);
            imp.ImPlot_PlotToPixels_double(&tool_r_pos, time_f64 + half_width * 1.5, mouse_point.y, imp.ImAxis_X1, imp.ImAxis_Y1);

            var plot_pos: imp.ImVec2 = undefined;
            imp.ImPlot_GetPlotPos(&plot_pos);

            var plot_size: imp.ImVec2 = undefined;
            imp.ImPlot_GetPlotSize(&plot_size);

            const tool_l = tool_l_pos.x;
            const tool_r = tool_r_pos.x;
            const tool_t = plot_pos.y;
            const tool_b = tool_t + plot_size.y;

            imp.ImPlot_PushPlotClipRect(0);
            imp.ImDrawList_AddRectFilled(draw_list, .{ .x = tool_l, .y = tool_t }, .{ .x = tool_r, .y = tool_b }, ig.igGetColorU32_Vec4(.{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 0.25 }), 0, 0);
            imp.ImPlot_PopPlotClipRect();

            // Show tooltip with formatted time
            _ = ig.igBeginTooltip();
            if (datetime.formatTimestamp(stick.time)) |formatted_time| {
                ig.igText("Day:   %.*s", @as(c_int, @intCast(formatted_time.len)), formatted_time.ptr);
            } else |_| {
                ig.igText("Day:   <error>", .{});
            }
            ig.igText("Open:  $%.2f", stick.open);
            ig.igText("Close: $%.2f", stick.close);
            ig.igText("Low:   $%.2f", stick.low);
            ig.igText("High:  $%.2f", stick.high);
            ig.igEndTooltip();
        }
    }

    if (imp.ImPlot_BeginItem(label_id, imp.ImPlotFlags_None, imp.ImPlotCol_Line)) {
        defer imp.ImPlot_EndItem();

        // Set legend icon color
        const current_item = imp.ImPlot_GetCurrentItem();
        if (current_item) |item| {
            item.*.Color = ig.igGetColorU32_Vec4(.{ .x = 0.25, .y = 0.25, .z = 0.25, .w = 1.0 });
        }

        // Fit data if requested
        if (imp.ImPlot_FitThisFrame()) {
            for (candlesticks) |stick| {
                imp.ImPlot_FitPoint(.{ .x = @as(f64, @floatFromInt(stick.time)), .y = stick.low });
                imp.ImPlot_FitPoint(.{ .x = @as(f64, @floatFromInt(stick.time)), .y = stick.high });
            }
        }

        // Render candlesticks
        for (candlesticks) |stick| {
            const time_f64 = @as(f64, @floatFromInt(stick.time));
            var open_pos: imp.ImVec2 = undefined;
            var close_pos: imp.ImVec2 = undefined;
            var low_pos: imp.ImVec2 = undefined;
            var high_pos: imp.ImVec2 = undefined;

            imp.ImPlot_PlotToPixels_double(&open_pos, time_f64 - half_width, stick.open, imp.ImAxis_X1, imp.ImAxis_Y1);
            imp.ImPlot_PlotToPixels_double(&close_pos, time_f64 + half_width, stick.close, imp.ImAxis_X1, imp.ImAxis_Y1);
            imp.ImPlot_PlotToPixels_double(&low_pos, time_f64, stick.low, imp.ImAxis_X1, imp.ImAxis_Y1);
            imp.ImPlot_PlotToPixels_double(&high_pos, time_f64, stick.high, imp.ImAxis_X1, imp.ImAxis_Y1);

            const color = if (stick.open > stick.close)
                ig.igGetColorU32_Vec4(style.bear_color)
            else
                ig.igGetColorU32_Vec4(style.bull_color);

            imp.ImDrawList_AddLine(draw_list, .{ .x = low_pos.x, .y = low_pos.y }, .{ .x = high_pos.x, .y = high_pos.y }, color, 1);
            imp.ImDrawList_AddRectFilled(draw_list, .{ .x = open_pos.x, .y = open_pos.y }, .{ .x = close_pos.x, .y = close_pos.y }, color, 0, 0);
        }
    }
}
