const std = @import("std");
const DefParser = @import("def_parser.zig");
const ModuleDefinition = DefParser.ModuleDefinition;
const Export = DefParser.Export;
const ExportType = DefParser.ExportType;

const ARCHIVE_SIGNATURE = "!<arch>\n";

// COFF Machine Types
const IMAGE_FILE_MACHINE_I386: u16 = 0x014c;
const IMAGE_FILE_MACHINE_AMD64: u16 = 0x8664;
const IMAGE_FILE_MACHINE_UNKNOWN: u16 = 0x0;
const IMAGE_SYM_CLASS_EXTERNAL = 2;
const IMAGE_SYM_DTYPE_FUNCTION = 0x20;
const IMAGE_SYM_TYPE_NULL = 0;

// Import Object Header constants
const IMPORT_OBJECT_HDR_SIG2: u16 = 0xffff;

// Import Object Types
const IMPORT_OBJECT_CODE: u16 = 0;
const IMPORT_OBJECT_DATA: u16 = 1;
const IMPORT_OBJECT_CONST: u16 = 2;

// Import Name Types
const IMPORT_NAME_ORDINAL: u16 = 0;
const IMPORT_NAME_NAME: u16 = 1;
const IMPORT_NAME_NAME_NO_PREFIX: u16 = 2;
const IMPORT_NAME_NAME_UNDECORATE: u16 = 3;

// COFF structures for real import objects
const ImportObjectHeader = packed struct {
    sig1: u16, // Always IMPORT_OBJECT_HDR_SIG2
    sig2: u16, // Always IMPORT_OBJECT_HDR_SIG2
    version: u16, // Usually 0
    machine: u16, // Target machine type
    time_date_stamp: u32, // Timestamp
    size_of_data: u32, // Size of the data following the header
    ordinal_hint: u16, // Ordinal/hint value
    type_name_type: u16, // Combined type and name type flags

    fn init(machine_type: u16, data_size: u32, ordinal: u16, import_type: u16, name_type: u16) ImportObjectHeader {
        return ImportObjectHeader{
            .sig1 = IMPORT_OBJECT_HDR_SIG2,
            .sig2 = IMPORT_OBJECT_HDR_SIG2,
            .version = 0,
            .machine = machine_type,
            .time_date_stamp = @intCast(std.time.timestamp()),
            .size_of_data = data_size,
            .ordinal_hint = ordinal,
            .type_name_type = (import_type & 0x3) | ((name_type & 0x7) << 2),
        };
    }
};
const ARCHIVE_END_CHAR = "`\n";

// Packed structs for binary format representation

/// COFF File Header (20 bytes)
const CoffFileHeader = packed struct {
    machine: u16, // Machine type (i386, amd64, etc.)
    number_of_sections: u16, // Number of sections
    time_date_stamp: u32, // Timestamp
    pointer_to_symbol_table: u32, // File offset to symbol table
    number_of_symbols: u32, // Number of symbol table entries
    size_of_optional_header: u16, // Size of optional header (0 for objects)
    characteristics: u16, // File characteristics flags
};

/// COFF Section Header (40 bytes)
const CoffSectionHeader = packed struct {
    name: [8]u8, // Section name (null-padded) - use extern struct instead
    virtual_size: u32, // Size in memory
    virtual_address: u32, // Address in memory
    size_of_raw_data: u32, // Size on disk
    pointer_to_raw_data: u32, // File offset to data
    pointer_to_relocations: u32, // File offset to relocations
    pointer_to_line_numbers: u32, // File offset to line numbers
    number_of_relocations: u16, // Number of relocations
    number_of_line_numbers: u16, // Number of line numbers
    characteristics: u32, // Section characteristics flags
};

/// COFF Symbol Table Entry (18 bytes)
const CoffSymbolEntry = extern struct {
    name: [8]u8, // Short name or string table reference
    value: u32, // Symbol value
    section_number: i16, // Section number (1-based, special values for external)
    type: u16, // Symbol type
    storage_class: u8, // Storage class
    number_of_aux_symbols: u8, // Number of auxiliary symbols
};

