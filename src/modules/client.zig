const std = @import("std");

const interfaces = @import("../interfaces.zig");
const core = @import("../core.zig");
const event = @import("../event.zig");

const Module = @import("Module.zig");

const zhook = @import("zhook");

const sdk = @import("sdk");
const Vector = sdk.Vector;
const QAngle = sdk.QAngle;
const CUserCmd = sdk.CUserCmd;

pub var module: Module = .{
    .name = "client",
    .init = init,
    .deinit = deinit,
};

const IClientEntityList = extern struct {
    _vt: [*]*const anyopaque,

    const VTIndex = struct {
        const getClientEntity = 3;
        const getHighestEntityIndex = 6;
    };

    pub fn getClientEntity(self: *IClientEntityList, index: c_int) ?*anyopaque {
        const _getClientEntity: *const fn (this: *anyopaque, index: c_int) callconv(.Thiscall) ?*anyopaque = @ptrCast(self._vt[VTIndex.getClientEntity]);
        return _getClientEntity(self, index);
    }

    pub fn getHighestEntityIndex(self: *IClientEntityList) c_int {
        const _getHighestEntityIndex: *const fn (this: *anyopaque) callconv(.Thiscall) c_int = @ptrCast(self._vt[VTIndex.getHighestEntityIndex]);
        return _getHighestEntityIndex(self);
    }
};

const IBaseClientDLL = extern struct {
    _vt: [*]*const anyopaque,

    const VTIndex = struct {
        var decodeUserCmdFromBuffer: usize = undefined;
    };

    fn findIInput(self: *IBaseClientDLL) ?*IInput {
        const addr: [*]const u8 = @ptrCast(self._vt[VTIndex.decodeUserCmdFromBuffer]);
        var p = addr;
        while (@intFromPtr(p) - @intFromPtr(addr) < 32) : (p = p + (zhook.x86.x86_len(p) catch {
            return null;
        })) {
            if (p[0] == zhook.x86.Opcode.Op1.movrmw and p[1] == zhook.x86.modrm(0, 1, 5)) {
                return zhook.mem.loadValue(**IInput, p + 2).*;
            }
        }
        return null;
    }
};

const IInput = extern struct {
    _vt: [*]*const anyopaque,

    const VTIndex = struct {
        const createMove = 3;
        const decodeUserCmdFromBuffer = 7;
        const getUserCmd = 8;
    };

    const CreateMoveFunc = *const @TypeOf(hookedCreateMove);
    var origCreateMove: CreateMoveFunc = undefined;

    fn hookedCreateMove(self: *IInput, sequence_number: c_int, input_sample_frametime: f32, active: bool) callconv(.Thiscall) void {
        origCreateMove(self, sequence_number, input_sample_frametime, active);
        event.create_move.emit(.{self.getUserCmd(sequence_number)});
    }

    const DecodeUserCmdFromBufferFunc = *const @TypeOf(hookedDecodeUserCmdFromBuffer);
    var origDecodeUserCmdFromBuffer: DecodeUserCmdFromBufferFunc = undefined;

    fn hookedDecodeUserCmdFromBuffer(self: *IInput, buf: *anyopaque, sequence_number: c_int) callconv(.Thiscall) void {
        origDecodeUserCmdFromBuffer(self, buf, sequence_number);
        event.decode_usercmd_from_buffer.emit(.{self.getUserCmd(sequence_number)});
    }

    fn getUserCmd(self: *IInput, sequence_number: c_int) callconv(.Thiscall) *CUserCmd {
        const _getUserCmd: *const fn (this: *anyopaque, sequence_number: c_int) callconv(.Thiscall) *CUserCmd = @ptrCast(self._vt[VTIndex.getUserCmd]);
        return _getUserCmd(self, sequence_number);
    }
};

pub var entlist: *IClientEntityList = undefined;
pub var vclient: *IBaseClientDLL = undefined;
pub var iinput: *IInput = undefined;

