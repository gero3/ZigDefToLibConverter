const std = @import("std");

pub const ParseError = error{
    InvalidSyntax,
    MissingName,
    InvalidOrdinal,
    EmptyExportName,
    MalformedDescription,
    MalformedVersion,
    UnknownSection,
    DuplicateSection,
    OutOfMemory,
};

pub const ParseErrorInfo = struct {
    error_type: ParseError,
    line_number: u32,
    line_content: []const u8,
    message: []const u8,

    pub fn init(error_type: ParseError, line_number: u32, line_content: []const u8, message: []const u8) ParseErrorInfo {
        return ParseErrorInfo{
            .error_type = error_type,
            .line_number = line_number,
            .line_content = line_content,
            .message = message,
        };
    }
};

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
    last_error: ?ParseErrorInfo = null,

    pub fn init(allocator: std.mem.Allocator) DefParser {
        return DefParser{
            .allocator = allocator,
            .last_error = null,
        };
    }

    pub fn deinit(self: *DefParser) void {
        _ = self;
    }

    pub fn getLastError(self: *const DefParser) ?ParseErrorInfo {
        return self.last_error;
    }

    fn setError(self: *DefParser, error_type: ParseError, line_number: u32, line_content: []const u8, message: []const u8) void {
        self.last_error = ParseErrorInfo.init(error_type, line_number, line_content, message);
    }

    pub fn parse(self: *DefParser, content: []const u8) ParseError!ModuleDefinition {
        self.last_error = null; // Clear previous errors

        var module_def = ModuleDefinition.init(self.allocator);
        errdefer module_def.deinit(self.allocator);

        var lines = std.mem.splitSequence(u8, content, "\n");
        var current_section: ?[]const u8 = null;
        var line_number: u32 = 0;
        var has_exports_section = false;

        while (lines.next()) |line| {
            line_number += 1;
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == ';') continue; // Skip empty lines and comments

            // Check for section headers
            if (std.ascii.eqlIgnoreCase(trimmed, "EXPORTS")) {
                if (has_exports_section) {
                    self.setError(ParseError.DuplicateSection, line_number, trimmed, "Duplicate EXPORTS section found");
                    return ParseError.DuplicateSection;
                }
                current_section = "EXPORTS";
                has_exports_section = true;
                continue;
            } else if (std.ascii.eqlIgnoreCase(trimmed, "IMPORTS")) {
                current_section = "IMPORTS";
                continue;
            } else if (std.ascii.startsWithIgnoreCase(trimmed, "NAME")) {
                self.parseName(trimmed, &module_def, line_number) catch |err| {
                    return err;
                };
                continue;
            } else if (std.ascii.startsWithIgnoreCase(trimmed, "DESCRIPTION")) {
                self.parseDescription(trimmed, &module_def, line_number) catch |err| {
                    return err;
                };
                continue;
            } else if (std.ascii.startsWithIgnoreCase(trimmed, "VERSION")) {
                self.parseVersion(trimmed, &module_def, line_number) catch |err| {
                    return err;
                };
                continue;
            }

            // Process section content
            if (current_section) |section| {
                if (std.mem.eql(u8, section, "EXPORTS")) {
                    // Skip completely empty lines in exports section
                    if (trimmed.len == 0) continue;

                    const exp = self.parseExport(trimmed, line_number) catch |err| {
                        return err;
                    };
                    if (exp) |export_entry| {
                        try module_def.exports.append(export_entry);
                    }
                }
                // IMPORTS section would be handled here if needed
            } else {
                // Line outside of any known section and not a recognized directive
                self.setError(ParseError.UnknownSection, line_number, trimmed, "Line found outside of recognized section");
                return ParseError.UnknownSection;
            }
        }

        // Validate that we have at least a name or exports
        if (module_def.name == null and module_def.exports.items.len == 0) {
            self.setError(ParseError.MissingName, 0, "", "DEF file must have either a NAME directive or EXPORTS section");
            return ParseError.MissingName;
        }

        return module_def;
    }

    fn parseName(self: *DefParser, line: []const u8, module_def: *ModuleDefinition, line_number: u32) ParseError!void {
        // Parse: NAME modulename
        const parts = std.mem.tokenizeAny(u8, line, " \t");
        var iterator = parts;
        _ = iterator.next(); // Skip "NAME"
        if (iterator.next()) |name| {
            // Validate name is not empty and contains valid characters
            if (name.len == 0) {
                self.setError(ParseError.MissingName, line_number, line, "Module name cannot be empty");
                return ParseError.MissingName;
            }
            module_def.name = self.allocator.dupe(u8, name) catch return ParseError.OutOfMemory;
        } else {
            self.setError(ParseError.MissingName, line_number, line, "NAME directive requires a module name");
            return ParseError.MissingName;
        }
    }

    fn parseDescription(self: *DefParser, line: []const u8, module_def: *ModuleDefinition, line_number: u32) ParseError!void {
        // Parse: DESCRIPTION "description text"
        const start_quote = std.mem.indexOf(u8, line, "\"");
        if (start_quote) |start| {
            const end_quote = std.mem.lastIndexOf(u8, line, "\"");
            if (end_quote != null and end_quote.? > start) {
                const desc = line[start + 1 .. end_quote.?];
                module_def.description = self.allocator.dupe(u8, desc) catch return ParseError.OutOfMemory;
            } else {
                self.setError(ParseError.MalformedDescription, line_number, line, "DESCRIPTION must be enclosed in quotes");
                return ParseError.MalformedDescription;
            }
        } else {
            self.setError(ParseError.MalformedDescription, line_number, line, "DESCRIPTION must be enclosed in quotes");
            return ParseError.MalformedDescription;
        }
    }

    fn parseVersion(self: *DefParser, line: []const u8, module_def: *ModuleDefinition, line_number: u32) ParseError!void {
        // Parse: VERSION major.minor
        const parts = std.mem.tokenizeAny(u8, line, " \t");
        var iterator = parts;
        _ = iterator.next(); // Skip "VERSION"
        if (iterator.next()) |version| {
            // Basic validation - should contain at least one digit or dot
            var has_digit = false;
            for (version) |c| {
                if (std.ascii.isDigit(c) or c == '.') {
                    if (std.ascii.isDigit(c)) has_digit = true;
                } else {
                    self.setError(ParseError.MalformedVersion, line_number, line, "VERSION must contain only digits and dots");
                    return ParseError.MalformedVersion;
                }
            }
            if (!has_digit) {
                self.setError(ParseError.MalformedVersion, line_number, line, "VERSION must contain at least one digit");
                return ParseError.MalformedVersion;
            }
            module_def.version = self.allocator.dupe(u8, version) catch return ParseError.OutOfMemory;
        } else {
            self.setError(ParseError.MalformedVersion, line_number, line, "VERSION directive requires a version number");
            return ParseError.MalformedVersion;
        }
    }

    fn parseExport(self: *DefParser, line: []const u8, line_number: u32) ParseError!?Export {
        // Parse export lines in various formats:
        // functionname
        // functionname=internalname
        // functionname @ordinal
        // functionname=internalname @ordinal NONAME
        // functionname @ordinal PRIVATE
        // functionname DATA

        if (line.len == 0) {
            self.setError(ParseError.EmptyExportName, line_number, line, "Export line cannot be empty");
            return ParseError.EmptyExportName;
        }

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
                    core_part.append(' ') catch return ParseError.OutOfMemory;
                }
                core_part.appendSlice(token) catch return ParseError.OutOfMemory;
            }
        }

        remaining = core_part.items;
        remaining = std.mem.trim(u8, remaining, " \t");

        if (remaining.len == 0) {
            self.setError(ParseError.EmptyExportName, line_number, line, "Export name cannot be empty after removing keywords");
            return ParseError.EmptyExportName;
        }

        // Parse ordinal (@number) - but distinguish from stdcall decoration
        // Ordinal format: "function @123" (space before @)
        // Decoration format: "function@123" (no space before @)
        if (std.mem.indexOf(u8, remaining, " @")) |space_at_pos| {
            const ordinal_part = remaining[space_at_pos + 2 ..]; // +2 to skip " @"
            const ordinal_end = std.mem.indexOfAny(u8, ordinal_part, " \t") orelse ordinal_part.len;
            const ordinal_str = ordinal_part[0..ordinal_end];

            if (ordinal_str.len == 0) {
                self.setError(ParseError.InvalidOrdinal, line_number, line, "Ordinal number cannot be empty after @");
                return ParseError.InvalidOrdinal;
            }

            exp.ordinal = std.fmt.parseInt(u32, ordinal_str, 10) catch {
                self.setError(ParseError.InvalidOrdinal, line_number, line, "Invalid ordinal number format");
                return ParseError.InvalidOrdinal;
            };

            if (exp.ordinal.? == 0) {
                self.setError(ParseError.InvalidOrdinal, line_number, line, "Ordinal number must be greater than 0");
                return ParseError.InvalidOrdinal;
            }

            remaining = remaining[0..space_at_pos];
        }

        remaining = std.mem.trim(u8, remaining, " \t");

        // Parse name and internal name (name=internalname)
        if (std.mem.indexOf(u8, remaining, "=")) |eq_pos| {
            const name_part = std.mem.trim(u8, remaining[0..eq_pos], " \t");
            const internal_part = std.mem.trim(u8, remaining[eq_pos + 1 ..], " \t");

            if (name_part.len == 0) {
                self.setError(ParseError.EmptyExportName, line_number, line, "Export name cannot be empty before '='");
                return ParseError.EmptyExportName;
            }

            if (internal_part.len == 0) {
                self.setError(ParseError.EmptyExportName, line_number, line, "Internal name cannot be empty after '='");
                return ParseError.EmptyExportName;
            }

            exp.name = self.allocator.dupe(u8, name_part) catch return ParseError.OutOfMemory;
            exp.internal_name = self.allocator.dupe(u8, internal_part) catch return ParseError.OutOfMemory;
        } else {
            if (remaining.len == 0) {
                self.setError(ParseError.EmptyExportName, line_number, line, "Export name cannot be empty");
                return ParseError.EmptyExportName;
            }
            exp.name = self.allocator.dupe(u8, remaining) catch return ParseError.OutOfMemory;
        }

        return exp;
    }
};

