{
  tool = "ThreadSanitizer";
  optionsVar = "TSAN_OPTIONS";

  programs = {
    # Races on plain loads and stores, which the compiler instruments.
    catches-data-race = {
      source = ''
        #include <thread>

        int counter = 0;

        void increment() {
          for (int i = 0; i < 100000; i++) {
            counter++;
          }
        }

        int main() {
          std::thread t1(increment);
          std::thread t2(increment);
          t1.join();
          t2.join();
          return 0;
        }
      '';
      report = [
        "^WARNING: ThreadSanitizer: data race \\(pid=[0-9]+\\)$"
        " increment\\(\\) /build/test\\.cpp:"
      ];
    };

    # Races through memcpy(), which TSan intercepts. The size is unknown at compile time, so
    # _FORTIFY_SOURCE would replace the call with glibc's __memcpy_chk(). TSan doesn't intercept
    # that, so the race would go unreported.
    catches-memcpy-race = {
      source = ''
        #include <cstring>
        #include <thread>

        char buffer[64];
        const char source[] = "hello";
        volatile std::size_t size = sizeof(source);

        void copy() { std::memcpy(buffer, source, size); }

        int main() {
          std::thread t1(copy);
          std::thread t2(copy);
          t1.join();
          t2.join();
          return 0;
        }
      '';
      report = [
        "^WARNING: ThreadSanitizer: data race \\(pid=[0-9]+\\)$"
        " copy\\(\\) /build/test\\.cpp:"
      ];
    };

    # std::call_once() synchronizes inside the compiled libc++ library. If libc++ weren't
    # instrumented, TSan wouldn't see that synchronization, and would report reading `value` as a
    # race.
    no-false-positives = {
      source = ''
        #include <cstdlib>
        #include <mutex>
        #include <thread>

        std::once_flag once;
        int value = 0;

        void initialize() {
          std::call_once(once, [] { value = 42; });
          if (value != 42) std::abort();
        }

        int main() {
          std::thread t1(initialize);
          std::thread t2(initialize);
          t1.join();
          t2.join();
          return 0;
        }
      '';
      report = null;
    };
  };
}
