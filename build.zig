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
            .outputs = &.{
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
    name: ?[]const u8 = null,
    build_dir: []const u8,
    outputs: []const []const u8,
    target: std.zig.CrossTarget = .{},
    optimize: std.builtin.Mode = .Debug,
};

pub fn addSandboxBuild(b: *std.Build, config: SandboxConfig) *SandboxBuildStep {
    return SandboxBuildStep.create(b, config) catch @panic("Creating sandbox build step failed");
}

const SandboxBuildStep = struct {
    step: std.Build.Step,
    config: SandboxConfig,
    outputs: []std.Build.LazyPath,
    script: *std.Build.Step.Run,
    stdout: std.Build.LazyPath,
    stderr: std.Build.LazyPath,

    // Internal
    generated: []std.Build.GeneratedFile,
    ok_file: std.Build.LazyPath,

    fn create(b: *std.Build, config: SandboxConfig) !*@This() {
        const bwrap_dep = b.dependency("bubblewrap_zig", .{});
        const bwrap = bwrap_dep.artifact("bwrap");

        const arch = b.host.target.cpu.arch;
        const tarname = switch (arch) {
            .x86_64 => "alpine-x86_64.tar.gz",
            .aarch64 => "alpine-aarch64.tar.gz",
            .arm => "alpine-arm.tar.gz",
            .x86 => "alpine-x86.tar.gz",
            else => @panic("Unsupport cpu arch"),
        };
        const name = config.name orelse config.build_dir;

        const scratch_path = try b.cache_root.join(b.allocator, &[_][]const u8{try std.fs.path.join(b.allocator, &.{ "tmp", "alpine-zig", name, "scratch" })});
        const out_path = try b.cache_root.join(b.allocator, &[_][]const u8{try std.fs.path.join(b.allocator, &.{ "tmp", "alpine-zig", name, "out" })});

        // TODO: this needs to use a alpine-zig binary...
        const build_bin = try b.build_root.join(b.allocator, &[_][]const u8{"build.sh"});
        // TODO: this needs to use a alpine-zig tar file...
        const alpine_tar = try b.build_root.join(b.allocator, &.{ "alpine", tarname });

        const build_script = b.addSystemCommand(&.{build_bin});
        const ok_file = blk: {
            // BWRAP_BIN
            build_script.addArtifactArg(bwrap);
            // ALPINE_TAR
            build_script.addFileArg(.{ .path = alpine_tar });
            // APK_CACHE_DIR
            build_script.addArg(try b.global_cache_root.join(b.allocator, &.{ package_name, alpine_version_str, @tagName(arch) }));
            // BUILD_DIR
            build_script.addArg(try b.build_root.join(b.allocator, &.{config.build_dir}));
            // SCRATCH_DIR
            build_script.addArg(scratch_path);
            // OUT_DIR
            build_script.addArg(out_path);
            // OUT_OK
            const ok_file = build_script.addOutputFileArg("ok");
            // ZIG_TRIPLE
            build_script.addArg(try config.target.zigTriple(b.allocator));
            // ZIG_OPTIMIZE
            build_script.addArg(@tagName(config.optimize));

            break :blk ok_file;
        };

        build_script.extra_file_dependencies = blk: {
            // The inputs are everything in config.build_dir.
            // These are used here only to specify caching dependencies.
            var input_args = std.ArrayList([]const u8).init(b.allocator);
            try input_args.append(build_bin);
            var build_iter_dir = try b.build_root.handle.openIterableDir(config.build_dir, .{});
            defer build_iter_dir.close();
            var walker = try build_iter_dir.walk(b.allocator);
            defer walker.deinit();
            while (try walker.next()) |entry| {
                if (entry.kind != .file) continue;
                const path = try entry.dir.realpathAlloc(b.allocator, entry.basename);
                try input_args.append(path);
            }
            break :blk input_args.items;
        };

        var self = try b.allocator.create(@This());
        self.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = name,
                .owner = b,
                .makeFn = make,
            }),
            .config = config,
            .outputs = try b.allocator.alloc(std.Build.LazyPath, config.outputs.len),
            .script = build_script,
            .stdout = build_script.captureStdOut(),
            .stderr = build_script.captureStdErr(),
            .generated = try b.allocator.alloc(std.Build.GeneratedFile, config.outputs.len),
            .ok_file = ok_file,
        };
        for (0..config.outputs.len) |i| {
            self.generated[i] = .{ .step = &self.step };
            self.outputs[i] = .{ .generated = &self.generated[i] };
        }
        self.step.dependOn(&build_script.step);
        return self;
    }

    fn make(step: *std.Build.Step, _: *std.Progress.Node) !void {
        const b = step.owner;
        var self = @fieldParentPtr(@This(), "step", step);

        std.fs.accessAbsolute(self.ok_file.generated.path.?, .{}) catch {
            @panic("Sandbox script does not seem to have ended cleanly");
        };

        // Fill outputs
        for (self.config.outputs, 0..) |out, i| {
            const out_path = try b.cache_root.join(b.allocator, &[_][]const u8{try std.fs.path.join(b.allocator, &.{ "tmp", "alpine-zig", "out", out })});
            self.generated[i].path = out_path;
        }
    }
};
