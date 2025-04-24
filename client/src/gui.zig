const std = @import("std");
pub const backend = @import("backend_glfw_opengl.zig");

pub fn init(_: std.mem.Allocator) void {
    if (igGetCurrentContext() == null) {
        // mem_allocator = allocator;
        // mem_allocations = std.AutoHashMap(usize, usize).init(allocator);
        // mem_allocations.?.ensureTotalCapacity(32) catch @panic("ig: out of memory");
        // igSetAllocatorFunctions(igMemAlloc, igMemFree);

        // TODO It needs to do path traversal to /libs/imgui
        _ = igCreateContext(null);

        // temp_buffer = std.ArrayList(u8).init(allocator);
        // temp_buffer.?.resize(3 * 1024 + 1) catch unreachable;

        // if (te_enabled) {
        //     te.init();
        // }
    }
}

const Context = *opaque {};
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

extern fn igCreateContext(shared_font_atlas: ?*const anyopaque) Context;
extern fn igDestroyContext(ctx: ?Context) void;
extern fn igGetCurrentContext() ?Context;

pub const newFrame = igNewFrame;
extern fn igNewFrame() void;

pub const render = igRender;
extern fn igRender() void;

pub const getDrawData = igGetDrawData;
extern fn igGetDrawData() DrawData;

pub const showDemoWindow = igShowDemoWindow;
extern fn igShowDemoWindow(popen: ?*bool) void;

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

const Begin = struct {
    popen: ?*bool = null,
    flags: WindowFlags = .{},
};
pub fn begin(name: [:0]const u8, args: Begin) bool {
    return igBegin(name, args.popen, args.flags);
}
/// `pub fn end() void`
pub const end = igEnd;
extern fn igBegin(name: [*:0]const u8, popen: ?*bool, flags: WindowFlags) bool;
extern fn igEnd() void;

const Button = struct {
    w: f32 = 0.0,
    h: f32 = 0.0,
};
pub fn button(label: [:0]const u8, args: Button) bool {
    return igButton(label, args.w, args.h);
}
extern fn igButton(label: [*:0]const u8, w: f32, h: f32) bool;

