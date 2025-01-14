const std = @import("std");

fn ROSIDL_TYPESUPPORT_LIBRARY_NAME(comptime package_name: []const u8, comptime typesupport_name: []const u8) []const u8 {
    return std.fmt.comptimePrint("{s}__{s}", .{ package_name, typesupport_name });
}

fn ROSIDL_TYPESUPPORT_INTERFACE__SYMBOL_NAME(comptime typesupport_name: []const u8, comptime function_name: []const u8, comptime package_name: []const u8, comptime interface_type: []const u8, comptime interface_name: []const u8) []const u8 {
    return std.fmt.comptimePrint("{s}__{s}__{s}__{s}__{s}", .{ typesupport_name, function_name, package_name, interface_type, interface_name });
}

fn ROSIDL_TYPESUPPORT_INTERFACE__MESSAGE_SYMBOL_NAME(comptime typesupport_name: []const u8, comptime package_name: []const u8, comptime interface_type: []const u8, comptime message_name: []const u8) []const u8 {
    return ROSIDL_TYPESUPPORT_INTERFACE__SYMBOL_NAME(typesupport_name, "get_message_type_support_handle", package_name, interface_type, message_name);
}

fn ROSIDL_TYPESUPPORT_INTERFACE__SERVICE_SYMBOL_NAME(comptime typesupport_name: []const u8, comptime package_name: []const u8, comptime interface_type: []const u8, comptime service_name: []const u8) []const u8 {
    return ROSIDL_TYPESUPPORT_INTERFACE__SYMBOL_NAME(typesupport_name, "get_service_type_support_handle", package_name, interface_type, service_name);
}

fn ROSIDL_TYPESUPPORT_INTERFACE__ACTION_SYMBOL_NAME(comptime typesupport_name: []const u8, comptime package_name: []const u8, comptime interface_type: []const u8, comptime action_name: []const u8) []const u8 {
    return ROSIDL_TYPESUPPORT_INTERFACE__SYMBOL_NAME(typesupport_name, "get_action_type_support_handle", package_name, interface_type, action_name);
}

fn ROSIDL_TYPESUPPORT_MSG_TYPENAME(comptime package_name: []const u8, comptime definition_subfolder: []const u8, comptime msg_name: []const u8) []const u8 {
    return std.fmt.comptimePrint("{s}__{s}__{s}", .{ package_name, definition_subfolder, msg_name });
}

