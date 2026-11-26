/* Negative controls ensure the VC-1 demuxer does not claim unrelated inputs. */
#include "../../third_party/vlc_vc1/vc1_probe.h"
#include <assert.h>

int main(void)
{
    const uint8_t vc1[] = {0, 0, 1, 0x0f, 0xdb};
    const uint8_t h264[] = {0, 0, 1, 0x67, 0xdb};
    const uint8_t wrong_profile[] = {0, 0, 1, 0x0f, 0x40};
    assert(vlc_player_vc1_probe("x.vc1", vc1, sizeof(vc1)));
    assert(vlc_player_vc1_probe("HTTPS://host/file.VC1?token=x", vc1, sizeof(vc1)));
    assert(vlc_player_vc1_probe("file.vc1#part", vc1, sizeof(vc1)));
    assert(!vlc_player_vc1_probe("file.h264", vc1, sizeof(vc1)));
    assert(!vlc_player_vc1_probe("file.vc1.txt", vc1, sizeof(vc1)));
    assert(!vlc_player_vc1_probe("file.vc1", h264, sizeof(h264)));
    assert(!vlc_player_vc1_probe("file.vc1", wrong_profile, sizeof(wrong_profile)));
    assert(!vlc_player_vc1_probe("file.vc1", vc1, 4));
    assert(!vlc_player_vc1_probe(NULL, vc1, sizeof(vc1)));
    assert(!vlc_player_vc1_probe("file.vc1", NULL, 5));
    return 0;
}
