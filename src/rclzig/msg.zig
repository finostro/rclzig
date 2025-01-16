const std = @import("std");
const meta = @import("meta.zig");

pub fn Msg(comptime c_libs: type, comptime package_name: []const u8, comptime definition_subfolder: []const u8, comptime msg_name: []const u8) type {
    const RclMessage: type = comptime @field(c_libs, meta.ROSIDL_TYPESUPPORT_MSG_TYPENAME(package_name, definition_subfolder, msg_name));

    return struct {
        const MsgType = @This();
        rcl_type_support: *const c_libs.rosidl_message_type_support_t,
        rcl_message: *@field(c_libs, meta.ROSIDL_TYPESUPPORT_MSG_TYPENAME(package_name, definition_subfolder, msg_name)),
        // @field(@This(), "test_field"): u32,

        pub fn init(allocator: std.mem.Allocator) !MsgType {
            // TODO(jacobperron): Use allocator to initialize message when it is available
            //                    https://github.com/ros2/rosidl/issues/306
            _ = allocator;
            // std.debug.print("calling create : {s}\n", .{comptime RCL_MESSAGE_FUNC(package_name, definition_subfolder, msg_name, "create")});
            const rcl_message = @field(c_libs, meta.RCL_MESSAGE_FUNC(package_name, definition_subfolder, msg_name, "create"))();
            // const rcl_message = c_libs.std_msgs__msg__String__create();
            if (!@field(c_libs, meta.RCL_MESSAGE_FUNC(package_name, definition_subfolder, msg_name, "init"))(rcl_message)) {
                return error.BadInit;
            }
            // std.debug.print("address {any} string {any} , len {d} , cap {d}\n", .{ &rcl_message[0].data.data, rcl_message[0].data.data, rcl_message[0].data.size, rcl_message[0].data.capacity });
            const message: MsgType = .{
                .rcl_type_support = @field(c_libs, meta.ROSIDL_TYPESUPPORT_INTERFACE__MESSAGE_SYMBOL_NAME("rosidl_typesupport_c", package_name, "msg", msg_name))(),
                .rcl_message = rcl_message,
            };
            return message;
        }

        pub fn deinit(self: *MsgType) void {
            // std.debug.print("calling destroy : {s}\n", .{comptime RCL_MESSAGE_FUNC(package_name, definition_subfolder, msg_name, "destroy")});
            @field(c_libs, meta.RCL_MESSAGE_FUNC(package_name, definition_subfolder, msg_name, "destroy"))(self.rcl_message);
        }

        pub fn copyTo(self: *MsgType, other: *MsgType) !void {
            @field(c_libs, meta.RCL_MESSAGE_FUNC(package_name, definition_subfolder, msg_name, "copy"))(self, other);
        }

        pub fn isEqual(self: *MsgType, other: *MsgType) bool {
            @field(c_libs, meta.RCL_MESSAGE_FUNC(package_name, definition_subfolder, msg_name, "are_equal"))(self, other);
        }
        pub fn setField(self: *MsgType, comptime field_name: []const u8, value: anytype) !void {
            comptime var found_field: bool = false;
            comptime var field: std.builtin.Type.StructField = undefined;
            comptime var is_sequence: bool = false;

            comptime {
                for (std.meta.fields(RclMessage)) |f| {
                    if (std.mem.eql(u8, f.name, field_name)) {
                        field = f;
                        found_field = true;
                        is_sequence = meta.isSequence(field.type);
                    }
                }
                if (!found_field) {
                    @compileLog(std.fmt.comptimePrint(" Field {s} not found \n", .{field_name}));
                    @compileLog(std.fmt.comptimePrint("Fields are: {", .{}));
                    for (std.meta.fields(RclMessage)) |f| {
                        @compileLog(std.fmt.comptimePrint("{s},", .{f.name}));
                    }
                    @compileLog(std.fmt.comptimePrint("}\n", .{}));
                    @compileError(" msg field_name not found\n ");
                }
            }
            if (is_sequence) {
                const sequence_type_info = comptime @typeInfo(@TypeOf(@field(self.rcl_message, field_name).data));
                const element_type = comptime sequence_type_info.pointer.child;
                if (comptime meta.isZigSequenceOf(@TypeOf(value), element_type)) {
                    if (@field(self.rcl_message, field_name).capacity >= value.len) {
                        @memcpy(@field(self.rcl_message, field_name).data[0..value.len], value[0..value.len]);
                        @field(self.rcl_message, field_name).size = value.len;
                    } else {
                        const allocator = c_libs.rcutils_get_default_allocator();

                        @field(self.rcl_message, field_name).data = @as([*c]element_type, @ptrCast(@alignCast(allocator.reallocate.?(@field(self.rcl_message, field_name).data, value.len * @sizeOf(@TypeOf(@field(self.rcl_message, field_name).data)), allocator.state))));
                        @memcpy(@field(self.rcl_message, field_name).data[0..value.len], value[0..value.len]);
                        @field(self.rcl_message, field_name).capacity = value.len;
                        @field(self.rcl_message, field_name).size = value.len;
                    }
                } else {
                    @compileLog(std.fmt.comptimePrint("value should be a slice of {s} but is {s}", .{ @typeName(field.type), @typeName(@TypeOf(value)) }));
                    @compileError("wrong value type");
                }
            } else {
                if (comptime meta.isStringMsg(field.type)) {
                    if (@TypeOf(value) == []const u8) {
                        if (@field(self.rcl_message, field_name).capacity >= value.len + 1) {
                            @field(self.rcl_message, field_name).size = value.len;
                            const ptr = @as([]u8, @ptrCast(@field(self.rcl_message, field_name).data[0..@field(self.rcl_message, field_name).capacity]));
                            @memcpy(ptr[0..value.len], value);
                            @field(self.rcl_message, field_name).data[value.len] = 0;
                        } else {
                            const allocator = c_libs.rcutils_get_default_allocator();
                            @field(self.rcl_message, field_name).data = @ptrCast(allocator.reallocate.?(@field(self.rcl_message, field_name).data, value.len + 1, allocator.state));
                            @field(self.rcl_message, field_name).capacity = value.len + 1;
                            @field(self.rcl_message, field_name).size = value.len;
                            if (@field(self.rcl_message, field_name).data == null) {
                                return error.AllocationError;
                            }
                            const ptr = @as([]u8, @ptrCast(@field(self.rcl_message, field_name).data[0..@field(self.rcl_message, field_name).capacity]));
                            @memcpy(ptr[0..value.len], value);
                            @field(self.rcl_message, field_name).data[value.len] = 0;
                        }
                    } else {
                        @compileLog(std.fmt.comptimePrint("value should be a string, but is {s}", .{@typeName(@TypeOf(value))}));
                        @compileError("wrong value type");
                    }
                } else {
                    if (meta.isU16StringMsg(@TypeOf(value))) {
                        if (@TypeOf(value) == []const u16) {
                            if (@field(self.rcl_message, field_name).capacity >= value.len + 1) {
                                @field(self.rcl_message, field_name).size = value.len;
                                const ptr = @as([]u16, @ptrCast(@field(self.rcl_message, field_name).data[0..@field(self.rcl_message, field_name).capacity]));
                                @memcpy(ptr[0..value.len], value);
                                @field(self.rcl_message, field_name).data[value.len] = 0;
                            } else {
                                const allocator = c_libs.rcutils_get_default_allocator();
                                @field(self.rcl_message, field_name).data = @ptrCast(allocator.reallocate.?(@field(self.rcl_message, field_name).data, value.len + 1, allocator.state));
                                @field(self.rcl_message, field_name).capacity = value.len + 1;
                                @field(self.rcl_message, field_name).size = value.len;
                                if (@field(self.rcl_message, field_name).data == null) {
                                    return error.AllocationError;
                                }
                                const ptr = @as([]u16, @ptrCast(@field(self.rcl_message, field_name).data[0..@field(self.rcl_message, field_name).capacity]));
                                @memcpy(ptr[0..value.len], value);
                                @field(self.rcl_message, field_name).data[value.len] = 0;
                            }
                        } else {
                            @compileLog(std.fmt.comptimePrint("value should be a string, but is {s}", .{@typeName(@TypeOf(value))}));
                            @compileError("wrong value type");
                        }
                    } else {
                        if (@TypeOf(value) == field.type) {
                            @field(self.rcl_message, field_name) = value;
                        } else {
                            @compileLog(std.fmt.comptimePrint(" value should be a {s} but is {s}", .{ @typeName(field.type), @typeName(@TypeOf(value)) }));
                            @compileError("wrong value type");
                        }
                    }
                }
            }
        }
    };
}
