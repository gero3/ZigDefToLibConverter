const std = @import("std");

pub const ExportType = enum {
    function,
    data,
    constant,
};

pub const Export = struct {
    name: []const u8,
    internal_name: ?[]const u8,
    ordinal: ?u32,
    export_type: ExportType,
    is_private: bool,
    is_noname: bool,

    pub fn deinit(self: *Export, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.internal_name) |internal| {
            allocator.free(internal);
        }
    }
};

pub const ModuleDefinition = struct {
    name: ?[]const u8,
    description: ?[]const u8,
    version: ?[]const u8,
    exports: std.ArrayList(Export),

    pub fn init(allocator: std.mem.Allocator) ModuleDefinition {
        return ModuleDefinition{
            .name = null,
            .description = null,
            .version = null,
            .exports = std.ArrayList(Export).init(allocator),
        };
    }

    pub fn deinit(self: *ModuleDefinition, allocator: std.mem.Allocator) void {
        if (self.name) |name| allocator.free(name);
        if (self.description) |desc| allocator.free(desc);
        if (self.version) |version| allocator.free(version);

        for (self.exports.items) |*exp| {
            exp.deinit(allocator);
        }
        self.exports.deinit();
    }
};

pub const DefParser = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DefParser {
        return DefParser{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DefParser) void {
        _ = self;
    }

    pub fn parse(self: *DefParser, content: []const u8) !ModuleDefinition {
        var module_def = ModuleDefinition.init(self.allocator);
        errdefer module_def.deinit(self.allocator);

        var lines = std.mem.splitSequence(u8, content, "\n");
        var current_section: ?[]const u8 = null;

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == ';') continue; // Skip empty lines and comments

            // Check for section headers
            if (std.ascii.eqlIgnoreCase(trimmed, "EXPORTS")) {
                current_section = "EXPORTS";
                continue;
            } else if (std.ascii.eqlIgnoreCase(trimmed, "IMPORTS")) {
                current_section = "IMPORTS";
                continue;
            } else if (std.ascii.startsWithIgnoreCase(trimmed, "NAME")) {
                try self.parseName(trimmed, &module_def);
                continue;
            } else if (std.ascii.startsWithIgnoreCase(trimmed, "DESCRIPTION")) {
                try self.parseDescription(trimmed, &module_def);
                continue;
            } else if (std.ascii.startsWithIgnoreCase(trimmed, "VERSION")) {
                try self.parseVersion(trimmed, &module_def);
                continue;
            }

            // Process section content
            if (current_section) |section| {
                if (std.mem.eql(u8, section, "EXPORTS")) {
                    if (try self.parseExport(trimmed)) |exp| {
                        try module_def.exports.append(exp);
                    }
                }
                // IMPORTS section would be handled here if needed
            }
        }

        return module_def;
    }

    fn parseName(self: *DefParser, line: []const u8, module_def: *ModuleDefinition) !void {
        // Parse: NAME modulename
        const parts = std.mem.tokenizeAny(u8, line, " \t");
        var iterator = parts;
        _ = iterator.next(); // Skip "NAME"
        if (iterator.next()) |name| {
            module_def.name = try self.allocator.dupe(u8, name);
        }
    }

    fn parseDescription(self: *DefParser, line: []const u8, module_def: *ModuleDefinition) !void {
        // Parse: DESCRIPTION "description text"
        const start_quote = std.mem.indexOf(u8, line, "\"");
        if (start_quote) |start| {
            const end_quote = std.mem.lastIndexOf(u8, line, "\"");
            if (end_quote != null and end_quote.? > start) {
                const desc = line[start + 1 .. end_quote.?];
                module_def.description = try self.allocator.dupe(u8, desc);
            }
        }
    }

    fn parseVersion(self: *DefParser, line: []const u8, module_def: *ModuleDefinition) !void {
        // Parse: VERSION major.minor
        const parts = std.mem.tokenizeAny(u8, line, " \t");
        var iterator = parts;
        _ = iterator.next(); // Skip "VERSION"
        if (iterator.next()) |version| {
            module_def.version = try self.allocator.dupe(u8, version);
        }
    }

    fn parseExport(self: *DefParser, line: []const u8) !?Export {
        // Parse export lines in various formats:
        // functionname
        // functionname=internalname
        // functionname @ordinal
        // functionname=internalname @ordinal NONAME
        // functionname @ordinal PRIVATE
        // functionname DATA

        var exp = Export{
            .name = undefined,
            .internal_name = null,
            .ordinal = null,
            .export_type = .function,
            .is_private = false,
            .is_noname = false,
        };

        var remaining = line;

        // Parse keywords and flags first
        if (std.mem.indexOf(u8, remaining, "PRIVATE")) |_| {
            exp.is_private = true;
        }

        if (std.mem.indexOf(u8, remaining, "NONAME")) |_| {
            exp.is_noname = true;
        }

        if (std.mem.indexOf(u8, remaining, "DATA")) |_| {
            exp.export_type = .data;
        }

        // Now extract the core part (name and ordinal) by removing keywords
        var core_part = std.ArrayList(u8).init(self.allocator);
        defer core_part.deinit();

        var tokens = std.mem.tokenizeAny(u8, remaining, " \t");
        while (tokens.next()) |token| {
            if (!std.mem.eql(u8, token, "PRIVATE") and
                !std.mem.eql(u8, token, "NONAME") and
                !std.mem.eql(u8, token, "DATA"))
            {
                if (core_part.items.len > 0) {
                    try core_part.append(' ');
                }
                try core_part.appendSlice(token);
            }
        }

        remaining = core_part.items;

        remaining = std.mem.trim(u8, remaining, " \t");

        // Parse ordinal (@number) - but distinguish from stdcall decoration
        // Ordinal format: "function @123" (space before @)
        // Decoration format: "function@123" (no space before @)
        if (std.mem.indexOf(u8, remaining, " @")) |space_at_pos| {
            const ordinal_part = remaining[space_at_pos + 2 ..]; // +2 to skip " @"
            const ordinal_end = std.mem.indexOfAny(u8, ordinal_part, " \t") orelse ordinal_part.len;
            const ordinal_str = ordinal_part[0..ordinal_end];
            exp.ordinal = std.fmt.parseInt(u32, ordinal_str, 10) catch null;
            remaining = remaining[0..space_at_pos];
        }

        remaining = std.mem.trim(u8, remaining, " \t");

        // Parse name and internal name (name=internalname)
        if (std.mem.indexOf(u8, remaining, "=")) |eq_pos| {
            exp.name = try self.allocator.dupe(u8, std.mem.trim(u8, remaining[0..eq_pos], " \t"));
            exp.internal_name = try self.allocator.dupe(u8, std.mem.trim(u8, remaining[eq_pos + 1 ..], " \t"));
        } else {
            exp.name = try self.allocator.dupe(u8, remaining);
        }

        if (exp.name.len == 0) return null;

        return exp;
    }
};

test "def parser basic functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parser = DefParser.init(allocator);
    defer parser.deinit();

    const def_content =
        \\NAME MyLibrary
        \\DESCRIPTION "My test library"
        \\VERSION 1.0
        \\EXPORTS
        \\MyFunction
        \\MyData DATA
        \\MyPrivateFunc @1 PRIVATE
    ;

    var module_def = try parser.parse(def_content);
    defer module_def.deinit(allocator);

    try std.testing.expect(module_def.exports.items.len == 3);
    try std.testing.expectEqualStrings("MyLibrary", module_def.name.?);
}
