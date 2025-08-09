const std = @import("std");
const testing = std.testing;
const def2lib = @import("def2lib.zig");

test "performance benchmark - small library" {
    const allocator = testing.allocator;

    const def_content =
        \\NAME SmallLibrary
        \\EXPORTS
        \\    Function1
        \\    Function2
        \\    Function3
        \\    Function4
        \\    Function5
    ;

    const iterations = 1000;
    const start_time = std.time.nanoTimestamp();

    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        const options = def2lib.ConversionOptions{};
        const lib_content = try def2lib.convertDefToLib(allocator, def_content, options);
        allocator.free(lib_content);
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ns = end_time - start_time;
    const duration_ms = @divTrunc(duration_ns, 1_000_000);

    std.debug.print("Small library ({} iterations): {}ms, {:.2}ms per conversion\n", .{ iterations, duration_ms, @as(f64, @floatFromInt(duration_ms)) / @as(f64, @floatFromInt(iterations)) });

    // Should be fast - less than 1ms per conversion on average
    try testing.expect(duration_ms < iterations);
}

test "performance benchmark - medium library" {
    const allocator = testing.allocator;

    // Create a medium-sized DEF file
    var def_content = std.ArrayList(u8).init(allocator);
    defer def_content.deinit();

    try def_content.appendSlice("NAME MediumLibrary\nEXPORTS\n");

    // Add 50 exports
    var i: u32 = 1;
    while (i <= 50) : (i += 1) {
        const export_line = try std.fmt.allocPrint(allocator, "    Function{d}@{d}\n", .{ i, i * 4 });
        defer allocator.free(export_line);
        try def_content.appendSlice(export_line);
    }

    const iterations = 100;
    const start_time = std.time.nanoTimestamp();

    var iter: u32 = 0;
    while (iter < iterations) : (iter += 1) {
        const options = def2lib.ConversionOptions{};
        const lib_content = try def2lib.convertDefToLib(allocator, def_content.items, options);
        allocator.free(lib_content);
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ns = end_time - start_time;
    const duration_ms = @divTrunc(duration_ns, 1_000_000);

    std.debug.print("Medium library (50 exports, {} iterations): {}ms, {:.2}ms per conversion\n", .{ iterations, duration_ms, @as(f64, @floatFromInt(duration_ms)) / @as(f64, @floatFromInt(iterations)) });

    // Should still be reasonably fast
    try testing.expect(duration_ms < iterations * 10);
}

test "performance benchmark - large library" {
    const allocator = testing.allocator;

    // Create a large DEF file
    var def_content = std.ArrayList(u8).init(allocator);
    defer def_content.deinit();

    try def_content.appendSlice("NAME LargeLibrary\nEXPORTS\n");

    // Add 500 exports
    var i: u32 = 1;
    while (i <= 500) : (i += 1) {
        const export_line = try std.fmt.allocPrint(allocator, "    Function{d}@{d}\n", .{ i, i * 4 });
        defer allocator.free(export_line);
        try def_content.appendSlice(export_line);
    }

    const iterations = 10;
    const start_time = std.time.nanoTimestamp();

    var iter: u32 = 0;
    while (iter < iterations) : (iter += 1) {
        const options = def2lib.ConversionOptions{};
        const lib_content = try def2lib.convertDefToLib(allocator, def_content.items, options);
        allocator.free(lib_content);
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ns = end_time - start_time;
    const duration_ms = @divTrunc(duration_ns, 1_000_000);

    std.debug.print("Large library (500 exports, {} iterations): {}ms, {:.2}ms per conversion\n", .{ iterations, duration_ms, @as(f64, @floatFromInt(duration_ms)) / @as(f64, @floatFromInt(iterations)) });

    // Should complete in reasonable time
    try testing.expect(duration_ms < iterations * 100);
}

test "memory allocation patterns" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const def_content =
        \\NAME MemoryTest
        \\EXPORTS
        \\    Function1
        \\    Function2@8
        \\    DataItem DATA
        \\    ExternalName=InternalName
    ;

    // Test multiple conversions to check for memory leaks
    const iterations = 100;
    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        const options = def2lib.ConversionOptions{};
        const lib_content = try def2lib.convertDefToLib(allocator, def_content, options);
        allocator.free(lib_content);

        // Trigger garbage collection periodically
        if (i % 10 == 0) {
            _ = gpa.detectLeaks();
        }
    }

    // Final leak check
    try testing.expect(!gpa.detectLeaks());
}

test "concurrent conversion safety" {
    const allocator = testing.allocator;

    const def_content =
        \\NAME ConcurrentTest
        \\EXPORTS
        \\    Function1
        \\    Function2@4
        \\    DataItem DATA
    ;

    // Test that multiple concurrent conversions work correctly
    // (Even though we're not actually running them concurrently in this test,
    // we're testing that the conversion is stateless)

    var results: [10][]u8 = undefined;
    var i: usize = 0;
    while (i < results.len) : (i += 1) {
        const options = def2lib.ConversionOptions{};
        results[i] = try def2lib.convertDefToLib(allocator, def_content, options);
    }
    defer {
        for (results) |result| {
            allocator.free(result);
        }
    }

    // All results should be identical
    for (results[1..]) |result| {
        try testing.expectEqualSlices(u8, results[0], result);
    }
}

test "edge case - extremely long symbol names" {
    const allocator = testing.allocator;

    // Create a symbol with a very long name
    const long_name = "VeryLongFunctionNameThatExceedsTypicalLimitsAndTestsHowWellTheSystemHandlesLongSymbolNamesInWindowsLibrariesWhichShouldStillWorkCorrectly";

    const def_content = try std.fmt.allocPrint(allocator,
        \\NAME LongNamesTest
        \\EXPORTS
        \\    {s}
        \\    {s}@16
        \\    ShortName
    , .{ long_name, long_name });
    defer allocator.free(def_content);

    const options = def2lib.ConversionOptions{};
    const lib_content = try def2lib.convertDefToLib(allocator, def_content, options);
    defer allocator.free(lib_content);

    // Should still create a valid archive
    try testing.expect(lib_content.len >= 8);
    try testing.expectEqualSlices(u8, "!<arch>\n", lib_content[0..8]);
}

test "edge case - unicode and special characters" {
    const allocator = testing.allocator;

    const def_content =
        \\NAME UnicodeTest
        \\EXPORTS
        \\    Function_With_Underscores
        \\    Function-With-Dashes
        \\    Function$With$Dollars
        \\    Function123WithNumbers
    ;

    const options = def2lib.ConversionOptions{};
    const lib_content = try def2lib.convertDefToLib(allocator, def_content, options);
    defer allocator.free(lib_content);

    // Should create valid archive even with special characters
    try testing.expect(lib_content.len >= 8);
    try testing.expectEqualSlices(u8, "!<arch>\n", lib_content[0..8]);
}
