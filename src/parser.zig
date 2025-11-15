const std = @import("std");
const Xml = @import("xml.zig").Xml;

pub const Atom = struct {
    element: Element,
    id: u32,
    explicit: bool,
};

pub const BondType = enum {
    single,
    double,
    triple,
    aromatic
};

pub const BondStereo = enum {
    none,
    entgegen,
    zusammen
};

pub const Bond = struct {
    from: u32,
    to: u32,
    bond_type: BondType,
    bond_stereo: BondStereo
};

pub const Element = struct {
    name: []const u8,
    symbol: []const u8,
    relative_atomic_mass: f32,
    valences: [5]?u7
};

pub const elements: []const Element = parseCSV(@embedFile("AtomicData.csv"));

pub fn findElement(symbol: []const u8) ?Element {
    for (elements) |elem| {
        if (std.mem.eql(u8, elem.symbol, symbol))
            return elem;
    }
    return null;
}

pub const Molecule = struct {
    name: ?[]const u8 = null,
    atoms: std.ArrayList(Atom) = .{},
    bonds: std.ArrayList(Bond) = .{},
};

pub const SmilesError = error {
    InvalidRingNumber
};

pub const CmlParseError = error {
    TooManyAtoms
};

pub fn parseSMILES(smiles: []const u8, allocator: std.mem.Allocator) !Molecule {
    var molecule = Molecule{};
    var stack = std.ArrayList(u32){};
    var previous_atom_id: ?u32 = null;

    var rings_open: [100]?u31 = .{null} ** 100;

    var next_bond_type: BondType = .single;
    var next_explicit: bool = false;

    var i: usize = 0;
    while (i < smiles.len) : (i += 1) {
        var symbol_len: usize = 0;
        var matched_element: ?Element = null;

        if (i + 1 < smiles.len) {
            matched_element = findElement(smiles[i..i + 2]);
            if (matched_element) |_|
                symbol_len = 2;
        }
        if (matched_element == null) {
            matched_element = findElement(smiles[i..i + 1]);
            if (matched_element) |_|
                symbol_len = 1;
        }

        if (matched_element) |element| {
            const atom = Atom{
                .element = element,
                .id = @intCast(molecule.atoms.items.len),
                .explicit = next_explicit
            };
            try molecule.atoms.append(allocator, atom);
            //std.debug.print("FBA remaining = {}\n", .{getFBARemaining(&fba)});

            if (previous_atom_id) |pid| {
                try molecule.bonds.append(allocator, Bond{
                    .from = pid,
                    .to = atom.id,
                    .bond_type = next_bond_type,
                    .bond_stereo = .none,
                });
                //std.debug.print("FBA remaining = {}\n", .{getFBARemaining(&fba)});

                next_bond_type = .single;
            }

            previous_atom_id = atom.id;

            if (i + symbol_len < smiles.len and (isDigit(smiles[i + symbol_len]) or smiles[i + symbol_len] == '%')) {
                var ring_index = i + symbol_len;

                if (smiles[ring_index] == '%') {
                    if (ring_index < smiles.len) {
                        return error.InvalidRingNumber; // must be in form %nn
                    }

                    const idStr = smiles[ring_index + 1 .. ring_index + 3];
                    const ring_id = try std.fmt.parseInt(u8, idStr, 10);

                    if (rings_open[ring_id]) |opening_atom| {
                        try molecule.bonds.append(allocator, Bond{
                            .from = @intCast(opening_atom),
                            .to = previous_atom_id.?,
                            .bond_type = next_bond_type,
                            .bond_stereo = .none,
                        });
                        //std.debug.print("FBA remaining = {}\n", .{getFBARemaining(&fba)});
                        rings_open[ring_id] = null;
                        next_bond_type = .single;
                    } else {
                        rings_open[ring_id] = @intCast(previous_atom_id.?);
                    }

                    ring_index += 3;
                } else if (isDigit(smiles[ring_index])) {
                    const digit = smiles[ring_index] - '0';
                    const ring_id: u8 = @intCast(digit);

                    if (rings_open[ring_id]) |opening_atom| {
                        try molecule.bonds.append(allocator, Bond{
                            .from = @intCast(opening_atom),
                            .to = previous_atom_id.?,
                            .bond_type = next_bond_type,
                            .bond_stereo = .none,
                        });
                        //std.debug.print("FBA remaining = {}\n", .{getFBARemaining(&fba)});
                        rings_open[ring_id] = null;
                        next_bond_type = .single;
                    } else {
                        rings_open[ring_id] = @intCast(previous_atom_id.?);
                    }
                    
                    ring_index += 1;
                }

                const consumed = ring_index - (i + symbol_len);
                i += consumed;
            }

            i += symbol_len - 1;
        } else switch(smiles[i]) {
            '(' => try stack.append(allocator, previous_atom_id.?),
            ')' => previous_atom_id = stack.pop(),
            '[' => next_explicit = true,
            ']' => next_explicit = false,
            '=' => next_bond_type = .double,
            '#' => next_bond_type = .triple,
            else => {}
        }
    }

    var to_add_atoms = std.ArrayList(Atom){};
    var to_add_bonds = std.ArrayList(Bond){};

    for (molecule.atoms.items) |*atom| {
        const bond_count = getAtomBondCount(&molecule, atom);

        if (atom.explicit) {
            continue;
        }

        if (atom.element.valences[0]) |default_valence| {
            if (bond_count != default_valence) {
                const to_add = default_valence - bond_count;

                for (0..to_add) |_| {
                    const hydrogen = Atom{
                        .element = findElement("H").?,
                        .id = @intCast(molecule.atoms.items.len + to_add_atoms.items.len),
                        .explicit = true
                    };
                    try to_add_atoms.append(allocator, hydrogen);
                    try to_add_bonds.append(allocator, Bond{
                        .from = atom.id,
                        .to = hydrogen.id,
                        .bond_type = .single,
                        .bond_stereo = .none,
                    });
                }
            }
        }
    }

    for (to_add_atoms.items) |*atom| {
        try molecule.atoms.append(allocator, atom.*);
    }

    to_add_atoms.deinit(allocator);

    for (to_add_bonds.items) |*bond| {
        try molecule.bonds.append(allocator, bond.*);
    }

    to_add_bonds.deinit(allocator);

    return molecule;
}

