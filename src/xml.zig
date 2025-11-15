const std = @import("std");
const smixml = @cImport({
    @cInclude("smixml.h");
});

pub const Xml = struct {

    xml_handle: isize = 0,

    pub fn begin(file: *std.fs.File) Xml {
        var self = Xml{};

        const sr = @as(isize, @bitCast(@intFromPtr(&streamRead)));
        const sw = @as(isize, @bitCast(@intFromPtr(&streamWrite)));
        const ss = @as(isize, @bitCast(@intFromPtr(&streamSeek)));

        self.xml_handle = smixml.BeginXml(@bitCast(@intFromPtr(file)), sr, sw, ss);
    
        return self;
    }

    pub fn end(self: *Xml) void {
        smixml.EndXml(self.xml_handle);
    }

    pub fn startElement(self: *Xml, name: []const u8, namespace: ?[]const u8) void {
        var namespace_ptr: isize = 0;
        if (namespace) |ns| {
            namespace_ptr = @bitCast(@intFromPtr(ns.ptr));
        }
        const namespace_len = if (namespace) |ns| ns.len else 0;

        smixml.StartElement(self.xml_handle, @bitCast(@intFromPtr(name.ptr)), @intCast(name.len), namespace_ptr, @intCast(namespace_len));
    }

    pub fn endElement(self: *Xml) void {
        smixml.EndElement(self.xml_handle);
    }

    pub fn attributeString(self: *Xml, local_name: []const u8, value: ?[]const u8) void {
        var value_ptr: isize = 0;
        if (value) |val| {
            value_ptr = @bitCast(@intFromPtr(val.ptr));
        }
        const value_len = if (value) |val| val.len else 0;
        const local_name_len = local_name.len;

        smixml.AttributeString(self.xml_handle, 0, 0, @bitCast(@intFromPtr(local_name.ptr)), @intCast(local_name_len), 0, 0, value_ptr, @intCast(value_len));
    }

    pub fn attributeStringWithPrefix(self: *Xml, prefix: []const u8, local_name: []const u8, value: ?[]const u8) void {
        var value_ptr: isize = 0;
        if (value) |val| {
            value_ptr = @bitCast(@intFromPtr(val.ptr));
        }
        const value_len = if (value) |val| val.len else 0;

        smixml.AttributeString(self.xml_handle, @bitCast(@intFromPtr(prefix.ptr)), @intCast(prefix.len), @bitCast(@intFromPtr(local_name.ptr)), @intCast(local_name.len), 0, 0, value_ptr, @intCast(value_len));
    }

    pub fn string(self: *Xml, str: ?[]const u8) void {
        var str_ptr: isize = 0;
        if (str) |stri| {
            str_ptr = @bitCast(@intFromPtr(stri.ptr));
        }
        const str_len = if (str) |s| s.len else 0;

        smixml.String(self.xml_handle, str_ptr, @intCast(str_len));
    }

};

fn streamRead(data: ?*anyopaque, buffer: [*c]u8, size: usize) callconv(.c) i32 {
    var file = @as(*std.fs.File, @ptrCast(@alignCast(data.?)));
    
    return @intCast(file.read(buffer[0..size]) catch { return 0; });
}


fn streamWrite(data: ?*anyopaque, buffer: [*c]u8, size: usize) callconv(.c) void {
    var file = @as(*std.fs.File, @ptrCast(@alignCast(data.?)));

    _ = file.write(buffer[0..size]) catch { return; };
}

fn streamSeek(data: ?*anyopaque, offset: i64, origin: i32) callconv(.c) i64 {
    var file = @as(*std.fs.File, @ptrCast(@alignCast(data.?)));
    
    var pos = file.getPos() catch { return 0; };
    const end_pos = file.getEndPos() catch { return 0; };

    if (origin == 0) {
        file.seekTo(@intCast(offset)) catch { return @intCast(pos); };
        pos = @intCast(offset);
    } else if (origin == 1) {
        file.seekBy(offset) catch { return @intCast(pos); };
        pos += @intCast(offset);
    } else if (origin == 2) {
        file.seekFromEnd(offset)  catch { return @intCast(pos); };
        pos += end_pos - @as(u64, @intCast(offset));
    }

    return @intCast(pos);
}
