const std = @import("std");
pub const backend = @import("backend_glfw_wgpu.zig");

pub fn init(allocator: std.mem.Allocator) void {
    if (igGetCurrentContext() == null) {
        mem_allocator = allocator;
        mem_allocations = std.AutoHashMap(usize, usize).init(allocator);
        mem_allocations.?.ensureTotalCapacity(32) catch @panic("ig: out of memory");
        igSetAllocatorFunctions(igMemAlloc, igMemFree);

        _ = igCreateContext(null);

        temp_buffer = std.ArrayList(u8).init(allocator);
        temp_buffer.?.resize(3 * 1024 + 1) catch unreachable;

        // if (te_enabled) {
        //     te.init();
        // }
    }
}

fn igMemAlloc(size: usize, _: ?*anyopaque) callconv(.C) ?*anyopaque {
    mem_mutex.lock();
    defer mem_mutex.unlock();

    const mem = mem_allocator.?.alignedAlloc(
        u8,
        mem_alignment,
        size,
    ) catch @panic("ig: out of memory");

    mem_allocations.?.put(@intFromPtr(mem.ptr), size) catch @panic("ig: out of memory");

    return mem.ptr;
}

fn igMemFree(maybe_ptr: ?*anyopaque, _: ?*anyopaque) callconv(.C) void {
    if (maybe_ptr) |ptr| {
        mem_mutex.lock();
        defer mem_mutex.unlock();

        if (mem_allocations != null) {
            if (mem_allocations.?.fetchRemove(@intFromPtr(ptr))) |kv| {
                const size = kv.value;
                const mem = @as([*]align(mem_alignment) u8, @ptrCast(@alignCast(ptr)))[0..size];
                mem_allocator.?.free(mem);
            }
        }
    }
}

var mem_allocator: ?std.mem.Allocator = null;
var mem_allocations: ?std.AutoHashMap(usize, usize) = null;
var mem_mutex: std.Thread.Mutex = .{};
const mem_alignment = 16;

extern fn igSetAllocatorFunctions(
    alloc_func: ?*const fn (usize, ?*anyopaque) callconv(.C) ?*anyopaque,
    free_func: ?*const fn (?*anyopaque, ?*anyopaque) callconv(.C) void,
) void;

extern fn igCreateContext(shared_font_atlas: ?*const anyopaque) Context;
extern fn igDestroyContext(ctx: ?Context) void;
extern fn igGetCurrentContext() ?Context;

// Forward declarations for core opaque types
pub const Context = *opaque {};
pub const Font = *opaque {};

// Core Structs and Enums

pub const ImVec2 = extern struct {
    x: f32,
    y: f32,
};

pub const DrawData = *extern struct {
    valid: bool,
    cmd_lists_count: c_int,
    total_idx_count: c_int,
    total_vtx_count: c_int,
    cmd_lists: Vector(DrawList),
    display_pos: [2]f32,
    display_size: [2]f32,
    framebuffer_scale: [2]f32,
};

fn Vector(comptime T: type) type {
    return extern struct {
        len: c_int,
        capacity: c_int,
        items: [*]T,
    };
}

pub const IO = extern struct {
    display_size: [2]f32,
    display_framebuffer_scale: [2]f32,
    delta_time: f32,
    mouse_pos: [2]f32,
    mouse_delta: [2]f32,
    mouse_down: [5]bool,
};
pub const DrawVert = extern struct {
    pos: [2]f32,
    uv: [2]f32,
    color: u32,
};

pub const DrawIdx = u32;
pub const TextureIdent = *anyopaque;
pub const DrawCallback = *const fn (*const anyopaque, *const DrawCmd) callconv(.C) void;

pub const DrawCmd = extern struct {
    clip_rect: [4]f32,
    texture_id: TextureIdent,
    vtx_offset: c_uint,
    idx_offset: c_uint,
    elem_count: c_uint,
    user_callback: ?DrawCallback,
    user_callback_data: ?*anyopaque,
    user_callback_data_size: c_int, // Unused? Check ImGui source
    user_callback_data_offset: c_int, // Unused? Check ImGui source
};

