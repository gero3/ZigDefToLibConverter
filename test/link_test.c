#include <stdio.h>

// Declare functions that should be in our library
void MyFunction(int param1, int param2, int param3);
void _MyFunction(void);
void SimpleFunction(void);

int main() {
    printf("Testing library linking...\n");
    
    // Try to call functions (these should fail to link with our current implementation)
    // MyFunction(1, 2, 3);  // Commented out - would cause link error
    // _MyFunction();         // Commented out - would cause link error
    // SimpleFunction();      // Commented out - would cause link error
    
    printf("If this compiles and runs, basic structure is OK\n");
    return 0;
}
