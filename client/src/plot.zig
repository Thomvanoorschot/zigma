const gui = @import("gui.zig");
//--------------------------------------------------------------------------------------------------
pub fn init() void {
    if (zguiPlot_GetCurrentContext() == null) {
        _ = zguiPlot_CreateContext();
    }
}
pub fn deinit() void {
    if (zguiPlot_GetCurrentContext() != null) {
        zguiPlot_DestroyContext(null);
    }
}
const Context = *opaque {};

extern fn zguiPlot_GetCurrentContext() ?Context;
extern fn zguiPlot_CreateContext() Context;
extern fn zguiPlot_DestroyContext(ctx: ?Context) void;
