# Names used by the native transport's JNI entry points.
-keep class com.lingjhf.vlc_player.VlcNativeTransport {
    static boolean enqueue(long, long, long, byte[]);
    static native void post(long, long, byte[]);
    static native long probeDvdVideoSize(byte[], int);
}
