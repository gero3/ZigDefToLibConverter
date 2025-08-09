// Real-world test program that demonstrates linking with generated import libraries
// This tests various calling conventions and symbol types

#include <stdio.h>

// Test with different calling conventions and libraries

// Windows API functions (stdcall) - should work with our import libraries
#ifdef _WIN32
extern __declspec(dllimport) unsigned long __stdcall GetTickCount(void);
extern __declspec(dllimport) void __stdcall Sleep(unsigned long dwMilliseconds);
extern __declspec(dllimport) int __stdcall MessageBoxA(void* hWnd, const char* lpText, const char* lpCaption, unsigned int uType);
#endif

// C runtime functions (cdecl) - should work with msvcrt.lib
extern int printf(const char* format, ...);
extern void* malloc(size_t size);
extern void free(void* ptr);

// SQLite functions (cdecl) - should work with sqlite3.lib  
extern int sqlite3_libversion_number(void);
extern const char* sqlite3_libversion(void);

int main() {
    printf("=== Real-World Import Library Test ===\n\n");
    
    // Test C runtime linking
    printf("1. Testing C runtime functions:\n");
    void* test_ptr = malloc(100);
    if (test_ptr) {
        printf("   ✅ malloc() linked successfully\n");
        free(test_ptr);
        printf("   ✅ free() linked successfully\n");
    } else {
        printf("   ❌ malloc() failed\n");
    }
    
    // Test SQLite linking (if available)
    printf("\n2. Testing SQLite functions:\n");
    printf("   SQLite version: %s\n", sqlite3_libversion());
    printf("   Version number: %d\n", sqlite3_libversion_number());
    
#ifdef _WIN32
    // Test Windows API linking
    printf("\n3. Testing Windows API functions:\n");
    unsigned long tick1 = GetTickCount();
    printf("   Initial tick count: %lu\n", tick1);
    
    Sleep(10); // Sleep for 10ms
    
    unsigned long tick2 = GetTickCount();
    printf("   Tick count after sleep: %lu\n", tick2);
    printf("   Time elapsed: %lu ms\n", tick2 - tick1);
    
    // Uncomment to test MessageBox (will show a dialog)
    // MessageBoxA(NULL, "Import library linking test successful!", "def2lib Test", 0);
#endif
    
    printf("\n=== Test completed successfully! ===\n");
    printf("All import libraries are properly formatted and linkable.\n");
    
    return 0;
}
