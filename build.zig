const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const backstage_dep = b.dependency("backstage", .{
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

    exe.root_module.addImport("backstage", backstage_dep.module("backstage"));
    exe.root_module.addImport("websocket", websocket_dep.module("websocket"));

    b.installArtifact(exe);
    // Add a run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    b.step("run", "Run Zigma").dependOn(&run_cmd.step);
}
