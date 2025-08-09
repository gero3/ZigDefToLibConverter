# def2lib DLL Usage Guide

The def2lib library is available as both a command-line tool and a C-compatible DLL for integration into other applications.

## Files

- `def2lib.dll` - The dynamic library
- `def2lib.lib` - Import library for linking
- `def2lib.h` - C/C++ header file
- `def2lib.exe` - Command-line tool

## Building the DLL

```bash
# Build everything (executable and DLL)
zig build

# Build only the DLL
zig build dll

# Build and test the DLL
zig build test-dll
zig build run-dll-test
```

## C API Reference

### Initialization

```c
#include "def2lib.h"

// Initialize the library (call once at startup)
int def2lib_init(void);

// Cleanup the library (call once at shutdown)  
void def2lib_cleanup(void);
```

### Basic Conversion

```c
// Simple conversion function
int def2lib_convert_simple(
    const char* def_content,    // DEF file content
    size_t def_size,           // Size of DEF content
    bool kill_at,              // Enable --kill-at processing
    unsigned char** lib_data,   // Output: library data (must free)
    size_t* lib_size           // Output: library size
);

// Free memory allocated by conversion functions
void def2lib_free(unsigned char* data, size_t size);
```

### Advanced Conversion

```c
typedef struct {
    bool kill_at;
} Def2LibOptions;

typedef struct {
    unsigned char* data;
    size_t size;
    int error_code;
} Def2LibResult;

int def2lib_convert(
    const char* def_content,
    size_t def_size,
    const Def2LibOptions* options,
    Def2LibResult* result
);
```

### Error Handling

```c
// Error codes
#define DEF2LIB_SUCCESS                 0
#define DEF2LIB_ERROR_INVALID_INPUT    -1
#define DEF2LIB_ERROR_PARSE_FAILED     -2
#define DEF2LIB_ERROR_GENERATION_FAILED -3
#define DEF2LIB_ERROR_OUT_OF_MEMORY    -4

// Get error message
const char* def2lib_get_error_message(int error_code);

// Get library version
const char* def2lib_get_version(void);
```

## C Example

```c
#include "def2lib.h"
#include <stdio.h>
#include <string.h>

int main() {
    // Initialize
    def2lib_init();
    
    // DEF content
    const char* def_content = 
        "NAME MyLibrary\n"
        "EXPORTS\n"
        "    Function1\n"
        "    Function2@8\n";
    
    // Convert
    unsigned char* lib_data;
    size_t lib_size;
    
    int result = def2lib_convert_simple(
        def_content, strlen(def_content), 
        true, // enable kill-at
        &lib_data, &lib_size
    );
    
    if (result == DEF2LIB_SUCCESS) {
        printf("Generated %zu bytes\n", lib_size);
        // Use lib_data...
        def2lib_free(lib_data, lib_size);
    } else {
        printf("Error: %s\n", def2lib_get_error_message(result));
    }
    
    def2lib_cleanup();
    return 0;
}
```

## C++ Example

```cpp
#include "def2lib.h"
#include <iostream>
#include <string>
#include <fstream>

int main() {
    def2lib_init();
    
    std::string def_content = R"(
        NAME MyLibrary
        EXPORTS
            Initialize
            Process@8
            Cleanup
    )";
    
    Def2LibOptions options = { .kill_at = true };
    Def2LibResult result;
    
    if (def2lib_convert(def_content.c_str(), def_content.length(), &options, &result) == DEF2LIB_SUCCESS) {
        // Save to file
        std::ofstream file("output.lib", std::ios::binary);
        file.write(reinterpret_cast<const char*>(result.data), result.size);
        
        std::cout << "Generated " << result.size << " bytes\n";
        def2lib_free(result.data, result.size);
    }
    
    def2lib_cleanup();
    return 0;
}
```

## Compilation Examples

### Using zig cc
```bash
zig cc -o myapp.exe myapp.c -L path/to/lib -l def2lib -I path/to/include
```

### Using GCC/MinGW
```bash
gcc -o myapp.exe myapp.c -L path/to/lib -l def2lib -I path/to/include
```

### Using MSVC
```cmd
cl /Fe:myapp.exe myapp.c /I path\to\include path\to\lib\def2lib.lib
```

## Notes

- Always call `def2lib_init()` before using the library
- Always call `def2lib_cleanup()` when done
- Free all memory returned by conversion functions using `def2lib_free()`
- The DLL must be in your PATH or in the same directory as your executable
- Generated LIB files are Microsoft-compatible COFF import libraries
- The `kill_at` option removes `@` decorations from stdcall functions (like LLVM's llvm-dlltool)

## Thread Safety

The current implementation uses a global allocator and is not thread-safe. For multi-threaded applications, ensure conversions are serialized or consider using the command-line tool instead.
