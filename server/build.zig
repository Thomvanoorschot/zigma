const std = @import("std");
const protobuf = @import("protobuf");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const enable_inspector = true;

    // Dependencies
    const backstage_dep = b.dependency("backstage", .{
        .target = target,
        .optimize = optimize,
        .enable_inspector = enable_inspector,
    });
    if (enable_inspector) {
        const inspector = backstage_dep.artifact("inspector");
        b.installArtifact(inspector);
    }
    const async_zocket_dep = b.dependency("async_zocket", .{
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

    // Server module
    const server_mod = b.addModule("server", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = .{ .cwd_relative = "src/main.zig" },
    });

    const exe = b.addExecutable(.{
        .name = "zigma_server",
        .root_module = server_mod,
    });

    // Add imports to executable
    exe.root_module.addImport("backstage", backstage_dep.module("backstage"));
    exe.root_module.addImport("async_zocket", async_zocket_dep.module("async_zocket"));
    exe.root_module.addImport("zbor", zbor_dep.module("zbor"));
    exe.root_module.addImport("shared_models", shared_models_dep.module("shared_models"));

    b.installArtifact(exe);

    // Add a run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    b.step("run", "Run Zigma server").dependOn(&run_cmd.step);

    // Add test step
    const tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    tests.root_module.addImport("backstage", backstage_dep.module("backstage"));
    tests.root_module.addImport("async_zocket", async_zocket_dep.module("async_zocket"));
    tests.root_module.addImport("zbor", zbor_dep.module("zbor"));
    tests.root_module.addImport("shared_models", shared_models_dep.module("shared_models"));

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
