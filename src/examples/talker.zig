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

const rcl = @import("rclzig");

pub const c = @cImport({
    @cInclude("std_msgs/msg/string.h");
    @cInclude("std_msgs/msg/float32_multi_array.h");
    @cInclude("rcutils/allocator.h");
});

const StringMsg = rcl.msg.Msg(c, "std_msgs", "msg", "String");
const MultiArrayMsg = rcl.msg.Msg(c, "std_msgs", "msg", "Float32MultiArray");

fn setString(msg: *StringMsg, string: []const u8) bool {
    std.debug.print("setString\n", .{});
    std.debug.print("to : {s}\n ", .{string});
    std.debug.print("orig : {s}  {d}  cap {d}\n", .{ msg.rcl_message.data.data, msg.rcl_message.data.size, msg.rcl_message.data.capacity });
    const allocator = c.rcutils_get_default_allocator();
    const new_data = allocator.reallocate.?(msg.rcl_message.data.data, string.len + 1, allocator.state);
    if (new_data) |data| {
        var array_data: []u8 = @as([*]u8, @ptrCast(data))[0 .. string.len + 1];
        @memcpy(array_data[0..string.len], string);
        array_data[string.len] = 0;
        msg.rcl_message.data.data = @as([*c]u8, @ptrCast(array_data));
        msg.rcl_message.data.size = string.len;
        msg.rcl_message.data.capacity = string.len + 1;
        return true;
    } else {
        return false;
    }
}

pub fn main() anyerror!void {
    std.log.info("Start rclzig talker\n", .{});

    // Initialize zig allocator
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Initialize rcl allocator (using zig allocator)
    var rcl_allocator = try rcl.RclAllocator.init(allocator);
    defer rcl_allocator.deinit();

    const argv = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argv);

    // Initialize Context
    var context_options = try rcl.ContextOptions.init(rcl_allocator);
    defer context_options.deinit();
    var context = try rcl.Context.init(argv, context_options);
    defer context.deinit();

    // Initialize Node
    var node_options = rcl.NodeOptions.init(rcl_allocator);
    defer node_options.deinit();
    var node = try rcl.Node.init("talker", "", &context, node_options);
    defer node.deinit();

    // Create publisher
    const publisher_options = rcl.PublisherOptions.init(rcl_allocator);
    var publisher = try rcl.Publisher(MultiArrayMsg).init(node, "chatter", publisher_options);
    defer publisher.deinit(&node);

    // Create a message to publish
    var message = try MultiArrayMsg.init(rcl_allocator.zig_allocator);
    defer message.deinit();
    // if (!setString(&message, "Hello world")) {
    //     std.debug.panic("setString failed", .{});
    // }
    // const str: []const u8 = "hola tortuga hola oruga contento voy";
    // if (message.setField("data", str)) {} else |_| {
    //     std.debug.panic("could not set strng", .{});
    // }
    const floats = [_]f32{ 2.3, 1.0, 1.0, 3.5 };
    try message.setField("data", floats);

    // Start publishing
    var timer = try std.time.Timer.start();
    const publish_period: u64 = 1e9;
    while (true) {
        const time_since_publish: u64 = timer.read();
        if (time_since_publish >= publish_period) {
            const now = try node.now();
            std.log.info("Publishing message at time {any}\n", .{now});
            publisher.publish(message);
            timer.reset();
            continue;
        }
        std.time.sleep(publish_period - time_since_publish);
    }

    // Shutdown Context
    try context.shutdown();
}
