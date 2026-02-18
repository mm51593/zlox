const std = @import("std");

pub fn ensureCapacity(comptime T: type, array: []u8, count: usize, alloc: std.mem.Allocator) ![]u8 {
    var newArray = array;
    while (array.len < count + @sizeOf(T)) {
        const newCap = growCapacity(array.len);
        newArray = try alloc.realloc(array, newCap);
    }

    return newArray;
}

fn growCapacity(capacity: usize) usize {
    if (capacity < 8) {
        return 8;
    }

    return capacity * 2;
}

fn reallocateArray(comptime T: type, ptr: []T, new_size: usize, alloc: std.mem.Allocator) ![]T {
    return try alloc.realloc(ptr, new_size);
}
