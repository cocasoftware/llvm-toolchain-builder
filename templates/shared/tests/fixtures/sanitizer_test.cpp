// sanitizer_test.cpp — Verify sanitizer and coverage support
// Usage modes (controlled by preprocessor defines):
//   -DTEST_ASAN        : trigger heap-buffer-overflow (ASan should catch)
//   -DTEST_UBSAN       : trigger signed integer overflow (UBSan should catch)
//   -DTEST_CLEAN       : no bugs, for coverage testing
//   (no define)        : same as TEST_CLEAN

#include <cstdio>
#include <cstdlib>
#include <cstring>

// A function with multiple branches for coverage testing
int classify(int x) {
    if (x < 0) {
        return -1;
    } else if (x == 0) {
        return 0;
    } else if (x < 100) {
        return 1;
    } else {
        return 2;
    }
}

// Function that does some string work (for ASan testing)
void string_work(const char* input) {
    size_t len = strlen(input);
    char* buf = (char*)malloc(len + 1);
    if (!buf) return;
    strcpy(buf, input);
    printf("  string_work: copied '%s' (len=%zu)\n", buf, len);
    free(buf);
}

// Function with potential UB (signed integer overflow)
int accumulate(int start, int step, int count) {
    int sum = start;
    for (int i = 0; i < count; i++) {
        sum += step;  // potential signed overflow if step*count is large
    }
    return sum;
}

#ifdef TEST_ASAN
void trigger_asan_bug() {
    printf("[ASan test] Allocating 10 bytes, reading index 10 (out of bounds)...\n");
    char* p = (char*)malloc(10);
    // heap-buffer-overflow: reading 1 byte past the end
    char c = p[10];
    printf("  read value: %d\n", (int)c);
    free(p);
}
#endif

#ifdef TEST_UBSAN
void trigger_ubsan_bug() {
    printf("[UBSan test] Triggering signed integer overflow...\n");
    int x = 2147483647; // INT_MAX
    int y = x + 1;      // signed integer overflow — undefined behavior
    printf("  INT_MAX + 1 = %d\n", y);
}
#endif

int main() {
    printf("=== Sanitizer/Coverage Test ===\n");
    printf("Build mode: ");

#ifdef TEST_ASAN
    printf("ASan (expect heap-buffer-overflow)\n");
    string_work("hello");
    trigger_asan_bug();
    // should not reach here if ASan is working
    printf("ERROR: ASan did not catch the bug!\n");
    return 1;
#elif defined(TEST_UBSAN)
    printf("UBSan (expect signed-integer-overflow)\n");
    printf("  classify(42) = %d\n", classify(42));
    trigger_ubsan_bug();
    printf("  UBSan reported the error above (program may continue)\n");
    return 0;
#else
    printf("Clean (for coverage)\n");
    // Exercise all branches of classify()
    printf("  classify(-5)  = %d\n", classify(-5));
    printf("  classify(0)   = %d\n", classify(0));
    printf("  classify(42)  = %d\n", classify(42));
    printf("  classify(200) = %d\n", classify(200));

    string_work("coverage test");

    printf("  accumulate(0, 1, 10) = %d\n", accumulate(0, 1, 10));
    printf("All tests passed.\n");
    return 0;
#endif
}
