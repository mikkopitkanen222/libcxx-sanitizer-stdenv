{
  tool = "MemorySanitizer";
  optionsVar = "MSAN_OPTIONS";

  programs = {
    # Reads uninitialized heap memory through a non-inlined allocator, so the optimizer can't prove
    # the memory is uninitialized. Reading an uninitialized local is undefined behaviour, which
    # Clang may delete at -O1 and above before MSan instruments it.
    catches-uninitialized-read = {
      source = ''
        [[gnu::noinline]] int* allocate() { return new int[4]; }

        int main() {
          int* values = allocate();
          int result = values[1] == 42 ? 1 : 0;
          delete[] values;
          return result;
        }
      '';
      report = [
        "^==[0-9]+==WARNING: MemorySanitizer: use-of-uninitialized-value$"
        "^SUMMARY: MemorySanitizer: use-of-uninitialized-value /build/test\\.cpp:[0-9]+:[0-9]+ in main$"
      ];
    };

    # String streams run code from the compiled libc++ library. The memcpy() size is unknown at
    # compile time, so _FORTIFY_SOURCE would turn it into glibc's __memcpy_chk(). MSan doesn't
    # intercept it, so the copy would stay marked uninitialized and reading it would be reported.
    no-false-positives = {
      source = ''
        #include <cstring>
        #include <sstream>
        #include <string>

        [[gnu::noinline]] std::size_t size(const char* s) { return std::strlen(s) + 1; }

        int main(int argc, char**) {
          std::ostringstream stream;
          stream << "hello " << argc;
          std::string text = stream.str();
          char copy[32];
          std::memcpy(copy, text.c_str(), size(text.c_str()));
          return copy[0] == 'h' ? 0 : 1;
        }
      '';
      report = null;
    };
  };
}
