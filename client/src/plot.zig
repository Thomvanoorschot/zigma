const gui = @import("gui.zig");
//--------------------------------------------------------------------------------------------------
pub fn init() void {
    if (ImPlot_GetCurrentContext() == null) {
        _ = ImPlot_CreateContext();
    }
}
pub fn deinit() void {
    if (ImPlot_GetCurrentContext() != null) {
        ImPlot_DestroyContext(null);
    }
}
const Context = *opaque {};

// --- Core Structs and Enums ---
pub const PlotPoint = extern struct {
    x: f64,
    y: f64,
};

// --- Context ---
extern fn ImPlot_GetCurrentContext() ?Context;
extern fn ImPlot_CreateContext() Context;
extern fn ImPlot_DestroyContext(ctx: ?Context) void;

// --- Demo Window ---
pub const showDemoWindow = ImPlot_ShowDemoWindow;
extern fn ImPlot_ShowDemoWindow(popen: ?*bool) void;

// --- Plot API ---
pub const Flags = packed struct(u32) {
    no_title: bool = false,
    no_legend: bool = false,
    no_mouse_text: bool = false,
    no_inputs: bool = false,
    no_menus: bool = false,
    no_box_select: bool = false,
    no_frame: bool = false,
    equal: bool = false,
    crosshairs: bool = false,
    _padding: u23 = 0,

    pub const canvas_only = Flags{
        .no_title = true,
        .no_legend = true,
        .no_menus = true,
        .no_box_select = true,
        .no_mouse_text = true,
    };
};

pub const BeginPlot = struct {
    w: f32 = -1.0,
    h: f32 = 0.0,
    flags: Flags = .{},
};
pub fn beginPlot(title_id: [:0]const u8, args: BeginPlot) bool {
    return ImPlot_BeginPlot(title_id, &gui.ImVec2{ .x = args.w, .y = args.h }, args.flags);
}
extern fn ImPlot_BeginPlot(title_id: [*:0]const u8, size: *const gui.ImVec2, flags: Flags) bool;

pub const endPlot = ImPlot_EndPlot;
extern fn ImPlot_EndPlot() void;

pub const ItemFlags = packed struct(u32) {
    no_legend: bool = false,
    no_fit: bool = false,
    _padding: u30 = 0,
};
pub const Col = enum(u32) {
    line,
    fill,
    marker_outline,
    marker_fill,
    error_bar,
    frame_bg,
    plot_bg,
    plot_border,
    legend_bg,
    legend_border,
    legend_text,
    title_text,
    inlay_text,
    axis_text,
    axis_grid,
    axis_tick,
    axis_bg,
    axis_bg_hovered,
    axis_bg_active,
    selection,
    crosshairs,
    count,
};
pub fn beginItem(label_id: [:0]const u8) bool {
    return ImPlot_BeginItem(label_id, .{}, .fill);
}
extern fn ImPlot_BeginItem(label_id: [*:0]const u8, flags: ItemFlags, recolor_from: Col) bool;

pub const endItem = ImPlot_EndItem;
extern fn ImPlot_EndItem() void;

// Plot lines
pub const LineFlags = packed struct(u32) {
    _reserved0: bool = false,
    _reserved1: bool = false,
    _reserved2: bool = false,
    _reserved3: bool = false,
    _reserved4: bool = false,
    _reserved5: bool = false,
    _reserved6: bool = false,
    _reserved7: bool = false,
    _reserved8: bool = false,
    _reserved9: bool = false,
    segments: bool = false,
    loop: bool = false,
    skip_nan: bool = false,
    no_clip: bool = false,
    shaded: bool = false,
    _padding: u17 = 0,
};
fn PlotLineGen(comptime T: type) type {
    return struct {
        xv: []const T,
        yv: []const T,
        flags: LineFlags = .{},
        offset: i32 = 0,
        stride: i32 = @sizeOf(T),
    };
}
pub fn plotLine(label_id: [:0]const u8, comptime T: type, args: PlotLineGen(T)) void {
    ImPlot_PlotLine_doublePtrdoublePtr(
        label_id,
        // gui.typeToDataTypeEnum(T),
        args.xv.ptr,
        args.yv.ptr,
        @as(i32, @intCast(args.xv.len)),
        args.flags,
        args.offset,
        args.stride,
    );
}
extern fn ImPlot_PlotLine_doublePtrdoublePtr(
    label_id: [*:0]const u8,
    // data_type: gui.DataType,
    xv: *const anyopaque,
    yv: *const anyopaque,
    count: i32,
    flags: LineFlags,
    offset: i32,
    stride: i32,
) void;

