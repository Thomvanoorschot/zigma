pub const backend = @import("backend_glfw_opengl.zig");

const Context = *opaque {};

extern fn zguiCreateContext(shared_font_atlas: ?*const anyopaque) Context;
