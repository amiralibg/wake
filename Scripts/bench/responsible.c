// Prints "<pid> <responsible pid>" for each pid given. WebKit's WebContent,
// Networking and GPU processes are XPC services whose parent is launchd; the
// responsible pid is the app that asked for them.
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>

extern pid_t responsibility_get_pid_responsible_for_pid(pid_t);

int main(int argc, char **argv) {
    for (int i = 1; i < argc; i++) {
        pid_t pid = atoi(argv[i]);
        printf("%d %d\n", pid, responsibility_get_pid_responsible_for_pid(pid));
    }
    return 0;
}