// Plot bars
pub const BarsFlags = packed struct(u32) {
    _reserved0: bool = false,
    _reserved1: bool = false,
    _reserved2: bool = false,
    _reserved3: bool = false,
    _reserved4: bool = false,
    _reserved5: bool = false,
    _reserved6: bool = false,
    _reserved7: bool = false,
    _reserved8: bool = false,
    _reserved9: bool = false,
    horizontal: bool = false,
    _padding: u21 = 0,
};
fn PlotBarsGen(comptime T: type) type {
    return struct {
        xv: []const T,
        yv: []const T,
        bar_size: f64 = 0.67,
        flags: BarsFlags = .{},
        offset: i32 = 0,
        stride: i32 = @sizeOf(T),
    };
}

pub fn plotBars(label_id: [:0]const u8, comptime T: type, args: PlotBarsGen(T)) void {
    ImPlot_PlotBars_doublePtrdoublePtr(
        label_id,
        // gui.typeToDataTypeEnum(T),
        args.xv.ptr,
        args.yv.ptr,
        @as(i32, @intCast(args.xv.len)),
        args.bar_size,
        args.flags,
        args.offset,
        args.stride,
    );
}
extern fn ImPlot_PlotBars_doublePtrdoublePtr(
    label_id: [*:0]const u8,
    xv: *const anyopaque,
    yv: *const anyopaque,
    count: i32,
    bar_size: f64,
    flags: BarsFlags,
    offset: i32,
    stride: i32,
) void;

// --- Setup API ---
pub const AxisFlags = packed struct(u32) {
    no_label: bool = false,
    no_grid_lines: bool = false,
    no_tick_marks: bool = false,
    no_tick_labels: bool = false,
    no_initial_fit: bool = false,
    no_menus: bool = false,
    no_side_switch: bool = false,
    no_highlight: bool = false,
    opposite: bool = false,
    foreground: bool = false,
    invert: bool = false,
    auto_fit: bool = false,
    range_fit: bool = false,
    pan_stretch: bool = false,
    lock_min: bool = false,
    lock_max: bool = false,
    _padding: u16 = 0,

    pub const lock = AxisFlags{
        .lock_min = true,
        .lock_max = true,
    };
    pub const no_decorations = AxisFlags{
        .no_label = true,
        .no_grid_lines = true,
        .no_tick_marks = true,
        .no_tick_labels = true,
    };
    pub const aux_default = AxisFlags{
        .no_grid_lines = true,
        .opposite = true,
    };
};
pub const Axis = enum(u32) { x1 = 0, x2, x3, y1, y2, y3 };
pub const SetupAxis = struct {
    label: ?[:0]const u8 = null,
    flags: AxisFlags = .{},
};
pub fn setupAxis(axis: Axis, args: SetupAxis) void {
    ImPlot_SetupAxis(axis, if (args.label) |l| l else null, args.flags);
}
extern fn ImPlot_SetupAxis(axis: Axis, label: ?[*:0]const u8, flags: AxisFlags) void;

pub const Scale = enum(u32) {
    linear = 0,
    time,
    log10,
    symlog,
};
pub const setupAxisScale = ImPlot_SetupAxisScale_PlotScale;
extern fn ImPlot_SetupAxisScale_PlotScale(axis: Axis, scale: Scale) void;

pub const setupAxisFormat = ImPlot_SetupAxisFormat_Str;
extern fn ImPlot_SetupAxisFormat_Str(axis: Axis, fmt: [*:0]const u8) void;

pub const setupAxisZoomConstraints = ImPlot_SetupAxisZoomConstraints;
extern fn ImPlot_SetupAxisZoomConstraints(axis: Axis, min: f64, max: f64) void;

