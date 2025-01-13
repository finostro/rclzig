const std = @import("std");
fn isPackageLib(allocator: std.mem.Allocator, entry: std.fs.Dir.Entry, package_names: []const []const u8) !bool {
    for (package_names) |pname| {
        const potential_lib_name = try std.mem.concat(allocator, u8, &[_][]const u8{ "lib", pname });
        if (std.mem.startsWith(u8, entry.name, potential_lib_name)) {
            return true;
        }
    }
    return false;
}
fn linkAllFiles(module: *std.Build.Module, folder_path: []const u8) !void {
    var package_lib_dir = try std.fs.openDirAbsolute(folder_path, .{ .iterate = true });
    defer package_lib_dir.close();
    var package_iter = package_lib_dir.iterate();
    while (try package_iter.next()) |entry| {
        if (entry.kind == .file and std.mem.startsWith(u8, entry.name, "lib") and std.mem.endsWith(u8, entry.name, ".so")) {
            module.linkSystemLibrary(entry.name[3 .. entry.name.len - 3], .{});
        }
    }
}
/// Link a single ament C package.
fn amentTargetCDependencies(allocator: std.mem.Allocator, module: *std.Build.Module, package_names: []const []const u8) !void {
    // _ = allocator;

    comptime {
        switch (@TypeOf(module)) {
            *std.Build.Module => {},
            *std.Build.Step.Compile => {},
            else => {
                @compileError("amentTargetCDependency only works with Module or Compile");
            },
        }
    }

    std.debug.print("amentTargetCDependencies\n", .{});

    for (package_names) |name| {
        std.debug.print("dependency name:    {s}\n", .{name});
    }
    // const package_lib_found = [package_names.len]bool{false};

    const ament_env = std.posix.getenv("AMENT_PREFIX_PATH");
    if (ament_env) |ament_prefix| {
        var ament_prefix_iterator = std.mem.tokenizeAny(u8, ament_prefix, ":");
        while (ament_prefix_iterator.next()) |prefix| {
            // TODO(jacobperron): This assumption is wrong if packages install their headers to a subdirectory
            const base_include_dir = try std.fmt.allocPrint(allocator, "{s}/include", .{prefix});
            defer allocator.free(base_include_dir);
            {
                var dir = try std.fs.openDirAbsolute(base_include_dir, .{ .iterate = true });
                defer dir.close();

                var iter = dir.iterate();
                while (try iter.next()) |entry| {
                    switch (entry.kind) {
                        .directory => {
                            for (package_names) |pname| {
                                if (std.mem.eql(u8, pname, entry.name)) {
                                    const paths = [_][]const u8{ base_include_dir, entry.name };
                                    const full_path = try std.fs.path.join(allocator, &paths);
                                    std.debug.print("adding include path: {s} \n", .{full_path});
                                    defer allocator.free(full_path);
                                    module.addIncludePath(.{ .cwd_relative = full_path });
                                }
                            }
                        },
                        else => {},
                    }
                }
            }
            module.addIncludePath(.{ .cwd_relative = base_include_dir });

            const base_lib_dir = try std.fmt.allocPrint(allocator, "{s}/lib", .{prefix});
            defer allocator.free(base_lib_dir);

            {
                var dir = try std.fs.openDirAbsolute(base_lib_dir, .{ .iterate = true });
                defer dir.close();

                var iter = dir.iterate();
                while (try iter.next()) |entry| {
                    switch (entry.kind) {
                        .directory => {
                            for (package_names) |pname| {
                                if (std.mem.eql(u8, pname, entry.name)) {
                                    const paths = [_][]const u8{ base_include_dir, entry.name };
                                    const full_path = try std.fs.path.join(allocator, &paths);
                                    defer allocator.free(full_path);
                                    std.debug.print("adding link path: {s} \n", .{full_path});
                                    module.addLibraryPath(.{ .cwd_relative = full_path });
                                    try linkAllFiles(module, full_path);
                                }
                            }
                        },
                        .file => {
                            if (try isPackageLib(allocator, entry, package_names)) {
                                if (std.mem.endsWith(u8, entry.name, ".so")) {
                                    module.linkSystemLibrary(entry.name[3 .. entry.name.len - 3], .{});
                                } else {
                                    module.linkSystemLibrary(entry.name[3..], .{});
                                }
                            }
                        },
                        else => {},
                    }
                }
            }
            module.addLibraryPath(.{ .cwd_relative = base_lib_dir });
        }
    } else {
        std.log.warn("AMENT_PREFIX_PATH is not set\n", .{});
        return error.RclAmentPrefixPathNotSet;
    }

    module.linkSystemLibrary("c", .{});
}

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {

    // Ament stuff requires an allocator
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const rcl_dependencies = [_][]const u8{
        "rcl",
        "rcl_interfaces__rosidl_typesupport_c",
        "rcl_interfaces__rosidl_generator_c",
        "rcl_logging_interface",
        "rcl_logging_spdlog",
        "rcl_yaml_param_parser",
        "rcutils",
        "rmw",
        "rmw_implementation",
        "rosidl_runtime_c",
        "rosidl_typesupport_interface",
        "tracetools",
    };
    const std_msgs_dependencies = [_][]const u8{
        "std_msgs",
        "std_msgs__rosidl_typesupport_c",
        "std_msgs__rosidl_generator_c",
        "rosidl_runtime_c",
        "rosidl_typesupport_interface",
    };
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // This creates a "module", which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Every executable or library we compile will be based on one or more modules.
    const rclzig_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/rclzig/rclzig.zig"),
        .target = target,
        .optimize = optimize,
    });

    amentTargetCDependencies(allocator, rclzig_mod, &rcl_dependencies) catch |err| {
        std.log.err("Error adding ament depenedencies to target {s}", .{@errorName(err)});
        return err;
    };

    // We will also create a module for our other entry point, 'main.zig'.
    const std_msgs_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/std_msgs/std_msgs.zig"),
        .target = target,
        .optimize = optimize,
    });

    amentTargetCDependencies(allocator, std_msgs_mod, &std_msgs_dependencies) catch |err| {
        std.log.err("Error adding ament depenedencies to target {s}", .{@errorName(err)});
        return err;
    };

    // Modules can depend on one another using the `std.Build.Module.addImport` function.
    // This is what allows Zig source code to use `@import("foo")` where 'foo' is not a
    // file path. In this case, we set up `exe_mod` to import `lib_mod`.
    // exe_mod.addImport("rclzig2_lib", lib_mod);

    // Now, we will create a static library based on the module we created above.
    // This creates a `std.Build.Step.Compile`, which is the build step responsible
    // for actually invoking the compiler.
    const rclzig_lib = b.addStaticLibrary(.{
        .name = "rclzig",
        .root_module = rclzig_mod,
    });
    // amentTargetCDependencies(allocator, rclzig_lib, &rcl_dependencies);

    // Now, we will create a static library based on the module we created above.
    // This creates a `std.Build.Step.Compile`, which is the build step responsible
    // for actually invoking the compiler.
    const std_msgs_lib = b.addStaticLibrary(.{
        .name = "std_msgs",
        .root_module = std_msgs_mod,
    });
    // amentTargetCDependencies(allocator, std_msgs_lib, &std_msgs_dependencies);

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(std_msgs_lib);
    b.installArtifact(rclzig_lib);

    // This creates another `std.Build.Step.Compile`, but this one builds an executable
    // rather than a static library.
    const talker_exe = b.addExecutable(.{ .name = "talker", .root_source_file = b.path("src/examples/talker.zig"), .target = target });
    talker_exe.root_module.addImport("rclzig", rclzig_mod);
    talker_exe.root_module.addImport("std_msgs", std_msgs_mod);
    // talker_exe.linkLibrary(std_msgs_lib);
    // talker_exe.linkLibrary(rclzig_lib);
    amentTargetCDependencies(allocator, talker_exe.root_module, &rcl_dependencies) catch |err| {
        std.log.err("Error adding ament depenedencies to target {s}", .{@errorName(err)});
        return err;
    };
    amentTargetCDependencies(allocator, talker_exe.root_module, &std_msgs_dependencies) catch |err| {
        std.log.err("Error adding ament depenedencies to target {s}", .{@errorName(err)});
        return err;
    };

    // amentTargetCDependencies(allocator, talker_exe, std_msgs_dependencies);
    // amentTargetCDependencies(allocator, talker_exe, rcl_dependencies);

    const listener_exe = b.addExecutable(.{ .name = "listener", .root_source_file = b.path("src/examples/listener.zig"), .target = target });
    listener_exe.root_module.addImport("rclzig", rclzig_mod);
    listener_exe.root_module.addImport("std_msgs", std_msgs_mod);
    // listener_exe.linkLibrary(std_msgs_lib);
    // listener_exe.linkLibrary(rclzig_lib);
    amentTargetCDependencies(allocator, listener_exe.root_module, &rcl_dependencies) catch |err| {
        std.log.err("Error adding ament depenedencies to target {s}", .{@errorName(err)});
        return err;
    };
    amentTargetCDependencies(allocator, listener_exe.root_module, &std_msgs_dependencies) catch |err| {
        std.log.err("Error adding ament depenedencies to target {s}", .{@errorName(err)});
        return err;
    };

    // amentTargetCDependencies(allocator, listener_exe, std_msgs_dependencies);
    // amentTargetCDependencies(allocator, listener_exe, rcl_dependencies);

    // const exe = b.addExecutable(.{ .name = "rclzig2", .root_module = rclzig_mod });

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    // b.installArtifact(exe);
    b.installArtifact(listener_exe);
    b.installArtifact(talker_exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const talker_cmd = b.addRunArtifact(talker_exe);
    const listener_cmd = b.addRunArtifact(listener_exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    talker_cmd.step.dependOn(b.getInstallStep());
    listener_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        talker_cmd.addArgs(args);
        listener_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&talker_cmd.step);
    run_step.dependOn(&listener_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const rclzig_tests = b.addTest(.{
        .root_module = rclzig_mod,
    });
    const std_msgs_tests = b.addTest(.{
        .root_module = std_msgs_mod,
    });

    const run_rclzig_tests = b.addRunArtifact(rclzig_tests);
    const run_std_msgs_tests = b.addRunArtifact(std_msgs_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_rclzig_tests.step);
    test_step.dependOn(&run_std_msgs_tests.step);
}
