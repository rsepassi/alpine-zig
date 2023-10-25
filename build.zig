const std = @import("std");

const package_name = "alpine-zig";
// SYNC alpine_version_str
const alpine_version_str = "3.18.4";

pub fn build(b: *std.Build) !void {
    for (&[_][]const u8{
        "alpine/alpine-aarch64.tar.gz",
        "alpine/alpine-arm.tar.gz",
        "alpine/alpine-x86_64.tar.gz",
        "alpine/alpine-x86.tar.gz",
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
            .build_dir = "test_build",
            .outputs = &[_][]const u8{
                "hi",
                "foo/bar",
            },
        });

        const install = b.addInstallFile(sbox.outputs[0], "test/hi");
        install.step.dependOn(&b.addInstallFile(sbox.outputs[1], "test/foobar").step);

        const test_step = b.step("test", "Run test");
        test_step.dependOn(&install.step);
        test_step.dependOn(&sbox.step);
    }
}

const SandboxConfig = struct {
    build_dir: []const u8,
    outputs: []const []const u8,
};

pub fn addSandboxBuild(b: *std.Build, config: SandboxConfig) *SandboxBuildStep {
    return SandboxBuildStep.create(b, config) catch @panic("Fail");
}

const SandboxBuildStep = struct {
    step: std.Build.Step,
    config: SandboxConfig,
    outputs: []std.Build.LazyPath,
    script: *std.Build.Step.Run,

    // Internal
    generated: []std.Build.GeneratedFile,

    fn create(b: *std.Build, config: SandboxConfig) !*@This() {
        const bwrap_dep = b.dependency("bubblewrap_zig", .{
        });
        const bwrap = bwrap_dep.artifact("bwrap");

        const arch = b.host.target.cpu.arch;
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
        build_script.has_side_effects = true;

        // BWRAP_BIN
        build_script.addArtifactArg(bwrap);
        // TODO: this needs to use a alpine-zig tar file...
        // ALPINE_TAR
        build_script.addArg(try b.build_root.join(b.allocator, &[_][]const u8{"alpine", tarname}));
        // APK_CACHE_DIR
        build_script.addArg(try b.global_cache_root.join(b.allocator, &[_][]const u8{ package_name, alpine_version_str, @tagName(arch) }));
        // BUILD_DIR
        build_script.addArg(config.build_dir);
        // SCRATCH_DIR
        build_script.addArg(scratch_path);
        // OUT_DIR
        build_script.addArg(out_path);

        // TODO: update name
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
            .script = build_script,
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
