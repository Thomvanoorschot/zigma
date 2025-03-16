const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const alphazig_dep = b.dependency("alphazig", .{
        .target = target,
        .optimize = optimize,
    });
    const websocket_dep = b.dependency("websocket", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "zigma",
        .root_source_file = .{ .cwd_relative = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("alphazig", alphazig_dep.module("alphazig"));
    exe.root_module.addImport("websocket", websocket_dep.module("websocket"));

    b.installArtifact(exe);
    // Add a run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    b.step("run", "Run Zigma").dependOn(&run_cmd.step);
}
