const std = @import("std");

const tier0 = @import("tier0.zig");
const interfaces = @import("../interfaces.zig");
const core = @import("../core.zig");

const Module = @import("Module.zig");

const Color = @import("sdk").Color;

const Thiscall = std.builtin.CallingConvention.Thiscall;

pub var module: Module = .{
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
        const _setEnabled: *const fn (this: *anyopaque, panel: u32) callconv(.Thiscall) [*:0]const u8 = @ptrCast(self._vt[VTIndex.getName]);
        return _setEnabled(self, panel);
    }

    fn hookedPaintTraverse(this: *IPanel, vgui_panel: u32, force_repaint: bool, allow_force: bool) callconv(Thiscall) void {
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
            core.emitPaint();
        }
    }
};

const IEngineVGui = extern struct {
    _vt: *align(@alignOf(*anyopaque)) const anyopaque = undefined,

    const VTable = extern struct {
        destruct: *const anyopaque,
        getPanel: *const fn (this: *anyopaque, panel_type: c_int) callconv(Thiscall) c_uint,
        isGameUIVisible: *const fn (this: *anyopaque) callconv(Thiscall) bool,
    };

    fn vt(self: *IEngineVGui) *const VTable {
        return @ptrCast(self._vt);
    }

    pub fn isGameUIVisible(self: *IEngineVGui) bool {
        return self.vt().isGameUIVisible(self);
    }
};

const IMatSystemSurface = extern struct {
    _vt: [*]*const anyopaque,

    const VTIndex = struct {
        const drawSetColor: usize = 10;
        const drawFilledRect: usize = 12;
        const drawOutlinedRect: usize = 14;
        const drawLine: usize = 15;
        const drawSetTextFont: usize = 17;
        const drawSetTextColor: usize = 18;
        const drawSetTextPos: usize = 20;
        const drawPrintText: usize = 22;
        var getScreenSize: usize = undefined;
        var getFontTall: usize = undefined;
        var getTextSize: usize = undefined;
    };

    pub fn drawSetColor(self: *IMatSystemSurface, color: Color) void {
        const _drawSetColor: *const fn (this: *anyopaque, color: Color) callconv(Thiscall) void = @ptrCast(self._vt[VTIndex.drawSetColor]);
        _drawSetColor(self, color);
    }

    pub fn drawFilledRect(self: *IMatSystemSurface, x0: i32, y0: i32, x1: i32, y1: i32) void {
        const _drawFilledRect: *const fn (this: *anyopaque, x0: c_int, y0: c_int, x1: c_int, y1: c_int) callconv(Thiscall) void = @ptrCast(self._vt[VTIndex.drawFilledRect]);
        _drawFilledRect(self, x0, y0, x1, y1);
    }

    pub fn drawOutlinedRect(self: *IMatSystemSurface, x0: i32, y0: i32, x1: i32, y1: i32) void {
        const _drawOutlinedRect: *const fn (this: *anyopaque, x0: c_int, y0: c_int, x1: c_int, y1: c_int) callconv(Thiscall) void = @ptrCast(self._vt[VTIndex.drawOutlinedRect]);
        _drawOutlinedRect(self, x0, y0, x1, y1);
    }

    pub fn drawLine(self: *IMatSystemSurface, x0: i32, y0: i32, x1: i32, y1: i32) void {
        const _drawLine: *const fn (this: *anyopaque, x0: c_int, y0: c_int, x1: c_int, y1: c_int) callconv(Thiscall) void = @ptrCast(self._vt[VTIndex.drawLine]);
        _drawLine(self, x0, y0, x1, y1);
    }

    pub fn drawSetTextFont(self: *IMatSystemSurface, font: c_ulong) void {
        const _drawSetTextFont: *const fn (this: *anyopaque, font: c_ulong) callconv(Thiscall) void = @ptrCast(self._vt[VTIndex.drawSetTextFont]);
        _drawSetTextFont(self, font);
    }

    pub fn drawSetTextColor(self: *IMatSystemSurface, color: Color) void {
        const _drawSetTextColor: *const fn (this: *anyopaque, color: Color) callconv(Thiscall) void = @ptrCast(self._vt[VTIndex.drawSetTextColor]);
        _drawSetTextColor(self, color);
    }

    pub fn drawSetTextPos(self: *IMatSystemSurface, x: i32, y: i32) void {
        const _drawSetTextPos: *const fn (this: *anyopaque, x: c_int, y: c_int) callconv(Thiscall) void = @ptrCast(self._vt[VTIndex.drawSetTextPos]);
        _drawSetTextPos(self, x, y);
    }

    pub fn drawPrintText(self: *IMatSystemSurface, comptime fmt: []const u8, args: anytype) void {
        const _drawPrintText: *const fn (this: *anyopaque, text: [*]u16, text_len: c_int, draw_type: c_int) callconv(Thiscall) void = @ptrCast(self._vt[VTIndex.drawPrintText]);

        const text = std.fmt.allocPrint(tier0.allocator, fmt, args) catch {
            return;
        };

        defer tier0.allocator.free(text);

        const utf16_len = std.unicode.calcUtf16LeLen(text) catch {
            return;
        };
        const utf16_buf = tier0.allocator.alloc(u16, utf16_len) catch {
            return;
        };
        defer tier0.allocator.free(utf16_buf);

        _ = std.unicode.utf8ToUtf16Le(utf16_buf, text) catch {
            return;
        };

        _drawPrintText(self, utf16_buf.ptr, @intCast(utf16_buf.len), 0);
    }

    pub fn getScreenSize(self: *IMatSystemSurface) struct { wide: i32, tall: i32 } {
        var wide: c_int = undefined;
        var tall: c_int = undefined;

        const _getScreenSize: *const fn (this: *anyopaque, wide: *c_int, tall: *c_int) callconv(Thiscall) void = @ptrCast(self._vt[VTIndex.getScreenSize]);
        _getScreenSize(self, &wide, &tall);

        return .{
            .wide = wide,
            .tall = tall,
        };
    }

    pub fn getFontTall(self: *IMatSystemSurface, font: c_ulong) c_int {
        const _getFontTall: *const fn (this: *anyopaque, font: c_ulong) callconv(Thiscall) c_int = @ptrCast(self._vt[VTIndex.getFontTall]);
        return _getFontTall(self, font);
    }
};

