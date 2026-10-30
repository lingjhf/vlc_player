// SPDX-License-Identifier: LGPL-2.1-or-later
#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_demux.h>
#include <vlc_aout.h>
#include <libavcodec/avcodec.h>
#include <libavutil/channel_layout.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
extern const uint8_t *vlc_shorten_header(const AVCodecContext *, int *);
struct demux_sys_t
{
    AVCodecContext *codec;
    AVPacket *packet;
    AVFrame *frame;
    es_out_id_t *es;
    uint64_t samples;
    unsigned rate, channels, chunk;
    uint8_t map[8];
    int format;
    bool eof, flushed, aiff8, aiff, aifc, aifc_big;
    uint8_t prefix_bytes[8], prefix_read;
    unsigned char *pending;
    size_t queued, cap;
    uint64_t discard, total_samples, prefix, prefix_left;
};

static uint32_t ReadLe32(const uint8_t *p)
{
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 |
           (uint32_t)p[3] << 24;
}
static uint32_t ReadBe32(const uint8_t *p)
{
    return (uint32_t)p[3] | (uint32_t)p[2] << 8 | (uint32_t)p[1] << 16 |
           (uint32_t)p[0] << 24;
}
static uint64_t HeaderSamples(AVCodecContext *codec, unsigned ch, unsigned bytes)
{
    int n = 0;
    const uint8_t *h = vlc_shorten_header(codec, &n);
    if (!h || n < 12)
        return 0;
    bool wav = !memcmp(h, "RIFF", 4) && !memcmp(h + 8, "WAVE", 4),
         aiff = !memcmp(h, "FORM", 4) &&
                (!memcmp(h + 8, "AIFF", 4) || !memcmp(h + 8, "AIFC", 4));
    if (!wav && !aiff)
        return 0;
    for (size_t p = 12; p + 8 <= (size_t)n;)
    {
        uint32_t sz = wav ? ReadLe32(h + p + 4) : ReadBe32(h + p + 4);
        if (wav && !memcmp(h + p, "data", 4))
        {
            size_t stride = ch * bytes;
            if (!stride || !sz || sz == UINT32_MAX || sz % stride)
                return 0;
            return sz / stride;
        }
        if (aiff && !memcmp(h + p, "COMM", 4))
        {
            if (sz < 18 || p + 8 + 18 > (size_t)n)
                return 0;
            return ReadBe32(h + p + 10);
        }
        size_t padded = (size_t)sz + (sz & 1);
        if (padded > (size_t)n - p - 8)
            return 0;
        p += 8 + padded;
    }
    return 0;
}
static int InitAiff(AVCodecContext *codec, AVFrame *f, demux_sys_t *s)
{
    int n = 0;
    const uint8_t *h = vlc_shorten_header(codec, &n);
    s->prefix_read = 8;
    if (!h || n < 12 || memcmp(h, "FORM", 4))
        return VLC_SUCCESS;
    size_t pos = 12;
    bool found = false, format_ok = memcmp(h + 8, "AIFC", 4) != 0;
    while (pos + 8 <= (size_t)n)
    {
        uint32_t len = ReadBe32(h + pos + 4);
        if (!memcmp(h + pos, "SSND", 4))
        {
            found = true;
            break;
        }
        if (!memcmp(h + 8, "AIFC", 4) && !memcmp(h + pos, "COMM", 4))
        {
            if (len < 22 || pos + 30 > (size_t)n)
                return VLC_EGENERIC;
            const uint8_t *tag = h + pos + 26;
            if (!memcmp(tag, "NONE", 4))
            {
                s->aifc_big = f->format == AV_SAMPLE_FMT_S16P;
                format_ok = true;
            }
            else if (!memcmp(tag, "sowt", 4))
                format_ok = true;
            else
                return VLC_EGENERIC;
        }
        size_t pad = (size_t)len + (len & 1);
        if (pad > (size_t)n - pos - 8)
            return VLC_EGENERIC;
        pos += 8 + pad;
    }
    if (!found || !format_ok || pos + 8 != (size_t)n ||
        (f->format != AV_SAMPLE_FMT_S16P && f->format != AV_SAMPLE_FMT_U8P) ||
        f->ch_layout.nb_channels < 1 || f->ch_layout.nb_channels > 2)
        return VLC_EGENERIC;
    s->aiff = true;
    s->aifc = !memcmp(h + 8, "AIFC", 4);
    s->aiff8 = f->format == AV_SAMPLE_FMT_U8P;
    s->prefix_read = 0;
    return VLC_SUCCESS;
}
/* Shorten stores the AIFF SSND offset and block size as compressed samples.
 * Accumulate those bytes across frames, then skip the declared padding. */
