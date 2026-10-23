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
        const dvui_dep = b.dependency("dvui", .{
            .target = target,
            .optimize = optimize,
            .backend = .sdl3,
        });
        const exe = b.addExecutable(.{
            .name = "deztype",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "dvui", .module = dvui_dep.module("dvui_sdl3") },
                },
            }),
        });
        b.installArtifact(exe);

        const run = b.addRunArtifact(exe);
        run.step.dependOn(b.getInstallStep());
        if (b.args) |args| run.addArgs(args);
        b.step("run", "Run the native app").dependOn(&run.step);
    }

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
