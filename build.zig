const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const test_step = b.step("test", "Run composer, keymap, translator, and dictionary tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);

    if (target.result.cpu.arch != .wasm32) {
        const exe = addApp(b, target, optimize, "deztype", false);
        b.installArtifact(exe);

        const run = b.addRunArtifact(exe);
        run.step.dependOn(b.getInstallStep());
        if (b.args) |args| run.addArgs(args);
        b.step("run", "Run the native app").dependOn(&run.step);
    }

    // Same shape as the Dez Games release step: Windows cross-compiles from
    // any host, macOS is a universal .app built on a Mac, and Linux is an
    // x86_64 binary pinned to glibc 2.31. SDL's Zig package vendors its
    // libraries, so Linux is included from a Mac too.
    const release_step = b.step("release", "Build release binaries into zig-out/release/<platform>");
    switch (b.graph.host.result.os.tag) {
        .macos => {
            addMacUniversal(b, release_step);
            addRelease(b, release_step, "linux-x86_64", linuxTarget(b));
        },
        .linux => addRelease(b, release_step, "linux-x86_64", linuxTarget(b)),
        else => {},
    }
    addRelease(b, release_step, "windows-x86_64", b.resolveTargetQuery(.{ .cpu_arch = .x86_64, .os_tag = .windows }));

    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    const dvui_web = b.dependency("dvui", .{
        .target = wasm_target,
        .optimize = optimize,
        .backend = .web,
    });
    const wasm = b.addExecutable(.{
        .name = "deztype",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = wasm_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "dvui", .module = dvui_web.module("dvui_web") },
                .{ .name = "web", .module = dvui_web.module("web") },
            },
        }),
    });
    wasm.entry = .disabled;

    const install_wasm = b.addInstallArtifact(wasm, .{
        .dest_dir = .{ .override = .{ .custom = "web" } },
    });

    const cache_buster = b.addExecutable(.{
        .name = "cacheBuster",
        .root_module = b.createModule(.{
            .root_source_file = dvui_web.path("src/cacheBuster.zig"),
            .target = b.graph.host,
        }),
    });
    const bust = b.addRunArtifact(cache_buster);
    bust.addFileArg(b.path("web/index.html"));
    bust.addFileArg(dvui_web.path("src/backends/web.js"));
    bust.addFileArg(wasm.getEmittedBin());
    const index_html = bust.captureStdOut(.{ .basename = "index.html" });

    const web_step = b.step("web", "Build the hosted web app into zig-out/web");
    web_step.dependOn(&install_wasm.step);
    web_step.dependOn(&b.addInstallFileWithDir(index_html, .{ .custom = "web" }, "index.html").step);
    web_step.dependOn(&b.addInstallFileWithDir(dvui_web.path("src/backends/web.js"), .{ .custom = "web" }, "web.js").step);

    const serve_exe = b.addExecutable(.{
        .name = "serve",
        .root_module = b.createModule(.{
            .root_source_file = dvui_web.path("tools/serve_web_demo.zig"),
            .target = b.graph.host,
        }),
    });
    const serve = b.addRunArtifact(serve_exe);
    serve.addFileArg(index_html);
    serve.addFileArg(dvui_web.path("src/backends/web.js"));
    serve.addArtifactArg(wasm);
    b.step("serve", "Serve the web app at http://127.0.0.1:8080").dependOn(&serve.step);
}

/// glibc 2.31 runs on Ubuntu 20.04 and Debian 11 and newer. A generic x86_64
/// CPU avoids baking in the build machine's AVX flags.
fn linuxTarget(b: *std.Build) std.Build.ResolvedTarget {
    return b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
        .abi = .gnu,
        .glibc_version = .{ .major = 2, .minor = 31, .patch = 0 },
    });
}

fn addRelease(b: *std.Build, step: *std.Build.Step, name: []const u8, target: std.Build.ResolvedTarget) void {
    const exe = addApp(b, target, .ReleaseFast, "Deztype", true);
    const dest = b.fmt("release/{s}", .{name});
    const inst = b.addInstallArtifact(exe, .{
        .dest_dir = .{ .override = .{ .custom = dest } },
    });
    step.dependOn(&inst.step);
    addLicenses(b, step, dest);
}