static int ConsumeAiffPrefix(demux_sys_t *s, AVFrame *f, size_t *used)
{
    size_t count = f->nb_samples;
    unsigned ch = s->channels, bytes = s->format == AV_SAMPLE_FMT_S16P ? 2 : 1;
    *used = 0;
    while (s->aiff && s->prefix_read < 8 && *used < count)
    {
        for (unsigned c = 0; c < ch; c++)
        {
            if (bytes == 1)
                s->prefix_bytes[s->prefix_read++] = f->extended_data[c][*used];
            else
            {
                uint16_t v;
                memcpy(&v, f->extended_data[c] + (*used) * 2, 2);
                s->prefix_bytes[s->prefix_read++] =
                    s->aifc ? (uint8_t)v : (uint8_t)(v >> 8);
                s->prefix_bytes[s->prefix_read++] =
                    s->aifc ? (uint8_t)(v >> 8) : (uint8_t)v;
            }
        }
        ++*used;
        if (s->prefix_read == 8)
        {
            uint32_t offset = ReadBe32(s->prefix_bytes);
            if (offset > 1048576 || offset % (ch * bytes))
                return VLC_EGENERIC;
            s->prefix = (8 + offset) / (ch * bytes);
            s->prefix_left = offset / (ch * bytes);
        }
    }
    size_t available = count - *used,
           skip = s->prefix_left < available ? s->prefix_left : available;
    s->prefix_left -= skip;
    *used += skip;
    return VLC_SUCCESS;
}
static uint32_t MapWaveChannels(unsigned count, uint8_t map[8])
{
    static const uint32_t wave[] = {AOUT_CHAN_LEFT,       AOUT_CHAN_RIGHT,
                                    AOUT_CHAN_CENTER,     AOUT_CHAN_LFE,
                                    AOUT_CHAN_REARLEFT,   AOUT_CHAN_REARRIGHT,
                                    AOUT_CHAN_MIDDLELEFT, AOUT_CHAN_MIDDLERIGHT};
    uint32_t mask = 0;
    if (count == 1)
    {
        map[0] = 0;
        return AOUT_CHAN_CENTER;
    }
    if (count < 2 || count > 8)
        return 0;
    for (unsigned i = 0; i < count; i++)
        mask |= wave[i];
    unsigned out = 0;
    for (unsigned i = 0; pi_vlc_chan_order_wg4[i]; i++)
        for (unsigned j = 0; j < count; j++)
            if (pi_vlc_chan_order_wg4[i] == wave[j])
                map[out++] = j;
    return out == count ? mask : 0;
}
/* Align blocks for common output rates: VLC 3.0's fallback resampler
 * otherwise rounds each short block separately and drifts. */
