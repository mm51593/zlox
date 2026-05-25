const std = @import("std");
const cnk = @import("chunk.zig");
const debug = @import("debug.zig");
const Scanner = @import("scanner.zig").Scanner;
const Parser = @import("parser.zig").Parser;
const Vm = @import("vm.zig").Vm;
const ObjectList = @import("object.zig").ObjectList;

const OpCode = @import("op_code.zig").OpCode;

const LINE_LENGTH: usize = 1024;
const FILE_SIZE: usize = 4096;

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;
    const args = try init.minimal.args.toSlice(alloc);
    const io = init.io;

    if (args.len == 1) {
        try repl(alloc, io);
    } else if (args.len == 2) {
        try runFile(args[2], alloc, io);
    } else {
        std.log.err("Usage: zlox [filename]\n", .{});
    }
}

fn repl(alloc: std.mem.Allocator, io: std.Io) !void {
    var buffer: [LINE_LENGTH]u8 = undefined;
    var reader = std.Io.File.stdin().reader(io, &buffer);
    const stdin = &reader.interface;

    while (true) {
        std.debug.print("> ", .{});
        const input = try stdin.takeDelimiter('\n');
        if (input) |line| {
            try interpret(line, alloc);
        } else {
            break;
        }
    }
}

fn runFile(filename: []const u8, alloc: std.mem.Allocator, io: std.Io) !void {
    const buffer = try std.Io.Dir.cwd().readFileAlloc(io, filename, alloc, .unlimited);
    defer alloc.free(buffer);

    try interpret(buffer, alloc);
}

fn interpret(line: []u8, alloc: std.mem.Allocator) !void {
    const scanner = Scanner.init(line);
    const obj_list = ObjectList.init();
    var parser = try Parser.init(alloc, obj_list);
    const chunk = try parser.compile(alloc, scanner);
    if (chunk) |valid_chunk| {
        var vm = Vm.init(alloc, obj_list);
        vm.interpret(valid_chunk) catch |err|
            std.debug.print("Runtime error: {}\n", .{err});
    } else {
        for (parser.diagnostics.items) |diag| {
            std.debug.print("Line {}: syntax error: {s}\n", .{ diag.token.line, @tagName(diag.error_type) });
        }
    }

    parser.deinit();
}
