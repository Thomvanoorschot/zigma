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

extern fn ImPlot_GetCurrentContext() ?Context;
extern fn ImPlot_CreateContext() Context;
extern fn ImPlot_DestroyContext(ctx: ?Context) void;

pub const showDemoWindow = ImPlot_ShowDemoWindow;
extern fn ImPlot_ShowDemoWindow(popen: ?*bool) void;