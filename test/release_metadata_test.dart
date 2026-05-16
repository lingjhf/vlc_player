import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release metadata uses one package version', () {
    final version = _pubspecVersion();

    expect(_fileText('README.md'), contains('vlc_player: ^$version'));
    expect(_fileText('CHANGELOG.md'), contains('## $version - '));
    expect(
      _fileText('ios/vlc_player.podspec'),
      contains("s.version          = '$version'"),
    );
    expect(
      _fileText('macos/vlc_player.podspec'),
      contains("s.version          = '$version'"),
    );
    expect(_fileText('example/pubspec.lock'), contains('version: "$version"'));
    expect(
      _fileText('example/ios/Podfile.lock'),
      contains('vlc_player ($version)'),
    );
    expect(
      _fileText('example/macos/Podfile.lock'),
      contains('vlc_player ($version)'),
    );
  });

  test('podspec metadata points to the project owner', () {
    for (final path in <String>[
      'ios/vlc_player.podspec',
      'macos/vlc_player.podspec',
    ]) {
      final podspec = _fileText(path);

      expect(
        podspec,
        contains(
          "s.homepage         = 'https://github.com/lingjhf/vlc_player'",
        ),
      );
      expect(
        podspec,
        contains(
          "s.author           = { 'lingjhf' => 'lingjhf@users.noreply.github.com' }",
        ),
      );
      expect(podspec, isNot(contains('https://flutter.dev')));
      expect(podspec, isNot(contains('noreply@example.com')));
    }
  });

  test('third-party notices are linked from README', () {
    final notices = _fileText('THIRD_PARTY_NOTICES.md');

    expect(_fileText('README.md'), contains('THIRD_PARTY_NOTICES.md'));
    expect(notices, contains('VideoLAN'));
    expect(notices, contains('VLCKit'));
    expect(notices, contains('MobileVLCKit'));
    expect(notices, contains('libvlcpp'));
  });

  test('workflows pin the Windows runner image', () {
    for (final path in <String>[
      '.github/workflows/ci.yml',
      '.github/workflows/publish.yml',
    ]) {
      final workflow = _fileText(path);

      expect(workflow, contains('runs-on: windows-2025-vs2026'));
      expect(workflow, isNot(contains('runs-on: windows-latest')));
    }
  });
}

String _pubspecVersion() {
  final match = RegExp(
    r'^version:\s*(\S+)$',
    multiLine: true,
  ).firstMatch(_fileText('pubspec.yaml'));
  if (match == null) {
    fail('pubspec.yaml does not define a package version.');
  }
  return match.group(1)!;
}

String _fileText(String path) => File(path).readAsStringSync();
