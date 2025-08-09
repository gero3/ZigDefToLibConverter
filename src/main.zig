const std = @import("std");
const DefParser = @import("def_parser.zig").DefParser;
const CoffGenerator = @import("coff_generator.zig").CoffGenerator;
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

    // Read and parse the DEF file
    const def_content = std.fs.cwd().readFileAlloc(allocator, input_file, 1024 * 1024) catch |err| {
        print("Error reading file {s}: {}\n", .{ input_file, err });
        return;
    };
    defer allocator.free(def_content);

    var def_parser = DefParser.init(allocator);
    defer def_parser.deinit();

    var module_def = def_parser.parse(def_content) catch |err| {
        print("Error parsing DEF file: {}\n", .{err});
        return;
    };
    defer module_def.deinit(allocator);

    // Generate COFF library file
    var coff_generator = CoffGenerator.init(allocator);
    defer coff_generator.deinit();

    coff_generator.generate(module_def, output_file, kill_at) catch |err| {
        print("Error generating COFF library: {}\n", .{err});
        return;
    };

    print("Successfully generated {s}\n", .{output_file});
}

test "main functionality" {
    // Basic test to ensure main module compiles
    try std.testing.expect(true);
}
