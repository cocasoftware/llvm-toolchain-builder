#include <cstdio>
#include <cstddef>

// Functions exported from Rust staticlib
extern "C" {
    int rust_add(int a, int b);
    size_t rust_greeting_len();
}

static int g_pass = 0, g_fail = 0;
static void check(bool cond, const char* label) {
    if (cond) { ++g_pass; }
    else { ++g_fail; std::printf("  FAIL: %s\n", label); }
}

int main() {
    std::printf("=== test_rust_interop ===\n");

    check(rust_add(2, 3) == 5,    "rust_add(2, 3) == 5");
    check(rust_add(-1, 1) == 0,   "rust_add(-1, 1) == 0");
    check(rust_add(0, 0) == 0,    "rust_add(0, 0) == 0");

    size_t len = rust_greeting_len();
    std::printf("  rust_greeting_len() = %zu\n", len);
    check(len == 16, "rust_greeting_len() == 16");

    std::printf("%s: test_rust_interop — %d checks passed, %d failed\n",
                g_fail == 0 ? "PASS" : "FAIL", g_pass, g_fail);
    return g_fail == 0 ? 0 : 1;
}
