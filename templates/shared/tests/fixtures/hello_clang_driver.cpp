// hello_clang_driver.cpp — Test win-x64-clang profile (clang++/clang GNU driver, MSVC ABI)
#include <cstdio>
#include <string>
#include <vector>

int main() {
    std::printf("Hello from COCA toolchain clang++ driver!\n");
    std::vector<int> v = {1, 2, 3, 4, 5};
    int sum = 0;
    for (auto x : v) sum += x;
    std::printf("sum = %d\n", sum);
    std::string s = "COCA toolchain clang++ driver test";
    std::printf("%s\n", s.c_str());
    return sum == 15 ? 0 : 1;
}
