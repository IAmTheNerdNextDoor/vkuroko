const std = @import("std");
const builtin = @import("builtin");

const tier0 = @import("modules.zig").tier0;
const event = @import("event.zig");

const Module = @import("modules/Module.zig");
const Feature = @import("features/Feature.zig");

const HookManager = @import("zhook").HookManager;

pub var hook_manager: HookManager = undefined;

const modules: []const *Module = mods: {
    var mods: []const *Module = &.{};
    for (&.{
        @import("modules/tier0.zig"),
        @import("modules/tier1.zig"),
        @import("modules/engine.zig"),
        @import("modules/server.zig"),
        @import("modules/client.zig"),
        @import("modules/vgui.zig"),
    }) |file| {
        mods = mods ++ .{&file.module};
    }
    break :mods mods;
};

const features: []const *Feature = mods: {
    var mods: []const *Feature = &.{};
    for (&.{
        @import("features/datamap.zig"),
        @import("features/texthud.zig"),
        @import("features/playerio.zig"),
        @import("features/strafehud.zig"),
        @import("features/oobent.zig"),
    }) |file| {
        mods = mods ++ .{&file.feature};
    }

    if (builtin.mode == .Debug) {
        mods = mods ++ .{&@import("features/dev.zig").feature};
    }

    break :mods mods;
};

pub fn init() bool {
    event.init();
    hook_manager = HookManager.init(tier0.allocator);

    for (modules) |module| {
        module.loaded = module.init();
        if (!module.loaded) {
            std.log.err("Failed to load module {s}.", .{module.name});
            return false;
        }
        std.log.debug("Module {s} loaded.", .{module.name});
    }

    for (features) |feature| {
        if (feature.shouldLoad()) {
            feature.loaded = feature.init();
            if (!feature.loaded) {
                std.log.warn("Failed to load feature {s}.", .{feature.name});
            } else {
                std.log.debug("Feature {s} loaded.", .{feature.name});
            }
        } else {
            std.log.warn("Skipped loading feature {s}.", .{feature.name});
        }
    }

    return true;
}

pub fn deinit() void {
    for (modules) |module| {
        if (!module.loaded) {
            continue;
        }
        module.deinit();
        module.loaded = false;
    }

    for (features) |feature| {
        if (!feature.loaded) {
            continue;
        }
        feature.deinit();
        feature.loaded = false;
    }

    hook_manager.deinit();
    event.deinit();
}
