const std = @import("std");
const obj = @import("object.zig");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const meta = std.meta;

const INITIAL_CAPACITY = 8;
pub const ValueError = error{
    InvalidType,
};

pub const ValueTag = enum {
    Number,
    Bool,
    Nil,
    Obj,
};

pub const Value = union(ValueTag) {
    Number: f64,
    Bool: bool,
    Nil,
    Obj: *obj.Obj,

    pub fn as(self: Value, comptime tag: ValueTag) ValueError!@FieldType(Value, @tagName(tag)) {
        if (!self.is(tag)) {
            return ValueError.InvalidType;
        }

        return @field(self, @tagName(tag));
    }

    pub fn is(self: Value, comptime tag: ValueTag) bool {
        return meta.activeTag(self) == tag;
    }
};

pub const ValueArray = struct {
    alloc: Allocator,
    values: ArrayList(Value),

    pub fn init(alloc: Allocator) !ValueArray {
        const values = try ArrayList(Value).initCapacity(alloc, INITIAL_CAPACITY);
        return ValueArray{ .alloc = alloc, .values = values };
    }

    pub fn write(self: *ValueArray, value: Value) !void {
        try self.values.append(self.alloc, value);
    }

    pub fn deinit(self: *ValueArray) void {
        self.values.deinit(self.alloc);
    }
};