static unsigned GreatestCommonDivisor(unsigned a, unsigned b)
{
    while (b)
    {
        unsigned r = a % b;
        a = b;
        b = r;
    }
    return a;
}
static int Emit(demux_t *d, size_t count)
{
    demux_sys_t *s = d->p_sys;
    size_t bytes = s->format == AV_SAMPLE_FMT_S16P ? 2 : 1;
    size_t stride = s->channels * bytes;
    block_t *b = block_Alloc(count * stride);
    if (!b)
        return VLC_DEMUXER_EGENERIC;
    memcpy(b->p_buffer, s->pending, count * stride);
    s->queued -= count;
    memmove(s->pending, s->pending + count * stride, s->queued * stride);
    vlc_tick_t t = VLC_TICK_0 + (vlc_tick_t)(s->samples * CLOCK_FREQ / s->rate);
    b->i_dts = b->i_pts = t;
    b->i_nb_samples = count;
    b->i_length = (vlc_tick_t)(count * CLOCK_FREQ / s->rate);
    s->samples += count;
    es_out_SetPCR(d->out, t);
    es_out_Send(d->out, s->es, b);
    return VLC_DEMUXER_SUCCESS;
}
static int Demux(demux_t *d)
{
    demux_sys_t *s = d->p_sys;
    for (;;)
    {
        if (s->total_samples && s->samples + s->queued >= s->total_samples)
            return s->queued ? Emit(d, s->queued) : VLC_DEMUXER_EOF;
        if (s->rate && s->queued >= s->chunk)
            return Emit(d, s->chunk);
        int ret = avcodec_receive_frame(s->codec, s->frame);
        if (ret == 0)
        {
            AVFrame *f = s->frame;
            unsigned ch = f->ch_layout.nb_channels;
            unsigned rate = f->sample_rate;
            if ((ch < 1 || ch > 8) || rate < 10 || rate > 768000 ||
                (f->format != AV_SAMPLE_FMT_S16P && f->format != AV_SAMPLE_FMT_U8P))
            {
                msg_Err(d, "unsupported Shorten audio format");
                return VLC_DEMUXER_EGENERIC;
            }
            if (!s->es)
            {
                es_format_t fmt;
                es_format_Init(&fmt, AUDIO_ES,
                               f->format == AV_SAMPLE_FMT_S16P ? VLC_CODEC_S16L
                                                               : VLC_CODEC_U8);
                fmt.audio.i_rate = rate;
                fmt.audio.i_channels = ch;
                fmt.audio.i_physical_channels = MapWaveChannels(ch, s->map);
                if (!fmt.audio.i_physical_channels)
                    return VLC_DEMUXER_EGENERIC;
                fmt.audio.i_bitspersample = f->format == AV_SAMPLE_FMT_S16P ? 16 : 8;
                fmt.b_packetized = true;
                s->rate = rate;
                unsigned quantum = rate / GreatestCommonDivisor(rate, 25);
                s->chunk = ((rate / 10 + quantum - 1) / quantum) * quantum;
                s->channels = ch;
                s->format = f->format;
                s->total_samples =
                    HeaderSamples(s->codec, ch, f->format == AV_SAMPLE_FMT_S16P ? 2 : 1);
                if (InitAiff(s->codec, f, s) != VLC_SUCCESS)
                {
                    msg_Err(d, "unsupported Shorten AIFF header");
                    return VLC_DEMUXER_EGENERIC;
                }
                s->es = es_out_Add(d->out, &fmt);
                if (!s->es)
                    return VLC_DEMUXER_EGENERIC;
            }
            if (rate != s->rate || ch != s->channels || f->format != s->format)
                return VLC_DEMUXER_EGENERIC;
            size_t bytes = (s->format == AV_SAMPLE_FMT_S16P ? 2 : 1),
                   count = f->nb_samples, prefix = 0;
            if (ConsumeAiffPrefix(s, f, &prefix) != VLC_SUCCESS)
                return VLC_DEMUXER_EGENERIC;
            count -= prefix;
            size_t skip = s->discard < count ? s->discard : count;
            s->discard -= skip;
            s->samples += skip;
            count -= skip;
            skip += prefix;
            if (s->total_samples)
            {
                uint64_t used = s->samples + s->queued;
                uint64_t remaining =
                    used >= s->total_samples ? 0 : s->total_samples - used;
                if (count > remaining)
                    count = (size_t)remaining;
            }
            size_t need = s->queued + count;
            if (need < s->queued || need > SIZE_MAX / ch / bytes)
                return VLC_DEMUXER_EGENERIC;
            if (need > s->cap)
            {
                size_t capacity = need > s->chunk ? need : s->chunk;
                unsigned char *p = realloc(s->pending, capacity * ch * bytes);
                if (!p)
                    return VLC_DEMUXER_EGENERIC;
                s->pending = p;
                s->cap = capacity;
            }
            for (size_t i = 0; i < count; i++)
                for (unsigned c = 0; c < ch; c++)
                {
                    unsigned char *out = s->pending + ((s->queued + i) * ch + c) * bytes;
                    memcpy(out, f->extended_data[s->map[c]] + (i + skip) * bytes, bytes);
                    if (s->aiff8)
                        *out ^= 0x80;
                    if (s->aifc_big)
                    {
                        uint8_t tmp = out[0];
                        out[0] = out[1];
                        out[1] = tmp;
                    }
                }
            s->queued += count;
            av_frame_unref(f);
            continue;
        }
        if (ret == AVERROR_EOF)
            return s->prefix_read < 8
                       ? VLC_DEMUXER_EGENERIC
                       : (s->queued ? Emit(d, s->queued) : VLC_DEMUXER_EOF);
        if (ret != AVERROR(EAGAIN))
        {
            msg_Err(d, "shorten decode error: %d", ret);
            return VLC_DEMUXER_EGENERIC;
        }
        if (s->eof)
        {
            if (s->flushed)
                return s->queued ? Emit(d, s->queued) : VLC_DEMUXER_EOF;
            ret = avcodec_send_packet(s->codec, NULL);
            s->flushed = true;
        }
        else
        {
            av_packet_unref(s->packet);
            if (av_new_packet(s->packet, 4096) < 0)
                return VLC_DEMUXER_EGENERIC;
            ssize_t n = vlc_stream_Read(d->s, s->packet->data, 4096);
            if (n < 0)
                return VLC_DEMUXER_EGENERIC;
            if (n == 0)
            {
                s->eof = true;
                continue;
            }
            s->packet->size = n;
            memset(s->packet->data + n, 0, AV_INPUT_BUFFER_PADDING_SIZE);
            ret = avcodec_send_packet(s->codec, s->packet);
        }
        if (ret < 0)
        {
            msg_Err(d, "shorten input error: %d", ret);
            return VLC_DEMUXER_EGENERIC;
        }
    }
}
/* Shorten has no general independent frame index: restart decoding and
 * discard samples until the requested time. This can be slow for long files. */
