/* Compatibility functions needed by VLC's Ogg module on the MSVCRT toolchain. */
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int asprintf(char **output, const char *format, ...)
{
    va_list args, copy;
    va_start(args, format);
    va_copy(copy, args);
    const int length = vsnprintf(NULL, 0, format, copy);
    va_end(copy);
    if (length < 0 || !(*output = malloc((size_t)length + 1))) {
        *output = NULL;
        va_end(args);
        return -1;
    }
    const int result = vsnprintf(*output, (size_t)length + 1, format, args);
    va_end(args);
    if (result < 0) {
        free(*output);
        *output = NULL;
    }
    return result;
}

char *strndup(const char *source, size_t limit)
{
    size_t length = 0;
    while (length < limit && source[length])
        ++length;
    char *result = malloc(length + 1);
    if (result) {
        memcpy(result, source, length);
        result[length] = '\0';
    }
    return result;
}
