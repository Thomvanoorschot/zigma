const std = @import("std");
const zignite_pkg = @import("zignite");

const name = "client";
pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm64,
        .os_tag = .emscripten,
    });
    const optimize = b.standardOptimizeOption(.{});

    // Dependencies
    const zignite_dep = b.dependency("zignite", .{
        .target = target,
        .optimize = optimize,
        .with_imgui = true,
        .with_implot = true,
        .use_glfw = true,
        .use_webgpu = true,
        .use_websockets = true,
        .use_filesystem = true,
    });
    const zignite_lib = zignite_dep.artifact("zignite");
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
        .name = name,
        .root_module = client_mod,
    });
    exe.linkLibrary(zignite_lib);
    // Add imports to executable
    exe.root_module.addImport("zignite", zignite_dep.module("zignite"));
    exe.root_module.addImport("shared_models", shared_models_dep.module("shared_models"));

    exe.linkLibC();
    b.installArtifact(exe);

    zignite_pkg.emRunStep(b, .{
        .name = name,
        .zignite_dep = zignite_dep,
        .lib_main = exe,
    });
}
