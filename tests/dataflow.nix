{
  tool = "DataFlowSanitizer";
  optionsVar = "DFSAN_OPTIONS";

  # DFSan reports nothing by itself: the programs check labels with its API and exit non-zero on
  # failure.
  programs = {
    # Labels propagate through instrumented code.
    propagates-through-arithmetic = {
      source = ''
        #include <sanitizer/dfsan_interface.h>

        int main() {
          int a = 42;
          dfsan_set_label(0x01, &a, sizeof(a));
          int b = a + 1;
          return dfsan_get_label(b) == 0x01 ? 0 : 1;
        }
      '';
      report = null;
    };

    # The memcpy() size is unknown at compile time, so _FORTIFY_SOURCE would turn it into glibc's
    # __memcpy_chk(). DFSan doesn't intercept it, so the copy would lose its label.
    propagates-through-memcpy = {
      source = ''
        #include <sanitizer/dfsan_interface.h>
        #include <cstring>

        [[gnu::noinline]] std::size_t size(const char* s) { return std::strlen(s) + 1; }

        int main() {
          char source[16] = "hello";
          dfsan_set_label(0x01, source, sizeof(source));
          char copy[16];
          std::memcpy(copy, source, size(source));
          return dfsan_read_label(copy, 6) == 0x01 ? 0 : 1;
        }
      '';
      report = null;
    };

    # Number formatting runs in the compiled libc++ library. An uninstrumented libc++ lacks its
    # .dfsan clones, so this doesn't link.
    propagates-through-libcxx = {
      source = ''
        #include <sanitizer/dfsan_interface.h>
        #include <sstream>
        #include <string>

        int main() {
          int number = 12345;
          dfsan_set_label(0x01, &number, sizeof(number));
          std::ostringstream stream;
          stream << number;
          std::string text = stream.str();
          return dfsan_read_label(text.data(), text.size()) == 0x01 ? 0 : 1;
        }
      '';
      report = null;
    };
  };
}
