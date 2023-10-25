const std = @import("std");

const package_name = "alpine-zig";
// SYNC alpine_version_str
const alpine_version_str = "3.18.4";

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{
        .default_target = std.zig.CrossTarget{
            .abi = .musl,
        },
    });
    const optimize = b.standardOptimizeOption(.{});

    for (&[_][]const u8{
        "alpine-aarch64.tar.gz",
        "alpine-arm.tar.gz",
        "alpine-x86_64.tar.gz",
        "alpine-x86.tar.gz",
        "build.sh",
    }) |tar| {
        b.getInstallStep().dependOn(
            &b.addInstallFileWithDir(
                .{ .path = tar },
                .{ .custom = "alpine-" ++ alpine_version_str },
                tar,
            ).step,
        );
    }

    // Test
    {
        const sbox = addSandboxBuild(b, .{
            .build_dir = .{ .path = "test_build" },
            .outputs = &[_][]const u8{
                "hi",
                "foo/bar",
            },
            .target = target,
            .optimize = optimize,
        });

        const install = b.addInstallFile(sbox.outputs[0], "hi");
        install.step.dependOn(&b.addInstallFile(sbox.outputs[1], "foobar").step);

        const test_step = b.step("test", "Run test");
        test_step.dependOn(&install.step);
        test_step.dependOn(&sbox.step);
    }
}

const SandboxConfig = struct {
    build_dir: std.Build.LazyPath,
    outputs: []const []const u8,
    target: std.zig.CrossTarget = .{
        .abi = .musl,
    },
    optimize: std.builtin.Mode = .ReleaseFast,
};

pub fn addSandboxBuild(b: *std.Build, config: SandboxConfig) *SandboxBuildStep {
    return SandboxBuildStep.create(b, config) catch @panic("Fail");
}

const SandboxBuildStep = struct {
    step: std.Build.Step,
    config: SandboxConfig,
    outputs: []std.Build.LazyPath,

    generated: []std.Build.GeneratedFile,

    fn create(b: *std.Build, config: SandboxConfig) !*@This() {
        const bwrap_dep = b.dependency("bubblewrap_zig", .{
            .target = config.target,
            .optimize = config.optimize,
        });
        const bwrap = bwrap_dep.artifact("bwrap");

        const arch = config.target.cpu_arch orelse b.host.target.cpu.arch;
        const tarname = switch (arch) {
            .x86_64 => "alpine-x86_64.tar.gz",
            .aarch64 => "alpine-aarch64.tar.gz",
            .arm => "alpine-arm.tar.gz",
            .x86 => "alpine-x86.tar.gz",
            else => @panic("Unsupport cpu arch"),
        };

        // TODO: identify this build for caching
        // alpine-zig/$arch/hash(build_dir)

        const scratch_path = try b.cache_root.join(b.allocator, &[_][]const u8{try std.fs.path.join(b.allocator, &.{ "tmp", "alpine-zig", "scratch" })});
        const out_path = try b.cache_root.join(b.allocator, &[_][]const u8{try std.fs.path.join(b.allocator, &.{ "tmp", "alpine-zig", "out" })});

        // TODO: this needs to use a alpine-zig binary...
        const build_script = b.addSystemCommand(&[_][]const u8{try b.build_root.join(b.allocator, &[_][]const u8{"build.sh"})});

        // BWRAP_BIN
        build_script.addArtifactArg(bwrap);
        // TODO: this needs to use a alpine-zig tar file...
        // ALPINE_TAR
        build_script.addArg(try b.build_root.join(b.allocator, &[_][]const u8{tarname}));
        // APK_CACHE_DIR
        build_script.addArg(try b.global_cache_root.join(b.allocator, &[_][]const u8{ package_name, alpine_version_str, @tagName(arch) }));
        // BUILD_DIR
        build_script.addFileArg(config.build_dir);
        // SCRATCH_DIR
        build_script.addArg(scratch_path);
        // OUT_DIR
        build_script.addArg(out_path);

        var self = try b.allocator.create(@This());
        self.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "sandbox_build",
                .owner = b,
                .makeFn = make,
            }),
            .config = config,
            .outputs = try b.allocator.alloc(std.Build.LazyPath, config.outputs.len),
            .generated = try b.allocator.alloc(std.Build.GeneratedFile, config.outputs.len),
        };

        for (self.outputs, 0..) |*out, i| {
            const gen = &self.generated[i];
            gen.* = .{ .step = &self.step };
            out.* = .{ .generated = gen };
        }

        self.step.dependOn(&build_script.step);
        return self;
    }

    fn make(step: *std.Build.Step, _: *std.Progress.Node) !void {
        const b = step.owner;
        var self = @fieldParentPtr(@This(), "step", step);

        // Fill outputs
        for (self.config.outputs, 0..) |out, i| {
            const out_path = try b.cache_root.join(b.allocator, &[_][]const u8{try std.fs.path.join(b.allocator, &.{ "tmp", "alpine-zig", "out", out })});
            self.generated[i].path = out_path;
        }
    }
};
