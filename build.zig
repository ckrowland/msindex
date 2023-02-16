const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const facil_dep = b.dependency("facil.io", .{
        .target = target,
        .optimize = optimize,
    });
    const zap = b.dependency("zap", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "msindex",
        .root_source_file = .{ .path = "main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibrary(facil_dep.artifact("facil.io"));
    exe.addModule("zap", zap.module("zap"));

    const run_step = b.step("run", "Run the app");
    const run_cmd = exe.run();
    run_step.dependOn(&run_cmd.step);

    b.default_step.dependOn(&exe.step);
    b.installArtifact(exe);


    const updateExe = b.addExecutable(.{
        .name = "update",
        .root_source_file = .{ .path = "update.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_update_step = b.step("run-update", "Run update process");
    const run_update_cmd = updateExe.run();
    run_update_step.dependOn(&run_update_cmd.step);
    b.installArtifact(updateExe);
    b.default_step.dependOn(&updateExe.step);
}
