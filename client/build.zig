const std = @import("std");
const sokol_build = @import("sokol");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get dependencies
    const sokol_dep = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
        .with_sokol_imgui = true,
    });
    const imgui_dep = b.dependency("imgui", .{
        .target = target,
        .optimize = optimize,
    });
    const implot_dep = b.dependency("implot", .{
        .target = target,
        .optimize = optimize,
    });

    // Setup cimgui and cimplot modules for our executable
    const mod_cimgui = setupCimgui(b, sokol_dep, target, optimize, imgui_dep);
    const mod_cimplot = setupCimplot(b, sokol_dep, target, optimize, imgui_dep, implot_dep);

    // Inject the cimgui header search path into the sokol C library compile step
    sokol_dep.artifact("sokol_clib").addIncludePath(b.path("deps"));

    // Create the executable based on target architecture
    if (target.result.cpu.arch == .wasm32) {
        try buildWasmExecutable(b, target, optimize, sokol_dep, mod_cimgui, mod_cimplot);
    } else {
        buildNativeExecutable(b, target, optimize, sokol_dep, mod_cimgui, mod_cimplot);
    }
}

fn buildNativeExecutable(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Mode,
    sokol_dep: *std.Build.Dependency,
    mod_cimgui: *std.Build.Module,
    mod_cimplot: *std.Build.Module,
) void {
    const exe = b.addExecutable(.{
        .name = "example",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
    });

    // Add imports directly to the executable
    exe.root_module.addImport("sokol", sokol_dep.module("sokol"));
    exe.root_module.addImport("imgui", mod_cimgui);
    exe.root_module.addImport("implot", mod_cimplot);

    b.installArtifact(exe);
    b.step("run", "Run example").dependOn(&b.addRunArtifact(exe).step);
}

fn buildWasmExecutable(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Mode,
    sokol_dep: *std.Build.Dependency,
    mod_cimgui: *std.Build.Module,
    mod_cimplot: *std.Build.Module,
) !void {
    const example = b.addStaticLibrary(.{
        .name = "example",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
    });

    // Add imports directly to the library
    example.root_module.addImport("sokol", sokol_dep.module("sokol"));
    example.root_module.addImport("imgui", mod_cimgui);
    example.root_module.addImport("implot", mod_cimplot);

    // Setup EMSDK for WebAssembly
    const dep_emsdk = sokol_dep.builder.dependency("emsdk", .{});
    const emsdk_incl_path = dep_emsdk.path("upstream/emscripten/cache/sysroot/include");
    example.root_module.addSystemIncludePath(emsdk_incl_path);

    const link_step = try sokol_build.emLinkStep(b, .{
        .lib_main = example,
        .target = target,
        .optimize = optimize,
        .emsdk = dep_emsdk,
        .use_webgl2 = true,
        .use_emmalloc = true,
        // Changed to true do HTTP requests
        .use_filesystem = true,
        .shell_file_path = sokol_dep.path("src/sokol/web/shell.html"),
    });

    const run = sokol_build.emRunStep(b, .{ .name = "example", .emsdk = dep_emsdk });
    run.step.dependOn(&link_step.step);
    b.step("run", "Run example").dependOn(&run.step);
}

fn setupCimgui(
    b: *std.Build,
    sokol_dep: *std.Build.Dependency,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Mode,
    imgui_dep: *std.Build.Dependency,
) *std.Build.Module {
    const lib_imgui = b.addStaticLibrary(.{
        .name = "imgui",
        .target = target,
        .optimize = optimize,
    });

    if (target.result.cpu.arch == .wasm32) {
        const dep_emsdk = sokol_dep.builder.dependency("emsdk", .{});
        const emsdk_incl_path = dep_emsdk.path("upstream/emscripten/cache/sysroot/include");
        lib_imgui.addSystemIncludePath(emsdk_incl_path);
    }

    lib_imgui.linkLibC();
    lib_imgui.linkLibCpp();

    lib_imgui.addIncludePath(imgui_dep.path("."));
    lib_imgui.addIncludePath(b.path("deps"));

    // Add the imgui sources
    lib_imgui.addCSourceFiles(.{
        .root = imgui_dep.path("."),
        .files = &.{
            "imgui_demo.cpp",
            "imgui_draw.cpp",
            "imgui_tables.cpp",
            "imgui_widgets.cpp",
            "imgui.cpp",
        },
    });

    // Add the cimgui sources
    lib_imgui.addCSourceFiles(.{
        .files = &.{
            "deps/cimgui.cpp",
        },
    });

    const cimgui_translate_c = b.addTranslateC(.{
        .root_source_file = b.path("deps/cimgui.h"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    cimgui_translate_c.defineCMacro("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", null);
    cimgui_translate_c.addIncludePath(b.path("deps"));

    // Make cimgui module
    const mod_cimgui = b.addModule("cimgui", .{
        .root_source_file = cimgui_translate_c.getOutput(),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    mod_cimgui.linkLibrary(lib_imgui);
    return mod_cimgui;
}

fn setupCimplot(
    b: *std.Build,
    sokol_dep: *std.Build.Dependency,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Mode,
    imgui_dep: *std.Build.Dependency,
    implot_dep: *std.Build.Dependency,
) *std.Build.Module {
    const cimplot_translate_c = b.addTranslateC(.{
        .root_source_file = b.path("deps/cimplot.h"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    cimplot_translate_c.defineCMacro("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", null);
    cimplot_translate_c.addIncludePath(b.path("deps"));

    const lib_implot = b.addStaticLibrary(.{
        .name = "implot",
        .target = target,
        .optimize = optimize,
    });

    if (target.result.cpu.arch == .wasm32) {
        const dep_emsdk = sokol_dep.builder.dependency("emsdk", .{});
        const emsdk_incl_path = dep_emsdk.path("upstream/emscripten/cache/sysroot/include");
        lib_implot.addSystemIncludePath(emsdk_incl_path);
    }

    lib_implot.linkLibC();
    lib_implot.linkLibCpp();

    lib_implot.addIncludePath(implot_dep.path("."));
    lib_implot.addIncludePath(imgui_dep.path("."));
    lib_implot.addIncludePath(b.path("deps"));

    lib_implot.addCSourceFiles(.{
        .root = implot_dep.path("."),
        .files = &.{
            "implot.cpp", "implot_items.cpp", "implot_demo.cpp",
        },
    });
    lib_implot.addCSourceFiles(.{
        .files = &.{"deps/cimplot.cpp"},
    });

    // Build cimplot as module
    const mod_cimplot = b.addModule("cimplot", .{
        .root_source_file = cimplot_translate_c.getOutput(),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    mod_cimplot.linkLibrary(lib_implot);
    return mod_cimplot;
}
