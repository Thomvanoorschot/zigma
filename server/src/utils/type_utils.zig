pub fn anyOpaqueCast(comptime Userdata: type, v: ?*anyopaque) ?*Userdata {
    if (Userdata == void) return null;
    return @ptrCast(@alignCast(v));
}
pub fn unsafeAnyOpaqueCast(comptime Userdata: type, v: ?*anyopaque) *Userdata {
    return @ptrCast(@alignCast(v));
}