const std = @import("std");

const cflags = &.{
    "-fno-sanitize=undefined",
    "-Wno-elaborated-enum-base",
    "-Wno-error=date-time",
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Dependencies
    const zglfw_dep = b.dependency("zglfw", .{
        .target = target,
    });
    const zopengl_dep = b.dependency("zopengl", .{});

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
    client_mod.addImport("xev", xev_dep.module("xev"));
    client_mod.addImport("shared_models", shared_models_dep.module("shared_models"));
    client_mod.addImport("zul", zul_dep.module("zul"));

    // Add executable
    const exe = b.addExecutable(.{
        .name = "client",
        .root_module = client_mod,
    });

    // Add imports to executable
    exe.root_module.addImport("zglfw", zglfw_dep.module("root"));
    exe.linkLibrary(zglfw_dep.artifact("glfw"));
    exe.root_module.addImport("zopengl", zopengl_dep.module("root"));
    exe.root_module.addImport("xev", xev_dep.module("xev"));
    exe.root_module.addImport("shared_models", shared_models_dep.module("shared_models"));
    exe.root_module.addImport("zul", zul_dep.module("zul"));

    const imgui = addImgui(b, target, optimize);
    addImplot(b, imgui);
    // Add run step
    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run example");
    run_step.dependOn(&run_cmd.step);

    b.installArtifact(exe);
}

fn addImgui(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const imgui = b.addStaticLibrary(.{
        .name = "cimgui",
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(imgui);

    imgui.addIncludePath(b.path("libs"));
    imgui.addIncludePath(b.path("libs/imgui"));

    imgui.linkLibC();

    imgui.addCSourceFile(.{
        .file = b.path("libs/cimgui.cpp"),
        .flags = cflags,
    });

    imgui.addCSourceFiles(.{
        .files = &.{
            "libs/imgui/imgui.cpp",
            "libs/imgui/imgui_widgets.cpp",
            "libs/imgui/imgui_tables.cpp",
            "libs/imgui/imgui_draw.cpp",
            "libs/imgui/imgui_demo.cpp",
        },
        .flags = cflags,
    });
    return imgui;
}

fn addImplot(b: *std.Build, imgui: *std.Build.Step.Compile) void {
    imgui.addIncludePath(b.path("libs/implot"));

    imgui.addCSourceFile(.{
        .file = b.path("src/zplot.cpp"),
        .flags = cflags,
    });

    imgui.addCSourceFiles(.{
        .files = &.{
            "libs/implot/implot_demo.cpp",
            "libs/implot/implot.cpp",
            "libs/implot/implot_items.cpp",
        },
        .flags = cflags,
    });
}

fn addBackend(b: *std.Build, imgui: *std.Build.Step.Compile) void {
    if (b.lazyDependency("zglfw", .{})) |zglfw| {
        imgui.addIncludePath(zglfw.path("libs/glfw/include"));
    }
    imgui.addCSourceFiles(.{
        .files = &.{
            "libs/imgui/backends/imgui_impl_glfw.cpp",
            "libs/imgui/backends/imgui_impl_opengl3.cpp",
        },
        .flags = &(cflags.* ++ .{"-DIMGUI_IMPL_OPENGL_LOADER_CUSTOM"}),
    });
}
