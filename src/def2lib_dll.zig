const std = @import("std");
const def2lib = @import("def2lib.zig");
const windows = std.os.windows;

// C-compatible allocator for DLL interface
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

// Error codes for C interface
pub const DEF2LIB_SUCCESS: c_int = 0;
pub const DEF2LIB_ERROR_INVALID_INPUT: c_int = -1;
pub const DEF2LIB_ERROR_PARSE_FAILED: c_int = -2;
pub const DEF2LIB_ERROR_GENERATION_FAILED: c_int = -3;
pub const DEF2LIB_ERROR_OUT_OF_MEMORY: c_int = -4;

// C-compatible structure for conversion options
pub const Def2LibOptions = extern struct {
    kill_at: bool,
};

// C-compatible structure for result
pub const Def2LibResult = extern struct {
    data: ?[*]u8,
    size: usize,
    error_code: c_int,
};

// Initialize the library (call once at startup)
export fn def2lib_init() c_int {
    return DEF2LIB_SUCCESS;
}

// Cleanup the library (call once at shutdown)
export fn def2lib_cleanup() void {
    _ = gpa.deinit();
}

// Convert DEF content to LIB content
// Returns allocated memory that must be freed with def2lib_free()
export fn def2lib_convert(
    def_content: [*:0]const u8,
    def_size: usize,
    options: *const Def2LibOptions,
    result: *Def2LibResult,
) c_int {
    // Initialize result
    result.data = null;
    result.size = 0;
    result.error_code = DEF2LIB_SUCCESS;

    // Validate input
    if (def_size == 0) {
        result.error_code = DEF2LIB_ERROR_INVALID_INPUT;
        return DEF2LIB_ERROR_INVALID_INPUT;
    }

    // Convert to Zig slice
    const def_slice = def_content[0..def_size];

    // Set up conversion options
    const conv_options = def2lib.ConversionOptions{
        .kill_at = options.kill_at,
    };

    // Perform conversion
    const lib_content = def2lib.convertDefToLib(allocator, def_slice, conv_options) catch |err| {
        result.error_code = switch (err) {
            def2lib.ConversionError.ParseError => DEF2LIB_ERROR_PARSE_FAILED,
            def2lib.ConversionError.GenerationError => DEF2LIB_ERROR_GENERATION_FAILED,
            def2lib.ConversionError.OutOfMemory => DEF2LIB_ERROR_OUT_OF_MEMORY,
        };
        return result.error_code;
    };

    // Return the result
    result.data = lib_content.ptr;
    result.size = lib_content.len;
    result.error_code = DEF2LIB_SUCCESS;

    return DEF2LIB_SUCCESS;
}

// Free memory allocated by def2lib_convert()
export fn def2lib_free(data: ?[*]u8, size: usize) void {
    if (data) |ptr| {
        const slice = ptr[0..size];
        allocator.free(slice);
    }
}

// Get version information
export fn def2lib_get_version() [*:0]const u8 {
    return "1.0.0";
}

// Get last error message (for debugging)
export fn def2lib_get_error_message(error_code: c_int) [*:0]const u8 {
    return switch (error_code) {
        DEF2LIB_SUCCESS => "Success",
        DEF2LIB_ERROR_INVALID_INPUT => "Invalid input parameters",
        DEF2LIB_ERROR_PARSE_FAILED => "Failed to parse DEF file",
        DEF2LIB_ERROR_GENERATION_FAILED => "Failed to generate LIB file",
        DEF2LIB_ERROR_OUT_OF_MEMORY => "Out of memory",
        else => "Unknown error",
    };
}

// Convenience function for single-call conversion
export fn def2lib_convert_simple(
    def_content: [*:0]const u8,
    def_size: usize,
    kill_at: bool,
    lib_data: *?[*]u8,
    lib_size: *usize,
) c_int {
    const options = Def2LibOptions{
        .kill_at = kill_at,
    };
    
    var result: Def2LibResult = undefined;
    const ret = def2lib_convert(def_content, def_size, &options, &result);
    
    lib_data.* = result.data;
    lib_size.* = result.size;
    
    return ret;
}

// Test exports for validation
export fn def2lib_test_basic() c_int {
    const test_def = 
        \\NAME TestLibrary
        \\EXPORTS
        \\    TestFunction
        \\    TestData DATA
    ;
    
    const options = Def2LibOptions{ .kill_at = false };
    var result: Def2LibResult = undefined;
    
    const ret = def2lib_convert(test_def.ptr, test_def.len, &options, &result);
    
    if (ret == DEF2LIB_SUCCESS) {
        def2lib_free(result.data, result.size);
        return DEF2LIB_SUCCESS;
    } else {
        return ret;
    }
}