pub const DrawFlags = packed struct(c_int) {
    closed: bool = false,
    _padding0: u3 = 0,
    round_corners_top_left: bool = false,
    round_corners_top_right: bool = false,
    round_corners_bottom_left: bool = false,
    round_corners_bottom_right: bool = false,
    round_corners_none: bool = false, // Was top_left & top_right & bot_left & bot_right
    _padding1: u23 = 0,

    pub const round_corners_top = DrawFlags{
        .round_corners_top_left = true,
        .round_corners_top_right = true,
    };

    pub const round_corners_bottom = DrawFlags{
        .round_corners_bottom_left = true,
        .round_corners_bottom_right = true,
    };

    pub const round_corners_left = DrawFlags{
        .round_corners_top_left = true,
        .round_corners_bottom_left = true,
    };

    pub const round_corners_right = DrawFlags{
        .round_corners_top_right = true,
        .round_corners_bottom_right = true,
    };

    pub const round_corners_all = DrawFlags{
        .round_corners_top_left = true,
        .round_corners_top_right = true,
        .round_corners_bottom_left = true,
        .round_corners_bottom_right = true,
    };
};

pub const WindowFlags = packed struct(c_int) {
    no_title_bar: bool = false,
    no_resize: bool = false,
    no_move: bool = false,
    no_scrollbar: bool = false,
    no_scroll_with_mouse: bool = false,
    no_collapse: bool = false,
    always_auto_resize: bool = false,
    no_background: bool = false,
    no_saved_settings: bool = false,
    no_mouse_inputs: bool = false,
    menu_bar: bool = false,
    horizontal_scrollbar: bool = false,
    no_focus_on_appearing: bool = false,
    no_bring_to_front_on_focus: bool = false,
    always_vertical_scrollbar: bool = false,
    always_horizontal_scrollbar: bool = false,
    no_nav_inputs: bool = false,
    no_nav_focus: bool = false,
    unsaved_document: bool = false,
    no_docking: bool = false,
    _padding: u12 = 0,

    pub const no_nav = WindowFlags{ .no_nav_inputs = true, .no_nav_focus = true };
    pub const no_decoration = WindowFlags{
        .no_title_bar = true,
        .no_resize = true,
        .no_scrollbar = true,
        .no_collapse = true,
    };
    pub const no_inputs = WindowFlags{
        .no_mouse_inputs = true,
        .no_nav_inputs = true,
        .no_nav_focus = true,
    };
};

pub const ConfigFlags = packed struct(c_int) {
    nav_enable_keyboard: bool = false,
    nav_enable_gamepad: bool = false,
    nav_enable_set_mouse_pos: bool = false,
    nav_no_capture_keyboard: bool = false,
    no_mouse: bool = false,
    no_mouse_cursor_change: bool = false,
    no_keyboard: bool = false,
    dock_enable: bool = false,
    _pading0: u2 = 0,
    viewport_enable: bool = false,
    _pading1: u3 = 0,
    dpi_enable_scale_viewport: bool = false,
    dpi_enable_scale_fonts: bool = false,
    user_storage: u4 = 0,
    is_srgb: bool = false,
    is_touch_screen: bool = false,
    _padding: u10 = 0,
};
pub const FontBuilderFlags = packed struct(c_uint) {
    no_hinting: bool = false,
    no_auto_hint: bool = false,
    force_auto_hint: bool = false,
    light_hinting: bool = false,
    mono_hinting: bool = false,
    bold: bool = false,
    oblique: bool = false,
    monochrome: bool = false,
    load_color: bool = false,
    bitmap: bool = false,
    _padding: u22 = 0,
};
pub const FontConfig = extern struct {
    font_data: ?*anyopaque,
    font_data_size: c_int,
    font_data_owned_by_atlas: bool,
    merge_mode: bool,
    pixel_snap_h: bool,
    font_no: c_int,
    oversample_h: c_int,
    oversample_v: c_int,
    size_pixels: f32,
    glyph_extra_spacing: [2]f32,
    glyph_offset: [2]f32,
    glyph_ranges: [*c]u16,
    glyph_min_advance_x: f32,
    glyph_max_advance_x: f32,
    font_builder_flags: FontBuilderFlags,
    rasterizer_multiply: f32,
    rasterizer_density: f32,
    ellipsis_char: Wchar,
    name: [40]u8,
    dst_font: *Font,

    pub fn init() FontConfig {
        return igFontConfig_Init();
    }
    extern fn igFontConfig_Init() FontConfig;
};

