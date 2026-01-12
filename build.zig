const std = @import("std");

fn benchmark(
    b: *std.Build,
    comptime name: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const bm_exe = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/" ++ name ++ ".zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(bm_exe);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mule = b.addExecutable(.{
        .name = "mule",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/mule.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(mule);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(mule);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mule_tests = b.addTest(.{
        .root_module = mule.root_module,
    });

    const run_mule_tests = b.addRunArtifact(mule_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mule_tests.step);

    benchmark(b, "bm-numbers", target, optimize);
}
