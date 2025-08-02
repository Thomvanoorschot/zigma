const std = @import("std");
const protobuf = @import("protobuf");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const enable_inspector = false;

    // Dependencies
    const backstage_dep = b.dependency("backstage", .{
        .target = target,
        .optimize = optimize,
        .enable_inspector = enable_inspector,
        .generate_proxies = true,
    });
    generateActorProxies(b, backstage_dep);

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

    // TODO Protobuf is probably no longer needed, want to move the encoding logic to the backstage module
    // Handle shared protobuf dependency -- This is pretty annoying but I don't know how to do it better
    const protobuf_dep = b.dependency("protobuf", .{
        .target = target,
        .optimize = optimize,
    });
    const backstage_mod = backstage_dep.module("backstage");
    const shared_models_mod = shared_models_dep.module("shared_models");
    backstage_mod.addImport("protobuf", protobuf_dep.module("protobuf"));
    shared_models_mod.addImport("protobuf", protobuf_dep.module("protobuf"));

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
    exe.root_module.addImport("backstage", backstage_mod);
    exe.root_module.addImport("async_zocket", async_zocket_dep.module("async_zocket"));
    exe.root_module.addImport("zbor", zbor_dep.module("zbor"));
    exe.root_module.addImport("shared_models", shared_models_mod);

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

fn generateActorProxies(b: *std.Build, backstage_dep: *std.Build.Dependency) void {
    const generator = backstage_dep.artifact("generator");
    b.installArtifact(generator);
    const run_generator = b.addRunArtifact(generator);
    run_generator.addArg("src/generated");
    run_generator.addArg("src/http");
    run_generator.addArg("src/trading");

    const gen_proxies = b.step("gen-proxies", "Generate actor proxies");
    gen_proxies.dependOn(&run_generator.step);
    b.getInstallStep().dependOn(gen_proxies);
}
