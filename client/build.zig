const std = @import("std");

const demo_name = "main";

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = demo_name,
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const zglfw = b.dependency("zglfw", .{
        .target = target,
    });
    exe.root_module.addImport("zglfw", zglfw.module("root"));
    exe.linkLibrary(zglfw.artifact("glfw"));

    const zopengl = b.dependency("zopengl", .{});
    exe.root_module.addImport("zopengl", zopengl.module("root"));

    const zgui = b.dependency("zgui", .{
        .target = target,
        .backend = .glfw_opengl3,
        .with_implot = true,
    });
    exe.root_module.addImport("zgui", zgui.module("root"));
    exe.linkLibrary(zgui.artifact("imgui"));

    const xev = b.dependency("libxev", .{
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("xev", xev.module("xev"));

    const shared_models = b.dependency("shared_models", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("shared_models", shared_models.module("shared_models"));

    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run example");
    run_step.dependOn(&run_cmd.step);

    b.installArtifact(exe);
}
