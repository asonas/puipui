#include "TerminalPTY.h"
#include <util.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <crt_externs.h>
#include <stdlib.h>
#include <string.h>
#include <pwd.h>
#include <stdio.h>

pid_t terminal_spawn(int *master, const char *directory) {
    const struct passwd *account = getpwuid(getuid());
    if (!account || !account->pw_shell || !account->pw_shell[0]) return -1;
    char *shell = strdup(account->pw_shell);
    if (!shell) return -1;
    char *shell_variable = NULL;
    if (asprintf(&shell_variable, "SHELL=%s", shell) < 0) { free(shell); return -1; }
    char **inherited = *_NSGetEnviron();
    size_t count = 0;
    while (inherited[count]) count++;
    char **environment = calloc(count + 3, sizeof(char *));
    if (!environment) { free(shell); free(shell_variable); return -1; }
    size_t index = 0;
    for (size_t i = 0; i < count; i++) {
        if (strncmp(inherited[i], "TERM=", 5) != 0 && strncmp(inherited[i], "SHELL=", 6) != 0) environment[index++] = inherited[i];
    }
    environment[index++] = "TERM=xterm-256color";
    environment[index] = shell_variable;
    struct winsize size = {.ws_col = 80, .ws_row = 24};
    pid_t pid = forkpty(master, NULL, NULL, &size);
    if (pid == 0) {
        if (chdir(directory) != 0) _exit(126);
        char *const argv[] = {shell, "-l", "-i", NULL};
        execve(argv[0], argv, environment);
        _exit(127);
    }
    free(environment);
    free(shell_variable);
    free(shell);
    if (pid > 0) {
        fcntl(*master, F_SETFD, FD_CLOEXEC);
        fcntl(*master, F_SETFL, O_NONBLOCK);
    }
    return pid;
}

int terminal_resize(int fd, unsigned short columns, unsigned short rows) {
    struct winsize size = {.ws_col = columns, .ws_row = rows};
    return ioctl(fd, TIOCSWINSZ, &size);
}

int terminal_wait(pid_t pid, int *code) {
    int status;
    pid_t result = waitpid(pid, &status, WNOHANG);
    if (result <= 0) return (int)result;
    *code = WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
    return 1;
}
