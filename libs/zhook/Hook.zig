const std = @import("std");
const builtin = @import("builtin");

const x86 = @import("x86.zig");
const utils = @import("utils.zig");

const loadValue = @import("mem.zig").loadValue;

const Hook = @This();

const HookType = enum {
    vmt,
    detour,
};

const Rel32Patch = struct {
    offset: u32, // offset into the trampoline
    dest: u32, // absolute address rel32 points to
    orig: u32, // original data in the instruction
};

// Windows doesn't use PIC
const PICPatch = switch (builtin.os.tag) {
    .linux => struct {
        offset: u32, // offset into the original function
        orig: u32, // original data in the instruction
    },
    .windows => void,
    else => @compileError("Unsupported OS"),
};

const HookData = union(HookType) {
    const HookVMTResult = struct {
        vt: [*]*const anyopaque,
        index: u32,
    };

    const HookDetourResult = struct {
        func: [*]u8,
        trampoline: []u8,
        rel32_patch: ?Rel32Patch = null,
        pic_patch: ?PICPatch = null,
    };

    vmt: HookVMTResult,
    detour: HookDetourResult,
};

orig: ?*const anyopaque,
data: HookData,

pub fn hookVMT(vt: [*]*const anyopaque, index: usize, target: *const anyopaque) !Hook {
    const orig: *const anyopaque = vt[index];
    const entry_ptr: [*]u8 = @ptrCast(vt + index);

    const bytes = std.mem.toBytes(target);
    try utils.patchCode(entry_ptr, &bytes, 0b001); // restore to read-only

    return Hook{
        .orig = orig,
        .data = .{
            .vmt = .{
                .vt = vt,
                .index = index,
            },
        },
    };
}

