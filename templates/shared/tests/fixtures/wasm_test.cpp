// wasm_test.cpp — Verify WASI compilation target
#include <cstdio>
#include <cstdlib>
#include <cstring>

int fibonacci(int n) {
    if (n <= 1) return n;
    int a = 0, b = 1;
    for (int i = 2; i <= n; i++) {
        int c = a + b;
        a = b;
        b = c;
    }
    return b;
}

const char* classify_number(int n) {
    if (n < 0) return "negative";
    if (n == 0) return "zero";
    if (n % 2 == 0) return "even";
    return "odd";
}

int main() {
    printf("=== COCA WASM (WASI) Test ===\n");

    // Test basic computation
    for (int i = 0; i <= 10; i++) {
        printf("  fib(%d) = %d\n", i, fibonacci(i));
    }

    // Test string operations
    const char* categories[] = {"negative", "zero", "even", "odd"};
    int test_values[] = {-5, 0, 42, 7};
    for (int i = 0; i < 4; i++) {
        const char* result = classify_number(test_values[i]);
        printf("  classify(%d) = %s", test_values[i], result);
        if (strcmp(result, categories[i]) == 0) {
            printf(" [OK]\n");
        } else {
            printf(" [FAIL: expected %s]\n", categories[i]);
            return 1;
        }
    }

    // Test dynamic memory
    int* arr = (int*)malloc(10 * sizeof(int));
    if (!arr) {
        printf("  malloc failed!\n");
        return 1;
    }
    for (int i = 0; i < 10; i++) arr[i] = i * i;
    printf("  squares: ");
    for (int i = 0; i < 10; i++) printf("%d ", arr[i]);
    printf("\n");
    free(arr);

    printf("All COCA WASI tests passed.\n");
    return 0;
}