pub const Wchar = u16;
pub const Key = enum(c_int) {
    none = 0,
    tab = 512,
    left_arrow,
    right_arrow,
    up_arrow,
    down_arrow,
    page_up,
    page_down,
    home,
    end,
    insert,
    delete,
    back_space,
    space,
    enter,
    escape,
    left_ctrl,
    left_shift,
    left_alt,
    left_super,
    right_ctrl,
    right_shift,
    right_alt,
    right_super,
    menu,
    zero,
    one,
    two,
    three,
    four,
    five,
    six,
    seven,
    eight,
    nine,
    a,
    b,
    c,
    d,
    e,
    f,
    g,
    h,
    i,
    j,
    k,
    l,
    m,
    n,
    o,
    p,
    q,
    r,
    s,
    t,
    u,
    v,
    w,
    x,
    y,
    z,
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,
    f13,
    f14,
    f15,
    f16,
    f17,
    f18,
    f19,
    f20,
    f21,
    f22,
    f23,
    f24,
    apostrophe,
    comma,
    minus,
    period,
    slash,
    semicolon,
    equal,
    left_bracket,
    back_slash,
    right_bracket,
    grave_accent,
    caps_lock,
    scroll_lock,
    num_lock,
    print_screen,
    pause,
    keypad_0,
    keypad_1,
    keypad_2,
    keypad_3,
    keypad_4,
    keypad_5,
    keypad_6,
    keypad_7,
    keypad_8,
    keypad_9,
    keypad_decimal,
    keypad_divide,
    keypad_multiply,
    keypad_subtract,
    keypad_add,
    keypad_enter,
    keypad_equal,

    app_back,
    app_forward,

    gamepad_start,
    gamepad_back,
    gamepad_faceleft,
    gamepad_faceright,
    gamepad_faceup,
    gamepad_facedown,
    gamepad_dpadleft,
    gamepad_dpadright,
    gamepad_dpadup,
    gamepad_dpaddown,
    gamepad_l1,
    gamepad_r1,
    gamepad_l2,
    gamepad_r2,
    gamepad_l3,
    gamepad_r3,
    gamepad_lstickleft,
    gamepad_lstickright,
    gamepad_lstickup,
    gamepad_lstickdown,
    gamepad_rstickleft,
    gamepad_rstickright,
    gamepad_rstickup,
    gamepad_rstickdown,

    mouse_left,
    mouse_right,
    mouse_middle,
    mouse_x1,
    mouse_x2,

    mouse_wheel_x,
    mouse_wheel_y,

    mod_ctrl = 1 << 12,
    mod_shift = 1 << 13,
    mod_alt = 1 << 14,
    mod_super = 1 << 15,
    mod_mask_ = 0xf000,
};

pub const MouseButton = enum(u32) {
    left = 0,
    right = 1,
    middle = 2,
};

pub const Direction = enum(c_int) {
    none = -1,
    left = 0,
    right = 1,
    up = 2,
    down = 3,
};

pub const HoveredFlags = packed struct(c_int) {
    child_windows: bool = false,
    root_window: bool = false,
    any_window: bool = false,
    no_popup_hierarchy: bool = false,
    dock_hierarchy: bool = false,
    allow_when_blocked_by_popup: bool = false,
    _reserved1: bool = false,
    allow_when_blocked_by_active_item: bool = false,
    allow_when_overlapped_by_item: bool = false,
    allow_when_overlapped_by_window: bool = false,
    allow_when_disabled: bool = false,
    no_nav_override: bool = false,
    for_tooltip: bool = false,
    stationary: bool = false,
    delay_none: bool = false,
    delay_normal: bool = false,
    delay_short: bool = false,
    no_shared_delay: bool = false,
    _padding: u14 = 0,

    pub const rect_only = HoveredFlags{
        .allow_when_blocked_by_popup = true,
        .allow_when_blocked_by_active_item = true,
        .allow_when_overlapped_by_item = true,
        .allow_when_overlapped_by_window = true,
    };
    pub const root_and_child_windows = HoveredFlags{ .root_window = true, .child_windows = true };
};

const Begin = struct {
    popen: ?*bool = null,
    flags: WindowFlags = .{},
};

pub const Condition = enum(c_int) {
    none = 0,
    always = 1,
    once = 2,
    first_use_ever = 4,
    appearing = 8,
};

const SetNextWindowSize = struct {
    w: f32,
    h: f32,
    cond: Condition = .none,
};
pub fn setNextWindowSize(args: SetNextWindowSize) void {
    igSetNextWindowSize(args.w, args.h, args.cond);
}
extern fn igSetNextWindowSize(w: f32, h: f32, cond: Condition) void;

pub fn getWindowSize() [2]f32 {
    var size: [2]f32 = undefined;
    igGetWindowSize(&size);
    return size;
}
extern fn igGetWindowSize(size: *[2]f32) void;

// --- Main ---
pub const newFrame = igNewFrame;
extern fn igNewFrame() void;

pub const endFrame = igEndFrame;
extern fn igEndFrame() void;

pub const render = igRender;
extern fn igRender() void;

pub const getDrawData = igGetDrawData;
extern fn igGetDrawData() DrawData;

