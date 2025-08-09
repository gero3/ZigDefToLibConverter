// Test program to verify the generated import library
#include <stdio.h>
#include <windows.h>

// Declare the functions that should be in our library
// These are external declarations matching our DEF file

// Simple function export
extern void MyFunction(void);

// Function with internal name mapping  
extern void PublicFunction(void);  // maps to InternalFunction

// Function with ordinal
extern void OrdinalFunction(void);

// Function with ordinal and NONAME
extern void HiddenFunction(void);

// Data exports
extern int MyGlobalData;
extern int AnotherData;

int main() {
    printf("Testing generated import library...\n");
    
    // Try to get the address of the functions
    // We can't actually call them since we don't have the DLL,
    // but we can verify that the linker can resolve them
    
    HMODULE hLib = LoadLibraryA("MyLibrary.dll");
    if (hLib == NULL) {
        printf("Cannot load MyLibrary.dll (expected - we only have import lib)\n");
        
        // Instead, let's try to get function addresses by name
        // This tests if our import library has the right symbols
        printf("Function addresses from import library:\n");
        printf("MyFunction: %p\n", (void*)&MyFunction);
        printf("PublicFunction: %p\n", (void*)&PublicFunction);
        printf("OrdinalFunction: %p\n", (void*)&OrdinalFunction);
        printf("HiddenFunction: %p\n", (void*)&HiddenFunction);
        
        printf("Data addresses from import library:\n");
        printf("MyGlobalData: %p\n", (void*)&MyGlobalData);
        printf("AnotherData: %p\n", (void*)&AnotherData);
        
        printf("If this program compiles and links, the import library is valid!\n");
    } else {
        FreeLibrary(hLib);
    }
    
    return 0;
}