pub const DrawList = *opaque {
    pub const getOwnerName = igDrawList_GetOwnerName;
    extern fn igDrawList_GetOwnerName(draw_list: DrawList) ?[*:0]const u8;

    pub fn reset(draw_list: DrawList) void {
        if (draw_list.getOwnerName()) |owner| {
            @panic(format("ig: illegally resetting DrawList of {s}", .{owner}));
        }
        igDrawList_ResetForNewFrame(draw_list);
    }
    extern fn igDrawList_ResetForNewFrame(draw_list: DrawList) void;

    pub fn clearMemory(draw_list: DrawList) void {
        if (draw_list.getOwnerName()) |owner| {
            @panic(format("ig: illegally clearing memory DrawList of {s}", .{owner}));
        }
        igDrawList_ClearFreeMemory(draw_list);
    }
    extern fn igDrawList_ClearFreeMemory(draw_list: DrawList) void;

    //----------------------------------------------------------------------------------------------
    pub fn getVertexBufferLength(draw_list: DrawList) i32 {
        return igDrawList_GetVertexBufferLength(draw_list);
    }
    extern fn igDrawList_GetVertexBufferLength(draw_list: DrawList) c_int;

    pub const getVertexBufferData = igDrawList_GetVertexBufferData;
    extern fn igDrawList_GetVertexBufferData(draw_list: DrawList) [*]DrawVert;
    pub fn getVertexBuffer(draw_list: DrawList) []DrawVert {
        const len: usize = @intCast(draw_list.getVertexBufferLength());
        return draw_list.getVertexBufferData()[0..len];
    }

    pub fn getIndexBufferLength(draw_list: DrawList) i32 {
        return igDrawList_GetIndexBufferLength(draw_list);
    }
    extern fn igDrawList_GetIndexBufferLength(draw_list: DrawList) c_int;

    pub const getIndexBufferData = igDrawList_GetIndexBufferData;
    extern fn igDrawList_GetIndexBufferData(draw_list: DrawList) [*]DrawIdx;
    pub fn getIndexBuffer(draw_list: DrawList) []DrawIdx {
        const len: usize = @intCast(draw_list.getIndexBufferLength());
        return draw_list.getIndexBufferData()[0..len];
    }

    pub fn getCurrentIndex(draw_list: DrawList) u32 {
        return igDrawList_GetCurrentIndex(draw_list);
    }
    extern fn igDrawList_GetCurrentIndex(draw_list: DrawList) c_uint;

    pub fn getCmdBufferLength(draw_list: DrawList) i32 {
        return igDrawList_GetCmdBufferLength(draw_list);
    }
    extern fn igDrawList_GetCmdBufferLength(draw_list: DrawList) c_int;

    pub const getCmdBufferData = igDrawList_GetCmdBufferData;
    extern fn igDrawList_GetCmdBufferData(draw_list: DrawList) [*]DrawCmd;
    pub fn getCmdBuffer(draw_list: DrawList) []DrawCmd {
        const len: usize = @intCast(draw_list.getCmdBufferLength());
        return draw_list.getCmdBufferData()[0..len];
    }

    pub const DrawListFlags = packed struct(c_int) {
        anti_aliased_lines: bool = false,
        anti_aliased_lines_use_tex: bool = false,
        anti_aliased_fill: bool = false,
        allow_vtx_offset: bool = false,

        _padding: u28 = 0,
    };

    pub const setDrawListFlags = igDrawList_SetFlags;
    extern fn igDrawList_SetFlags(draw_list: DrawList, flags: DrawListFlags) void;
    pub const getDrawListFlags = igDrawList_GetFlags;
    extern fn igDrawList_GetFlags(draw_list: DrawList) DrawListFlags;

    //----------------------------------------------------------------------------------------------
    const ClipRect = struct {
        pmin: [2]f32,
        pmax: [2]f32,
        intersect_with_current: bool = false,
    };
    pub fn pushClipRect(draw_list: DrawList, args: ClipRect) void {
        igDrawList_PushClipRect(
            draw_list,
            &args.pmin,
            &args.pmax,
            args.intersect_with_current,
        );
    }
    extern fn igDrawList_PushClipRect(
        draw_list: DrawList,
        clip_rect_min: *const [2]f32,
        clip_rect_max: *const [2]f32,
        intersect_with_current_clip_rect: bool,
    ) void;
    //----------------------------------------------------------------------------------------------
    pub const pushClipRectFullScreen = igDrawList_PushClipRectFullScreen;
    extern fn igDrawList_PushClipRectFullScreen(draw_list: DrawList) void;

    pub const popClipRect = igDrawList_PopClipRect;
    extern fn igDrawList_PopClipRect(draw_list: DrawList) void;
    //----------------------------------------------------------------------------------------------
    pub const pushTextureId = igDrawList_PushTextureId;
    extern fn igDrawList_PushTextureId(draw_list: DrawList, texture_id: TextureIdent) void;

    pub const popTextureId = igDrawList_PopTextureId;
    extern fn igDrawList_PopTextureId(draw_list: DrawList) void;
    //----------------------------------------------------------------------------------------------
    pub fn getClipRectMin(draw_list: DrawList) [2]f32 {
        var v: [2]f32 = undefined;
        igDrawList_GetClipRectMin(draw_list, &v);
        return v;
    }
    extern fn igDrawList_GetClipRectMin(draw_list: DrawList, clip_min: *[2]f32) void;

    pub fn getClipRectMax(draw_list: DrawList) [2]f32 {
        var v: [2]f32 = undefined;
        igDrawList_GetClipRectMax(draw_list, &v);
        return v;
    }
    extern fn igDrawList_GetClipRectMax(draw_list: DrawList, clip_min: *[2]f32) void;
    //----------------------------------------------------------------------------------------------
    pub fn addLine(draw_list: DrawList, args: struct {
        p1: [2]f32,
        p2: [2]f32,
        col: u32,
        thickness: f32,
    }) void {
        igDrawList_AddLine(draw_list, &args.p1, &args.p2, args.col, args.thickness);
    }
    extern fn igDrawList_AddLine(
        draw_list: DrawList,
        p1: *const [2]f32,
        p2: *const [2]f32,
        col: u32,
        thickness: f32,
    ) void;
    //----------------------------------------------------------------------------------------------
    pub fn addRect(draw_list: DrawList, args: struct {
        pmin: [2]f32,
        pmax: [2]f32,
        col: u32,
        rounding: f32 = 0.0,
        flags: DrawFlags = .{},
        thickness: f32 = 1.0,
    }) void {
        igDrawList_AddRect(
            draw_list,
            &args.pmin,
            &args.pmax,
            args.col,
            args.rounding,
            args.flags,
            args.thickness,
        );
    }
    extern fn igDrawList_AddRect(
        draw_list: DrawList,
        pmin: *const [2]f32,
        pmax: *const [2]f32,
        col: u32,
        rounding: f32,
        flags: DrawFlags,
        thickness: f32,
    ) void;
    //----------------------------------------------------------------------------------------------
    pub fn addRectFilled(draw_list: DrawList, args: struct {
        pmin: [2]f32,
        pmax: [2]f32,
        col: u32,
        rounding: f32 = 0.0,
        flags: DrawFlags = .{},
    }) void {
        igDrawList_AddRectFilled(
            draw_list,
            &args.pmin,
            &args.pmax,
            args.col,
            args.rounding,
            args.flags,
        );
    }
    extern fn igDrawList_AddRectFilled(
        draw_list: DrawList,
        pmin: *const [2]f32,
        pmax: *const [2]f32,
        col: u32,
        rounding: f32,
        flags: DrawFlags,
    ) void;
    //----------------------------------------------------------------------------------------------
    pub fn addRectFilledMultiColor(draw_list: DrawList, args: struct {
        pmin: [2]f32,
        pmax: [2]f32,
        col_upr_left: u32,
        col_upr_right: u32,
        col_bot_right: u32,
        col_bot_left: u32,
    }) void {
        igDrawList_AddRectFilledMultiColor(
            draw_list,
            &args.pmin,
            &args.pmax,
            args.col_upr_left,
            args.col_upr_right,
            args.col_bot_right,
            args.col_bot_left,
        );
    }
    extern fn igDrawList_AddRectFilledMultiColor(
        draw_list: DrawList,
        pmin: *const [2]f32,
        pmax: *const [2]f32,
        col_upr_left: c_uint,
        col_upr_right: c_uint,
        col_bot_right: c_uint,
        col_bot_left: c_uint,
    ) void;
    //----------------------------------------------------------------------------------------------
    pub fn addQuad(draw_list: DrawList, args: struct {
        p1: [2]f32,
        p2: [2]f32,
        p3: [2]f32,
        p4: [2]f32,
        col: u32,
        thickness: f32 = 1.0,
    }) void {
        igDrawList_AddQuad(
            draw_list,
            &args.p1,
            &args.p2,
            &args.p3,
            &args.p4,
            args.col,
            args.thickness,
        );
    }
    extern fn igDrawList_AddQuad(
        draw_list: DrawList,
        p1: *const [2]f32,
        p2: *const [2]f32,
        p3: *const [2]f32,
        p4: *const [2]f32,
        col: u32,
        thickness: f32,
    ) void;
    //----------------------------------------------------------------------------------------------
    pub fn addQuadFilled(draw_list: DrawList, args: struct {
        p1: [2]f32,
        p2: [2]f32,
        p3: [2]f32,
        p4: [2]f32,
        col: u32,
    }) void {
        igDrawList_AddQuadFilled(draw_list, &args.p1, &args.p2, &args.p3, &args.p4, args.col);
    }
    extern fn igDrawList_AddQuadFilled(
        draw_list: DrawList,
        p1: *const [2]f32,
        p2: *const [2]f32,
        p3: *const [2]f32,
        p4: *const [2]f32,
        col: u32,
    ) void;
    //----------------------------------------------------------------------------------------------
    pub fn addTriangle(draw_list: DrawList, args: struct {
        p1: [2]f32,
        p2: [2]f32,
        p3: [2]f32,
        col: u32,
        thickness: f32 = 1.0,
    }) void {
        igDrawList_AddTriangle(draw_list, &args.p1, &args.p2, &args.p3, args.col, args.thickness);
    }
    extern fn igDrawList_AddTriangle(
        draw_list: DrawList,
        p1: *const [2]f32,
        p2: *const [2]f32,
        p3: *const [2]f32,
        col: u32,
        thickness: f32,
    ) void;
    //----------------------------------------------------------------------------------------------
    pub fn addTriangleFilled(draw_list: DrawList, args: struct {
        p1: [2]f32,
        p2: [2]f32,
        p3: [2]f32,
        col: u32,
    }) void {
        igDrawList_AddTriangleFilled(draw_list, &args.p1, &args.p2, &args.p3, args.col);
    }
    extern fn igDrawList_AddTriangleFilled(
        draw_list: DrawList,
        p1: *const [2]f32,
        p2: *const [2]f32,
        p3: *const [2]f32,
        col: u32,
    ) void;
    //----------------------------------------------------------------------------------------------
    pub fn addCircle(draw_list: DrawList, args: struct {
        p: [2]f32,
        r: f32,
        col: u32,
        num_segments: i32 = 0,
        thickness: f32 = 1.0,
    }) void {
        igDrawList_AddCircle(
            draw_list,
            &args.p,
            args.r,
            args.col,
            args.num_segments,
            args.thickness,
        );
    }
    extern fn igDrawList_AddCircle(
        draw_list: DrawList,
        center: *const [2]f32,
        radius: f32,
        col: u32,
        num_segments: c_int,
        thickness: f32,
    ) void;
    //----------------------------------------------------------------------------------------------
    pub fn addCircleFilled(draw_list: DrawList, args: struct {
        p: [2]f32,
        r: f32,
        col: u32,
        num_segments: u16 = 0,
    }) void {
        igDrawList_AddCircleFilled(draw_list, &args.p, args.r, args.col, args.num_segments);
    }
    extern fn igDrawList_AddCircleFilled(
        draw_list: DrawList,
        center: *const [2]f32,
        radius: f32,
        col: u32,
        num_segments: c_int,
    ) void;
    //----------------------------------------------------------------------------------------------
    pub fn addEllipse(draw_list: DrawList, args: struct {
        p: [2]f32,
        r: [2]f32,
        col: u32,
        rot: f32 = 0,
        num_segments: i32 = 0,
        thickness: f32 = 1.0,
    }) void {
        igDrawList_AddEllipse(
            draw_list,
            &args.p,
            &args.r,
            args.col,
            args.rot,
            args.num_segments,
            args.thickness,
        );
    }
    extern fn igDrawList_AddEllipse(
        draw_list: DrawList,
        center: *const [2]f32,
        radius: *const [2]f32,
        col: u32,
        rot: f32,
        num_segments: c_int,
        thickness: f32,
    ) void;
    //----------------------------------------------------------------------------------------------
    pub fn addEllipseFilled(draw_list: DrawList, args: struct {
        p: [2]f32,
        r: [2]f32,
        col: u32,
        rot: f32 = 0,
        num_segments: u16 = 0,
    }) void {
        igDrawList_AddEllipseFilled(
            draw_list,
            &args.p,
            &args.r,
            args.col,
            args.rot,
            args.num_segments,
        );
    }
    extern fn igDrawList_AddEllipseFilled(
        draw_list: DrawList,
        center: *const [2]f32,
        radius: *const [2]f32,
        col: u32,
        rot: f32,
        num_segments: c_int,
    ) void;
    //----------------------------------------------------------------------------------------------
    pub fn addNgon(draw_list: DrawList, args: struct {
        p: [2]f32,
        r: f32,
        col: u32,
        num_segments: u32,
        thickness: f32 = 1.0,
    }) void {
        igDrawList_AddNgon(
            draw_list,
            &args.p,
            args.r,
            args.col,
            @intCast(args.num_segments),
            args.thickness,
        );
    }
    extern fn igDrawList_AddNgon(
        draw_list: DrawList,
        center: *const [2]f32,
        radius: f32,
        col: u32,
        num_segments: c_int,
        thickness: f32,
    ) void;
    //----------------------------------------------------------------------------------------------
    pub fn addNgonFilled(draw_list: DrawList, args: struct {
        p: [2]f32,
        r: f32,
        col: u32,
        num_segments: u32,
    }) void {
        igDrawList_AddNgonFilled(draw_list, &args.p, args.r, args.col, @intCast(args.num_segments));
    }
    extern fn igDrawList_AddNgonFilled(
        draw_list: DrawList,
        center: *const [2]f32,
        radius: f32,
        col: u32,
        num_segments: c_int,
    ) void;
    //----------------------------------------------------------------------------------------------
    pub fn addText(draw_list: DrawList, pos: [2]f32, col: u32, comptime fmt: []const u8, args: anytype) void {
        const txt = format(fmt, args);
        draw_list.addTextUnformatted(pos, col, txt);
    }
    pub fn addTextUnformatted(draw_list: DrawList, pos: [2]f32, col: u32, txt: []const u8) void {
        igDrawList_AddText(draw_list, &pos, col, txt.ptr, txt.ptr + txt.len);
    }
    extern fn igDrawList_AddText(
        draw_list: DrawList,
        pos: *const [2]f32,
        col: u32,
        text: [*]const u8,
        text_end: [*]const u8,
    ) void;
    //----------------------------------------------------------------------------------------------
    pub fn addPolyline(draw_list: DrawList, points: []const [2]f32, args: struct {
        col: u32,
        flags: DrawFlags = .{},
        thickness: f32 = 1.0,
    }) void {
        igDrawList_AddPolyline(
            draw_list,
            points.ptr,
            @intCast(points.len),
            args.col,
            args.flags,
            args.thickness,
        );
    }
    extern fn igDrawList_AddPolyline(
        draw_list: DrawList,
        points: [*]const [2]f32,
        num_points: c_int,
        col: u32,
        flags: DrawFlags,
        thickness: f32,
    ) void;
    //----------------------------------------------------------------------------------------------
    pub fn addConvexPolyFilled(
        draw_list: DrawList,
        points: []const [2]f32,
        col: u32,
    ) void {
        igDrawList_AddConvexPolyFilled(
            draw_list,
            points.ptr,
            @intCast(points.len),
            col,
        );
    }
    extern fn igDrawList_AddConvexPolyFilled(
        draw_list: DrawList,
        points: [*]const [2]f32,
        num_points: c_int,
        col: u32,
    ) void;
    //----------------------------------------------------------------------------------------------
    pub fn addConcavePolyFilled(
        draw_list: DrawList,
        points: []const [2]f32,
        col: u32,
    ) void {
        igDrawList_AddConcavePolyFilled(
            draw_list,
            points.ptr,
            @intCast(points.len),
            col,
        );
    }
    extern fn igDrawList_AddConcavePolyFilled(
        draw_list: DrawList,
        points: [*]const [2]f32,
        num_points: c_int,
        col: u32,
    ) void;
    //----------------------------------------------------------------------------------------------
    pub fn addBezierCubic(draw_list: DrawList, args: struct {
        p1: [2]f32,
        p2: [2]f32,
        p3: [2]f32,
        p4: [2]f32,
        col: u32,
        thickness: f32 = 1.0,
        num_segments: u32 = 0,
    }) void {
        igDrawList_AddBezierCubic(
            draw_list,
            &args.p1,
            &args.p2,
            &args.p3,
            &args.p4,
            args.col,
            args.thickness,
            @intCast(args.num_segments),
        );
    }
    extern fn igDrawList_AddBezierCubic(
        draw_list: DrawList,
        p1: *const [2]f32,
        p2: *const [2]f32,
        p3: *const [2]f32,
        p4: *const [2]f32,
        col: u32,
        thickness: f32,
        num_segments: c_int,
    ) void;
    //----------------------------------------------------------------------------------------------
    pub fn addBezierQuadratic(draw_list: DrawList, args: struct {
        p1: [2]f32,
        p2: [2]f32,
        p3: [2]f32,
        col: u32,
        thickness: f32 = 1.0,
        num_segments: u32 = 0,
    }) void {
        igDrawList_AddBezierQuadratic(
            draw_list,
            &args.p1,
            &args.p2,
            &args.p3,
            args.col,
            args.thickness,
            @intCast(args.num_segments),
        );
    }
    extern fn igDrawList_AddBezierQuadratic(
        draw_list: DrawList,
        p1: *const [2]f32,
        p2: *const [2]f32,
        p3: *const [2]f32,
        col: u32,
        thickness: f32,
        num_segments: c_int,
    ) void;
    //----------------------------------------------------------------------------------------------
    pub fn addImage(draw_list: DrawList, user_texture_id: TextureIdent, args: struct {
        pmin: [2]f32,
        pmax: [2]f32,
        uvmin: [2]f32 = .{ 0, 0 },
        uvmax: [2]f32 = .{ 1, 1 },
        col: u32 = 0xff_ff_ff_ff,
    }) void {
        igDrawList_AddImage(
            draw_list,
            user_texture_id,
            &args.pmin,
            &args.pmax,
            &args.uvmin,
            &args.uvmax,
            args.col,
        );
    }
    extern fn igDrawList_AddImage(
        draw_list: DrawList,
        user_texture_id: TextureIdent,
        pmin: *const [2]f32,
        pmax: *const [2]f32,
        uvmin: *const [2]f32,
        uvmax: *const [2]f32,
        col: u32,
    ) void;
    //----------------------------------------------------------------------------------------------
    pub fn addImageQuad(draw_list: DrawList, user_texture_id: TextureIdent, args: struct {
        p1: [2]f32,
        p2: [2]f32,
        p3: [2]f32,
        p4: [2]f32,
        uv1: [2]f32 = .{ 0, 0 },
        uv2: [2]f32 = .{ 1, 0 },
        uv3: [2]f32 = .{ 1, 1 },
        uv4: [2]f32 = .{ 0, 1 },
        col: u32 = 0xff_ff_ff_ff,
    }) void {
        igDrawList_AddImageQuad(
            draw_list,
            user_texture_id,
            &args.p1,
            &args.p2,
            &args.p3,
            &args.p4,
            &args.uv1,
            &args.uv2,
            &args.uv3,
            &args.uv4,
            args.col,
        );
    }
    extern fn igDrawList_AddImageQuad(
        draw_list: DrawList,
        user_texture_id: TextureIdent,
        p1: *const [2]f32,
        p2: *const [2]f32,
        p3: *const [2]f32,
        p4: *const [2]f32,
        uv1: *const [2]f32,
        uv2: *const [2]f32,
        uv3: *const [2]f32,
        uv4: *const [2]f32,
        col: u32,
    ) void;
    //----------------------------------------------------------------------------------------------
    pub fn addImageRounded(draw_list: DrawList, user_texture_id: TextureIdent, args: struct {
        pmin: [2]f32,
        pmax: [2]f32,
        uvmin: [2]f32 = .{ 0, 0 },
        uvmax: [2]f32 = .{ 1, 1 },
        col: u32 = 0xff_ff_ff_ff,
        rounding: f32 = 4.0,
        flags: DrawFlags = .{},
    }) void {
        igDrawList_AddImageRounded(
            draw_list,
            user_texture_id,
            &args.pmin,
            &args.pmax,
            &args.uvmin,
            &args.uvmax,
            args.col,
            args.rounding,
            args.flags,
        );
    }
    extern fn igDrawList_AddImageRounded(
        draw_list: DrawList,
        user_texture_id: TextureIdent,
        pmin: *const [2]f32,
        pmax: *const [2]f32,
        uvmin: *const [2]f32,
        uvmax: *const [2]f32,
        col: u32,
        rounding: f32,
        flags: DrawFlags,
    ) void;
    //----------------------------------------------------------------------------------------------
    pub const pathClear = igDrawList_PathClear;
    extern fn igDrawList_PathClear(draw_list: DrawList) void;
    //----------------------------------------------------------------------------------------------
    pub fn pathLineTo(draw_list: DrawList, pos: [2]f32) void {
        igDrawList_PathLineTo(draw_list, &pos);
    }
    extern fn igDrawList_PathLineTo(draw_list: DrawList, pos: *const [2]f32) void;
    //----------------------------------------------------------------------------------------------
    pub fn pathLineToMergeDuplicate(draw_list: DrawList, pos: [2]f32) void {
        igDrawList_PathLineToMergeDuplicate(draw_list, &pos);
    }
    extern fn igDrawList_PathLineToMergeDuplicate(draw_list: DrawList, pos: *const [2]f32) void;
    //----------------------------------------------------------------------------------------------
    pub fn pathFillConvex(draw_list: DrawList, col: u32) void {
        return igDrawList_PathFillConvex(draw_list, col);
    }
    extern fn igDrawList_PathFillConvex(draw_list: DrawList, col: c_uint) void;
    //----------------------------------------------------------------------------------------------
    pub fn pathFillConcave(draw_list: DrawList, col: u32) void {
        return igDrawList_PathFillConcave(draw_list, col);
    }
    extern fn igDrawList_PathFillConcave(draw_list: DrawList, col: c_uint) void;
    //----------------------------------------------------------------------------------------------
    pub fn pathStroke(draw_list: DrawList, args: struct {
        col: u32,
        flags: DrawFlags = .{},
        thickness: f32 = 1.0,
    }) void {
        igDrawList_PathStroke(draw_list, args.col, args.flags, args.thickness);
    }
    extern fn igDrawList_PathStroke(draw_list: DrawList, col: u32, flags: DrawFlags, thickness: f32) void;
    //----------------------------------------------------------------------------------------------
    pub fn pathArcTo(draw_list: DrawList, args: struct {
        p: [2]f32,
        r: f32,
        amin: f32,
        amax: f32,
        num_segments: u16 = 0,
    }) void {
        igDrawList_PathArcTo(
            draw_list,
            &args.p,
            args.r,
            args.amin,
            args.amax,
            args.num_segments,
        );
    }
    extern fn igDrawList_PathArcTo(
        draw_list: DrawList,
        center: *const [2]f32,
        radius: f32,
        amin: f32,
        amax: f32,
        num_segments: c_int,
    ) void;
    //----------------------------------------------------------------------------------------------
    pub fn pathArcToFast(draw_list: DrawList, args: struct {
        p: [2]f32,
        r: f32,
        amin_of_12: u16,
        amax_of_12: u16,
    }) void {
        igDrawList_PathArcToFast(draw_list, &args.p, args.r, args.amin_of_12, args.amax_of_12);
    }
    extern fn igDrawList_PathArcToFast(
        draw_list: DrawList,
        center: *const [2]f32,
        radius: f32,
        a_min_of_12: c_int,
        a_max_of_12: c_int,
    ) void;
    //----------------------------------------------------------------------------------------------
    pub fn pathEllipticalArcTo(draw_list: DrawList, args: struct {
        p: [2]f32,
        r: [2]f32,
        rot: f32,
        amin: f32,
        amax: f32,
        num_segments: u16 = 0,
    }) void {
        igDrawList_PathEllipticalArcTo(
            draw_list,
            &args.p,
            &args.r,
            args.rot,
            args.amin,
            args.amax,
            args.num_segments,
        );
    }
    extern fn igDrawList_PathEllipticalArcTo(
        draw_list: DrawList,
        center: *const [2]f32,
        radius: *const [2]f32,
        rot: f32,
        amin: f32,
        amax: f32,
        num_segments: c_int,
    ) void;
    //----------------------------------------------------------------------------------------------
    pub fn pathBezierCubicCurveTo(draw_list: DrawList, args: struct {
        p2: [2]f32,
        p3: [2]f32,
        p4: [2]f32,
        num_segments: u16 = 0,
    }) void {
        igDrawList_PathBezierCubicCurveTo(
            draw_list,
            &args.p2,
            &args.p3,
            &args.p4,
            args.num_segments,
        );
    }
    extern fn igDrawList_PathBezierCubicCurveTo(
        draw_list: DrawList,
        p2: *const [2]f32,
        p3: *const [2]f32,
        p4: *const [2]f32,
        num_segments: c_int,
    ) void;
    //----------------------------------------------------------------------------------------------
    pub fn pathBezierQuadraticCurveTo(draw_list: DrawList, args: struct {
        p2: [2]f32,
        p3: [2]f32,
        num_segments: u16 = 0,
    }) void {
        igDrawList_PathBezierQuadraticCurveTo(draw_list, &args.p2, &args.p3, args.num_segments);
    }
    extern fn igDrawList_PathBezierQuadraticCurveTo(
        draw_list: DrawList,
        p2: *const [2]f32,
        p3: *const [2]f32,
        num_segments: c_int,
    ) void;
    //----------------------------------------------------------------------------------------------
    const PathRect = struct {
        bmin: [2]f32,
        bmax: [2]f32,
        rounding: f32 = 0.0,
        flags: DrawFlags = .{},
    };
    pub fn pathRect(draw_list: DrawList, args: PathRect) void {
        igDrawList_PathRect(draw_list, &args.bmin, &args.bmax, args.rounding, args.flags);
    }
    extern fn igDrawList_PathRect(
        draw_list: DrawList,
        rect_min: *const [2]f32,
        rect_max: *const [2]f32,
        rounding: f32,
        flags: DrawFlags,
    ) void;
    //----------------------------------------------------------------------------------------------
    pub const primReserve = igDrawList_PrimReserve;
    extern fn igDrawList_PrimReserve(
        draw_list: DrawList,
        idx_count: i32,
        vtx_count: i32,
    ) void;

    pub const primUnreserve = igDrawList_PrimUnreserve;
    extern fn igDrawList_PrimUnreserve(
        draw_list: DrawList,
        idx_count: i32,
        vtx_count: i32,
    ) void;

    pub fn primRect(
        draw_list: DrawList,
        a: [2]f32,
        b: [2]f32,
        col: u32,
    ) void {
        return igDrawList_PrimRect(draw_list, &a, &b, col);
    }
    extern fn igDrawList_PrimRect(
        draw_list: DrawList,
        a: *const [2]f32,
        b: *const [2]f32,
        col: u32,
    ) void;

    pub fn primRectUV(
        draw_list: DrawList,
        a: [2]f32,
        b: [2]f32,
        uv_a: [2]f32,
        uv_b: [2]f32,
        col: u32,
    ) void {
        return igDrawList_PrimRectUV(draw_list, &a, &b, &uv_a, &uv_b, col);
    }
    extern fn igDrawList_PrimRectUV(
        draw_list: DrawList,
        a: *const [2]f32,
        b: *const [2]f32,
        uv_a: *const [2]f32,
        uv_b: *const [2]f32,
        col: u32,
    ) void;

    pub fn primQuadUV(
        draw_list: DrawList,
        a: [2]f32,
        b: [2]f32,
        c: [2]f32,
        d: [2]f32,
        uv_a: [2]f32,
        uv_b: [2]f32,
        uv_c: [2]f32,
        uv_d: [2]f32,
        col: u32,
    ) void {
        return igDrawList_PrimQuadUV(draw_list, &a, &b, &c, &d, &uv_a, &uv_b, &uv_c, &uv_d, col);
    }
    extern fn igDrawList_PrimQuadUV(
        draw_list: DrawList,
        a: *const [2]f32,
        b: *const [2]f32,
        c: *const [2]f32,
        d: *const [2]f32,
        uv_a: *const [2]f32,
        uv_b: *const [2]f32,
        uv_c: *const [2]f32,
        uv_d: *const [2]f32,
        col: u32,
    ) void;

    pub fn primWriteVtx(
        draw_list: DrawList,
        pos: [2]f32,
        uv: [2]f32,
        col: u32,
    ) void {
        return igDrawList_PrimWriteVtx(draw_list, &pos, &uv, col);
    }
    extern fn igDrawList_PrimWriteVtx(
        draw_list: DrawList,
        pos: *const [2]f32,
        uv: *const [2]f32,
        col: u32,
    ) void;

    pub const primWriteIdx = igDrawList_PrimWriteIdx;
    extern fn igDrawList_PrimWriteIdx(
        draw_list: DrawList,
        idx: DrawIdx,
    ) void;

    //----------------------------------------------------------------------------------------------

    pub fn addCallback(draw_list: DrawList, callback: DrawCallback, callback_data: ?*anyopaque) void {
        igDrawList_AddCallback(draw_list, callback, callback_data);
    }
    extern fn igDrawList_AddCallback(draw_list: DrawList, callback: DrawCallback, callback_data: ?*anyopaque) void;
    pub fn addResetRenderStateCallback(draw_list: DrawList) void {
        igDrawList_AddResetRenderStateCallback(draw_list);
    }
    extern fn igDrawList_AddResetRenderStateCallback(draw_list: DrawList) void;
};

