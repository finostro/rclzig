// Copyright 2021 Jacob Perron
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
const std = @import("std");

const rcl = @import("rcl.zig").rcl;

pub const RclAllocator = struct {
    c_allocator: rcl.rcl_allocator_t,
    zig_allocator: std.mem.Allocator,
    mem_map: *std.AutoHashMap(usize, usize),

    pub fn init(allocator: std.mem.Allocator) !*RclAllocator {
        var rcl_allocator = try allocator.create(RclAllocator);
        rcl_allocator.* = RclAllocator{
            .c_allocator = rcl.rcutils_get_zero_initialized_allocator(),
            .zig_allocator = allocator,
            .mem_map = blk: {
                const auto_hash_ptr = try allocator.create(std.AutoHashMap(usize, usize));
                auto_hash_ptr.* = std.AutoHashMap(usize, usize).init(allocator);
                break :blk auto_hash_ptr;
            },
        };

        rcl_allocator.c_allocator.state = @ptrCast(rcl_allocator);
        rcl_allocator.c_allocator.allocate = rclAllocate;
        rcl_allocator.c_allocator.deallocate = rclDeallocate;
        rcl_allocator.c_allocator.reallocate = rclReallocate;
        rcl_allocator.c_allocator.zero_allocate = rclZeroAllocate;
        return rcl_allocator;
    }

    pub fn deinit(self: *RclAllocator) void {
        self.mem_map.deinit();
        self.zig_allocator.destroy(self.mem_map);
        self.zig_allocator.destroy(self);
    }
};

fn rclAllocate(size: usize, state: ?*anyopaque) callconv(.C) ?*anyopaque {
    // var rcl_allocator: *RclAllocator = @alignCast(state_ptr);
    // Or without a packed struct:
    // var rcl_allocator = @intToPtr(*RclAllocator, @intFromPtr(state));
    var rcl_allocator = @as(*RclAllocator, @ptrCast(@alignCast(state.?)));
    const result = rcl_allocator.zig_allocator.alloc(u8, size) catch |err| {
        std.log.err("error allocating memory: {s}\n", .{@errorName(err)});
        return null;
    };
    rcl_allocator.mem_map.put(@intFromPtr(result.ptr), result.len) catch |err| {
        std.log.err("error updating memory map: {s}\n", .{@errorName(err)});
        rcl_allocator.zig_allocator.free(result);
        return null;
    };
    std.debug.print("allocator {any} allocated {any} bytes at {any}\n", .{ state, result.len, result.ptr });
    return result.ptr;
}

fn rclDeallocate(opt_c_pointer: ?*anyopaque, state: ?*anyopaque) callconv(.C) void {
    var rcl_allocator = @as(*RclAllocator, @ptrCast(@alignCast(state.?)));
    if (opt_c_pointer) |c_pointer| {
        var zig_pointer: [*]u8 = @ptrCast(c_pointer);
        // std.debug.print("deallocating at {}\n", .{@intFromPtr(c_pointer)});
        const opt_entry = rcl_allocator.mem_map.fetchRemove(@intFromPtr(c_pointer));
        if (opt_entry) |entry| {
            const size = entry.value;
            rcl_allocator.zig_allocator.free(zig_pointer[0..size]);
        } else {
            // unreachable, unless there's a bug in rcl/rmw
            // std.log.err("tried to deallocate at unknown address {}\n", .{@intFromPtr(c_pointer)});
            unreachable;
        }
    }
}

fn rclReallocate(opt_c_pointer: ?*anyopaque, size: usize, state: ?*anyopaque) callconv(.C) ?*anyopaque {
    var rcl_allocator = @as(*RclAllocator, @ptrCast(@alignCast(state.?)));
    std.debug.print("allocator {any} reallocating {any} bytes from {any}\n", .{ state, size, opt_c_pointer });
    if (opt_c_pointer) |c_pointer| {
        var zig_pointer: [*]u8 = @ptrCast(c_pointer);
        const opt_old_size = rcl_allocator.mem_map.get(@intFromPtr(c_pointer));
        if (opt_old_size) |old_size| {
            const result = rcl_allocator.zig_allocator.realloc(zig_pointer[0..old_size], size) catch |err| {
                std.log.err("error during realloc: {s}\n", .{@errorName(err)});
                return null;
            };
            rcl_allocator.mem_map.put(@intFromPtr(result.ptr), result.len) catch |err| {
                std.log.err("error updating memory map: {s}\n", .{@errorName(err)});
                rcl_allocator.zig_allocator.free(result);
                return null;
            };

            return result.ptr;
        } else {
            // unreachable, unless there's a bug in rcl
            // std.log.err("tried to reallocate at unknown address {}\n", .{@intFromPtr(c_pointer)});
            unreachable;
        }
    }
    return null;
}

fn rclZeroAllocate(numOfElements: usize, sizeOfElement: usize, state: ?*anyopaque) callconv(.C) ?*anyopaque {
    const numBytes: usize = numOfElements * sizeOfElement;
    const opt_result = rclAllocate(numBytes, state);
    if (opt_result) |result| {
        var ptr: [*]u8 = @ptrCast(result);
        const slice: []u8 = ptr[0..numBytes];
        @memset(slice, 0);
        return slice.ptr;
    }
    return null;
}

test "check for memory leaks" {
    var rcl_allocator = try RclAllocator.init(std.testing.allocator);
    defer rcl_allocator.deinit();
}
