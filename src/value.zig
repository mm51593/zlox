var gpa = @import("std").heap.DebugAllocator(.{}){};
const alloc = gpa.allocator();

const INITIAL_CAPACITY = 8;
const ArrayList = @import("std").ArrayList(Value);

pub const Value = f64;
pub const ValueArray = struct {
    values: ArrayList,

    pub fn init() !ValueArray {
        const values = try ArrayList.initCapacity(alloc, INITIAL_CAPACITY);
        return ValueArray{ .values = values };
    }

    pub fn write(self: *ValueArray, value: Value) !void {
        try self.values.append(alloc, value);
    }

    pub fn free(self: *ValueArray) void {
        alloc.free(self.values);
    }
};