// --- Demo, Debug, Information ---
/// `pub fn showDemoWindow(popen: ?*bool) void`
pub const showDemoWindow = igShowDemoWindow;
extern fn igShowDemoWindow(popen: ?*bool) void;

pub const showMetricsWindow = igShowMetricsWindow;
extern fn igShowMetricsWindow(popen: ?*bool) void;

// --- Window API ---
/// Push window to the stack and start appending to it.
/// Returns false if window is collapsed, so you can early out in your code.
/// Always call a matching end() for each begin() call, regardless of its return value!
/// [Important] Namen needs to be unique or the windows will interfere with each other!
pub fn begin(name: [:0]const u8, args: Begin) bool {
    return igBegin(name, args.popen, args.flags);
}
extern fn igBegin(name: [*:0]const u8, popen: ?*bool, flags: WindowFlags) bool;

/// Pop window from the stack.
pub const end = igEnd;
extern fn igEnd() void;

const Button = struct {
    w: f32 = 0.0,
    h: f32 = 0.0,
};
/// Button widget. Returns true when clicked.
pub fn button(label: [:0]const u8, args: Button) bool {
    return igButton(label, args.w, args.h);
}
extern fn igButton(label: [*:0]const u8, w: f32, h: f32) bool;

// --- Draw List API ---

pub const getWindowDrawList = igGetWindowDrawList;
pub const getBackgroundDrawList = igGetBackgroundDrawList;
pub const getForegroundDrawList = igGetForegroundDrawList;

extern fn igGetWindowDrawList() DrawList;
extern fn igGetBackgroundDrawList() DrawList;
extern fn igGetForegroundDrawList() DrawList;
extern fn igCreateDrawList() DrawList;
extern fn igDestroyDrawList(draw_list: DrawList) void;
/// Draw List: A single draw command list. Generally obtained via `igGetWindowDrawList()`, `igGetForegroundDrawList()`, `igGetBackgroundDrawList()`.
/// Important: Methods are only valid during the frame they were retrieved.
// pub const DrawList = extern struct {
// CmdBuffer: ImVector_ImDrawCmd,
// IdxBuffer: ImVector_ImDrawIdx,
// VtxBuffer: ImVector_ImDrawVert,
// Flags: ImDrawListFlags,
// _VtxCurrentIdx: c_uint,
// ImDrawListSharedData* _Data;
// ImDrawVert* _VtxWritePtr;
// ImDrawIdx* _IdxWritePtr;
// ImVector_ImVec2 _Path;
// ImDrawCmdHeader _CmdHeader;
// ImDrawListSplitter _Splitter;
// ImVector_ImVec4 _ClipRectStack;
// ImVector_ImTextureID _TextureIdStack;
// ImVector_ImU8 _CallbacksDataBuf;
// float _FringeScale;
// const char* _OwnerName;
// };

pub const DrawList = *opaque {
    // pub const addLine = ImDrawList_AddLine;
    // extern fn ImDrawList_AddLine(self: DrawList, p1: [2]f32, p2: [2]f32, col: u32, thickness: f32) void;

    pub fn addLine(
        draw_list: DrawList,
        args: struct {
            p1: ImVec2,
            p2: ImVec2,
            col: u32,
            // thickness: f32,
        },
    ) void {
        ImDrawList_AddLine(draw_list, &args.p1, &args.p2, args.col);
    }
    extern fn ImDrawList_AddLine(
        draw_list: DrawList,
        p1: *const ImVec2,
        p2: *const ImVec2,
        col: u32,
        // thickness: f32,
    ) void;

    pub fn addCircleFilled(draw_list: DrawList, args: struct {
        center: ImVec2,
        radius: f32,
        col: u32,
        num_segments: i32,
    }) void {
        ImDrawList_AddCircleFilled(draw_list, &args.center, args.radius, args.col, args.num_segments);
    }
    extern fn ImDrawList_AddCircleFilled(
        draw_list: DrawList,
        center: *const ImVec2,
        radius: f32,
        col: u32,
        num_segments: i32,
    ) void;
};

// --- Input/Output (IO) ---

