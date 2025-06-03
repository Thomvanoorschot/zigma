const std = @import("std");
const ProtoGenStep = @import("gremlin").ProtoGenStep;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zbor_dep = b.dependency("zbor", .{
        .target = target,
        .optimize = optimize,
    });

    const gremlin_dep = b.dependency("gremlin", .{
        .target = target,
        .optimize = optimize,
    }).module("gremlin");

    const protobuf_gen = ProtoGenStep.create(
        b,
        .{
            .proto_sources = b.path("proto"), // Directory containing .proto files
            .target = b.path("src/gen"), // Output directory for generated Zig code
        },
    );

    const shared_models = b.addModule("shared_models", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/root.zig"),
    });

    shared_models.addImport("gremlin", gremlin_dep);
    shared_models.addImport("zbor", zbor_dep.module("zbor"));

    var gen_step = b.step("genproto", "Generate protobuf sources");
    gen_step.dependOn(&protobuf_gen.step);

    // 4) Make the Install step depend on our “genproto” step
    //    so that `zig build` (which defaults to “install”) will run codegen.
    b.getInstallStep().dependOn(gen_step);
}
