const std = @import("std");

const demo_name = "main";

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Dependencies
    const zglfw_dep = b.dependency("zglfw", .{
        .target = target,
    });
    const zopengl_dep = b.dependency("zopengl", .{});
    const zgui_dep = b.dependency("zgui", .{
        .target = target,
        .backend = .glfw_opengl3,
        .with_implot = true,
    });
    const shared_models_dep = b.dependency("shared_models", .{
        .target = target,
        .optimize = optimize,
    });
    const xev_dep = b.dependency("libxev", .{
        .target = target,
        .optimize = optimize,
    });
    const zul_dep = b.dependency("zul", .{
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
    client_mod.addImport("zglfw", zglfw_dep.module("root"));
    client_mod.addImport("zopengl", zopengl_dep.module("root"));
    client_mod.addImport("zgui", zgui_dep.module("root"));
    client_mod.addImport("xev", xev_dep.module("xev"));
    client_mod.addImport("shared_models", shared_models_dep.module("shared_models"));
    client_mod.addImport("zul", zul_dep.module("zul"));

    // Add executable
    const exe = b.addExecutable(.{
        .name = demo_name,
        .root_module = client_mod,
    });

    // Add imports to executable
    exe.root_module.addImport("zglfw", zglfw_dep.module("root"));
    exe.linkLibrary(zglfw_dep.artifact("glfw"));
    exe.root_module.addImport("zopengl", zopengl_dep.module("root"));
    exe.root_module.addImport("zgui", zgui_dep.module("root"));
    exe.linkLibrary(zgui_dep.artifact("imgui"));
    exe.root_module.addImport("xev", xev_dep.module("xev"));
    exe.root_module.addImport("shared_models", shared_models_dep.module("shared_models"));
    exe.root_module.addImport("zul", zul_dep.module("zul"));

    // Add run step
    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run example");
    run_step.dependOn(&run_cmd.step);

    b.installArtifact(exe);
}