/// Access IO structure (mouse/keyboard/gamepad inputs, time, various configuration options/flags)
pub const io = struct {
    pub const getIO = igGetIO_Nil;
    extern fn igGetIO_Nil() *IO;
    // --- Configuration ---
    pub const setConfigFlags = igIoSetConfigFlags;
    extern fn igIoSetConfigFlags(flags: ConfigFlags) void;

    /// Set `IniFilename` to NULL to load/save .ini file in memory. Set to "" to disable .ini saving.
    pub fn setIniFilename(filename: ?[*:0]const u8) void {
        igIoSetIniFilename(filename);
    }
    extern fn igIoSetIniFilename(filename: ?[*:0]const u8) void;

    /// Moving window only works if title bar is visible. Disable to move window clicking anywhere.
    pub const setConfigWindowsMoveFromTitleBarOnly = igIoSetConfigWindowsMoveFromTitleBarOnly;
    extern fn igIoSetConfigWindowsMoveFromTitleBarOnly(enabled: bool) void;

    // --- Display ---
    /// Set display size, in pixels. For clamping windows positions.
    pub fn setDisplaySize(width: f32, height: f32) void {
        io.getIO().display_size = [2]f32{ width, height };
    }

    pub fn getDisplaySize() [2]f32 {
        var size: [2]f32 = undefined;
        igIoGetDisplaySize(&size);
        return size;
    }
    extern fn igIoGetDisplaySize(size: *[2]f32) void;

    /// Set display framebuffer scale. For retina displays. Generally (1, 1) or (2, 2).
    pub fn setDisplayFramebufferScale(sx: f32, sy: f32) void {
        io.getIO().display_framebuffer_scale = [2]f32{ sx, sy };
    }

    // --- Timing ---
    /// Set time delta in seconds.
    pub const setDeltaTime = igIoSetDeltaTime;
    extern fn igIoSetDeltaTime(delta_time: f32) void;

    /// Get frame rate estimation.
    pub const getFramerate = igIoFramerate;
    extern fn igIoFramerate() f32;

    // --- Input Query ---
    /// Is Dear ImGui using the mouse? (index = 0: Any mouse button is held. index = 1..4: Specific mouse button is held.)
    pub const getWantCaptureMouse = igIoGetWantCaptureMouse;
    extern fn igIoGetWantCaptureMouse() bool;

    /// Is Dear ImGui using the keyboard?
    pub const getWantCaptureKeyboard = igIoGetWantCaptureKeyboard;
    extern fn igIoGetWantCaptureKeyboard() bool;

    /// Mobile/console: Activate virtual keyboard. Gamepad/keyboard: Focus window + activate text input node. When true, do not assert keyboard data, instead call AddInputCharacter().
    pub const getWantTextInput = igIoGetWantTextInput;
    extern fn igIoGetWantTextInput() bool;

    // --- Input Events ---

    /// Queue activate/inactive focus event (sent from backend).
    pub const addFocusEvent = igIoAddFocusEvent;
    extern fn igIoAddFocusEvent(focused: bool) void;

    /// Queue mouse position update (sent from backend).
    pub const addMousePositionEvent = igIoAddMousePositionEvent;
    extern fn igIoAddMousePositionEvent(x: f32, y: f32) void;

    /// Queue mouse button change (sent from backend).
    pub const addMouseButtonEvent = igIoAddMouseButtonEvent;
    extern fn igIoAddMouseButtonEvent(button: MouseButton, down: bool) void;

    /// Queue mouse wheel delta (sent from backend). `y > 0` is scroll up. `x` is horizontal scroll.
    pub const addMouseWheelEvent = igIoAddMouseWheelEvent;
    extern fn igIoAddMouseWheelEvent(x: f32, y: f32) void;

    /// Queue key event (sent from backend). Use Key values. If `scan_code` is unknown, pass 0. If `key_code` is unknown, pass `scan_code`.
    pub const addKeyEvent = igIoAddKeyEvent;
    extern fn igIoAddKeyEvent(key: Key, down: bool) void;

    /// Queue key event using native backend data (sent from backend). This is generally preferable to AddKeyEvent(). Native backend data is stored in ImGuiKeyData::NativeData.
    pub fn setKeyEventNativeData(key: Key, keycode: i32, scancode: i32) void {
        // TODO: Check C types for keycode/scancode
        igIoSetKeyEventNativeData(key, keycode, scancode);
    }
    extern fn igIoSetKeyEventNativeData(key: Key, keycode: c_int, scancode: c_int) void; // TODO: What is `extra_flags` param in C API?

    /// Queue UTF-8 encoded text data (sent from backend).
    pub const addInputCharactersUTF8 = igIoAddInputCharactersUTF8;
    extern fn igIoAddInputCharactersUTF8(utf8_chars: ?[*:0]const u8) void;

    /// Queue single character data (sent from backend). `character` is the Unicode code point.
    pub fn addCharacterEvent(char: i32) void {
        // TODO: check C type for char, likely c_uint
        igIoAddCharacterEvent(char);
    }
    extern fn igIoAddCharacterEvent(char: c_uint) void; // TODO: check C type

    // --- Fonts ---

    /// Add font from file. Requires `filename` to be UTF-8. Returns `Font` on success, `null` on failure.
    pub fn addFontFromFile(filename: [:0]const u8, size_pixels: f32) Font {
        return igIoAddFontFromFile(filename, size_pixels);
    }
    extern fn igIoAddFontFromFile(filename: [*:0]const u8, size_pixels: f32) Font;

    /// Add font from file with custom configuration.
    pub fn addFontFromFileWithConfig(
        filename: [:0]const u8,
        size_pixels: f32,
        config: ?FontConfig,
        ranges: ?[*]const Wchar, // Null terminated array
    ) Font {
        return igIoAddFontFromFileWithConfig(filename, size_pixels, if (config) |c| &c else null, ranges);
    }
    extern fn igIoAddFontFromFileWithConfig(
        filename: [*:0]const u8,
        size_pixels: f32,
        config: ?*const FontConfig,
        ranges: ?[*]const Wchar,
    ) Font;

    /// Add font from memory buffer. Requires `fontdata` to be valid for the lifetime of the font atlas unless `FontConfig.font_data_owned_by_atlas` is true.
    pub fn addFontFromMemory(fontdata: []const u8, size_pixels: f32) Font {
        return igIoAddFontFromMemory(fontdata.ptr, @intCast(fontdata.len), size_pixels);
    }
    extern fn igIoAddFontFromMemory(font_data: *const anyopaque, font_size: c_int, size_pixels: f32) Font;

    /// Add font from memory buffer with custom configuration.
    pub fn addFontFromMemoryWithConfig(
        fontdata: []const u8,
        size_pixels: f32,
        config: ?FontConfig,
        ranges: ?[*]const Wchar, // Null terminated array
    ) Font {
        return igIoAddFontFromMemoryWithConfig(
            fontdata.ptr,
            @intCast(fontdata.len),
            size_pixels,
            if (config) |c| &c else null,
            ranges,
        );
    }
    extern fn igIoAddFontFromMemoryWithConfig(
        font_data: *const anyopaque,
        font_size: c_int,
        size_pixels: f32,
        config: ?*const FontConfig,
        ranges: ?[*]const Wchar,
    ) Font;

    /// Get font by index in the font atlas. Index 0 is the default font.
    pub fn getFont(index: u32) Font {
        return igIoGetFont(index);
    }
    extern fn igIoGetFont(index: c_uint) Font;

    /// Set the default font. Overwrites the default font built from proggy clean.
    pub const setDefaultFont = igIoSetDefaultFont;
    extern fn igIoSetDefaultFont(font: Font) void;

    /// Retrieves the font atlas texture data. Call this after building the font atlas (typically done automatically on the first frame).
    pub fn getFontsTextDataAsRgba32() struct {
        width: i32,
        height: i32,
        pixels: ?[*]const u32, // Pixel data RGBA8
    } {
        var width: c_int = undefined;
        var height: c_int = undefined;
        const ptr = igIoGetFontsTexDataAsRgba32(&width, &height);
        return .{
            .width = width,
            .height = height,
            .pixels = ptr,
        };
    }
    extern fn igIoGetFontsTexDataAsRgba32(width: *c_int, height: *c_int) [*c]u32; // TODO: check C type for pixels (const?)

    /// Set the texture identifier for the font atlas (used by the backend renderer).
    pub const setFontsTexId = igIoSetFontsTexId;
    extern fn igIoSetFontsTexId(id: TextureIdent) void;

    /// Get the texture identifier for the font atlas.
    pub const getFontsTexId = igIoGetFontsTexId;
    extern fn igIoGetFontsTexId() TextureIdent;
};

