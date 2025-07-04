const std = @import("std");
const builtin = @import("builtin");

const sdk = @import("sdk");
const abi = sdk.abi;

const interfaces = @import("../interfaces.zig");
const core = @import("../core.zig");
const event = @import("../event.zig");

const zhook = @import("zhook");

const Module = @import("Module.zig");

const Color = sdk.Color;
const VCallConv = abi.VCallConv;

pub var module: Module = .{
    .name = "vgui",
    .init = init,
    .deinit = deinit,
};

const IPanel = extern struct {
    _vt: [*]*const anyopaque,

    const VTIndex = struct {
        var getName: usize = undefined;
        var paintTraverse: usize = undefined;
    };

    const PaintTraverseFunc = *const @TypeOf(hookedPaintTraverse);
    var origPaintTraverse: PaintTraverseFunc = undefined;

    fn getName(self: *IPanel, panel: u32) [*:0]const u8 {
        const _setEnabled: *const fn (this: *anyopaque, panel: u32) callconv(VCallConv) [*:0]const u8 = @ptrCast(self._vt[VTIndex.getName]);
        return _setEnabled(self, panel);
    }

    fn hookedPaintTraverse(this: *IPanel, vgui_panel: u32, force_repaint: bool, allow_force: bool) callconv(VCallConv) void {
        const S = struct {
            var panel_id: u32 = 0;
            var found_panel_id: bool = false;
        };

        origPaintTraverse(this, vgui_panel, force_repaint, allow_force);

        if (!S.found_panel_id) {
            if (std.mem.eql(u8, std.mem.span(ipanel.getName(vgui_panel)), "FocusOverlayPanel")) {
                S.panel_id = vgui_panel;
                S.found_panel_id = true;
            }
        } else if (S.panel_id == vgui_panel) {
            event.paint.emit(.{});
        }
    }
};

const IEngineVGui = extern struct {
    _vt: [*]*const anyopaque,

    const VTIndex = struct {
        const isInitialized: usize = 7 + abi.dtor_adjust;
    };

    const VTable = extern struct {
        dtor: abi.DtorVTable,
        getPanel: *const fn (this: *anyopaque, panel_type: c_int) callconv(VCallConv) c_uint,
        isGameUIVisible: *const fn (this: *anyopaque) callconv(VCallConv) bool,
    };

    fn vt(self: *IEngineVGui) *const VTable {
        return @ptrCast(self._vt);
    }

    pub fn isGameUIVisible(self: *IEngineVGui) bool {
        return self.vt().isGameUIVisible(self);
    }

    pub fn isInitialized(self: *IEngineVGui) bool {
        const _isInitialized: *const fn (this: *anyopaque) callconv(VCallConv) bool = @ptrCast(self._vt[VTIndex.isInitialized]);
        return _isInitialized(self);
    }
};

