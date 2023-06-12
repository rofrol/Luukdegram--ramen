const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "ramen",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    const ramen = b.createModule(.{ .source_file = .{ .path = "src/lib.zig" } });
    exe.addModule("ramen", ramen);

    // exe.install();
    // const install_exe = b.addInstallArtifact(exe);
    // b.getInstallStep().dependOn(&install_exe.step);
    //
    // // const run_cmd = exe.run();
    // const run = b.addRunArtifact(exe);
    // b.default_step.dependOn(&run.step);
    //
    // run.step.dependOn(b.getInstallStep());
    // if (b.args) |args| {
    //     run.addArgs(args);
    // }

    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
    // const run_step = b.step("run", "Run the app");
    // run_step.dependOn(&run.step);

    // const main_tests = b.addTest("src/lib.zig");
    // main_tests.setBuildMode(mode);
    // const test_step = b.step("test", "Run library tests");
    // test_step.dependOn(&main_tests.step);
}
