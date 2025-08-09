const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: inspect_lib <library_file>\n", .{});
        return;
    }

    const lib_file = args[1];
    const content = try std.fs.cwd().readFileAlloc(allocator, lib_file, 1024 * 1024);
    defer allocator.free(content);

    std.debug.print("Inspecting library: {s}\n", .{lib_file});
    std.debug.print("File size: {d} bytes\n", .{content.len});

    if (content.len < 8) {
        std.debug.print("File too small to be a valid library\n", .{});
        return;
    }

    // Check archive signature
    if (std.mem.startsWith(u8, content, "!<arch>\n")) {
        std.debug.print("✓ Valid archive signature found\n", .{});

        var offset: usize = 8; // Skip signature
        var member_count: u32 = 0;

        while (offset + 60 <= content.len) { // 60 = sizeof(ArchiveMemberHeader)

            // Read member name (first 16 bytes)
            const name_bytes = content[offset .. offset + 16];
            const name = std.mem.trim(u8, name_bytes, " \x00");

            // Read size (bytes 48-58)
            const size_bytes = content[offset + 48 .. offset + 58];
            const size_str = std.mem.trim(u8, size_bytes, " \x00");

            const size = std.fmt.parseInt(usize, size_str, 10) catch {
                std.debug.print("Invalid size field in member header\n", .{});
                break;
            };

            std.debug.print("Member {d}: '{s}' (size: {d} bytes)\n", .{ member_count, name, size });

            // Skip to member content
            offset += 60; // Archive header size

            // Show first few bytes of content if it's text
            if (size > 0 and offset + size <= content.len) {
                const member_content = content[offset .. offset + @min(size, 100)];
                if (std.ascii.isPrint(member_content[0])) {
                    std.debug.print("  Content preview: {s}\n", .{member_content[0..@min(size, 50)]});
                }
            }

            // Move to next member (with padding)
            offset += size;
            if (offset % 2 == 1) offset += 1; // Align to even boundary

            member_count += 1;
            if (member_count > 20) break; // Prevent infinite loop
        }

        std.debug.print("Total members found: {d}\n", .{member_count});
    } else {
        std.debug.print("✗ Not a valid archive (missing signature)\n", .{});
    }
}
