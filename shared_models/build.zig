const std = @import("std");
const protobuf = @import("protobuf");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    // const target = b.resolveTargetQuery(.{
    //     .cpu_arch = .aarch64,
    //     .os_tag = .macos,
    // });
    const optimize = b.standardOptimizeOption(.{});

    const protobuf_dep = b.dependency("protobuf", .{
        .target = target,
        .optimize = optimize,
    });

    const shared_models = b.addModule("shared_models", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/root.zig"),
    });

    shared_models.addImport("protobuf", protobuf_dep.module("protobuf"));

    const gen_proto = b.step("gen-proto", "generates zig files from protocol buffer definitions");

    const protoc_step = protobuf.RunProtocStep.create(b, protobuf_dep.builder, target, .{
        .destination_directory = b.path("src"),
        .source_files = &.{
            "ws_message.proto",
            "actor_message.proto",
        },
        .include_directories = &.{"proto"},
    });

    gen_proto.dependOn(&protoc_step.step);

    b.getInstallStep().dependOn(gen_proto);
}