test "def parser error handling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test empty export name
    {
        var parser = DefParser.init(allocator);
        defer parser.deinit();

        const def_content =
            \\EXPORTS
            \\    ValidFunction
            \\    =InternalName
            \\    AnotherFunction
        ;

        const result = parser.parse(def_content);
        try std.testing.expectError(ParseError.EmptyExportName, result);

        if (parser.getLastError()) |error_info| {
            try std.testing.expect(error_info.error_type == ParseError.EmptyExportName);
            try std.testing.expect(error_info.line_number == 3);
        }
    }

    // Test invalid ordinal
    {
        var parser = DefParser.init(allocator);
        defer parser.deinit();

        const def_content =
            \\EXPORTS
            \\    TestFunction @abc
        ;

        const result = parser.parse(def_content);
        try std.testing.expectError(ParseError.InvalidOrdinal, result);

        if (parser.getLastError()) |error_info| {
            try std.testing.expect(error_info.error_type == ParseError.InvalidOrdinal);
            try std.testing.expect(error_info.line_number == 2);
        }
    }

    // Test missing name
    {
        var parser = DefParser.init(allocator);
        defer parser.deinit();

        const def_content =
            \\NAME
        ;

        const result = parser.parse(def_content);
        try std.testing.expectError(ParseError.MissingName, result);
    }

    // Test malformed description
    {
        var parser = DefParser.init(allocator);
        defer parser.deinit();

        const def_content =
            \\DESCRIPTION "Unclosed quote
        ;

        const result = parser.parse(def_content);
        try std.testing.expectError(ParseError.MalformedDescription, result);
    }

    // Test duplicate exports section
    {
        var parser = DefParser.init(allocator);
        defer parser.deinit();

        const def_content =
            \\EXPORTS
            \\    Function1
            \\EXPORTS
            \\    Function2
        ;

        const result = parser.parse(def_content);
        try std.testing.expectError(ParseError.DuplicateSection, result);
    }

    // Test unknown section
    {
        var parser = DefParser.init(allocator);
        defer parser.deinit();

        const def_content =
            \\InvalidDirective
        ;

        const result = parser.parse(def_content);
        try std.testing.expectError(ParseError.UnknownSection, result);
    }
}

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
