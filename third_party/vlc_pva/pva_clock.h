/* Relative PVA clock, measured in 90 kHz ticks. */
#ifndef VLC_PLAYER_PVA_CLOCK_H
#define VLC_PLAYER_PVA_CLOCK_H

#include <stdbool.h>
#include <stdint.h>

typedef struct {
    bool valid;
    bool audio;
    uint32_t last;
    int64_t elapsed;
} vlc_player_pva_clock;

typedef struct {
    bool valid;
    uint32_t last;
    int64_t extended;
} vlc_player_pva_video_clock;

static int64_t vlc_player_pva_delta(uint32_t current, uint32_t previous)
{
    const uint32_t difference = current - previous;
    return difference <= INT32_MAX
        ? difference : (int64_t)difference - INT64_C(4294967296);
}

static int64_t vlc_player_pva_video_update(vlc_player_pva_video_clock *clock,
                                           uint32_t pts)
{
    if (!clock->valid) {
        clock->valid = true;
        clock->extended = pts;
    } else {
        clock->extended += vlc_player_pva_delta(pts, clock->last);
    }
    clock->last = pts;
    return clock->extended;
}

static void vlc_player_pva_video_align(vlc_player_pva_video_clock *clock,
                                       int64_t audio_pts)
{
    if (!clock->valid)
        return;
    const int64_t cycle = INT64_C(4294967296);
    while (audio_pts - clock->extended > cycle / 2)
        clock->extended += cycle;
    while (clock->extended - audio_pts > cycle / 2)
        clock->extended -= cycle;
}

static void vlc_player_pva_clock_update(vlc_player_pva_clock *clock,
                                        uint32_t pts, bool audio)
{
    if (!clock->valid) {
        clock->valid = true;
        clock->audio = audio;
        clock->last = pts;
        clock->elapsed = 0;
        return;
    }
    clock->elapsed += vlc_player_pva_delta(pts, clock->last);
    clock->last = pts;
    if (audio && !clock->audio) {
        /* Audio may start before the first video timestamp. Rebase only if
         * necessary, without discarding elapsed time when audio starts late. */
        if (clock->elapsed < 0)
            clock->elapsed = 0;
        clock->audio = true;
    }
}

static int64_t vlc_player_pva_clock_microseconds(const vlc_player_pva_clock *clock)
{
    return clock->elapsed > 0 ? clock->elapsed * 100 / 9 : 0;
}

#endif
