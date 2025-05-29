const std = @import("std");
const zignite = @import("zignite");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Dependencies
    const zignite_dep = b.dependency("zignite", .{
        .target = target,
        .optimize = optimize,
    });
    const shared_models_dep = b.dependency("shared_models", .{
        .target = target,
        .optimize = optimize,
    });

    // Client module
    const client_mod = b.addModule("client", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = .{ .cwd_relative = "src/main.zig" },
    });

    // Add imports
    client_mod.addImport("zignite", zignite_dep.module("zignite"));
    client_mod.addImport("shared_models", shared_models_dep.module("shared_models"));

    // Add executable
    const exe = b.addStaticLibrary(.{
        .name = "client",
        .root_module = client_mod,
    });

    // Add imports to executable
    exe.root_module.addImport("zignite", zignite_dep.module("zignite"));
    exe.root_module.addImport("shared_models", shared_models_dep.module("shared_models"));


    exe.linkLibC();
    exe.root_module.addImport("zignite", zignite_dep.module("zignite"));

    const emsdk = zignite_dep.builder.dependency("emsdk", .{});
    const link_step = try zignite.emLinkStep(b, .{
        .lib_main = exe,
        .target = target,
        .optimize = optimize,
        .emsdk = emsdk,
        .use_webgpu = true,
        .use_glfw = true,
        .shell_file_path = zignite_dep.path("web/shell.html"),
        .extra_args = &.{
            "-lwebsocket.js",
        },
    });

    b.getInstallStep().dependOn(&link_step.step);

    // Add run step
    const run = zignite.emRunStep(b, .{ .name = "client", .emsdk = emsdk });
    run.step.dependOn(&link_step.step);
    b.step("run", "Run client").dependOn(&run.step);

    b.installArtifact(exe);
}