const ISchemeManager = extern struct {
    _vt: [*]*const anyopaque,

    const VTIndex = struct {
        const getDefaultScheme: usize = 4;
        const getIScheme: usize = 8;
    };

    fn getDefaultScheme(self: *ISchemeManager) c_ulong {
        const _getDefaultScheme: *const fn (this: *anyopaque) callconv(Thiscall) c_ulong = @ptrCast(self._vt[VTIndex.getDefaultScheme]);
        return _getDefaultScheme(self);
    }

    fn getIScheme(self: *ISchemeManager, font: c_ulong) ?*IScheme {
        const _getIScheme: *const fn (this: *anyopaque, font: c_ulong) callconv(Thiscall) ?*IScheme = @ptrCast(self._vt[VTIndex.getIScheme]);
        return _getIScheme(self, font);
    }
};

const IScheme = extern struct {
    _vt: [*]*const anyopaque,

    const VTIndex = struct {
        const getFont: usize = 3;
    };

    pub fn getFont(self: *IScheme, name: [*:0]const u8, proportional: bool) c_ulong {
        const _getFont: *const fn (this: *anyopaque, name: [*:0]const u8, proportional: bool) callconv(Thiscall) c_ulong = @ptrCast(self._vt[VTIndex.getFont]);
        return _getFont(self, name, proportional);
    }
};

pub var imatsystem: *IMatSystemSurface = undefined;
pub var ienginevgui: *IEngineVGui = undefined;
var ipanel: *IPanel = undefined;
var ischeme_mgr: *ISchemeManager = undefined;
pub var ischeme: *IScheme = undefined;

fn init() void {
    module.loaded = false;

    const imatsystem_info = interfaces.create(interfaces.engineFactory, "MatSystemSurface", .{ 6, 8 }) orelse {
        std.log.err("Failed to get IMatSystem interface", .{});
        return;
    };
    imatsystem = @ptrCast(imatsystem_info.interface);
    switch (imatsystem_info.version) {
        6 => {
            IMatSystemSurface.VTIndex.getScreenSize = 37;
            IMatSystemSurface.VTIndex.getFontTall = 67;
            IMatSystemSurface.VTIndex.getTextSize = 72;
            IPanel.VTIndex.getName = 35;
            IPanel.VTIndex.paintTraverse = 40;
        },
        8 => {
            IMatSystemSurface.VTIndex.getScreenSize = 38;
            IMatSystemSurface.VTIndex.getFontTall = 69;
            IMatSystemSurface.VTIndex.getTextSize = 75;
            IPanel.VTIndex.getName = 36;
            IPanel.VTIndex.paintTraverse = 41;
        },
        else => unreachable,
    }

    ischeme_mgr = @ptrCast(interfaces.engineFactory("VGUI_Scheme010", null) orelse {
        std.log.err("Failed to get ISchemeManager interface", .{});
        return;
    });

    ischeme = ischeme_mgr.getIScheme(ischeme_mgr.getDefaultScheme()) orelse {
        std.log.err("Failed to get IScheme", .{});
        return;
    };

    ienginevgui = @ptrCast(interfaces.engineFactory("VEngineVGui001", null) orelse {
        std.log.err("Failed to get IEngineVgui interface", .{});
        return;
    });

    ipanel = @ptrCast(interfaces.engineFactory("VGUI_Panel009", null) orelse {
        std.log.err("Failed to get IPanel interface", .{});
        return;
    });

    IPanel.origPaintTraverse = core.hook_manager.hookVMT(
        IPanel.PaintTraverseFunc,
        ipanel._vt,
        IPanel.VTIndex.paintTraverse,
        IPanel.hookedPaintTraverse,
    ) catch {
        std.log.err("Failed to hook PaintTraverse", .{});
        return;
    };

    module.loaded = true;
}

fn deinit() void {}
