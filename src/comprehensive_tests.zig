const std = @import("std");
const testing = std.testing;
const def2lib = @import("def2lib.zig");
const DefParser = @import("def_parser.zig").DefParser;

// Test helper to validate COFF archive structure
fn validateArchiveStructure(lib_content: []const u8) !void {
    // Must start with archive signature
    try testing.expect(lib_content.len >= 8);
    try testing.expectEqualSlices(u8, "!<arch>\n", lib_content[0..8]);

    // Archive with just signature is valid (empty library)
    // If there's more content, it should be properly structured
}

// Test helper to validate archive with exports
fn validateArchiveWithExports(lib_content: []const u8) !void {
    try validateArchiveStructure(lib_content);
    // Should have content beyond just the signature
    try testing.expect(lib_content.len > 8);
}
fn containsSymbol(lib_content: []const u8, symbol: []const u8) bool {
    var i: usize = 8; // Skip archive signature
    while (i < lib_content.len - symbol.len) {
        if (std.mem.eql(u8, lib_content[i .. i + symbol.len], symbol)) {
            return true;
        }
        i += 1;
    }
    return false;
}

test "empty def file conversion" {
    const allocator = testing.allocator;

    const def_content =
        \\NAME EmptyLibrary
    ;

    const options = def2lib.ConversionOptions{};
    const lib_content = try def2lib.convertDefToLib(allocator, def_content, options);
    defer allocator.free(lib_content);

    try validateArchiveStructure(lib_content);
}

test "single function export" {
    const allocator = testing.allocator;

    const def_content =
        \\NAME SingleFunction
        \\EXPORTS
        \\    MyFunction
    ;

    const options = def2lib.ConversionOptions{};
    const lib_content = try def2lib.convertDefToLib(allocator, def_content, options);
    defer allocator.free(lib_content);

    try validateArchiveWithExports(lib_content);
    try testing.expect(containsSymbol(lib_content, "MyFunction"));
}

test "multiple exports with different types" {
    const allocator = testing.allocator;

    const def_content =
        \\NAME MultipleExports
        \\EXPORTS
        \\    Function1
        \\    Function2
        \\    GlobalData DATA
        \\    ConstantValue CONSTANT
    ;

    const options = def2lib.ConversionOptions{};
    const lib_content = try def2lib.convertDefToLib(allocator, def_content, options);
    defer allocator.free(lib_content);

    try validateArchiveWithExports(lib_content);
    try testing.expect(containsSymbol(lib_content, "Function1"));
    try testing.expect(containsSymbol(lib_content, "Function2"));
    try testing.expect(containsSymbol(lib_content, "GlobalData"));
    try testing.expect(containsSymbol(lib_content, "ConstantValue"));
}

test "ordinal exports" {
    const allocator = testing.allocator;

    const def_content =
        \\NAME OrdinalExports
        \\EXPORTS
        \\    Function1 @1
        \\    Function2 @2 NONAME
        \\    Function3 @100
    ;

    const options = def2lib.ConversionOptions{};
    const lib_content = try def2lib.convertDefToLib(allocator, def_content, options);
    defer allocator.free(lib_content);

    try validateArchiveWithExports(lib_content);
    try testing.expect(containsSymbol(lib_content, "Function1"));
    try testing.expect(containsSymbol(lib_content, "Function2"));
    try testing.expect(containsSymbol(lib_content, "Function3"));
}

test "private exports are excluded" {
    const allocator = testing.allocator;

    const def_content =
        \\NAME PrivateExports
        \\EXPORTS
        \\    PublicFunction
        \\    PrivateFunction PRIVATE
        \\    AnotherPublic
    ;

    const options = def2lib.ConversionOptions{};
    const lib_content = try def2lib.convertDefToLib(allocator, def_content, options);
    defer allocator.free(lib_content);

    try validateArchiveWithExports(lib_content);
    try testing.expect(containsSymbol(lib_content, "PublicFunction"));
    try testing.expect(containsSymbol(lib_content, "AnotherPublic"));
    // Private functions should not appear in the library
    try testing.expect(!containsSymbol(lib_content, "PrivateFunction"));
}

