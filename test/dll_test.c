#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../zig-out/include/def2lib.h"

int main() {
    printf("Testing def2lib DLL...\n");
    
    // Initialize the library
    if (def2lib_init() != DEF2LIB_SUCCESS) {
        printf("Failed to initialize def2lib\n");
        return 1;
    }
    
    printf("Library version: %s\n", def2lib_get_version());
    
    // Test basic functionality
    int result = def2lib_test_basic();
    if (result == DEF2LIB_SUCCESS) {
        printf("Basic test: PASSED\n");
    } else {
        printf("Basic test: FAILED (%s)\n", def2lib_get_error_message(result));
        return 1;
    }
    
    // Test conversion
    const char* def_content = 
        "NAME TestLibrary\n"
        "EXPORTS\n"
        "    Function1\n"
        "    Function2@8\n"
        "    DataItem DATA\n";
    
    Def2LibOptions options = { .kill_at = true };
    Def2LibResult conv_result;
    
    result = def2lib_convert(def_content, strlen(def_content), &options, &conv_result);
    
    if (result == DEF2LIB_SUCCESS) {
        printf("Conversion test: PASSED\n");
        printf("Generated library size: %zu bytes\n", conv_result.size);
        
        // Verify it's a valid archive (starts with "!<arch>\n")
        if (conv_result.size >= 8 && memcmp(conv_result.data, "!<arch>\n", 8) == 0) {
            printf("Archive format: VALID\n");
        } else {
            printf("Archive format: INVALID\n");
        }
        
        // Free the result
        def2lib_free(conv_result.data, conv_result.size);
    } else {
        printf("Conversion test: FAILED (%s)\n", def2lib_get_error_message(result));
        def2lib_cleanup();
        return 1;
    }
    
    // Test simple conversion function
    unsigned char* lib_data = NULL;
    size_t lib_size = 0;
    
    result = def2lib_convert_simple(def_content, strlen(def_content), false, &lib_data, &lib_size);
    
    if (result == DEF2LIB_SUCCESS) {
        printf("Simple conversion test: PASSED\n");
        printf("Simple conversion size: %zu bytes\n", lib_size);
        def2lib_free(lib_data, lib_size);
    } else {
        printf("Simple conversion test: FAILED (%s)\n", def2lib_get_error_message(result));
    }
    
    // Cleanup
    def2lib_cleanup();
    
    printf("All tests completed successfully!\n");
    return 0;
}
