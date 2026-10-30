#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <stddef.h>
struct pollfd;
int poll(struct pollfd *, unsigned, int);
int asprintf(char **, const char *, ...);
char *strndup(const char *, size_t);
#define _(s) vlc_gettext(s)
#define N_(s) (s)
#define MODULE_STRING "ogg"