const IMatSystemSurface = extern struct {
    _vt: [*]*const anyopaque,

    const VTIndex = struct {
        const drawSetColor: usize = switch (builtin.os.tag) {
            .windows => 10,
            .linux => 11,
            else => unreachable,
        };
        const drawFilledRect: usize = 12;
        const drawOutlinedRect: usize = 14;
        const drawLine: usize = 15;
        var getScreenSize: usize = undefined;
        var getFontTall: usize = undefined;
        var getTextSize: usize = undefined;
        var drawOutlinedCircle: usize = undefined;
        var drawColoredText: usize = undefined;
    };

    pub fn drawSetColor(self: *IMatSystemSurface, color: Color) void {
        const _drawSetColor: *const fn (this: *anyopaque, color: Color) callconv(VCallConv) void = @ptrCast(self._vt[VTIndex.drawSetColor]);
        _drawSetColor(self, color);
    }

    pub fn drawFilledRect(self: *IMatSystemSurface, x0: i32, y0: i32, x1: i32, y1: i32) void {
        const _drawFilledRect: *const fn (this: *anyopaque, x0: c_int, y0: c_int, x1: c_int, y1: c_int) callconv(VCallConv) void = @ptrCast(self._vt[VTIndex.drawFilledRect]);
        _drawFilledRect(self, x0, y0, x1, y1);
    }

    pub fn drawOutlinedRect(self: *IMatSystemSurface, x0: i32, y0: i32, x1: i32, y1: i32) void {
        const _drawOutlinedRect: *const fn (this: *anyopaque, x0: c_int, y0: c_int, x1: c_int, y1: c_int) callconv(VCallConv) void = @ptrCast(self._vt[VTIndex.drawOutlinedRect]);
        _drawOutlinedRect(self, x0, y0, x1, y1);
    }

    pub fn drawLine(self: *IMatSystemSurface, x0: i32, y0: i32, x1: i32, y1: i32) void {
        const _drawLine: *const fn (this: *anyopaque, x0: c_int, y0: c_int, x1: c_int, y1: c_int) callconv(VCallConv) void = @ptrCast(self._vt[VTIndex.drawLine]);
        _drawLine(self, x0, y0, x1, y1);
    }

    pub fn getScreenSize(self: *IMatSystemSurface) struct { wide: i32, tall: i32 } {
        var wide: c_int = undefined;
        var tall: c_int = undefined;

        const _getScreenSize: *const fn (this: *anyopaque, wide: *c_int, tall: *c_int) callconv(VCallConv) void = @ptrCast(self._vt[VTIndex.getScreenSize]);
        _getScreenSize(self, &wide, &tall);

        return .{
            .wide = wide,
            .tall = tall,
        };
    }

    pub fn getFontTall(self: *IMatSystemSurface, font: c_ulong) c_int {
        const _getFontTall: *const fn (this: *anyopaque, font: c_ulong) callconv(VCallConv) c_int = @ptrCast(self._vt[VTIndex.getFontTall]);
        return _getFontTall(self, font);
    }

    pub fn drawOutlinedCircle(self: *IMatSystemSurface, x: i32, y: i32, radius: i32, segments: i32) void {
        const _drawOutlinedCircle: *const fn (this: *anyopaque, x: c_int, y: c_int, radius: c_int, segments: c_int) callconv(VCallConv) void = @ptrCast(self._vt[VTIndex.drawOutlinedCircle]);
        _drawOutlinedCircle(self, x, y, radius, segments);
    }

    pub fn drawText(
        self: *IMatSystemSurface,
        font: c_ulong,
        x: i32,
        y: i32,
        comptime fmt: []const u8,
        args: anytype,
    ) void {
        self.drawColoredText(
            self,
            font,
            x,
            y,
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

    pub fn drawColoredText(
        self: *IMatSystemSurface,
        font: c_ulong,
        x: i32,
        y: i32,
        color: Color,
        comptime fmt: []const u8,
        args: anytype,
    ) void {
        const _drawColoredText: *const fn (
            this: *anyopaque,
            font: c_ulong,
            x: c_int,
            y: c_int,
            r: c_int,
            g: c_int,
            b: c_int,
            a: c_int,
            fmt: [*:0]const u8,
            ...,
        ) callconv(.C) c_int = @ptrCast(self._vt[VTIndex.drawColoredText]);

        const text = std.fmt.allocPrintZ(core.allocator, fmt, args) catch return;
        defer core.allocator.free(text);

        _ = _drawColoredText(
            self,
            font,
            x,
            y,
            color.r,
            color.g,
            color.b,
            color.a,
            "%s",
            text.ptr,
        );
    }
};

const ISchemeManager = extern struct {
    _vt: [*]*const anyopaque,

    const VTIndex = struct {
        const getDefaultScheme: usize = 4 + abi.dtor_adjust;
        const getIScheme: usize = 8 + abi.dtor_adjust;
    };

    fn getDefaultScheme(self: *ISchemeManager) c_ulong {
        const _getDefaultScheme: *const fn (this: *anyopaque) callconv(VCallConv) c_ulong = @ptrCast(self._vt[VTIndex.getDefaultScheme]);
        return _getDefaultScheme(self);
    }

    fn getIScheme(self: *ISchemeManager, font: c_ulong) ?*IScheme {
        const _getIScheme: *const fn (this: *anyopaque, font: c_ulong) callconv(VCallConv) ?*IScheme = @ptrCast(self._vt[VTIndex.getIScheme]);
        return _getIScheme(self, font);
    }
};

const IScheme = extern struct {
    _vt: [*]*const anyopaque,

    const VTIndex = struct {
        const getFont: usize = 3 + abi.dtor_adjust;
    };

    pub fn getFont(self: *IScheme, name: [*:0]const u8, proportional: bool) c_ulong {
        const _getFont: *const fn (this: *anyopaque, name: [*:0]const u8, proportional: bool) callconv(VCallConv) c_ulong = @ptrCast(self._vt[VTIndex.getFont]);
        return _getFont(self, name, proportional);
    }
};

pub var imatsystem: *IMatSystemSurface = undefined;
pub var ienginevgui: *IEngineVGui = undefined;
var ipanel: *IPanel = undefined;
var ischeme_mgr: *ISchemeManager = undefined;
pub var ischeme: *IScheme = undefined;

pub fn getEngineVGui() ?*IEngineVGui {
    return @ptrCast(interfaces.engineFactory("VEngineVGui001", null));
}

fn init() bool {
    const imatsystem_info = interfaces.create(interfaces.engineFactory, "MatSystemSurface", .{ 6, 8 }) orelse {
        core.log.err("Failed to get IMatSystem interface", .{});
        return false;
    };
    imatsystem = @ptrCast(imatsystem_info.interface);
    switch (imatsystem_info.version) {
        6 => {
            IMatSystemSurface.VTIndex.getScreenSize = 37;
            IMatSystemSurface.VTIndex.getFontTall = 67;
            IMatSystemSurface.VTIndex.getTextSize = 72;
            IMatSystemSurface.VTIndex.drawOutlinedCircle = 96;
            IMatSystemSurface.VTIndex.drawColoredText = 138;
            IPanel.VTIndex.getName = 35 + abi.dtor_adjust;
            IPanel.VTIndex.paintTraverse = 40 + abi.dtor_adjust;
        },
        8 => {
            IMatSystemSurface.VTIndex.getScreenSize = 38;
            IMatSystemSurface.VTIndex.getFontTall = 69;
            IMatSystemSurface.VTIndex.getTextSize = 75;
            IMatSystemSurface.VTIndex.drawOutlinedCircle = 99;
            IMatSystemSurface.VTIndex.drawColoredText = 162;
            IPanel.VTIndex.getName = 36 + abi.dtor_adjust;
            IPanel.VTIndex.paintTraverse = 41 + abi.dtor_adjust;
        },
        else => unreachable,
    }

    ischeme_mgr = @ptrCast(interfaces.engineFactory("VGUI_Scheme010", null) orelse {
        core.log.err("Failed to get ISchemeManager interface", .{});
        return false;
    });

    ischeme = ischeme_mgr.getIScheme(ischeme_mgr.getDefaultScheme()) orelse {
        core.log.err("Failed to get IScheme", .{});
        return false;
    };

    ienginevgui = getEngineVGui() orelse {
        core.log.err("Failed to get IEngineVgui interface", .{});
        return false;
    };

    ipanel = @ptrCast(interfaces.engineFactory("VGUI_Panel009", null) orelse {
        core.log.err("Failed to get IPanel interface", .{});
        return false;
    });

    IPanel.origPaintTraverse = core.hook_manager.hookVMT(
        IPanel.PaintTraverseFunc,
        ipanel._vt,
        IPanel.VTIndex.paintTraverse,
        IPanel.hookedPaintTraverse,
    ) catch {
        core.log.err("Failed to hook PaintTraverse", .{});
        return false;
    };
    event.paint.works = true;

    return true;
}

fn deinit() void {}