/// Both macOS arches, lipo'd, inside Deztype.app. A bare executable opens
/// Terminal when double-clicked; the bundle launches the app.
fn addMacUniversal(b: *std.Build, step: *std.Build.Step) void {
    const arm = addApp(b, b.resolveTargetQuery(.{ .cpu_arch = .aarch64, .os_tag = .macos }), .ReleaseFast, "Deztype", false);
    const x86 = addApp(b, b.resolveTargetQuery(.{ .cpu_arch = .x86_64, .os_tag = .macos }), .ReleaseFast, "Deztype", false);
    const lipo = b.addSystemCommand(&.{ "lipo", "-create" });
    lipo.addArtifactArg(arm);
    lipo.addArtifactArg(x86);
    lipo.addArg("-output");
    const universal = lipo.addOutputFileArg("Deztype");

    const contents = "release/macos-universal/Deztype.app/Contents";
    step.dependOn(&b.addInstallFileWithDir(universal, .{ .custom = contents ++ "/MacOS" }, "Deztype").step);
    step.dependOn(&b.addInstallFileWithDir(b.path("assets/macos/Info.plist"), .{ .custom = contents }, "Info.plist").step);
    addLicenses(b, step, contents ++ "/Resources");
}

/// CMUdict and the Noto Deseret font require their notices to travel with the binary.
fn addLicenses(b: *std.Build, step: *std.Build.Step, dest: []const u8) void {
    step.dependOn(&b.addInstallFileWithDir(b.path("LICENSES/CMUdict.txt"), .{ .custom = dest }, "CMUdict.txt").step);
    step.dependOn(&b.addInstallFileWithDir(b.path("LICENSES/OFL-Deseret.txt"), .{ .custom = dest }, "OFL-Deseret.txt").step);
}

fn addApp(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    name: []const u8,
    windows_gui: bool,
) *std.Build.Step.Compile {
    const dvui_dep = b.dependency("dvui", .{
        .target = target,
        .optimize = optimize,
        .backend = .sdl3,
    });
    const exe = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "dvui", .module = dvui_dep.module("dvui_sdl3") },
            },
        }),
    });
    // Release builds ship without debug info. Windows also hides the console.
    if (optimize != .Debug) exe.root_module.strip = true;
    if (target.result.os.tag == .windows and windows_gui and optimize != .Debug) {
        exe.subsystem = .windows;
    }
    // An explicit macOS arch is a cross target. Passing any -L drops Zig's
    // default framework search, and the framework dir alone hides usr/include
    // (libDER/DERItem.h). All three SDK dirs have to be set together, on the
    // SDL3 module: that is where linkSystemLibrary("iconv") is recorded, and
    // the SDL package ignores its own library_path option on macOS.
    if (target.result.os.tag == .macos) {
        if (macSdkPath(b)) |sdk| {
            const lib_dir = b.fmt("{s}/usr/lib", .{sdk});
            const include_dir = b.fmt("{s}/usr/include", .{sdk});
            const fw_dir = b.fmt("{s}/System/Library/Frameworks", .{sdk});
            const sdl3 = dvui_dep.builder.lazyDependency("sdl3", .{
                .target = target,
                .optimize = optimize,
            }) orelse @panic("sdl3 dependency was not fetched");
            const sdl_mod = sdl3.artifact("SDL3").root_module;
            sdl_mod.addLibraryPath(.{ .cwd_relative = lib_dir });
            sdl_mod.addSystemIncludePath(.{ .cwd_relative = include_dir });
            sdl_mod.addSystemFrameworkPath(.{ .cwd_relative = fw_dir });
            exe.root_module.addLibraryPath(.{ .cwd_relative = lib_dir });
            exe.root_module.addSystemFrameworkPath(.{ .cwd_relative = fw_dir });
        }
    }
    return exe;
}

fn macSdkPath(b: *std.Build) ?[]const u8 {
    var threaded: std.Io.Threaded = .init(b.allocator, .{});
    defer threaded.deinit();
    const result = std.process.run(b.allocator, threaded.io(), .{
        .argv = &.{ "xcrun", "--sdk", "macosx", "--show-sdk-path" },
    }) catch return null;
    defer b.allocator.free(result.stdout);
    defer b.allocator.free(result.stderr);
    switch (result.term) {
        .exited => |code| if (code != 0) return null,
        else => return null,
    }
    return b.dupe(std.mem.trim(u8, result.stdout, " \r\n\t"));
}