fn RCL_MESSAGE_FUNC(comptime package_name: []const u8, comptime definition_subfolder: []const u8, comptime msg_name: []const u8, comptime func_name: []const u8) []const u8 {
    return std.fmt.comptimePrint("{s}__{s}", .{ ROSIDL_TYPESUPPORT_MSG_TYPENAME(package_name, definition_subfolder, msg_name), func_name });
}
// checks if type is a sequence of element ie, an array, slice or vector
fn isZigSequenceOf(comptime T: type, comptime elementT: type) bool {
    switch (@typeInfo(T)) {
        .array, .vector, .pointer => {
            return std.meta.Child(T) == elementT;
        },
        else => {
            return false;
        },
    }
}
/// Returns true if the passed type will coerce to []const u8.
/// Any of the following are considered strings:
/// ```
/// []const u8, [:S]const u8, *const [N]u8, *const [N:S]u8,
/// []u8, [:S]u8, *[:S]u8, *[N:S]u8.
/// ```
/// These types are not considered strings:
/// ```
/// u8, [N]u8, [*]const u8, [*:0]const u8,
/// [*]const [N]u8, []const u16, []const i8,
/// *const u8, ?[]const u8, ?*const [N]u8.
/// ```
pub fn isZigString(comptime T: type) bool {
    comptime {
        // Only pointer types can be strings, no optionals
        @compileLog("is string?\n");
        const info = @typeInfo(T);
        if (info != .pointer) return false;
        @compileLog("is pointer ok\n");

        const ptr = &info.pointer;
        // Check for CV qualifiers that would prevent coerction to []const u8
        if (ptr.is_volatile or ptr.is_allowzero) return false;
        @compileLog("is volatile allowzero ok\n");

        // If it's already a slice, simple check.
        if (ptr.size == .Slice) {
            if (ptr.child == u8) {
                @compileLog("child u8 \n");
                return true;
            } else {
                @compileLog("child fail\n");
                return false;
            }
            return ptr.child == u8;
        }
        @compileLog("is slice ok\n");

        // Otherwise check if it's an array type that coerces to slice.
        if (ptr.size == .One) {
            const child = @typeInfo(ptr.child);
            if (child == .array) {
                const arr = &child.array;
                return arr.child == u8;
            }
        }
        @compileLog("false \n");

        return false;
    }
}
fn isSequence(comptime T: type) bool {
    // @compileLog(std.fmt.comptimePrint("Tipename: {s}", .{@typeName(T)}));
    if (!std.mem.endsWith(u8, @typeName(T), "__Sequence")) {
        return false;
    }
    const subfields = std.meta.fields(T);
    // @compileLog(std.fmt.comptimePrint("subfields:  {any}", .{subfields.len}));
    if (subfields.len == 3) {
        var data_found = false;
        var size_found = false;
        var capacity_found = false;
        for (subfields) |f| {
            // @compileLog(std.fmt.comptimePrint("subfields:  {s}", .{f.name}));
            if (std.mem.eql(u8, f.name, "capacity")) {
                capacity_found = true;
            }
            if (std.mem.eql(u8, f.name, "data")) {
                data_found = true;
            }
            if (std.mem.eql(u8, f.name, "size")) {
                size_found = true;
            }
        }
        return data_found and size_found and capacity_found;
    }
    return false;
}

fn isStringMsg(comptime T: type) bool {
    return std.mem.eql(u8, @typeName(T), "cimport.struct_rosidl_runtime_c__String") or std.mem.eql(u8, @typeName(T), "rosidl_runtime_c_U16String");
}