pub const setupAxisLimitsConstraints = ImPlot_SetupAxisLimitsConstraints;
extern fn ImPlot_SetupAxisLimitsConstraints(axis: Axis, min: f64, max: f64) void;

pub const Condition = enum(u32) {
    none = @intFromEnum(gui.Condition.none),
    always = @intFromEnum(gui.Condition.always),
    once = @intFromEnum(gui.Condition.once),
};
const SetupAxisLimits = struct {
    min: f64,
    max: f64,
    cond: Condition = .once,
};
pub fn setupAxisLimits(axis: Axis, args: SetupAxisLimits) void {
    ImPlot_SetupAxisLimits(axis, args.min, args.max, args.cond);
}
extern fn ImPlot_SetupAxisLimits(axis: Axis, min: f64, max: f64, cond: Condition) void;

pub const PlotLocation = packed struct(u32) {
    north: bool = false,
    south: bool = false,
    west: bool = false,
    east: bool = false,
    _padding: u28 = 0,

    pub const north_west = PlotLocation{ .north = true, .west = true };
    pub const north_east = PlotLocation{ .north = true, .east = true };
    pub const south_west = PlotLocation{ .south = true, .west = true };
    pub const south_east = PlotLocation{ .south = true, .east = true };
};
pub const LegendFlags = packed struct(u32) {
    no_buttons: bool = false,
    no_highlight_item: bool = false,
    no_highlight_axis: bool = false,
    no_menus: bool = false,
    outside: bool = false,
    horizontal: bool = false,
    _padding: u26 = 0,
};
pub fn setupLegend(location: PlotLocation, flags: LegendFlags) void {
    ImPlot_SetupLegend(location, flags);
}
extern fn ImPlot_SetupLegend(location: PlotLocation, flags: LegendFlags) void;

pub const setupFinish = ImPlot_SetupFinish;
extern fn ImPlot_SetupFinish() void;

// --- DrawList API ---
pub const getPlotDrawList = ImPlot_GetPlotDrawList;
extern fn ImPlot_GetPlotDrawList() gui.DrawList;

// --- Style API ---
pub const Style = extern struct {
    line_weight: f32,
    // marker: Marker,
    marker_size: f32,
    marker_weight: f32,
    fill_alpha: f32,
    error_bar_size: f32,
    error_bar_weight: f32,
    digital_bit_height: f32,
    digital_bit_gap: f32,
    plot_border_size: f32,
    minor_alpha: f32,
    major_tick_len: [2]f32,
    minor_tick_len: [2]f32,
    major_tick_size: [2]f32,
    minor_tick_size: [2]f32,
    major_grid_size: [2]f32,
    minor_grid_size: [2]f32,
    plot_padding: [2]f32,
    label_padding: [2]f32,
    legend_padding: [2]f32,
    legend_inner_padding: [2]f32,
    legend_spacing: [2]f32,
    mouse_pos_padding: [2]f32,
    annotation_padding: [2]f32,
    fit_padding: [2]f32,
    plot_default_size: [2]f32,
    plot_min_size: [2]f32,

    colors: [@typeInfo(StyleCol).@"enum".fields.len][4]f32,
    colormap: Colormap,

    use_local_time: bool,
    use_iso_8601: bool,
    use_24h_clock: bool,

    /// `pub fn init() Style`
    pub const init = ImPlotStyle_Init;
    extern fn ImPlotStyle_Init() Style;

    pub fn getColor(style: Style, idx: StyleCol) [4]f32 {
        return style.colors[@intFromEnum(idx)];
    }
    pub fn setColor(style: *Style, idx: StyleCol, color: [4]f32) void {
        style.colors[@intFromEnum(idx)] = color;
    }
};

pub const Colormap = enum(u32) {
    deep,
    dark,
    pastel,
    paired,
    viridis,
    plasma,
    hot,
    cool,
    pink,
    jet,
    twilight,
    rd_bu,
    br_b_g,
    pi_y_g,
    spectral,
    greys,
};

