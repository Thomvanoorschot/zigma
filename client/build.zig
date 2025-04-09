const std = @import("std");

const demo_name = "main";

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Dependencies
    const zglfw = b.dependency("zglfw", .{
        .target = target,
    });
    const zopengl = b.dependency("zopengl", .{});
    const zgui = b.dependency("zgui", .{
        .target = target,
        .backend = .glfw_opengl3,
        .with_implot = true,
    });
    const shared_models = b.dependency("shared_models", .{
        .target = target,
        .optimize = optimize,
    });
    const xev = b.dependency("libxev", .{
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
    client_mod.addImport("zglfw", zglfw.module("root"));
    client_mod.addImport("zopengl", zopengl.module("root"));
    client_mod.addImport("zgui", zgui.module("root"));
    client_mod.addImport("xev", xev.module("xev"));
    client_mod.addImport("shared_models", shared_models.module("shared_models"));

    // Add executable
    const exe = b.addExecutable(.{
        .name = demo_name,
        .root_module = client_mod,
    });

    // Add imports to executable
    exe.root_module.addImport("zglfw", zglfw.module("root"));
    exe.linkLibrary(zglfw.artifact("glfw"));
    exe.root_module.addImport("zopengl", zopengl.module("root"));
    exe.root_module.addImport("zgui", zgui.module("root"));
    exe.linkLibrary(zgui.artifact("imgui"));
    exe.root_module.addImport("xev", xev.module("xev"));
    exe.root_module.addImport("shared_models", shared_models.module("shared_models"));

    // Add run step
    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run example");
    run_step.dependOn(&run_cmd.step);

    b.installArtifact(exe);
}