// --- Style ---
pub const Style = extern struct {
    alpha: f32,
    disabled_alpha: f32,
    window_padding: [2]f32,
    window_rounding: f32,
    window_border_size: f32,
    window_min_size: [2]f32,
    window_title_align: [2]f32,
    window_menu_button_position: Direction,
    child_rounding: f32,
    child_border_size: f32,
    popup_rounding: f32,
    popup_border_size: f32,
    frame_padding: [2]f32,
    frame_rounding: f32,
    frame_border_size: f32,
    item_spacing: [2]f32,
    item_inner_spacing: [2]f32,
    cell_padding: [2]f32,
    touch_extra_padding: [2]f32,
    indent_spacing: f32,
    columns_min_spacing: f32,
    scrollbar_size: f32,
    scrollbar_rounding: f32,
    grab_min_size: f32,
    grab_rounding: f32,
    log_slider_deadzone: f32,
    tab_rounding: f32,
    tab_border_size: f32,
    tab_min_width_for_close_button: f32,
    tab_bar_border_size: f32,
    tab_bar_overline_size: f32,
    table_angled_header_angle: f32,
    table_angled_headers_text_align: [2]f32,
    color_button_position: Direction,
    button_text_align: [2]f32,
    selectable_text_align: [2]f32,
    separator_text_border_size: f32,
    separator_text_align: [2]f32,
    separator_text_padding: [2]f32,
    display_window_padding: [2]f32,
    display_safe_area_padding: [2]f32,
    docking_separator_size: f32,
    mouse_cursor_scale: f32,
    anti_aliased_lines: bool,
    anti_aliased_lines_use_tex: bool,
    anti_aliased_fill: bool,
    curve_tessellation_tol: f32,
    circle_tessellation_max_error: f32,

    colors: [@typeInfo(StyleCol).@"enum".fields.len][4]f32,

    hover_stationary_delay: f32,
    hover_delay_short: f32,
    hover_delay_normal: f32,

    hover_flags_for_tooltip_mouse: HoveredFlags,
    hover_flags_for_tooltip_nav: HoveredFlags,

    /// `pub fn init() Style`
    pub const init = igStyle_Init;
    extern fn igStyle_Init() Style;

    /// `pub fn scaleAllSizes(style: *Style, scale_factor: f32) void`
    pub const scaleAllSizes = ImGuiStyle_ScaleAllSizes;
    extern fn ImGuiStyle_ScaleAllSizes(style: *Style, scale_factor: f32) void;

    /// `pub fn styleColorsDark(*Style)`
    pub const setColorsDark = igStyleColorsDark;

    /// `pub fn styleColorsLight(*Style)`
    pub const setColorsLight = igStyleColorsLight;

    /// `pub fn styleColorsClassic(*Style)`
    pub const setColorsClassic = igStyleColorsClassic;

    pub const StyleColorsBuiltin = enum {
        dark,
        light,
        classic,
    };
    pub fn setColorsBuiltin(style: *Style, variant: StyleColorsBuiltin) void {
        switch (variant) {
            .dark => igStyleColorsDark(style),
            .light => igStyleColorsLight(style),
            .classic => igStyleColorsClassic(style),
        }
    }

    pub fn getColor(style: Style, idx: StyleCol) [4]f32 {
        return style.colors[@intCast(@intFromEnum(idx))];
    }
    pub fn setColor(style: *Style, idx: StyleCol, color: [4]f32) void {
        style.colors[@intCast(@intFromEnum(idx))] = color;
    }
};
/// `pub fn getStyle() *Style`
pub const getStyle = igGetStyle;
extern fn igGetStyle() *Style;

