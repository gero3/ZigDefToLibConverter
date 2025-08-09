# def2lib - Windows DEF to LIB Converter

A high-performance tool written in Zig for converting Windows module definition (.def) files to COFF import library (.lib) files. This tool generates Microsoft-compatible import libraries that can be used with MSVC, MinGW, and other Windows development toolchains.

## Features

- ✅ **Real COFF Import Objects**: Generates proper Microsoft-compatible COFF import libraries
- ✅ **LLVM-Compatible Symbol Processing**: Supports `--kill-at` flag for MinGW compatibility
- ✅ **Multiple Calling Conventions**: Handles stdcall, cdecl, and C++ mangled symbols
- ✅ **Comprehensive DEF Parsing**: Supports all major DEF file constructs (EXPORTS, ordinals, decorations, internal names)
- ✅ **Cross-Platform**: Runs on any platform that supports Zig
- ✅ **Production Ready**: Tested with real-world Windows APIs

## Installation

### Prerequisites
- [Zig](https://ziglang.org/) 0.14.x or later

### Building
```bash
git clone https://github.com/yourusername/def2lib.git
cd def2lib
zig build
```

The executable will be created in `zig-out/bin/def2lib.exe`.

## Usage

### Basic Usage
```bash
def2lib input.def [output.lib] [--kill-at]
```

### Arguments
- `input.def` - Input module definition file
- `output.lib` - Output library file (optional, defaults to input basename)
- `--kill-at` - Remove '@' decoration from exported symbols (for MinGW compatibility)

### Examples

#### Convert a DEF file to import library:
```bash
def2lib kernel32.def kernel32.lib
```

#### Generate MinGW-compatible library:
```bash
def2lib kernel32.def kernel32_mingw.lib --kill-at
```

#### Auto-generate output filename:
```bash
def2lib sqlite3.def  # Creates sqlite3.lib
```

## DEF File Format Support

def2lib supports all major Windows DEF file constructs:

### Basic Exports
```def
NAME MyLibrary
DESCRIPTION "My custom library"

EXPORTS
    MyFunction
    MyData DATA
```

### Decorated Functions (stdcall)
```def
EXPORTS
    MyFunction@12      ; stdcall with 12 bytes of parameters
    _MyFunction        ; cdecl naming convention
```

### Ordinal Exports
```def
EXPORTS
    MyFunction @1      ; Export by ordinal
    MyFunction @2 NONAME  ; Export by ordinal only
```

### Internal Name Mapping
```def
EXPORTS
    PublicName = InternalFunction@8
    MyAlias = MyRealFunction
```

### Private Exports
```def
EXPORTS
    MyInternalFunction PRIVATE  ; Not included in import library
```

## Real-World Examples

The `examples/` directory contains DEF files for common Windows libraries:

- `kernel32.def` - Windows Kernel API
- `user32.def` - Windows User Interface API  
- `opengl32.def` - OpenGL Graphics API
- `sqlite3.def` - SQLite Database API
- `msvcrt.def` - Microsoft C Runtime Library
- `winsock2.def` - Windows Sockets API

## Symbol Decoration Handling

### Without `--kill-at` (Standard Mode)
- Preserves all symbol decorations as specified in the DEF file
- Compatible with MSVC and standard Windows development

### With `--kill-at` (MinGW Mode)
- Removes `@` decorations from stdcall functions
- Preserves C++ mangled names (starting with `?`)
- Compatible with MinGW/GCC toolchains

#### Example:
```
Input DEF:     MyFunction@12
Standard:      MyFunction@12  (preserved)
MinGW:         MyFunction     (decoration removed)
```

## Technical Details

### COFF Import Library Format
def2lib generates proper COFF import libraries with:
- Microsoft-compatible archive format (`!<arch>`)
- ImportObjectHeader structures with correct signatures
- Proper machine type specification (AMD64/i386)
- Symbol tables with appropriate import type flags

### Supported Architectures
- AMD64 (x86_64) - Primary target
- i386 (x86) - Supported

### Calling Conventions
- **stdcall** - Windows API standard (decorated with `@N`)
- **cdecl** - C runtime standard (no decoration or `_` prefix)
- **C++ mangled** - Compiler-generated names (preserved as-is)

## Contributing

Contributions are welcome! Please see the development guidelines in `.github/copilot-instructions.md`.

### Development Setup
1. Clone the repository
2. Install Zig 0.14.x or later
3. Build: `zig build`
4. Test: `zig build test-all`

### Testing

The project includes comprehensive testing:

```bash
# Run all test suites
zig build test-all

# Run specific test suites
zig build test               # Unit tests
zig build test-comprehensive # Comprehensive functionality tests
zig build test-integration  # Integration tests with real DEF files
zig build test-performance  # Performance benchmarks

# Test library validation with zig cc
zig cc test/validation_test.c -o validation_test.exe
./validation_test.exe
```

### Code Style
- Follow Zig naming conventions (snake_case for functions, PascalCase for types)
- Use proper allocator patterns and defer cleanup
- Include comprehensive error handling
- Write descriptive function and variable names

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Inspired by LLVM's `llvm-dlltool` and Microsoft's `lib.exe`
- DEF file format specification from Microsoft Documentation
- COFF format details from PE/COFF specification
