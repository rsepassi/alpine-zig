# alpine-zig

*Status: Nearly there.*

`zig build` anything hermetically within an Alpine Linux container.

Uses [Bubblewrap](https://github.com/containers/bubblewrap) for sandboxing,
built from source.

Supports Linux hosts on `{x86_64, x86, aarch64, arm}`.

Host system dependencies (see `build.sh`):
* `/bin/sh` along with `mkdir, tar, cp, cat, rm`
* Will use `/etc/resolv.conf` if available, otherwise uses a generated one
  with Google/Cloudflare nameservers.

Usage:

```
# my_repo/build_complex_thing/build

#!/bin/sh
apk add gcc musl-dev make  # These are cached in the global Zig cache
cd foo
./configure
make

# Store all outputs in /zig-out
mkdir -p /zig-out/foo
mv some_artifact /zig-out/foo/hi
mv another_artifact /zig-out/bar

# my_repo/build.zig

    const sbox = alpine_zig.addSandboxBuild(b, .{
        // This build directory will be copied into the container.
        // It is expected to have an executable "build" that will
        // produce the specified outputs in /zig-out.
        .build_dir = .{ .path = "build_complex_thing" },
        .outputs = &[_][]const u8{
            "foo/hi",
            "bar",
        },
    });

    // You can add additional arguments to the build script
    // sbox.script.addArg(...);

    const install_hi = b.addInstallFile(sbox.outputs[0], "hi");
    const install_bar = b.addInstallFile(sbox.outputs[1], "bar");
```

## Todos

* Fix directory naming and caching
* Capture logs ([bug](https://github.com/ziglang/zig/issues/17715))
