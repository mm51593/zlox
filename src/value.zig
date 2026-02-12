const mem = @import("memory.zig");

pub const Value = f64;

var gpa = @import("std").heap.DebugAllocator(.{}){};
const alloc = gpa.allocator();

const INITIAL_CAPACITY = 8;

pub const ValueArray = struct {
    count: usize,
    values: []Value,

    pub fn init() !ValueArray {
        const block = try alloc.alloc(Value, INITIAL_CAPACITY);
        return ValueArray{ .count = 0, .values = block };
    }

    pub fn write(self: *ValueArray, value: Value) !void {
        self.values = try mem.ensureCapacity(Value, self.values, self.count, alloc);

        self.values[self.count] = value;
        self.count += 1;
    }

    pub fn free(self: *ValueArray) void {
        self.count = 0;
        alloc.free(self.values);
    }
};
