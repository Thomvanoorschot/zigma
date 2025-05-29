const zignite = @import("zignite");
const std = @import("std");
const imgui = zignite.imgui;
const engine = zignite.engine;
const App = @import("visualization/app.zig").App;
const window_title = "zigma_client";

pub fn main() !void {
    var e = try engine.Engine.init(.{
        .width = 3456,
        .height = 2234,
        .with_implot = false,
    });
    defer e.deinit();

    while (e.startRender()) {
        defer e.endRender();
        imgui.igShowDemoWindow(null);
    }
}