/// `pub fn styleColorsDark(*Style)`
pub const styleColorsDark = igStyleColorsDark;
extern fn igStyleColorsDark(style: *Style) void;

/// `pub fn styleColorsLight(*Style)`
pub const styleColorsLight = igStyleColorsLight;
extern fn igStyleColorsLight(style: *Style) void;

/// `pub fn styleColorsClassic(*Style)`
pub const styleColorsClassic = igStyleColorsClassic;
extern fn igStyleColorsClassic(style: *Style) void;

pub const StyleCol = enum(c_int) {
    text,
    text_disabled,
    window_bg,
    child_bg,
    popup_bg,
    border,
    border_shadow,
    frame_bg,
    frame_bg_hovered,
    frame_bg_active,
    title_bg,
    title_bg_active,
    title_bg_collapsed,
    menu_bar_bg,
    scrollbar_bg,
    scrollbar_grab,
    scrollbar_grab_hovered,
    scrollbar_grab_active,
    check_mark,
    slider_grab,
    slider_grab_active,
    button,
    button_hovered,
    button_active,
    header,
    header_hovered,
    header_active,
    separator,
    separator_hovered,
    separator_active,
    resize_grip,
    resize_grip_hovered,
    resize_grip_active,
    tab_hovered,
    tab,
    tab_selected,
    tab_selected_overline,
    tab_dimmed,
    tab_dimmed_selected,
    tab_dimmed_selected_overline,
    docking_preview,
    docking_empty_bg,
    plot_lines,
    plot_lines_hovered,
    plot_histogram,
    plot_histogram_hovered,
    table_header_bg,
    table_border_strong,
    table_border_light,
    table_row_bg,
    table_row_bg_alt,
    text_link,
    text_selected_bg,
    drag_drop_target,
    nav_highlight,
    nav_windowing_highlight,
    nav_windowing_dim_bg,
    modal_window_dim_bg,
};