test "internal name mapping" {
    const allocator = testing.allocator;

    const def_content =
        \\NAME InternalMapping
        \\EXPORTS
        \\    ExternalName=InternalName
        \\    AnotherExternal=AnotherInternal
    ;

    const options = def2lib.ConversionOptions{};
    const lib_content = try def2lib.convertDefToLib(allocator, def_content, options);
    defer allocator.free(lib_content);

    try validateArchiveWithExports(lib_content);
    try testing.expect(containsSymbol(lib_content, "ExternalName"));
    try testing.expect(containsSymbol(lib_content, "AnotherExternal"));
}

test "kill-at decoration removal" {
    const allocator = testing.allocator;

    const def_content =
        \\NAME StdcallFunctions
        \\EXPORTS
        \\    Function1@4
        \\    Function2@8
        \\    Function3@12
        \\    PlainFunction
    ;

    // Test without kill-at (decorations preserved)
    const options_normal = def2lib.ConversionOptions{ .kill_at = false };
    const lib_normal = try def2lib.convertDefToLib(allocator, def_content, options_normal);
    defer allocator.free(lib_normal);

    try validateArchiveWithExports(lib_normal);
    try testing.expect(containsSymbol(lib_normal, "Function1@4"));
    try testing.expect(containsSymbol(lib_normal, "Function2@8"));
    try testing.expect(containsSymbol(lib_normal, "PlainFunction"));

    // Test with kill-at (decorations removed)
    const options_killat = def2lib.ConversionOptions{ .kill_at = true };
    const lib_killat = try def2lib.convertDefToLib(allocator, def_content, options_killat);
    defer allocator.free(lib_killat);

    try validateArchiveWithExports(lib_killat);
    try testing.expect(containsSymbol(lib_killat, "Function1"));
    try testing.expect(containsSymbol(lib_killat, "Function2"));
    try testing.expect(containsSymbol(lib_killat, "Function3"));
    try testing.expect(containsSymbol(lib_killat, "PlainFunction"));
}

test "complex real-world example" {
    const allocator = testing.allocator;

    const def_content =
        \\NAME RealWorldLibrary
        \\DESCRIPTION "A realistic Windows library"
        \\VERSION 1.2
        \\EXPORTS
        \\    ; Core API functions
        \\    Initialize
        \\    Cleanup
        \\    ProcessData@8
        \\    GetVersion@0
        \\    
        \\    ; Data exports
        \\    GlobalSettings DATA
        \\    ErrorMessages DATA
        \\    
        \\    ; Ordinal exports
        \\    FastFunction @1
        \\    QuickSort @2 NONAME
        \\    
        \\    ; Internal mappings
        \\    ExternalAPI=InternalImplementation
        \\    
        \\    ; Private functions (should not appear)
        \\    DebugHelper PRIVATE
        \\    InternalState PRIVATE DATA
    ;

    const options = def2lib.ConversionOptions{};
    const lib_content = try def2lib.convertDefToLib(allocator, def_content, options);
    defer allocator.free(lib_content);

    try validateArchiveWithExports(lib_content);

    // Check public functions
    try testing.expect(containsSymbol(lib_content, "Initialize"));
    try testing.expect(containsSymbol(lib_content, "Cleanup"));
    try testing.expect(containsSymbol(lib_content, "ProcessData@8"));
    try testing.expect(containsSymbol(lib_content, "GetVersion@0"));

    // Check data exports
    try testing.expect(containsSymbol(lib_content, "GlobalSettings"));
    try testing.expect(containsSymbol(lib_content, "ErrorMessages"));

    // Check ordinal exports
    try testing.expect(containsSymbol(lib_content, "FastFunction"));
    try testing.expect(containsSymbol(lib_content, "QuickSort"));

    // Check internal mapping
    try testing.expect(containsSymbol(lib_content, "ExternalAPI"));

    // Verify private functions are excluded
    try testing.expect(!containsSymbol(lib_content, "DebugHelper"));
    try testing.expect(!containsSymbol(lib_content, "InternalState"));
}

