/* Conservative automatic detection for advanced-profile VC-1 files. */
#ifndef VLC_PLAYER_VC1_PROBE_H
#define VLC_PLAYER_VC1_PROBE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <strings.h>

static bool vlc_player_vc1_probe(const char *path, const uint8_t *data, size_t size)
{
    if (path == NULL || data == NULL || size < 5)
        return false;
    const char *end = path + strcspn(path, "?#");
    return end - path >= 4 && !strncasecmp(end - 4, ".vc1", 4) &&
           data[0] == 0 && data[1] == 0 && data[2] == 1 && data[3] == 0x0f &&
           (data[4] >> 6) == 3; /* Advanced profile */
}

#endif
