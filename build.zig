const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void
{
  const target = b.standardTargetOptions(.{});
  const optimize = b.standardOptimizeOption(.{});
  
  const ecs_lib = b.dependency("ecs_lib", .{
    .target = target,
    .optimize = optimize
  });

  const sdlImage = b.dependency("SDL_image", .{
    .target = target,
    .optimize = optimize
  });
  const sdl = sdlImage.builder.dependency("SDL", .{
    .target = target,
    .optimize = optimize
  });

  const lua = b.dependency("lua", .{
    .target = target,
    .release = optimize != .Debug,
  });
  const luaLib =
    lua.artifact(if (target.result.os.tag == .windows) "lua54" else "lua");

  // We will also create a module for our other entry point, 'main.zig'.
  const exe_mod = b.createModule(.{
    // `root_source_file` is the Zig "entry point" of the module. If a module
    // only contains e.g. external object files, you can make this `null`.
    // In this case the main source file is merely a path, however, in more
    // complicated build scripts, this could be a generated file.
    .root_source_file = b.path("src/main.zig"),
    .target = target,
    .optimize = optimize,
    .link_libc = true,
    .imports = &.{
      .{.name = "ecs", .module = ecs_lib.module("ecs-lib")},
    },
  });

  exe_mod.linkSystemLibrary("ncurses", .{});
  exe_mod.linkLibrary(luaLib);
  exe_mod.linkLibrary(sdl.artifact("SDL3"));
  exe_mod.linkLibrary(sdlImage.artifact("SDL3_image"));
  exe_mod.addIncludePath(lua.path("src"));
  exe_mod.addIncludePath(sdl.path("include"));
  exe_mod.addIncludePath(sdlImage.path("include"));

  // This creates another `std.Build.Step.Compile`, but this one builds an executable
  // rather than a static library.
  const exe = b.addExecutable(.{
    .name = "fractal",
    .root_module = exe_mod,
  });

  // This declares intent for the executable to be installed into the
  // standard location when the user invokes the "install" step (the default
  // step when running `zig build`).
  b.installArtifact(exe);
  b.installDirectory(.{
    .source_dir = .{.src_path = .{.owner = b, .sub_path = "mods"}},
    .install_dir = .bin,
    .install_subdir = "mods",
  });

  // This *creates* a Run step in the build graph, to be executed when another
  // step is evaluated that depends on it. The next line below will establish
  // such a dependency.
  const run_cmd = b.addRunArtifact(exe);

  // By making the run step depend on the install step, it will be run from the
  // installation directory rather than directly from within the cache directory.
  // This is not necessary, however, if the application depends on other installed
  // files, this ensures they will be present and in the expected location.
  run_cmd.step.dependOn(b.getInstallStep());

  // This allows the user to pass arguments to the application in the build
  // command itself, like this: `zig build run -- arg1 arg2 etc`
  if (b.args) |args|
  {
    run_cmd.addArgs(args);
  }

  // This creates a build step. It will be visible in the `zig build --help` menu,
  // and can be selected like this: `zig build run`
  // This will evaluate the `run` step rather than the default, which is "install".
  const run_step = b.step("run", "Run the app");
  run_step.dependOn(&run_cmd.step);

  const exe_unit_tests = b.addTest(.{
    .root_module = exe_mod,
  });

  const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

  // Similar to creating the run step earlier, this exposes a `test` step to
  // the `zig build --help` menu, providing a way for the user to request
  // running the unit tests.
  const test_step = b.step("test", "Run unit tests");
  test_step.dependOn(&run_exe_unit_tests.step);

  // This is where the interesting part begins.
  // As you can see we are re-defining the same executable but
  // we're binding it to a dedicated build step.
  const exe_check = b.addExecutable(.{
      .name = "fractal",
      .root_module = exe_mod,
  });
  // There is no `b.installArtifact(exe_check);` here.
  
  // Finally we add the "check" step which will be detected
  // by ZLS and automatically enable Build-On-Save.
  // If you copy this into your `build.zig`, make sure to rename 'foo'
  const check = b.step("check", "Check if the app compiles");
  check.dependOn(&exe_check.step);
}
