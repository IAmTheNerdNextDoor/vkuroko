const std = @import("std");

const core = @import("../core.zig");
const modules = @import("../modules.zig");
const tier1 = modules.tier1;
const ConVar = tier1.ConVar;
const engine = modules.engine;
const client = modules.client;
const vgui = modules.vgui;

const event = @import("../event.zig");

const Color = @import("sdk").Color;

const Feature = @import("Feature.zig");

pub var feature: Feature = .{
    .name = "text HUD",
    .shouldLoad = shouldLoad,
    .init = init,
    .deinit = deinit,
};

var vkrk_hud_x = tier1.Variable.init(.{
    .name = "vkrk_hud_x",
    .help_string = "The X position for the text HUD.",
    .default_value = "-300",
});

var vkrk_hud_y = tier1.Variable.init(.{
    .name = "vkrk_hud_y",
    .help_string = "The Y position for the text HUD.",
    .default_value = "0",
});

var font_DefaultFixedOutline: c_ulong = 0;
var font_DefaultFixedOutline_tall: c_int = 0;

var x: i32 = 0;
var y: i32 = 0;
var offset: i32 = 0;

// This is kind of broken
const FPSTextHUD = struct {
    var cl_showfps: ?*ConVar = null;

    var average_fps: f32 = 0;
    var last_real_time: i64 = 0;
    var high: u32 = 0;
    var low: u32 = 0;

    fn shouldDraw() bool {
        if (!client.override_fps_panel) return false;

        if (cl_showfps == null) {
            cl_showfps = tier1.icvar.findVar("cl_showfps");
        }

        if (cl_showfps) |v| {
            return v.getBool();
        }

        return false;
    }

    fn getFPSColor(fps: u32) Color {
        const threshold1 = 60;
        const threshold2 = 50;

        if (fps >= threshold1) {
            return .{
                .r = 0,
                .g = 255,
                .b = 0,
            };
        }

        if (fps >= threshold2) {
            return .{
                .r = 255,
                .g = 255,
                .b = 0,
            };
        }

        return .{
            .r = 255,
            .g = 0,
            .b = 0,
        };
    }

    fn paint() void {
        const real_time: i64 = std.time.milliTimestamp();
        const frame_time: f32 = @as(f32, @floatFromInt(real_time - last_real_time)) / std.time.ms_per_s;

        if (frame_time <= 0.0) {
            // Still draw an empty line to prevent flickering
            drawTextHUD("", .{});
            return;
        }

        if (cl_showfps.?.getInt() == 2) {
            const new_weight = 0.1;
            const new_frame: f32 = 1.0 / frame_time;

            if (average_fps < 0.0) {
                average_fps = new_frame;
                high = @intFromFloat(average_fps);
                low = @intFromFloat(average_fps);
            } else {
                average_fps *= (1.0 - new_weight);
                average_fps += (new_frame * new_weight);
            }

            const i_new_frame: u32 = @intFromFloat(new_frame);
            if (i_new_frame < low) {
                low = i_new_frame;
            }
            if (i_new_frame > high) {
                high = i_new_frame;
            }

            const fps: u32 = @intFromFloat(average_fps);
            const frame_ms: f32 = frame_time * std.time.ms_per_s;
            drawColoredTextHUD(
                getFPSColor(fps),
                "{d: >3} fps ({d: >3}, {d: >3}) {d:.1} ms on {s}",
                .{ fps, low, high, frame_ms, engine.client.getLevelName() },
            );
        } else {
            average_fps = -1;
            const fps: u32 = @intFromFloat(1.0 / frame_time);
            drawColoredTextHUD(
                getFPSColor(fps),
                "{d: >3} fps on {s}",
                .{ fps, engine.client.getLevelName() },
            );
        }
        last_real_time = real_time;
    }

    fn register() void {
        addHUDElement(.{
            .shouldDraw = shouldDraw,
            .paint = paint,
        });
    }
};

pub fn drawTextHUD(comptime fmt: []const u8, args: anytype) void {
    drawColoredTextHUD(
        .{
            .r = 255,
            .g = 255,
            .b = 255,
            .a = 255,
        },
        fmt,
        args,
    );
}

pub fn drawColoredTextHUD(color: Color, comptime fmt: []const u8, args: anytype) void {
    vgui.imatsystem.drawColoredText(
        font_DefaultFixedOutline,
        x + 2,
        y + 2 + offset * (font_DefaultFixedOutline_tall + 2),
        color,
        fmt,
        args,
    );
    offset += 1;
}

const HUDElement = struct {
    shouldDraw: *const fn () bool,
    paint: *const fn () void,
};

var hud_elements: std.ArrayList(HUDElement) = undefined;

pub fn addHUDElement(element: HUDElement) void {
    hud_elements.append(element) catch {};
}

fn onPaint() void {
    if (!engine.client.isInGame()) {
        return;
    }

    const screen = vgui.imatsystem.getScreenSize();

    x = vkrk_hud_x.getInt();
    y = vkrk_hud_y.getInt();

    if (x < 0) {
        x += screen.wide;
    }
    if (y < 0) {
        y += screen.tall;
    }

    offset = 0;

    for (hud_elements.items) |element| {
        if (element.shouldDraw()) {
            element.paint();
        }
    }
}

fn shouldLoad() bool {
    return event.paint.works;
}

fn init() bool {
    hud_elements = std.ArrayList(HUDElement).init(core.allocator);

    font_DefaultFixedOutline = vgui.ischeme.getFont("DefaultFixedOutline", false);
    font_DefaultFixedOutline_tall = vgui.imatsystem.getFontTall(font_DefaultFixedOutline);

    event.paint.connect(onPaint);

    vkrk_hud_x.register();
    vkrk_hud_y.register();

    if (client.origCFPSPanel__ShouldDraw != null) {
        FPSTextHUD.register();
    }

    return true;
}

fn deinit() void {
    hud_elements.deinit();
}
