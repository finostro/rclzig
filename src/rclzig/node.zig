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

const std = @import("std");
const rcl = @import("rcl.zig").rcl;

const Context = @import("context.zig").Context;
const ContextOptions = @import("context.zig").ContextOptions;
const RclAllocator = @import("allocator.zig").RclAllocator;
const fromRclError = @import("errors.zig").fromRclError;

pub const NodeOptions = struct {
    rcl_options: rcl.rcl_node_options_t,
    rcl_clock_type: rcl.rcl_clock_type_t,

    pub fn init(allocator: *RclAllocator) NodeOptions {
        var node_options = NodeOptions{
            .rcl_options = rcl.rcl_node_get_default_options(),
            .rcl_clock_type = rcl.RCL_ROS_TIME,
        };
        node_options.rcl_options.allocator = allocator.c_allocator;

        return node_options;
    }

    pub fn deinit(self: *NodeOptions) void {
        const fini_ret = rcl.rcl_node_options_fini(&self.rcl_options);
        if (fini_ret != rcl.RCL_RET_OK) {
            std.log.err("failed to finalize rcl_node_options_t ({})\n", .{fini_ret});
        }
    }
};

pub const Node = struct {
    rcl_node: rcl.rcl_node_t,
    name: []const u8,
    namespace: []const u8,
    rcl_clock: rcl.rcl_clock_t,

    pub fn init(name: []const u8, namespace: []const u8, context: *Context, options: NodeOptions) !Node {
        var node = Node{
            .rcl_node = rcl.rcl_get_zero_initialized_node(),
            .name = name,
            .namespace = namespace,
            .rcl_clock = undefined,
        };
        const init_ret = rcl.rcl_node_init(&node.rcl_node, @intFromPtr(node.name.ptr), @intFromPtr(node.namespace.ptr), &context.rcl_context, &options.rcl_options);
        if (init_ret != rcl.RCL_RET_OK) {
            return fromRclError(init_ret);
        }
        const init_clock_ret = rcl.rcl_clock_init(
            options.rcl_clock_type,
            @intFromPtr(&node.rcl_clock),
            @intFromPtr(&options.rcl_options.allocator),
        );
        if (init_clock_ret != rcl.RCL_RET_OK) {
            return fromRclError(init_ret);
        }
        return node;
    }

    pub fn deinit(self: *Node) void {
        const fini_ret = rcl.rcl_node_fini(&self.rcl_node);
        if (fini_ret != rcl.RCL_RET_OK) {
            std.log.err("failed to finalize rcl_node_t ({})\n", .{fini_ret});
        }
        const clock_fini_ret = rcl.rcl_clock_fini(&self.rcl_clock);
        if (clock_fini_ret != rcl.RCL_RET_OK) {
            std.log.err("failed to finalize rcl_clock_t ({})\n", .{clock_fini_ret});
        }
    }

    pub fn now(self: *Node) !rcl.rcl_time_point_value_t {
        var ret: rcl.rcl_time_point_value_t = undefined;
        const rcl_ret = rcl.rcl_clock_get_now(@intFromPtr(&self.rcl_clock), @intFromPtr(&ret));
        if (rcl_ret != rcl.RCL_RET_OK) {
            return fromRclError(rcl_ret);
        }
        return ret;
    }
};

test "check for memory leaks" {
    var rcl_allocator = try RclAllocator.init(std.testing.allocator);
    defer rcl_allocator.deinit();

    // Initialize Context
    const argv = [_][]const u8{};
    var context_options = try ContextOptions.init(rcl_allocator);
    defer context_options.deinit();
    var context = try Context.init(&argv, context_options);
    defer context.deinit();

    // Initialize Node
    var node_options = NodeOptions.init(rcl_allocator);
    defer node_options.deinit();
    const node_name: []const u8 = "bar";
    const node_namespace: []const u8 = "foo";
    var node = try Node.init(node_name, node_namespace, &context, node_options);
    defer node.deinit();

    // Shutdown Context
    try context.shutdown();
}
