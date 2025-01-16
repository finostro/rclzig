const std = @import("std");

// helper functions for ros msg metaprograming

pub fn ROSIDL_TYPESUPPORT_LIBRARY_NAME(comptime package_name: []const u8, comptime typesupport_name: []const u8) []const u8 {
    return std.fmt.comptimePrint("{s}__{s}", .{ package_name, typesupport_name });
}

pub fn ROSIDL_TYPESUPPORT_INTERFACE__SYMBOL_NAME(comptime typesupport_name: []const u8, comptime function_name: []const u8, comptime package_name: []const u8, comptime interface_type: []const u8, comptime interface_name: []const u8) []const u8 {
    return std.fmt.comptimePrint("{s}__{s}__{s}__{s}__{s}", .{ typesupport_name, function_name, package_name, interface_type, interface_name });
}

pub fn ROSIDL_TYPESUPPORT_INTERFACE__MESSAGE_SYMBOL_NAME(comptime typesupport_name: []const u8, comptime package_name: []const u8, comptime interface_type: []const u8, comptime message_name: []const u8) []const u8 {
    return ROSIDL_TYPESUPPORT_INTERFACE__SYMBOL_NAME(typesupport_name, "get_message_type_support_handle", package_name, interface_type, message_name);
}

pub fn ROSIDL_TYPESUPPORT_INTERFACE__SERVICE_SYMBOL_NAME(comptime typesupport_name: []const u8, comptime package_name: []const u8, comptime interface_type: []const u8, comptime service_name: []const u8) []const u8 {
    return ROSIDL_TYPESUPPORT_INTERFACE__SYMBOL_NAME(typesupport_name, "get_service_type_support_handle", package_name, interface_type, service_name);
}

pub fn ROSIDL_TYPESUPPORT_INTERFACE__ACTION_SYMBOL_NAME(comptime typesupport_name: []const u8, comptime package_name: []const u8, comptime interface_type: []const u8, comptime action_name: []const u8) []const u8 {
    return ROSIDL_TYPESUPPORT_INTERFACE__SYMBOL_NAME(typesupport_name, "get_action_type_support_handle", package_name, interface_type, action_name);
}

pub fn ROSIDL_TYPESUPPORT_MSG_TYPENAME(comptime package_name: []const u8, comptime definition_subfolder: []const u8, comptime msg_name: []const u8) []const u8 {
    return std.fmt.comptimePrint("{s}__{s}__{s}", .{ package_name, definition_subfolder, msg_name });
}

pub fn RCL_MESSAGE_FUNC(comptime package_name: []const u8, comptime definition_subfolder: []const u8, comptime msg_name: []const u8, comptime func_name: []const u8) []const u8 {
    return std.fmt.comptimePrint("{s}__{s}", .{ ROSIDL_TYPESUPPORT_MSG_TYPENAME(package_name, definition_subfolder, msg_name), func_name });
}
// checks if type is a sequence of element ie, an array, slice or vector
pub fn isZigSequenceOf(comptime T: type, comptime elementT: type) bool {
    switch (@typeInfo(T)) {
        .array, .vector, .pointer => {
            return std.meta.Child(T) == elementT;
        },
        else => {
            return false;
        },
    }
}

pub fn isSequence(comptime rclMsgT: type) bool {
    if (!std.mem.endsWith(u8, @typeName(rclMsgT), "__Sequence")) {
        return false;
    }
    const subfields = std.meta.fields(rclMsgT);
    if (subfields.len == 3) {
        var data_found = false;
        var size_found = false;
        var capacity_found = false;
        for (subfields) |f| {
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

pub fn isU16StringMsg(comptime T: type) bool {
    return std.mem.eql(u8, @typeName(T), "cimport.struct_rosidl_rosidl_runtime_c_U16String");
}
pub fn isStringMsg(comptime T: type) bool {
    return std.mem.eql(u8, @typeName(T), "cimport.struct_rosidl_runtime_c__String");
}