static int SeekTime(demux_t *d, vlc_tick_t t)
{
    demux_sys_t *s = d->p_sys;
    if (t < 0 || !s->rate || !s->total_samples)
        return VLC_EGENERIC;
    uint64_t whole = (uint64_t)t / CLOCK_FREQ, part = (uint64_t)t % CLOCK_FREQ;
    if (whole > s->total_samples / s->rate)
        return VLC_EGENERIC;
    uint64_t target = whole * s->rate + part * s->rate / CLOCK_FREQ;
    if (target > s->total_samples)
        return VLC_EGENERIC;
    const AVCodec *codec = avcodec_find_decoder(AV_CODEC_ID_SHORTEN);
    AVCodecContext *ctx = avcodec_alloc_context3(codec);
    if (!ctx)
        return VLC_ENOMEM;
    if (avcodec_open2(ctx, codec, NULL) < 0)
    {
        avcodec_free_context(&ctx);
        return VLC_EGENERIC;
    }
    if (vlc_stream_Seek(d->s, 0) != VLC_SUCCESS)
    {
        avcodec_free_context(&ctx);
        return VLC_EGENERIC;
    }
    avcodec_free_context(&s->codec);
    s->codec = ctx;
    s->queued = 0;
    s->samples = 0;
    s->prefix_left = s->prefix;
    s->discard = target;
    s->eof = false;
    s->flushed = false;
    av_frame_unref(s->frame);
    av_packet_unref(s->packet);
    return VLC_SUCCESS;
}
static int Control(demux_t *d, int q, va_list a)
{
    demux_sys_t *s = d->p_sys;
    if (q == DEMUX_GET_TIME)
    {
        *va_arg(a, vlc_tick_t *) =
            s->rate ? (vlc_tick_t)(s->samples * CLOCK_FREQ / s->rate) : 0;
        return VLC_SUCCESS;
    }
    if (q == DEMUX_GET_LENGTH)
    {
        if (!s->rate || !s->total_samples)
            return VLC_EGENERIC;
        *va_arg(a, vlc_tick_t *) = (vlc_tick_t)(s->total_samples * CLOCK_FREQ / s->rate);
        return VLC_SUCCESS;
    }
    if (q == DEMUX_GET_POSITION)
    {
        if (!s->total_samples)
            return VLC_EGENERIC;
        *va_arg(a, double *) = (double)s->samples / s->total_samples;
        return VLC_SUCCESS;
    }
    /* A raw Shorten stream has no external timestamps. Pacing decoded sample
     * counts is necessary for a fast nonseekable byte source; true live sources
     * must be evaluated separately before this is used in a release. */
    if (q == DEMUX_CAN_CONTROL_PACE)
    {
        *va_arg(a, bool *) = true;
        return VLC_SUCCESS;
    }
    if (q == DEMUX_CAN_SEEK)
        return vlc_stream_Control(d->s, STREAM_CAN_SEEK, va_arg(a, bool *));
    if (q == DEMUX_SET_TIME)
        return SeekTime(d, va_arg(a, vlc_tick_t));
    if (q == DEMUX_SET_POSITION)
    {
        double x = va_arg(a, double);
        if (!s->total_samples || !s->rate || !(x >= 0.0 && x <= 1.0))
            return VLC_EGENERIC;
        return SeekTime(
            d, (vlc_tick_t)(x * (double)s->total_samples * CLOCK_FREQ / s->rate));
    }
    return demux_vaControlHelper(d->s, 0, -1, 0, 1, q, a);
}
static void Destroy(demux_sys_t *s)
{
    if (!s)
        return;
    av_frame_free(&s->frame);
    av_packet_free(&s->packet);
    avcodec_free_context(&s->codec);
    free(s->pending);
    free(s);
}
static int Open(vlc_object_t *obj)
{
    demux_t *d = (demux_t *)obj;
    const uint8_t *p;
    if (vlc_stream_Peek(d->s, &p, 5) < 5 || memcmp(p, "ajkg", 4))
        return VLC_EGENERIC;
    demux_sys_t *s = calloc(1, sizeof(*s));
    if (!s)
        return VLC_ENOMEM;
    const AVCodec *codec = avcodec_find_decoder(AV_CODEC_ID_SHORTEN);
    if (!codec)
    {
        Destroy(s);
        return VLC_EGENERIC;
    }
    s->codec = avcodec_alloc_context3(codec);
    s->packet = av_packet_alloc();
    s->frame = av_frame_alloc();
    if (!s->codec || !s->packet || !s->frame || avcodec_open2(s->codec, codec, NULL) < 0)
    {
        Destroy(s);
        return VLC_EGENERIC;
    }
    d->p_sys = s;
    d->pf_demux = Demux;
    d->pf_control = Control;
    return VLC_SUCCESS;
}
static void Close(vlc_object_t *obj)
{
    demux_t *d = (demux_t *)obj;
    Destroy(d->p_sys);
}
vlc_module_begin() set_description(N_("Shorten PCM demux (experimental)"))
    set_capability("demux", 6) set_callbacks(Open, Close) vlc_module_end()
