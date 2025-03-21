const std = @import("std");
const sokol_build = @import("sokol");

fn cimplotModule(
    b: *std.Build,
    sokol_dep: *std.Build.Dependency,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Mode,
) *std.Build.Module {
    const imgui_dep = b.dependency("imgui", .{
        .target = target,
        .optimize = optimize,
    });

    const implot_dep = b.dependency("implot", .{
        .target = target,
        .optimize = optimize,
    });

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

    // build cimplot as module
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

fn cimguiModule(
    b: *std.Build,
    sokol_dep: *std.Build.Dependency,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Mode,
) *std.Build.Module {
    const imgui_dep = b.dependency("imgui", .{
        .target = target,
        .optimize = optimize,
    });

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

    // add the imgui sources
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

    // add the cimgui sources
    lib_imgui.addCSourceFiles(.{
        .files = &.{
            "deps/cimgui.cpp",
        },
    });

    const cimgui_translate_c = b.addTranslateC(.{
        .root_source_file = b.path("deps/cimgui.h"),
        // note the target is for the host
        .target = b.graph.host,
        .optimize = optimize,
    });
    cimgui_translate_c.defineCMacro("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", null);
    cimgui_translate_c.addIncludePath(b.path("deps"));

    // make cimgui module
    const mod_cimgui = b.addModule("cimgui", .{
        .root_source_file = cimgui_translate_c.getOutput(),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    // link the module
    mod_cimgui.linkLibrary(lib_imgui);
    return mod_cimgui;
}

const BuildContext = struct {
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Mode,
    sokol_dep: *std.Build.Dependency,
    mod: *std.Build.Module,
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sokol_dep = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
        .with_sokol_imgui = true,
    });

    const mod_cimgui = cimguiModule(b, sokol_dep, target, optimize);
    const mod_cimplot = cimplotModule(b, sokol_dep, target, optimize);

    // inject the cimgui header search path into the sokol C library compile step
    sokol_dep.artifact("sokol_clib").addIncludePath(b.path("deps"));

    // module to be used by downstream projects
    const mod = b.addModule("skgui", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sokol", .module = sokol_dep.module("sokol") },
            .{ .name = "imgui", .module = mod_cimgui },
            .{ .name = "implot", .module = mod_cimplot },
        },
    });

    const ctx = BuildContext{
        .b = b,
        .target = target,
        .optimize = optimize,
        .sokol_dep = sokol_dep,
        .mod = mod,
    };

    if (target.result.cpu.arch == .wasm32) {
        try buildWasm(ctx);
    } else {
        try buildNative(ctx);
    }
}

fn buildNative(ctx: BuildContext) !void {
    const exe = ctx.b.addExecutable(.{
        .name = "example",
        .target = ctx.target,
        .optimize = ctx.optimize,
        .root_source_file = ctx.b.path("src/main.zig"),
    });
    exe.root_module.addImport("skgui", ctx.mod);
    ctx.b.installArtifact(exe);
    ctx.b.step("run", "Run example").dependOn(&ctx.b.addRunArtifact(exe).step);
}

// the following adapted from https://github.com/floooh/sokol-zig-imgui-sample
fn buildWasm(ctx: BuildContext) !void {
    const example = ctx.b.addStaticLibrary(.{
        .name = "example",
        .target = ctx.target,
        .optimize = ctx.optimize,
        .root_source_file = ctx.b.path("src/main.zig"),
    });
    example.root_module.addImport("skgui", ctx.mod);
    const dep_emsdk = ctx.sokol_dep.builder.dependency("emsdk", .{});
    const emsdk_incl_path = dep_emsdk.path("upstream/emscripten/cache/sysroot/include");
    ctx.mod.addSystemIncludePath(emsdk_incl_path);

    const link_step = try sokol_build.emLinkStep(ctx.b, .{
        .lib_main = example,
        .target = ctx.mod.resolved_target.?,
        .optimize = ctx.mod.optimize.?,
        .emsdk = dep_emsdk,
        .use_webgl2 = true,
        .use_emmalloc = true,
        .use_filesystem = false,
        .shell_file_path = ctx.sokol_dep.path("src/sokol/web/shell.html"),
    });

    // ...and a special run step to start the web build output via 'emrun'
    const run = sokol_build.emRunStep(ctx.b, .{ .name = "example", .emsdk = dep_emsdk });
    run.step.dependOn(&link_step.step);
    ctx.b.step("run", "Run example").dependOn(&run.step);
}
