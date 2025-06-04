const std = @import("std");
const protobuf = @import("protobuf");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Dependencies
    const backstage_dep = b.dependency("backstage", .{
        .target = target,
        .optimize = optimize,
    });
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

    const protobuf_dep = b.dependency("protobuf", .{
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
    // server_mod.addImport("backstage", backstage_dep.module("backstage"));
    // server_mod.addImport("async_zocket", async_zocket_dep.module("async_zocket"));
    // server_mod.addImport("zbor", zbor_dep.module("zbor"));
    // server_mod.addImport("shared_models", shared_models_dep.module("shared_models"));
    // Add executable
    const exe = b.addExecutable(.{
        .name = "zigma_server",
        .root_module = server_mod,
    });

    // Add imports to executable
    exe.root_module.addImport("backstage", backstage_dep.module("backstage"));
    exe.root_module.addImport("async_zocket", async_zocket_dep.module("async_zocket"));
    exe.root_module.addImport("zbor", zbor_dep.module("zbor"));
    exe.root_module.addImport("shared_models", shared_models_dep.module("shared_models"));
    exe.root_module.addImport("protobuf", shared_models_dep.module("shared_models").import_table.get("protobuf").?);

    b.installArtifact(exe);

    // Generate protobuf files
    const gen_proto = b.step("gen-proto", "generates zig files from protocol buffer definitions");

    const protoc_step = protobuf.RunProtocStep.create(b, protobuf_dep.builder, target, .{
        .destination_directory = b.path("src/actor_message"),
        .source_files = &.{
            "actor_message.proto",
        },
        .include_directories = &.{"proto"},
    });

    gen_proto.dependOn(&protoc_step.step);
    b.getInstallStep().dependOn(gen_proto);

    // Add a run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    b.step("run", "Run Zigma server").dependOn(&run_cmd.step);
}
