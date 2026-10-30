#include <assert.h>
#include <stdint.h>
#include "../../third_party/vlc_pva/pva_clock.h"

int main(void)
{
    vlc_player_pva_clock clock = {0};
    assert(!clock.valid);
    vlc_player_pva_clock_update(&clock, UINT32_MAX - 44999, false);
    assert(clock.valid && vlc_player_pva_clock_microseconds(&clock) == 0);
    vlc_player_pva_clock_update(&clock, 45000, false);
    assert(vlc_player_pva_clock_microseconds(&clock) == 1000000);
    vlc_player_pva_clock_update(&clock, 27000, false);
    assert(vlc_player_pva_clock_microseconds(&clock) == 800000);
    /* Audio becomes the PCR source and establishes its own start. */
    vlc_player_pva_clock_update(&clock, UINT32_MAX - 89999, true);
    assert(vlc_player_pva_clock_microseconds(&clock) == 0);
    vlc_player_pva_clock_update(&clock, 90000, true);
    assert(vlc_player_pva_clock_microseconds(&clock) == 2000000);
    /* A backward position seek must also move the reported time back. */
    vlc_player_pva_clock_update(&clock, UINT32_MAX - 44999, true);
    assert(vlc_player_pva_clock_microseconds(&clock) == 500000);

    clock = (vlc_player_pva_clock){0};
    vlc_player_pva_clock_update(&clock, 1000, false);
    vlc_player_pva_clock_update(&clock, 901000, false);
    vlc_player_pva_clock_update(&clock, 910000, true);
    assert(vlc_player_pva_clock_microseconds(&clock) == 10100000);

    vlc_player_pva_video_clock video = {0};
    assert(vlc_player_pva_video_update(&video, UINT32_MAX - 44999) ==
           INT64_C(4294922296));
    assert(vlc_player_pva_video_update(&video, 45000) == INT64_C(4295012296));
    assert(vlc_player_pva_video_update(&video, 27000) == INT64_C(4294994296));
    video = (vlc_player_pva_video_clock){0};
    vlc_player_pva_video_update(&video, 45000);
    vlc_player_pva_video_align(&video, INT64_C(4295012296));
    assert(video.extended == INT64_C(4295012296));
    assert(vlc_player_pva_video_update(&video, 90000) == INT64_C(4295057296));
    return 0;
}