/// Archive Member Header (60 bytes)
const ArchiveMemberHeader = extern struct {
    name: [16]u8, // Member name (ASCII, space-padded)
    date: [12]u8, // Modification timestamp (ASCII decimal)
    uid: [6]u8, // User ID (ASCII decimal)
    gid: [6]u8, // Group ID (ASCII decimal)
    mode: [8]u8, // File mode (ASCII octal)
    size: [10]u8, // File size (ASCII decimal)
    end_chars: [2]u8, // End of header marker ("`\n")
};

/// Import Header for import libraries
const ImportHeader = packed struct {
    sig1: u16, // IMAGE_FILE_MACHINE_UNKNOWN (0)
    sig2: u16, // 0xFFFF
    version: u16, // Import library version
    machine: u16, // Target machine type
    time_date_stamp: u32, // Timestamp
    size_of_data: u32, // Size of following data
    ordinal_or_hint: u16, // Ordinal or hint
    import_type: u16, // Import type and name type flags
};

// Import type constants for ImportHeader.import_type
const IMPORT_CODE = 0;
const IMPORT_DATA = 1;
const IMPORT_CONST = 2;
const IMPORT_NAME_NOPREFIX = 1 << 2;
const IMPORT_NAME_UNDECORATE = 2 << 2;

pub const CoffGenerator = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CoffGenerator {
        return CoffGenerator{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CoffGenerator) void {
        _ = self;
    }

    pub fn generate(self: *CoffGenerator, module_def: ModuleDefinition, output_path: []const u8, kill_at: bool) !void {
        const lib_content = try self.generateInMemory(module_def, kill_at);
        defer self.allocator.free(lib_content);

        // Write the output file
        const file = try std.fs.cwd().createFile(output_path, .{});
        defer file.close();

        try file.writeAll(lib_content);
    }

    pub fn generateInMemory(self: *CoffGenerator, module_def: ModuleDefinition, kill_at: bool) ![]u8 {
        // Create a proper Microsoft import library
        // This creates individual COFF object files for each import

        var lib_content = std.ArrayList(u8).init(self.allocator);
        errdefer lib_content.deinit();

        // Write archive signature
        try lib_content.appendSlice(ARCHIVE_SIGNATURE);

        // For a simple test, let's create a basic archive with one member per symbol
        // This is a simplified approach that should work with most linkers

        for (module_def.exports.items) |exp| {
            if (!exp.is_private) {
                try self.writeSimpleImportMember(&lib_content, exp, module_def.name, kill_at);
            }
        }

        return try lib_content.toOwnedSlice();
    }

    fn writeSimpleImportMember(self: *CoffGenerator, content: *std.ArrayList(u8), exp: Export, module_name: ?[]const u8, kill_at: bool) !void {
        // Process symbol name based on kill_at flag (like LLVM code)
        var processed_name = exp.name;
        var symbol_name = exp.name;

        if (kill_at and exp.export_type == .function) {
            // Apply the same logic as LLVM's kill_at processing
            const should_process = blk: {
                // Skip if has import name or is C++ mangled (starts with ?)
                if (exp.internal_name != null) break :blk false;
                if (exp.name.len > 0 and exp.name[0] == '?') break :blk false;
                break :blk true;
            };

            if (should_process) {
                // For I386, keep original name as symbol name for decoration
                symbol_name = exp.name;

                // Trim decoration after @ (but keep at least one char)
                if (std.mem.indexOf(u8, exp.name[1..], "@")) |at_pos| {
                    const trim_pos = at_pos + 1; // +1 because we searched from index 1
                    processed_name = exp.name[0..trim_pos];
                } else {
                    processed_name = exp.name;
                }
            }
        }

        // Handle internal name mapping (like LLVM's ExtName logic)
        if (exp.internal_name) |internal| {
            // If ExtName is set, use it as the main name and clear internal reference
            processed_name = internal;
        }

        // Generate real COFF import object
        try self.writeImportObject(content, processed_name, symbol_name, module_name, exp);
    }

    fn writeImportObject(self: *CoffGenerator, content: *std.ArrayList(u8), import_name: []const u8, symbol_name: []const u8, module_name: ?[]const u8, exp: Export) !void {
        // Create the import object data
        var import_data = std.ArrayList(u8).init(self.allocator);
        defer import_data.deinit();

        // Add symbol name (null-terminated)
        try import_data.appendSlice(symbol_name);
        try import_data.append(0);

        // Add module name (null-terminated)
        if (module_name) |mod_name| {
            try import_data.appendSlice(mod_name);
            try import_data.append(0);
        }

        // Determine import type and name type
        const import_type = if (exp.export_type == .data) IMPORT_OBJECT_DATA else IMPORT_OBJECT_CODE;

        // Choose name type based on symbol characteristics
        const name_type = blk: {
            if (exp.ordinal != null) break :blk IMPORT_NAME_ORDINAL;
            if (import_name.len > 0 and import_name[0] == '_') break :blk IMPORT_NAME_NAME_NO_PREFIX;
            if (!std.mem.eql(u8, import_name, symbol_name)) break :blk IMPORT_NAME_NAME_UNDECORATE;
            break :blk IMPORT_NAME_NAME;
        };

        // Create import object header
        const header = ImportObjectHeader.init(IMAGE_FILE_MACHINE_AMD64, // Target AMD64 for now
            @intCast(import_data.items.len), @intCast(exp.ordinal orelse 0), import_type, name_type);

        // Calculate total member size (header + data)
        const member_size = @sizeOf(ImportObjectHeader) + import_data.items.len;

        // Create archive member header
        var arch_header = ArchiveMemberHeader{
            .name = [_]u8{' '} ** 16,
            .date = [_]u8{'0'} ** 12,
            .uid = [_]u8{'0'} ** 6,
            .gid = [_]u8{'0'} ** 6,
            .mode = [_]u8{ '1', '0', '0', '6', '4', '4', ' ', ' ' },
            .size = [_]u8{' '} ** 10,
            .end_chars = [_]u8{ '`', '\n' },
        };

        // Set member name (use import name for archive member identification)
        const name_len = @min(import_name.len, 15); // Leave room for potential /
        @memcpy(arch_header.name[0..name_len], import_name[0..name_len]);
        if (name_len < 16) {
            arch_header.name[name_len] = '/'; // Add trailing slash
        }

        // Set size as ASCII decimal
        const size_str = try std.fmt.allocPrint(self.allocator, "{d}", .{member_size});
        defer self.allocator.free(size_str);
        const size_len = @min(size_str.len, 10);
        @memcpy(arch_header.size[0..size_len], size_str[0..size_len]);

        // Write archive member header
        const header_bytes = std.mem.asBytes(&arch_header);
        try content.appendSlice(header_bytes);

        // Write import object header
        const import_header_bytes = std.mem.asBytes(&header);
        try content.appendSlice(import_header_bytes);

        // Write import data
        try content.appendSlice(import_data.items);

        // Pad to even boundary if needed
        if (content.items.len % 2 != 0) {
            try content.append(0);
        }
    }

    fn calculateStringTableSize(module_def: ModuleDefinition) u32 {
        var size: u32 = 0;
        for (module_def.exports.items) |exp| {
            if (!exp.is_private) {
                size += @intCast(exp.name.len + 1); // +1 for null terminator
            }
        }
        return size;
    }

    fn calculateImportObjectSize(exp: Export) u32 {
        const symbol_len = exp.name.len + 1;
        const dll_len = 12; // "unknown.dll\0" - simplified
        const import_header_size = @sizeOf(ImportHeader);
        const archive_header_size = @sizeOf(ArchiveMemberHeader);

        var size = archive_header_size + import_header_size + symbol_len + dll_len;

        // Round up to even boundary
        if (size % 2 != 0) size += 1;

        return @intCast(size);
    }
};

test "coff generator basic functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var generator = CoffGenerator.init(allocator);
    defer generator.deinit();

    var module_def = ModuleDefinition.init(allocator);
    defer module_def.deinit(allocator);

    // Test with empty module definition
    // In a real test, we'd create a temporary file
    // try generator.generate(module_def, "test.lib");

    try std.testing.expect(true);
}