pub fn outputCML(path: []const u8, molecule: *const Molecule) !void {
    var file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    var xml = Xml.begin(&file);
    defer xml.end();

    xml.startElement("cml", "http://www.xml-cml.org/schema");
    xml.attributeString("convention", "conventions:molecular");
    xml.attributeStringWithPrefix("xmlns", "conventions", "http://www.xml-cml.org/convention");
    xml.attributeStringWithPrefix("xmlns", "cmlDict", "http://www.xml-cml.org/dictionary/cml");
    xml.attributeStringWithPrefix("xmlns", "nameDict", "http://www.xml-cml.org/dictionary/cml/name");
    defer xml.endElement();

    xml.startElement("molecule", null);
    xml.attributeString("id", "m1");
    defer xml.endElement();

    xml.startElement("name", null);
    xml.attributeString("dictRef", "nameDict:unknown");
    xml.string(molecule.name);
    xml.endElement();

    xml.startElement("atomArray", null);
    
    for (molecule.atoms.items) |*atom| {
        if (atom.id + 1 > 999) {
            return error.TooManyAtoms;
        }

        var buf: [4]u8 = undefined;
        const atom_id_name = try std.fmt.bufPrint(&buf, "a{}", .{atom.id + 1});

        xml.startElement("atom", null);
        xml.attributeString("id", atom_id_name);
        xml.attributeString("elementType", atom.element.symbol);
        xml.endElement();
    }

    xml.endElement();

    xml.startElement("bondArray", null);

    for (molecule.bonds.items) |*bond| {
        var id_buf: [9]u8 = undefined; // allowing up to "a998_a999"
        const bond_id_name = try std.fmt.bufPrint(&id_buf, "a{}_a{}", .{bond.from + 1, bond.to + 1});

        var refs_buf: [9]u8 = undefined; // allowing up to "a998 a999"
        const atom_refs = try std.fmt.bufPrint(&refs_buf, "a{} a{}", .{bond.from + 1, bond.to + 1});

        xml.startElement("bond", null);
        xml.attributeString("id", bond_id_name);
        xml.attributeString("atomRefs2", atom_refs);
        xml.attributeString("order", switch (bond.bond_type) {
            .single => "S",
            .double => "D",
            .triple => "T",
            .aromatic => "A" // don't actually think this works
        });
        xml.endElement();
    }

    xml.endElement();
}

fn getAtomBonds(molecule: *Molecule, atom: *Atom, allocator: std.mem.Allocator) !std.ArrayList(Bond) {
    var bonds = std.ArrayList(Bond){};
    for (molecule.bonds.items) |*bond| {
        if (bond.from == atom.id or bond.to == atom.id) {
            try bonds.append(allocator, bond.*);
        }
    }

    return bonds;
}