pub fn Msg(comptime c_libs: type, comptime package_name: []const u8, comptime definition_subfolder: []const u8, comptime msg_name: []const u8) type {
    const RclMessage: type = comptime @field(c_libs, ROSIDL_TYPESUPPORT_MSG_TYPENAME(package_name, definition_subfolder, msg_name));

    const baseType = struct {
        const MsgType = @This();
        rcl_type_support: *const c_libs.rosidl_message_type_support_t,
        rcl_message: *@field(c_libs, ROSIDL_TYPESUPPORT_MSG_TYPENAME(package_name, definition_subfolder, msg_name)),
        // @field(@This(), "test_field"): u32,

        pub fn init(allocator: std.mem.Allocator) !MsgType {
            // TODO(jacobperron): Use allocator to initialize message when it is available
            //                    https://github.com/ros2/rosidl/issues/306
            _ = allocator;
            // std.debug.print("calling create : {s}\n", .{comptime RCL_MESSAGE_FUNC(package_name, definition_subfolder, msg_name, "create")});
            const rcl_message = @field(c_libs, RCL_MESSAGE_FUNC(package_name, definition_subfolder, msg_name, "create"))();
            // const rcl_message = c_libs.std_msgs__msg__String__create();
            if (!@field(c_libs, RCL_MESSAGE_FUNC(package_name, definition_subfolder, msg_name, "init"))(rcl_message)) {
                return error.BadInit;
            }
            // std.debug.print("address {any} string {any} , len {d} , cap {d}\n", .{ &rcl_message[0].data.data, rcl_message[0].data.data, rcl_message[0].data.size, rcl_message[0].data.capacity });
            const message: MsgType = .{
                .rcl_type_support = @field(c_libs, ROSIDL_TYPESUPPORT_INTERFACE__MESSAGE_SYMBOL_NAME("rosidl_typesupport_c", package_name, "msg", msg_name))(),
                .rcl_message = rcl_message,
            };
            return message;
        }

        pub fn deinit(self: *MsgType) void {
            // std.debug.print("calling destroy : {s}\n", .{comptime RCL_MESSAGE_FUNC(package_name, definition_subfolder, msg_name, "destroy")});
            @field(c_libs, RCL_MESSAGE_FUNC(package_name, definition_subfolder, msg_name, "destroy"))(self.rcl_message);
        }

        pub fn copyTo(self: *MsgType, other: *MsgType) !void {
            @field(c_libs, RCL_MESSAGE_FUNC(package_name, definition_subfolder, msg_name, "copy"))(self, other);
        }

        pub fn isEqual(self: *MsgType, other: *MsgType) bool {
            @field(c_libs, RCL_MESSAGE_FUNC(package_name, definition_subfolder, msg_name, "are_equal"))(self, other);
        }
        // pub fn set(self: *MsgType, value: anytype) !void {
        //     comptime var is_sequence: bool = false;
        //
        //     comptime {
        //         is_sequence = isSequence(RclMessage);
        //     }
        //     if (is_sequence) {
        //         @compileError("wrong value type");
        //     } else {
        //         if (comptime isStringMsg(RclMessage)) {
        //             const is_string = comptime isZigString(@TypeOf(value));
        //             @compileLog(std.fmt.comptimePrint("is string {any}", .{is_string}));
        //             if (is_string) {
        //                 if (self.rcl_message.data.capacity >= value.len + 1) {
        //                     @memcpy(self.rcl_message.data.data[0..value.len], value);
        //                     self.rcl_message.data.data[value.len] = 0;
        //                     self.rcl_message.data.size = value.len + 1;
        //                 }
        //             } else {
        //                 @compileLog("info {any} \n", .{@typeInfo(@TypeOf(value))});
        //                 @compileLog(std.fmt.comptimePrint("value should be a string, but is {s}", .{@typeName(@TypeOf(value))}));
        //                 @compileError("wrong value type");
        //             }
        //         } else {
        //             if (@TypeOf(value) == RclMessage) {
        //                 self.rcl_message = value;
        //             } else {
        //                 @compileLog(std.fmt.comptimePrint(" value should be a {s} but is {s}", .{ @typeName(RclMessage), @typeName(@TypeOf(value)) }));
        //                 @compileError("wrong value type");
        //             }
        //         }
        //     }
        // }
        pub fn setField(self: *MsgType, comptime field_name: []const u8, value: anytype) !void {
            comptime var found_field: bool = false;
            comptime var field: std.builtin.Type.StructField = undefined;
            comptime var is_sequence: bool = false;

            comptime {
                for (std.meta.fields(RclMessage)) |f| {
                    if (std.mem.eql(u8, f.name, field_name)) {
                        field = f;
                        found_field = true;
                        is_sequence = isSequence(field.type);
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
            // @compileLog(std.fmt.comptimePrint("is_sequence {any}", .{is_sequence}));
            if (is_sequence) {
                const sequence_type_info = comptime @typeInfo(@TypeOf(@field(self.rcl_message, field_name).data));
                const element_type = comptime sequence_type_info.pointer.child;
                // @compileLog(std.fmt.comptimePrint("sqt m {any}", .{element_type}));
                if (comptime isZigSequenceOf(@TypeOf(value), element_type)) {
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
                if (comptime isStringMsg(field.type)) {
                    switch (@TypeOf(value)) {
                        []const u8, []const u16 => {
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
                        },
                        else => {
                            @compileLog(std.fmt.comptimePrint("value should be a string, but is {s}", .{@typeName(@TypeOf(value))}));
                            @compileError("wrong value type");
                        },
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
    };
    return baseType;
    // var info = @typeInfo(baseType);
    //
    // for (std.meta.fields(RclMessage)) |field| {
    //     if (isSequence(field)) {
    //         info.@"struct".fields = info.@"struct".fields ++ .{.{
    //             .name = "test_field",
    //             .type = u32,
    //             .default_value = null,
    //             .is_comptime = false,
    //             .alignment = @alignOf(u32),
    //         }};
    //     }
    // }
    // return @Type(info);
}
