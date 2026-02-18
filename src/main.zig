const std = @import("std");
const cnk = @import("chunk.zig");
const debug = @import("debug.zig");
const vm = @import("vm.zig");

const OpCode = @import("op_code.zig").OpCode;

const LINE_LENGTH: usize = 1024;
const FILE_SIZE: usize = 4096;

var gpa = std.heap.DebugAllocator(.{}){};
const alloc = gpa.allocator();

pub fn main() !void {
    var v_m = vm.Vm.init();

    const args = try std.process.argsAlloc(alloc);

    if (args.len == 1) {
        try repl(&v_m);
    } else if (args.len == 2) {
        try runFile(&v_m, args[1]);
    } else {
        std.log.err("Usage: zlox [filename]\n", .{});
    }

    v_m.free();
}

fn repl(v_m: *vm.Vm) !void {
    var buffer: [LINE_LENGTH]u8 = undefined;
    var reader = std.fs.File.stdin().reader(&buffer);
    const stdin = &reader.interface;

    while (true) {
        std.debug.print("> ", .{});
        const input = try stdin.takeDelimiter('\n');
        if (input) |line| {            
            _ = interpret(v_m, line);
        } else {
            break;
        }
    }
}

fn runFile(v_m: *vm.Vm, filename: []u8) !void {
    const file = try std.fs.cwd().openFile(filename, .{ .mode = .read_only });
    defer file.close();
    const size = (try file.stat()).size;

    const buffer = try std.fs.cwd().readFileAlloc(alloc, filename, size);

    _ = interpret(v_m, buffer);
}

fn interpret(v_m: *vm.Vm, line: []u8) vm.InterpretResult {
    return v_m.interpret(line);
}
