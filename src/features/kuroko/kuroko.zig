const std = @import("std");

const Feature = @import("../Feature.zig");

const modules = @import("../../modules.zig");
const tier0 = modules.tier0;
const tier1 = modules.tier1;
const engine = modules.engine;

const kuroko = @import("kuroko");
const VM = kuroko.KrkVM;
const KrkValue = kuroko.KrkValue;
const KrkString = kuroko.KrkString;
const KrkInstance = kuroko.KrkInstance;
const StringBuilder = kuroko.StringBuilder;

const vkrk_console = @import("vkrk_console.zig");
const vkrk_game = @import("vkrk_game.zig");

pub var feature: Feature = .{
    .name = "kuroko",
    .shouldLoad = shouldLoad,
    .init = init,
    .deinit = deinit,
};

const krk_from_file = "<console>";

var krk_path: [*:0]const u8 = undefined;

var vkrk_interpret = tier1.ConCommand.init(.{
    .name = "vkrk_interpret",
    .help_string = "Runs the text as a Kuroko script.",
    .command_callback = vkrk_interpret_Fn,
});

fn printResult(result: KrkValue) void {
    var sb: StringBuilder = std.mem.zeroes(StringBuilder);
    if (!sb.pushStringFormat(" => %R", .{result.value})) {
        VM.dumpTraceback();
    } else {
        std.log.info("{s}", .{sb.toString()});
    }
    sb.discard();
}

fn vkrk_interpret_Fn(args: *const tier1.CCommand) callconv(.C) void {
    if (args.argc != 2) {
        std.log.info("vkrk_interpret <code>", .{});
        return;
    }

    const result = VM.interpret(args.argv[1], krk_from_file);
    if (!result.isNone()) {
        VM.getInstance().builtins.fields.attachNamedValue("_", result);
        printResult(result);
    }
    VM.resetStack();
}

var vkrk_run = tier1.ConCommand.init(.{
    .name = "vkrk_run",
    .help_string = "Runs a Kuroko script file.",
    .command_callback = vkrk_run_Fn,
});

fn vkrk_run_Fn(args: *const tier1.CCommand) callconv(.C) void {
    if (args.argc != 2 or args.args(1).len == 0) {
        std.log.info("vkrk_run <file>", .{});
        return;
    }

    const ext = ".krk";

    var path = std.ArrayList(u8).init(tier0.allocator);
    defer path.deinit();

    path.appendSlice(args.args(1)) catch return;
    if (std.fs.path.extension(path.items).len == 0) {
        path.appendSlice(ext) catch return;
    }

    if (!std.fs.path.isAbsolute(path.items)) {
        path.insertSlice(0, std.mem.span(krk_path)) catch return;
    }

    path.append(0) catch return;

    _ = VM.runFile(@ptrCast(path.items.ptr), krk_from_file);
    VM.resetStack();
}

var krk_reset = tier1.ConCommand.init(.{
    .name = "vkrk_reset",
    .help_string = "Resets the Kuroko VM.",
    .command_callback = krk_reset_Fn,
});

fn krk_reset_Fn(args: *const tier1.CCommand) callconv(.C) void {
    _ = args;
    resetKrkVM();
}

fn resetKrkVM() void {
    vkrk_console.destroyDynCommands();

    VM.deinit();
    initKrkVM();
}

fn initKrkVM() void {
    VM.init(.{});

    initVkurokoModule();

    _ = VM.startModule("__main__");

    VM.push(VM.getInstance().system.asValue().getAttribute("module_paths"));
    VM.push(VM.peek(0).getAttribute("insert"));
    VM.push(KrkValue.intValue(0));

    VM.push(KrkString.copyString(krk_path).asValue());
    _ = VM.callStack(2); // module_paths.inset(0, krk_path)
    _ = VM.pop();
}

pub fn initVkurokoModule() void {
    const module_name = "vkuroko";
    const module = VM.startModule(module_name);

    module.setDoc("@brief Source Engine module.");

    vkrk_console.bindAttributes(module);
    vkrk_game.bindAttributes(module);

    _ = VM.interpret(
        \\class _Config:
        \\  '''@brief Object for finding ConVar and ConCommand'''
        \\
        \\  def __getattr__(self, name):
        \\    let cvar = find_var(name)
        \\    if cvar is not None:
        \\      return cvar
        \\    return find_command(name)
        \\
        \\let cfg = _Config()
    , module_name);
}

fn shouldLoad() bool {
    return true;
}

var path_buf = std.mem.zeroes([256]u8);

var stdout: *std.c.FILE = undefined;
var stderr: *std.c.FILE = undefined;

fn init() bool {
    krk_path = @ptrCast((std.fmt.bufPrint(
        &path_buf,
        "{s}\\kuroko\\",
        .{engine.client.getGameDirectory()},
    ) catch return false).ptr);

    stdout = kuroko.krk_getStdout();
    stderr = kuroko.krk_getStderr();

    initKrkVM();

    vkrk_interpret.register();
    vkrk_run.register();
    krk_reset.register();

    return true;
}

fn deinit() void {
    VM.deinit();
}

export fn krk_fwrite(ptr: [*]const u8, size_of_type: usize, item_count: usize, stream: *std.c.FILE) usize {
    if (@intFromPtr(stdout) == @intFromPtr(stream)) {
        tier0.msg("%s", ptr);
        return size_of_type * item_count;
    }

    if (@intFromPtr(stderr) == @intFromPtr(stream)) {
        tier0.warning("%s", ptr);
        return size_of_type * item_count;
    }

    return std.c.fwrite(ptr, size_of_type, item_count, stream);
}

export fn krk_fflush(stream: *std.c.FILE) c_int {
    _ = stream;
    return 0;
}