pub const StyleCol = enum(u32) {
    line,
    fill,
    marker_outline,
    marker_fill,
    error_bar,
    frame_bg,
    plot_bg,
    plot_border,
    legend_bg,
    legend_border,
    legend_text,
    title_text,
    inlay_text,
    axis_text,
    axis_grid,
    axis_tick,
    axis_bg,
    axis_bg_hovered,
    axis_bg_active,
    selection,
    crosshairs,
};

pub const getStyle = ImPlot_GetStyle;
extern fn ImPlot_GetStyle() *Style;

pub fn setNextLineStyle(args: struct {
    col: [4]f32,
    weight: f32,
}) void {
    ImPlot_SetNextLineStyle(&args.col, args.weight);
}
extern fn ImPlot_SetNextLineStyle(col: *const [4]f32, weight: f32) void;

pub const StyleVar = enum(u32) {
    line_weight,
    marker,
    marker_size,
    marker_weight,
    fill_alpha,
    error_bar_size,
    error_bar_weight,
    digital_bit_height,
    digital_bit_gap,
    plot_border_size,
    minor_alpha,
    major_tick_len,
    minor_tick_len,
    major_tick_size,
    minor_tick_size,
    major_grid_size,
    minor_grid_size,
    plot_padding,
    label_padding,
    legend_padding,
    legend_inner_padding,
    legend_spacing,
    mouse_pos_padding,
    annotation_padding,
    fit_padding,
    plot_default_size,
    plot_min_size,
    count,
};
pub fn pushPlotStyleVar_Float(idx: StyleVar, val: f32) void {
    ImPlot_PushStyleVar_Float(idx, val);
}
extern fn ImPlot_PushStyleVar_Float(idx: StyleVar, val: f32) void;

pub fn popPlotStyleVar(count: i32) void {
    ImPlot_PopStyleVar(count);
}
extern fn ImPlot_PopStyleVar(count: i32) void;

pub fn pushPlotStyleColor_Vec4(idx: StyleCol, col: [4]f32) void {
    ImPlot_PushStyleColor_Vec4(idx, &col);
}
extern fn ImPlot_PushStyleColor_Vec4(idx: StyleCol, col: *const [4]f32) void;

pub fn popPlotStyleColor(count: i32) void {
    ImPlot_PopStyleColor(count);
}
extern fn ImPlot_PopStyleColor(count: i32) void;

// --- Utility ---
pub fn plotToPixels(out: *gui.ImVec2, x: f64, y: f64) void {
    ImPlot_PlotToPixels_double(out, x, y, .x1, .y1);
}
extern fn ImPlot_PlotToPixels_double(pOut: *gui.ImVec2, x: f64, y: f64, x_axis: Axis, y_axis: Axis) void;

pub fn plotToPixelsPoint(out: *gui.ImVec2, p: PlotPoint) void {
    ImPlot_PlotToPixels_PlotPoInt(out, p, .x1, .y1);
}
extern fn ImPlot_PlotToPixels_PlotPoInt(pOut: *gui.ImVec2, plt: PlotPoint, x_axis: Axis, y_axis: Axis) void;

pub const fitThisFrame = ImPlot_FitThisFrame;
extern fn ImPlot_FitThisFrame() bool;

pub const fitPoint = ImPlot_FitPoint;
extern fn ImPlot_FitPoint(p: PlotPoint) void;

extern fn ImPlot_GetPlotPos(pOut: *gui.ImVec2) void;

/// Returns the screen-space position of the plot area (minimum bounds).
pub fn getPlotPos() [2]f32 {
    var vec: [2]f32 = undefined;
    ImPlot_GetPlotPos(&vec);
    return vec;
}
pub fn getPlotSize() [2]f32 {
    var vec: [2]f32 = undefined;
    ImPlot_GetPlotSize(&vec);
    return vec;
}
extern fn ImPlot_GetPlotSize(pOut: *[2]f32) void;

pub const pushPlotClipRect = ImPlot_PushPlotClipRect;
extern fn ImPlot_PushPlotClipRect() void;

pub const popPlotClipRect = ImPlot_PopPlotClipRect;
extern fn ImPlot_PopPlotClipRect() void;
