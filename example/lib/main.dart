import 'package:flutter/material.dart';

import 'src/full_player_example_page.dart';
import 'src/hls_example_page.dart';
import 'src/video_example_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.showPlayer = true});

  final bool showPlayer;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: _ExampleListPage(showPlayer: showPlayer));
  }
}

class _ExampleListPage extends StatelessWidget {
  const _ExampleListPage({required this.showPlayer});

  final bool showPlayer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('vlc_player example')),
      body: ListView(
        children: <Widget>[
          ListTile(
            key: const ValueKey<String>('video-example-tile'),
            title: const Text('Video file'),
            subtitle: const Text('Play an MP4 video file'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => VideoExamplePage(showPlayer: showPlayer),
                ),
              );
            },
          ),
          ListTile(
            key: const ValueKey<String>('hls-example-tile'),
            title: const Text('HLS stream'),
            subtitle: const Text('Play an M3U8 HLS stream'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => HlsExamplePage(showPlayer: showPlayer),
                ),
              );
            },
          ),
          ListTile(
            key: const ValueKey<String>('full-player-example-tile'),
            title: const Text('Full player'),
            subtitle: const Text('Fullscreen controls, seek, and orientation'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => FullPlayerExamplePage(showPlayer: showPlayer),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
