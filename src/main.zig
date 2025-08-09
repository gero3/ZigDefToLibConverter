const std = @import("std");
const def2lib = @import("def2lib.zig");
const print = std.debug.print;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Check for help flag first
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            print("Usage: def2lib <input.def> [output.lib] [--kill-at]\n", .{});
            print("Convert Windows module definition (.def) files to COFF library (.lib) files\n", .{});
            print("\n", .{});
            print("Options:\n", .{});
            print("  input.def    Input module definition file\n", .{});
            print("  output.lib   Output library file (optional, defaults to input basename)\n", .{});
            print("  --kill-at    Remove '@' decoration from exported symbols (stdcall)\n", .{});
            return;
        }
    }

    if (args.len < 2) {
        print("Usage: def2lib <input.def> [output.lib] [--kill-at]\n", .{});
        print("Convert Windows module definition (.def) files to COFF library (.lib) files\n", .{});
        print("\n", .{});
        print("Options:\n", .{});
        print("  input.def    Input module definition file\n", .{});
        print("  output.lib   Output library file (optional, defaults to input basename)\n", .{});
        print("  --kill-at    Remove '@' decoration from exported symbols (stdcall)\n", .{});
        return;
    }

    const input_file = args[1];

    // Parse command line arguments
    var output_file: []const u8 = undefined;
    var kill_at = false;

    // Check for --kill-at flag in any position
    for (args[2..]) |arg| {
        if (std.mem.eql(u8, arg, "--kill-at")) {
            kill_at = true;
        }
    }

    // Determine output file name
    output_file = blk: {
        // Look for output file (non-flag argument)
        if (args.len >= 3 and !std.mem.startsWith(u8, args[2], "--")) {
            break :blk args[2];
        } else if (args.len >= 4 and !std.mem.startsWith(u8, args[3], "--")) {
            break :blk args[3];
        } else {
            // Generate output filename from input filename
            const basename = std.fs.path.stem(input_file);
            break :blk try std.fmt.allocPrint(allocator, "{s}.lib", .{basename});
        }
    };

    const should_free_output = (args.len < 3 or std.mem.startsWith(u8, args[2], "--")) and
        (args.len < 4 or std.mem.startsWith(u8, args[3], "--"));
    defer if (should_free_output) allocator.free(output_file);

    print("Converting {s} to {s}...\n", .{ input_file, output_file });
    if (kill_at) print("Symbol decoration removal enabled (--kill-at)\n", .{});

    // Read the DEF file
    const def_content = std.fs.cwd().readFileAlloc(allocator, input_file, 1024 * 1024) catch |err| {
        print("Error reading file {s}: {}\n", .{ input_file, err });
        return;
    };
    defer allocator.free(def_content);

    // Convert DEF to LIB using the library
    const options = def2lib.ConversionOptions{
        .kill_at = kill_at,
    };

    const lib_content = def2lib.convertDefToLib(allocator, def_content, options) catch |err| {
        print("Error converting DEF to LIB: {}\n", .{err});

        // If it's a parse error, try to get detailed error information
        switch (err) {
            def2lib.ParseError.InvalidSyntax, def2lib.ParseError.MissingName, def2lib.ParseError.InvalidOrdinal, def2lib.ParseError.EmptyExportName, def2lib.ParseError.MalformedDescription, def2lib.ParseError.MalformedVersion, def2lib.ParseError.UnknownSection, def2lib.ParseError.DuplicateSection => {
                if (def2lib.getLastParseError(allocator, def_content)) |error_info| {
                    print("Parse error details:\n", .{});
                    print("  Line {}: {s}\n", .{ error_info.line_number, error_info.line_content });
                    print("  Error: {s}\n", .{error_info.message});
                }
            },
            else => {},
        }
        return;
    };
    defer allocator.free(lib_content);

    // Write the output file
    const file = std.fs.cwd().createFile(output_file, .{}) catch |err| {
        print("Error creating output file {s}: {}\n", .{ output_file, err });
        return;
    };
    defer file.close();

    file.writeAll(lib_content) catch |err| {
        print("Error writing output file: {}\n", .{err});
        return;
    };

    print("Successfully generated {s}\n", .{output_file});
}

test "main functionality" {
    // Basic test to ensure main module compiles
    try std.testing.expect(true);
}