pub fn pushStyleColor4f(args: struct {
    idx: StyleCol,
    c: [4]f32,
}) void {
    igPushStyleColor4f(args.idx, &args.c);
}
extern fn igPushStyleColor4f(idx: StyleCol, col: *const [4]f32) void;

pub fn pushStyleColor1u(args: struct {
    idx: StyleCol,
    c: u32,
}) void {
    igPushStyleColor1u(args.idx, args.c);
}
extern fn igPushStyleColor1u(idx: StyleCol, col: c_uint) void;

pub fn popStyleColor(args: struct {
    count: i32 = 1,
}) void {
    igPopStyleColor(args.count);
}
extern fn igPopStyleColor(count: c_int) void;

/// `fn pushTextWrapPos(wrap_pos_x: f32) void`
pub const pushTextWrapPos = igPushTextWrapPos;
extern fn igPushTextWrapPos(wrap_pos_x: f32) void;

/// `fn popTextWrapPos() void`
pub const popTextWrapPos = igPopTextWrapPos;
extern fn igPopTextWrapPos() void;

pub const StyleVar = enum(c_int) {
    alpha, // 1f
    disabled_alpha, // 1f
    window_padding, // 2f
    window_rounding, // 1f
    window_border_size, // 1f
    window_min_size, // 2f
    window_title_align, // 2f
    child_rounding, // 1f
    child_border_size, // 1f
    popup_rounding, // 1f
    popup_border_size, // 1f
    frame_padding, // 2f
    frame_rounding, // 1f
    frame_border_size, // 1f
    item_spacing, // 2f
    item_inner_spacing, // 2f
    indent_spacing, // 1f
    cell_padding, // 2f
    scrollbar_size, // 1f
    scrollbar_rounding, // 1f
    grab_min_size, // 1f
    grab_rounding, // 1f
    tab_rounding, // 1f
    tab_border_size, // 1f
    tab_bar_border_size, // 1f
    tab_bar_overline_size, // 1f
    table_angled_headers_angle, // 1f
    table_angled_headers_text_align, // 2f
    button_text_align, // 2f
    selectable_text_align, // 2f
    separator_text_border_size, // 1f
    separator_text_align, // 2f
    separator_text_padding, // 2f
    docking_separator_size, // 1f
};

pub fn pushStyleVar1f(args: struct {
    idx: StyleVar,
    v: f32,
}) void {
    igPushStyleVar1f(args.idx, args.v);
}
extern fn igPushStyleVar1f(idx: StyleVar, v: f32) void;

pub fn pushStyleVar2f(args: struct {
    idx: StyleVar,
    v: [2]f32,
}) void {
    igPushStyleVar2f(args.idx, &args.v);
}
extern fn igPushStyleVar2f(idx: StyleVar, v: *const [2]f32) void;

pub fn popStyleVar(args: struct {
    count: i32 = 1,
}) void {
    igPopStyleVar(args.count);
}
extern fn igPopStyleVar(count: c_int) void;

pub fn colorConvertFloat4ToU32(in: [4]f32) u32 {
    return igColorConvertFloat4ToU32(&in);
}
extern fn igColorConvertFloat4ToU32(in: *const [4]f32) u32;



// --- Utility ---

/// Simple wrapper around std.fmt.bufPrint using an internal temporary buffer.
/// WARNING: Not thread-safe. The returned slice is only valid until the next call to format.
/// Requires `temp_buffer` to be initialized.
var temp_buffer: ?std.ArrayList(u8) = null;
pub fn format(comptime fmt_str: []const u8, args: anytype) []const u8 {
    // Ensure temp_buffer is initialized before use
    const buf = temp_buffer orelse {
        std.log.err("ig.format called before ig.init or with uninitialized temp_buffer", .{});
        return ""; // Or handle error appropriately
    };

    // Calculate required size
    const len = std.fmt.count(fmt_str, args) catch |err| {
        std.log.err("ig.format: std.fmt.count failed: {s}", .{@errorName(err)});
        return ""; // Or handle error
    };

    // Resize buffer if necessary
    if (len > buf.items.len) {
        buf.resize(len + 64) catch |err| { // Add some slack
            std.log.err("ig.format: Failed to resize temp_buffer: {s}", .{@errorName(err)});
            return ""; // Or handle error
        };
    }

    // Format into the buffer
    return std.fmt.bufPrint(buf.items, fmt_str, args) catch |err| {
        std.log.err("ig.format: std.fmt.bufPrint failed: {s}", .{@errorName(err)});
        return ""; // Or handle error
    };
}
