const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Dependencies
    const xev_dep = b.dependency("libxev", .{
        .target = target,
        .optimize = optimize,
    });

    const xevtcp = b.addModule("xevtcp", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/root.zig"),
    });

    xevtcp.addImport("xev", xev_dep.module("xev"));
}
