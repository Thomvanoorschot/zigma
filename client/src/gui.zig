const std = @import("std");
pub const backend = @import("backend_glfw_opengl.zig");

pub fn init(_: std.mem.Allocator) void {
    if (igGetCurrentContext() == null) {
        // mem_allocator = allocator;
        // mem_allocations = std.AutoHashMap(usize, usize).init(allocator);
        // mem_allocations.?.ensureTotalCapacity(32) catch @panic("zgui: out of memory");
        // zguiSetAllocatorFunctions(zguiMemAlloc, zguiMemFree);


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
extern fn igCreateContext(shared_font_atlas: ?*const anyopaque) Context;
extern fn igDestroyContext(ctx: ?Context) void;
extern fn igGetCurrentContext() ?Context;

pub const newFrame = igNewFrame;
extern fn igNewFrame() void;