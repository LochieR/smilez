const std = @import("std");
const String = @import("string").String;

pub const Parser = @import("parser.zig");

test "parser" {
    _ = try Parser.parseSMILES("CCCC");
}