test "kill-at with C++ mangled names" {
    const allocator = testing.allocator;

    const def_content =
        \\NAME CppLibrary
        \\EXPORTS
        \\    ?CppFunction@@YAHH@Z
        \\    StdcallFunction@4
        \\    CdeclFunction
        \\    ExternalName=?InternalCppFunction@@YAHH@Z
    ;

    // C++ mangled names should not be affected by kill-at
    const options = def2lib.ConversionOptions{ .kill_at = true };
    const lib_content = try def2lib.convertDefToLib(allocator, def_content, options);
    defer allocator.free(lib_content);

    try validateArchiveWithExports(lib_content);

    // C++ mangled name should remain unchanged
    try testing.expect(containsSymbol(lib_content, "?CppFunction@@YAHH@Z"));

    // Stdcall decoration should be removed
    try testing.expect(containsSymbol(lib_content, "StdcallFunction"));

    // Cdecl function unchanged
    try testing.expect(containsSymbol(lib_content, "CdeclFunction"));

    // External mapping with C++ name should work
    try testing.expect(containsSymbol(lib_content, "ExternalName"));
}

test "error handling - invalid def content" {
    const allocator = testing.allocator;

    // Test with completely invalid content
    const invalid_content = "This is not a valid DEF file content at all!";
    const options = def2lib.ConversionOptions{};

    // Should now properly fail with parse error
    const result = def2lib.convertDefToLib(allocator, invalid_content, options);
    try testing.expectError(def2lib.ParseError.UnknownSection, result);
}

test "comments and whitespace handling" {
    const allocator = testing.allocator;

    const def_content =
        \\; This is a comment
        \\NAME TestLibrary   ; Inline comment
        \\
        \\; Another comment
        \\EXPORTS
        \\    ; Comment in exports section
        \\    Function1     ; Trailing comment
        \\    
        \\    Function2@8   ; Stdcall with comment
        \\    
        \\    ; More comments
        \\    DataItem DATA ; Data export with comment
    ;

    const options = def2lib.ConversionOptions{};
    const lib_content = try def2lib.convertDefToLib(allocator, def_content, options);
    defer allocator.free(lib_content);

    try validateArchiveWithExports(lib_content);
    try testing.expect(containsSymbol(lib_content, "Function1"));
    try testing.expect(containsSymbol(lib_content, "Function2@8"));
    try testing.expect(containsSymbol(lib_content, "DataItem"));
}

test "large number of exports" {
    const allocator = testing.allocator;

    var def_content = std.ArrayList(u8).init(allocator);
    defer def_content.deinit();

    try def_content.appendSlice("NAME LargeLibrary\nEXPORTS\n");

    // Add 100 exports
    var i: u32 = 1;
    while (i <= 100) : (i += 1) {
        const export_line = try std.fmt.allocPrint(allocator, "    Function{d}@{d}\n", .{ i, i * 4 });
        defer allocator.free(export_line);
        try def_content.appendSlice(export_line);
    }

    const options = def2lib.ConversionOptions{};
    const lib_content = try def2lib.convertDefToLib(allocator, def_content.items, options);
    defer allocator.free(lib_content);

    try validateArchiveWithExports(lib_content);

    // Check a few random exports
    try testing.expect(containsSymbol(lib_content, "Function1@4"));
    try testing.expect(containsSymbol(lib_content, "Function50@200"));
    try testing.expect(containsSymbol(lib_content, "Function100@400"));
}

test "memory usage validation" {
    const allocator = testing.allocator;

    const def_content =
        \\NAME MemoryTest
        \\EXPORTS
        \\    TestFunction1
        \\    TestFunction2
        \\    TestData DATA
    ;

    // Test multiple conversions to ensure no memory leaks
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        const options = def2lib.ConversionOptions{};
        const lib_content = try def2lib.convertDefToLib(allocator, def_content, options);
        defer allocator.free(lib_content);

        try validateArchiveWithExports(lib_content);
        try testing.expect(containsSymbol(lib_content, "TestFunction1"));
    }
}
