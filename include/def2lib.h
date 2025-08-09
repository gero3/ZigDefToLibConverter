#ifndef DEF2LIB_H
#define DEF2LIB_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stddef.h>
#include <stdbool.h>

// Error codes
#define DEF2LIB_SUCCESS                 0
#define DEF2LIB_ERROR_INVALID_INPUT    -1
#define DEF2LIB_ERROR_PARSE_FAILED     -2
#define DEF2LIB_ERROR_GENERATION_FAILED -3
#define DEF2LIB_ERROR_OUT_OF_MEMORY    -4

// Conversion options
typedef struct {
    bool kill_at;
} Def2LibOptions;

// Result structure
typedef struct {
    unsigned char* data;
    size_t size;
    int error_code;
} Def2LibResult;

// Library lifecycle functions
int def2lib_init(void);
void def2lib_cleanup(void);

// Core conversion function
int def2lib_convert(
    const char* def_content,
    size_t def_size,
    const Def2LibOptions* options,
    Def2LibResult* result
);

// Memory management
void def2lib_free(unsigned char* data, size_t size);

// Utility functions
const char* def2lib_get_version(void);
const char* def2lib_get_error_message(int error_code);

// Convenience function for simple conversions
int def2lib_convert_simple(
    const char* def_content,
    size_t def_size,
    bool kill_at,
    unsigned char** lib_data,
    size_t* lib_size
);

// Test function
int def2lib_test_basic(void);

#ifdef __cplusplus
}
#endif

#endif // DEF2LIB_H
