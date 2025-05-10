const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Dependencies
    const backstage_dep = b.dependency("backstage", .{
        .target = target,
        .optimize = optimize,
    });
    const jolt_dep = b.dependency("jolt", .{
        .target = target,
        .optimize = optimize,
    });
    const zbor_dep = b.dependency("zbor", .{
        .target = target,
        .optimize = optimize,
    });

    const shared_models_dep = b.dependency("shared_models", .{
        .target = target,
        .optimize = optimize,
    });
    const wire_dep = b.dependency("wire", .{
        .target = target,
        .optimize = optimize,
    });

    // Server module
    const server_mod = b.addModule("server", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = .{ .cwd_relative = "src/main.zig" },
    });

    // Add imports
    server_mod.addImport("backstage", backstage_dep.module("backstage"));
    server_mod.addImport("jolt", jolt_dep.module("jolt"));
    server_mod.addImport("zbor", zbor_dep.module("zbor"));
    server_mod.addImport("shared_models", shared_models_dep.module("shared_models"));
    server_mod.addImport("wire", wire_dep.module("wire"));
    // Add executable
    const exe = b.addExecutable(.{
        .name = "zigma_server",
        .root_module = server_mod,
    });

    // Add imports to executable
    exe.root_module.addImport("backstage", backstage_dep.module("backstage"));
    exe.root_module.addImport("jolt", jolt_dep.module("jolt"));
    exe.root_module.addImport("zbor", zbor_dep.module("zbor"));
    exe.root_module.addImport("shared_models", shared_models_dep.module("shared_models"));
    exe.root_module.addImport("wire", wire_dep.module("wire"));
    b.installArtifact(exe);
    // Add a run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    b.step("run", "Run Zigma server").dependOn(&run_cmd.step);
}