pub const DrawFlags = packed struct(c_int) {
    closed: bool = false,
    _padding0: u3 = 0,
    round_corners_top_left: bool = false,
    round_corners_top_right: bool = false,
    round_corners_bottom_left: bool = false,
    round_corners_bottom_right: bool = false,
    round_corners_none: bool = false,
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
pub const TextureIdent = *anyopaque;
pub const DrawCmd = extern struct {
    clip_rect: [4]f32,
    texture_id: TextureIdent,
    vtx_offset: c_uint,
    idx_offset: c_uint,
    elem_count: c_uint,
    user_callback: ?DrawCallback,
    user_callback_data: ?*anyopaque,
    user_callback_data_size: c_int,
    user_callback_data_offset: c_int,
};
pub const DrawCallback = *const fn (*const anyopaque, *const DrawCmd) callconv(.C) void;
pub const DrawIdx = u16;
pub const DrawVert = extern struct {
    pos: [2]f32,
    uv: [2]f32,
    color: u32,
};

var temp_buffer: ?std.ArrayList(u8) = null;
pub fn format(comptime fmt: []const u8, args: anytype) []const u8 {
    const len = std.fmt.count(fmt, args);
    if (len > temp_buffer.?.items.len) temp_buffer.?.resize(@intCast(len + 64)) catch unreachable;
    return std.fmt.bufPrint(temp_buffer.?.items, fmt, args) catch unreachable;
}

pub const io = struct {
    pub fn addFontFromFile(filename: [:0]const u8, size_pixels: f32) Font {
        return igIoAddFontFromFile(filename, size_pixels);
    }
    extern fn igIoAddFontFromFile(filename: [*:0]const u8, size_pixels: f32) Font;

    pub fn addFontFromFileWithConfig(
        filename: [:0]const u8,
        size_pixels: f32,
        config: ?FontConfig,
        ranges: ?[*]const Wchar,
    ) Font {
        return igIoAddFontFromFileWithConfig(filename, size_pixels, if (config) |c| &c else null, ranges);
    }
    extern fn igIoAddFontFromFileWithConfig(
        filename: [*:0]const u8,
        size_pixels: f32,
        config: ?*const FontConfig,
        ranges: ?[*]const Wchar,
    ) Font;

    pub fn addFontFromMemory(fontdata: []const u8, size_pixels: f32) Font {
        return igIoAddFontFromMemory(fontdata.ptr, @intCast(fontdata.len), size_pixels);
    }
    extern fn igIoAddFontFromMemory(font_data: *const anyopaque, font_size: c_int, size_pixels: f32) Font;

    pub fn addFontFromMemoryWithConfig(
        fontdata: []const u8,
        size_pixels: f32,
        config: ?FontConfig,
        ranges: ?[*]const Wchar,
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

    pub fn getFont(index: u32) Font {
        return igIoGetFont(index);
    }
    extern fn igIoGetFont(index: c_uint) Font;

    /// `pub fn setDefaultFont(font: Font) void`
    pub const setDefaultFont = igIoSetDefaultFont;
    extern fn igIoSetDefaultFont(font: Font) void;

    pub fn getFontsTextDataAsRgba32() struct {
        width: i32,
        height: i32,
        pixels: ?[*]const u32,
    } {
        var width: i32 = undefined;
        var height: i32 = undefined;
        const ptr = igIoGetFontsTexDataAsRgba32(&width, &height);
        return .{
            .width = width,
            .height = height,
            .pixels = ptr,
        };
    }
    extern fn igIoGetFontsTexDataAsRgba32(width: *c_int, height: *c_int) [*c]const u32;

    /// `pub fn setFontsTexId(id:TextureIdent) set the backend Id for the fonts atlas
    pub const setFontsTexId = igIoSetFontsTexId;
    extern fn igIoSetFontsTexId(id: TextureIdent) void;

    pub const getFontsTexId = igIoGetFontsTexId;
    extern fn igIoGetFontsTexId() TextureIdent;

    /// `pub fn igIoSetConfigWindowsMoveFromTitleBarOnly(bool) void`
    pub const setConfigWindowsMoveFromTitleBarOnly = igIoSetConfigWindowsMoveFromTitleBarOnly;
    extern fn igIoSetConfigWindowsMoveFromTitleBarOnly(enabled: bool) void;

    /// `pub fn igIoGetWantCaptureMouse() bool`
    pub const getWantCaptureMouse = igIoGetWantCaptureMouse;
    extern fn igIoGetWantCaptureMouse() bool;

    /// `pub fn igIoGetWantCaptureKeyboard() bool`
    pub const getWantCaptureKeyboard = igIoGetWantCaptureKeyboard;
    extern fn igIoGetWantCaptureKeyboard() bool;

    /// `pub fn igIoGetWantTextInput() bool`
    pub const getWantTextInput = igIoGetWantTextInput;
    extern fn igIoGetWantTextInput() bool;

    pub const getFramerate = igIoFramerate;
    extern fn igIoFramerate() f32;

    pub fn setIniFilename(filename: ?[*:0]const u8) void {
        igIoSetIniFilename(filename);
    }
    extern fn igIoSetIniFilename(filename: ?[*:0]const u8) void;

    /// `pub fn setDisplaySize(width: f32, height: f32) void`
    pub const setDisplaySize = igIoSetDisplaySize;
    extern fn igIoSetDisplaySize(width: f32, height: f32) void;

    pub fn getDisplaySize() [2]f32 {
        var size: [2]f32 = undefined;
        igIoGetDisplaySize(&size);
        return size;
    }
    extern fn igIoGetDisplaySize(size: *[2]f32) void;

    /// `pub fn setDisplayFramebufferScale(sx: f32, sy: f32) void`
    pub const setDisplayFramebufferScale = igIoSetDisplayFramebufferScale;
    extern fn igIoSetDisplayFramebufferScale(sx: f32, sy: f32) void;

    /// `pub fn setConfigFlags(flags: ConfigFlags) void`
    pub const setConfigFlags = igIoSetConfigFlags;
    extern fn igIoSetConfigFlags(flags: ConfigFlags) void;

    /// `pub fn setDeltaTime(delta_time: f32) void`
    pub const setDeltaTime = igIoSetDeltaTime;
    extern fn igIoSetDeltaTime(delta_time: f32) void;

    pub const addFocusEvent = igIoAddFocusEvent;
    extern fn igIoAddFocusEvent(focused: bool) void;

    pub const addMousePositionEvent = igIoAddMousePositionEvent;
    extern fn igIoAddMousePositionEvent(x: f32, y: f32) void;

    pub const addMouseButtonEvent = igIoAddMouseButtonEvent;
    extern fn igIoAddMouseButtonEvent(button: MouseButton, down: bool) void;

    pub const addMouseWheelEvent = igIoAddMouseWheelEvent;
    extern fn igIoAddMouseWheelEvent(x: f32, y: f32) void;

    pub const addKeyEvent = igIoAddKeyEvent;
    extern fn igIoAddKeyEvent(key: Key, down: bool) void;

    pub const addInputCharactersUTF8 = igIoAddInputCharactersUTF8;
    extern fn igIoAddInputCharactersUTF8(utf8_chars: ?[*:0]const u8) void;

    pub fn setKeyEventNativeData(key: Key, keycode: i32, scancode: i32) void {
        igIoSetKeyEventNativeData(key, keycode, scancode);
    }
    extern fn igIoSetKeyEventNativeData(key: Key, keycode: c_int, scancode: c_int) void;

    pub fn addCharacterEvent(char: i32) void {
        igIoAddCharacterEvent(char);
    }
    extern fn igIoAddCharacterEvent(char: c_int) void;
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
pub const MouseButton = enum(u32) {
    left = 0,
    right = 1,
    middle = 2,
};
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
        return zguiFontConfig_Init();
    }
    extern fn zguiFontConfig_Init() FontConfig;
};
pub const Wchar = u16;
pub const Font = *opaque {};