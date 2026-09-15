#include <sys/types.h>
pid_t terminal_spawn(int *master, const char *directory);
int terminal_resize(int fd, unsigned short columns, unsigned short rows);
int terminal_wait(pid_t pid, int *code);
