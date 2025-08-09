#include <iostream>
#include <fstream>
#include <vector>
#include "../zig-out/include/def2lib.h"

int main() {
    std::cout << "C++ def2lib DLL Example\n";
    std::cout << "======================\n";
    
    // Initialize the library
    if (def2lib_init() != DEF2LIB_SUCCESS) {
        std::cerr << "Failed to initialize def2lib\n";
        return 1;
    }
    
    std::cout << "Library version: " << def2lib_get_version() << "\n\n";
    
    try {
        // Example DEF content
        std::string def_content = R"(
NAME MyLibrary
DESCRIPTION "Example C++ library"
EXPORTS
    ; Core functions
    Initialize
    Process@8
    Cleanup
    
    ; Data exports
    GlobalSettings DATA
    ErrorTable DATA
    
    ; Decorated functions
    StdCallFunc@12
    CdeclFunc
)";
        
        // Convert with kill-at enabled
        std::cout << "Converting DEF to LIB with --kill-at...\n";
        
        Def2LibOptions options = { .kill_at = true };
        Def2LibResult result;
        
        int ret = def2lib_convert(
            def_content.c_str(), 
            def_content.length(), 
            &options, 
            &result
        );
        
        if (ret == DEF2LIB_SUCCESS) {
            std::cout << "Conversion successful!\n";
            std::cout << "Generated library size: " << result.size << " bytes\n";
            
            // Save to file
            std::ofstream file("example_output.lib", std::ios::binary);
            if (file.is_open()) {
                file.write(reinterpret_cast<const char*>(result.data), result.size);
                file.close();
                std::cout << "Library saved as 'example_output.lib'\n";
            }
            
            // Verify archive format
            if (result.size >= 8 && 
                std::string(reinterpret_cast<const char*>(result.data), 8) == "!<arch>\n") {
                std::cout << "Archive format: VALID\n";
            } else {
                std::cout << "Archive format: INVALID\n";
            }
            
            // Clean up
            def2lib_free(result.data, result.size);
        } else {
            std::cerr << "Conversion failed: " << def2lib_get_error_message(ret) << "\n";
            def2lib_cleanup();
            return 1;
        }
        
        // Test without kill-at
        std::cout << "\nConverting DEF to LIB without --kill-at...\n";
        
        options.kill_at = false;
        ret = def2lib_convert(
            def_content.c_str(), 
            def_content.length(), 
            &options, 
            &result
        );
        
        if (ret == DEF2LIB_SUCCESS) {
            std::cout << "Conversion successful!\n";
            std::cout << "Generated library size: " << result.size << " bytes\n";
            
            // Clean up
            def2lib_free(result.data, result.size);
        } else {
            std::cerr << "Conversion failed: " << def2lib_get_error_message(ret) << "\n";
        }
        
    } catch (const std::exception& e) {
        std::cerr << "Exception: " << e.what() << "\n";
        def2lib_cleanup();
        return 1;
    }
    
    // Cleanup
    def2lib_cleanup();
    
    std::cout << "\nExample completed successfully!\n";
    return 0;
}