// Trampoline memory must have rwx permissions
pub fn hookDetour(func: *anyopaque, target: *const anyopaque, trampoline: []u8) !Hook {
    var mem: [*]u8 = @ptrCast(func);

    // Hook the underlying thing if the function jmp immediately.
    while (mem[0] == x86.Opcode.Op1.jmpiw) {
        const offset = loadValue(u32, mem + 1);
        mem = @ptrFromInt(@intFromPtr(mem + 5) +% offset);
    }

    var rel32_patch: ?Rel32Patch = null;
    var pic_patch: ?PICPatch = null;

    var len: usize = 0;
    while (true) : (len += try x86.x86_len(mem + len)) {
        if (len >= 5) break;

        // No checks for rel16 at all. I don't think we will encounter them.
        const op0 = mem[len];
        switch (op0) {
            x86.Opcode.Op1.jmpi8,
            x86.Opcode.Op1.jcxz,
            x86.Opcode.Op1.jo,
            x86.Opcode.Op1.jno,
            x86.Opcode.Op1.jb,
            x86.Opcode.Op1.jnb,
            x86.Opcode.Op1.jz,
            x86.Opcode.Op1.jnz,
            x86.Opcode.Op1.jna,
            x86.Opcode.Op1.ja,
            x86.Opcode.Op1.js,
            x86.Opcode.Op1.jns,
            x86.Opcode.Op1.jp,
            x86.Opcode.Op1.jnp,
            x86.Opcode.Op1.jl,
            x86.Opcode.Op1.jnl,
            x86.Opcode.Op1.jng,
            x86.Opcode.Op1.jg,
            => {
                // TODO: Make it rel32 jump in the trampoline
                return error.BadInstruction;
            },

            x86.Opcode.Op1.jmpiw,
            x86.Opcode.Op1.call,
            => {
                const offset = loadValue(u32, mem + len + 1);
                rel32_patch = .{
                    .offset = len + 1,
                    .dest = @intFromPtr(mem + len + 5) +% offset,
                    .orig = offset,
                };

                if (op0 == x86.Opcode.Op1.call and builtin.os.tag == .linux) {
                    // Look for PIC pattern:
                    // call __i686.get_pc_thunk.reg
                    // add reg, imm32
                    if (utils.matchPIC(mem + len)) |off| {
                        const imm32 = loadValue(u32, mem + len + off);
                        pic_patch = .{
                            .offset = len + off,
                            .orig = imm32,
                        };
                    }
                }
            },

            x86.Opcode.op2_byte => {
                const op1 = mem[len + 1];
                switch (op1) {
                    x86.Opcode.Op2.joii,
                    x86.Opcode.Op2.jnoii,
                    x86.Opcode.Op2.jbii,
                    x86.Opcode.Op2.jnbii,
                    x86.Opcode.Op2.jzii,
                    x86.Opcode.Op2.jnzii,
                    x86.Opcode.Op2.jnaii,
                    x86.Opcode.Op2.jaii,
                    x86.Opcode.Op2.jsii,
                    x86.Opcode.Op2.jnsii,
                    x86.Opcode.Op2.jpii,
                    x86.Opcode.Op2.jnpii,
                    x86.Opcode.Op2.jlii,
                    x86.Opcode.Op2.jnlii,
                    x86.Opcode.Op2.jngii,
                    x86.Opcode.Op2.jgii,
                    => {
                        const offset = loadValue(u32, mem + len + 2);
                        rel32_patch = .{
                            .offset = len + 2,
                            .dest = @intFromPtr(mem + len + 6) +% offset,
                            .orig = offset,
                        };
                    },
                    else => {},
                }
            },
            else => {},
        }
    }

    const trampoline_size = len + 5;
    if (trampoline.len < trampoline_size) {
        return error.OutOfTrampoline;
    }

    @memcpy(trampoline[0..len], mem);
    trampoline[len] = x86.Opcode.Op1.jmpiw;
    const jmp1_offset: *align(1) u32 = @ptrCast(trampoline.ptr + len + 1);
    jmp1_offset.* = @intFromPtr(mem + len) -% @intFromPtr(trampoline.ptr + len + 5);

    if (rel32_patch) |r| {
        const rel_patch: *align(1) u32 = @ptrCast(trampoline.ptr + r.offset);
        rel_patch.* = r.dest -% (@intFromPtr(trampoline.ptr + r.offset + 4));
    }

    var detour: [5]u8 = undefined;
    detour[0] = x86.Opcode.Op1.jmpiw;
    const jmp2_offset: *align(1) u32 = @ptrCast(&detour[1]);
    jmp2_offset.* = @intFromPtr(target) -% @intFromPtr(mem + 5);

    try utils.patchCode(mem, detour[0..], 0b101);

    if (builtin.os.tag == .linux) {
        if (pic_patch) |p| {
            const delta: u32 = @intFromPtr(trampoline.ptr) -% @intFromPtr(mem);
            const new_value: u32 = p.orig -% delta;

            const bytes = std.mem.toBytes(new_value);
            try utils.patchCode(mem + p.offset, &bytes, 0b101);
        }
    }

    return Hook{
        .orig = trampoline.ptr,
        .data = .{ .detour = .{
            .func = mem,
            .trampoline = trampoline[0..trampoline_size],
            .rel32_patch = rel32_patch,
            .pic_patch = pic_patch,
        } },
    };
}

pub fn unhook(self: *Hook) !void {
    const orig = self.orig orelse return;
    switch (self.data) {
        .vmt => |v| {
            const entry_ptr: [*]u8 = @ptrCast(v.vt + v.index);
            const bytes = std.mem.toBytes(orig);
            try utils.patchCode(entry_ptr, &bytes, 0b001); // restore to read-only
        },
        .detour => |v| {
            if (v.rel32_patch) |r| {
                const orig_patch: *align(1) u32 = @ptrCast(v.trampoline.ptr + r.offset);
                orig_patch.* = r.orig;
            }
            try utils.patchCode(v.func, v.trampoline[0 .. v.trampoline.len - 5], 0b101);
            if (builtin.os.tag == .linux) {
                if (v.pic_patch) |p| {
                    const bytes = std.mem.toBytes(p.orig);
                    try utils.patchCode(v.func + p.offset, &bytes, 0b101);
                }
            }
        },
    }
    self.orig = null;
}
