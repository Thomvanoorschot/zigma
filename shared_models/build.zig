const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zbor_dep = b.dependency("zbor", .{
        .target = target,
        .optimize = optimize,
    });

    const shared_models = b.addModule("shared_models", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/root.zig"),
    });

    shared_models.addImport("zbor", zbor_dep.module("zbor"));
}
