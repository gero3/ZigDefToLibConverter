const std = @import("std");
const DefParser = @import("def_parser.zig").DefParser;
const CoffGenerator = @import("coff_generator.zig").CoffGenerator;

pub const ModuleDefinition = @import("def_parser.zig").ModuleDefinition;
pub const Export = @import("def_parser.zig").Export;
pub const ExportType = @import("def_parser.zig").ExportType;

pub const ConversionOptions = struct {
    kill_at: bool = false,
    machine_type: MachineType = .amd64,

    pub const MachineType = enum {
        i386,
        amd64,
    };
};

pub const ConversionError = error{
    ParseError,
    GenerationError,
    OutOfMemory,
};

/// Convert DEF file content to LIB file content in memory
/// Returns owned slice that must be freed by caller
pub fn convertDefToLib(
    allocator: std.mem.Allocator,
    def_content: []const u8,
    options: ConversionOptions,
) ConversionError![]u8 {
    // Parse the DEF content
    var def_parser = DefParser.init(allocator);
    defer def_parser.deinit();

    const module_def = def_parser.parse(def_content) catch {
        return ConversionError.ParseError;
    };
    var module_def_copy = module_def;
    defer module_def_copy.deinit(allocator);

    // Generate the COFF library content
    var coff_generator = CoffGenerator.init(allocator);
    defer coff_generator.deinit();

    const lib_content = coff_generator.generateInMemory(module_def_copy, options.kill_at) catch {
        return ConversionError.GenerationError;
    };

    return lib_content;
}

/// Parse DEF content and return module definition
/// Caller owns the returned ModuleDefinition and must call deinit()
pub fn parseDefContent(
    allocator: std.mem.Allocator,
    def_content: []const u8,
) ConversionError!ModuleDefinition {
    var def_parser = DefParser.init(allocator);
    defer def_parser.deinit();

    return def_parser.parse(def_content) catch |err| switch (err) {
        error.OutOfMemory => return ConversionError.OutOfMemory,
        else => return ConversionError.ParseError,
    };
}

/// Generate COFF library content from module definition
/// Returns owned slice that must be freed by caller
pub fn generateLibContent(
    allocator: std.mem.Allocator,
    module_def: ModuleDefinition,
    options: ConversionOptions,
) ConversionError![]u8 {
    var coff_generator = CoffGenerator.init(allocator);
    defer coff_generator.deinit();

    return coff_generator.generateInMemory(module_def, options.kill_at) catch |err| switch (err) {
        error.OutOfMemory => return ConversionError.OutOfMemory,
        else => return ConversionError.GenerationError,
    };
}

test "basic def to lib conversion" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const def_content =
        \\NAME TestLibrary
        \\EXPORTS
        \\    TestFunction
        \\    TestData DATA
    ;

    const options = ConversionOptions{};
    const lib_content = try convertDefToLib(allocator, def_content, options);
    defer allocator.free(lib_content);

    // Check basic archive format
    try testing.expect(lib_content.len > 8);
    try testing.expectEqualSlices(u8, "!<arch>\n", lib_content[0..8]);
}

test "kill-at option" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const def_content =
        \\NAME TestLibrary
        \\EXPORTS
        \\    TestFunction@12
    ;

    // Test without kill-at
    const options_normal = ConversionOptions{ .kill_at = false };
    const lib_normal = try convertDefToLib(allocator, def_content, options_normal);
    defer allocator.free(lib_normal);

    // Test with kill-at
    const options_killat = ConversionOptions{ .kill_at = true };
    const lib_killat = try convertDefToLib(allocator, def_content, options_killat);
    defer allocator.free(lib_killat);

    // Both should be valid archives
    try testing.expectEqualSlices(u8, "!<arch>\n", lib_normal[0..8]);
    try testing.expectEqualSlices(u8, "!<arch>\n", lib_killat[0..8]);
}