fn getAtomBondCount(molecule: *Molecule, atom: *Atom) u32 {
    var count: u32 = 0;
    for (molecule.bonds.items) |*bond| {
        if (bond.from == atom.id or bond.to == atom.id) {
            count += switch (bond.bond_type) {
                .single => 1,
                .double => 2,
                .triple => 3,
                .aromatic => 2
            };
        }
    }

    return count;
}

fn getFBARemaining(fba: *const std.heap.FixedBufferAllocator) usize {
    const used = fba.end_index;
    const total = fba.buffer.len;
    const remaining = total - used;

    return remaining;
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn parseCSV(comptime csv: []const u8) []const Element {
    @setEvalBranchQuota(50000);

    var parsed_elements: []const Element = &[_]Element{};

    var line_iter = std.mem.splitScalar(u8, csv, '\n');
    while (line_iter.next()) |line| {
        if (line.len == 0)
            continue;

        var col_iter = std.mem.splitScalar(u8, line, ',');
        const element = col_iter.next() orelse "";
        const symbol  = col_iter.next() orelse "";
        const ram_str = col_iter.next() orelse "";
        const valence0 = trimChars(col_iter.next() orelse "", "\r\n\t, ");
        const valence1 = trimChars(col_iter.next() orelse "", "\r\n\t, ");
        const valence2 = trimChars(col_iter.next() orelse "", "\r\n\t, ");
        const valence3 = trimChars(col_iter.next() orelse "", "\r\n\t, ");
        const valence4 = trimChars(col_iter.next() orelse "", "\r\n\t, ");

        if (std.mem.eql(u8, element, "Element"))
            continue;

        const new_element = Element{
            .name = element,
            .symbol = symbol,
            .relative_atomic_mass = parseFloat(f32, ram_str),
            .valences = [_]?u7 {
                if (valence0.len == 0) null else parseInt(u7, valence0),
                if (valence1.len == 0) null else parseInt(u7, valence1),
                if (valence2.len == 0) null else parseInt(u7, valence2),
                if (valence3.len == 0) null else parseInt(u7, valence3),
                if (valence4.len == 0) null else parseInt(u7, valence4),
            }
        };
        parsed_elements = parsed_elements ++ [_]Element{ new_element };
    }

    return parsed_elements;
}

fn contains(comptime c: u8, comptime chars: []const u8) bool {
    for (chars) |ch| {
        if (c == ch) {
            return true;
        }
    }
    return false;
}

fn trimChars(comptime str: []const u8, comptime chars: []const u8) []const u8 {
    var start: usize = 0;
    var end: usize = str.len;

    while (start < end and contains(str[start], chars)) : (start += 1) {}
    while (end > start and contains(str[end - 1], chars)) : (end -= 1) {}

    return str[start..end];
}

fn parseInt(comptime T: type, comptime s: []const u8) T {
    if (@typeInfo(T) != .int) {
        @compileError("T must be an integer type");
    }

    var i: usize = 0;
    var negative = false;

    if (s.len > 0 and s[0] == '-') {
        if (@typeInfo(T).int.signedness != .signed) {
            @compileError("cannot parse negative integer into an unsigned type");
        }
        negative = true;
        i += 1;
    } else if (s.len > 0 and s[0] == '+') {
        i += 1;
    }

    if (i == s.len) {
        @compileError("string contains no digits");
    }

    var result: T = 0;

    while (i < s.len) : (i += 1) {
        const c = s[i];
        if (c < '0' or c > '9') {
            const msg = std.fmt.comptimePrint("invalid character in integer string (character = {c})", .{c});
            @compileError(msg);
        }
        const digit: T = @intCast(c - '0');

        const next = result * 10 + digit;
        if (next < result) {
            @compileError("integer overflow");
        }
        result = next;
    }

    if (negative) {
        result = -result;
    }

    return result;
}

fn parseFloat(comptime T: type, comptime s: []const u8) T {
    if (@typeInfo(T) != .float) {
        @compileError("T must be a float type");
    }

    comptime var i: usize = 0;
    comptime var sign: T = 1.0;
    comptime var result: T = 0.0;

    if (i < s.len and s[i] == '-') {
        sign = -1.0;
        i += 1;
    }

    while (i < s.len and s[i] >= '0' and s[i] <= '9') : (i += 1) {
        result = result * 10.0 + @as(T, @floatFromInt(s[i] - '0'));
    }

    if (i < s.len and s[i] == '.') {
        i += 1;
        comptime var place: T = 0.1;
        while (i < s.len and s[i] >= '0' and s[i] <= '9') : (i += 1) {
            result += @as(T, @floatFromInt(s[i] - '0')) * place;
            place *= 0.1;
        }
    }

    return result * sign;
}