const GetDamagePosition_patterns = zhook.mem.makePatterns(.{
    "83 EC 18 E8 ?? ?? ?? ?? E8 ?? ?? ?? ?? 8B 08 89 4C 24 0C 8B 50 04 6A 00 89 54 24 14 8B 40 08 6A 00 8D 4C 24 08 51 8D 54 24 18 52 89 44 24 24",
    "55 8B EC 83 EC ?? 56 8B F1 E8 ?? ?? ?? ?? E8 ?? ?? ?? ??",
});

pub var mainViewOrigin: *const fn () callconv(.C) *const Vector = undefined;
pub var mainViewAngles: *const fn () callconv(.C) *const QAngle = undefined;

fn init() bool {
    const clientFactory = interfaces.getFactory("client.dll") orelse {
        std.log.err("Failed to get client interface factory", .{});
        return false;
    };

    entlist = @ptrCast(clientFactory("VClientEntityList003", null) orelse {
        std.log.err("Failed to get IClientEntityList interface", .{});
        return false;
    });

    const vclient_info = interfaces.create(clientFactory, "VClient", .{ 15, 17 }) orelse {
        std.log.err("Failed to get VClient interface", .{});
        return false;
    };
    vclient = @ptrCast(vclient_info.interface);
    switch (vclient_info.version) {
        15 => {
            IBaseClientDLL.VTIndex.decodeUserCmdFromBuffer = 22;
        },
        17 => {
            IBaseClientDLL.VTIndex.decodeUserCmdFromBuffer = 25;
        },
        else => unreachable,
    }

    iinput = vclient.findIInput() orelse {
        std.log.err("Failed to find IInput interface", .{});
        return false;
    };

    IInput.origCreateMove = core.hook_manager.hookVMT(
        IInput.CreateMoveFunc,
        iinput._vt,
        IInput.VTIndex.createMove,
        IInput.hookedCreateMove,
    ) catch {
        std.log.err("Failed to hook CreateMove", .{});
        return false;
    };
    event.create_move.works = true;

    IInput.origDecodeUserCmdFromBuffer = core.hook_manager.hookVMT(
        IInput.DecodeUserCmdFromBufferFunc,
        iinput._vt,
        IInput.VTIndex.decodeUserCmdFromBuffer,
        IInput.hookedDecodeUserCmdFromBuffer,
    ) catch {
        std.log.err("Failed to hook DecodeUserCmdFromBuffer", .{});
        return false;
    };
    event.decode_usercmd_from_buffer.works = true;

    const client = zhook.mem.getModule("client") orelse return false;
    const GetDamagePosition_match = zhook.mem.scanUniquePatterns(client, GetDamagePosition_patterns) orelse {
        std.log.err("Failed to find CHudDamageIndicator::GetDamagePosition", .{});
        return false;
    };

    switch (GetDamagePosition_match.index) {
        0 => {
            mainViewOrigin = @ptrCast(@as(*u8, @ptrFromInt(@intFromPtr(GetDamagePosition_match.ptr + 8) +% zhook.mem.loadValue(u32, GetDamagePosition_match.ptr + 4))));
            mainViewAngles = @ptrCast(@as(*u8, @ptrFromInt(@intFromPtr(GetDamagePosition_match.ptr + 13) +% zhook.mem.loadValue(u32, GetDamagePosition_match.ptr + 9))));
        },
        1 => {
            mainViewOrigin = @ptrCast(@as(*u8, @ptrFromInt(@intFromPtr(GetDamagePosition_match.ptr + 14) +% zhook.mem.loadValue(u32, GetDamagePosition_match.ptr + 10))));
            mainViewAngles = @ptrCast(@as(*u8, @ptrFromInt(@intFromPtr(GetDamagePosition_match.ptr + 19) +% zhook.mem.loadValue(u32, GetDamagePosition_match.ptr + 15))));
        },
        else => unreachable,
    }

    return true;
}

fn deinit() void {}
