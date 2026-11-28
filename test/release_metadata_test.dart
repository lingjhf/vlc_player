import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release metadata uses one package version', () {
    final version = _pubspecVersion();

    expect(_fileText('README.md'), contains('vlc_player: ^$version'));
    expect(_fileText('CHANGELOG.md'), contains('## $version - '));
    expect(_fileText('example/pubspec.lock'), contains('version: "$version"'));
  });

  test('pubspec description satisfies pub.dev length guidance', () {
    final description = _pubspecDescription();

    expect(description.length, inInclusiveRange(50, 180));
  });

  test('Apple plugins share a Swift package with pinned VLCKit binaries', () {
    final pubspec = _fileText('pubspec.yaml');
    for (final platform in ['ios', 'macos']) {
      expect(
        pubspec,
        contains(
          '$platform:\n'
          '        pluginClass: VlcPlayerPlugin\n'
          '        sharedDarwinSource: true',
        ),
      );
    }

    final manifest = _fileText('darwin/vlc_player/Package.swift');
    expect(manifest, contains('platforms: [.iOS(.v15), .macOS(.v12)]'));
    expect(manifest, contains('.library(name: "vlc-player"'));
    expect(manifest, contains('.process("PrivacyInfo.xcprivacy")'));

    const artifacts = {
      'MobileVLCKit': (version: '3.7.5', tag: 'mobilevlckit-3.7.5-swiftpm'),
      'VLCKit': (version: '3.7.3', tag: 'vlckit-3.7.3-swiftpm'),
    };
    for (final entry in artifacts.entries) {
      final framework = entry.key;
      final tag = RegExp.escape(entry.value.tag);
      final version = RegExp.escape(entry.value.version);
      expect(
        manifest,
        matches(
          '\\.binaryTarget\\(\\s*name: "$framework",\\s*'
          'url: "https://github\\.com/lingjhf/vlc_player/releases/download/'
          '$tag/$framework-$version-swiftpm\\.xcframework\\.zip",\\s*'
          'checksum: "[a-f0-9]{64}"',
        ),
      );
    }
  });

  test('Apple plugin and example use Swift Package Manager only', () {
    for (final path in [
      'ios/vlc_player.podspec',
      'macos/vlc_player.podspec',
      'darwin/vlc_player.podspec',
      'example/ios/Podfile',
      'example/ios/Podfile.lock',
      'example/macos/Podfile',
      'example/macos/Podfile.lock',
    ]) {
      expect(File(path).existsSync(), isFalse, reason: path);
    }
    for (final path in ['pubspec.yaml', 'example/pubspec.yaml']) {
      expect(
        _fileText(path),
        isNot(contains('enable-swift-package-manager: false')),
      );
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

String _pubspecDescription() {
  final match = RegExp(
    r'^description:\s*(.+)$',
    multiLine: true,
  ).firstMatch(_fileText('pubspec.yaml'));
  if (match == null) {
    fail('pubspec.yaml does not define a package description.');
  }

  final rawDescription = match.group(1)!.trim();
  if (rawDescription.length >= 2 &&
      ((rawDescription.startsWith('"') && rawDescription.endsWith('"')) ||
          (rawDescription.startsWith("'") && rawDescription.endsWith("'")))) {
    return rawDescription.substring(1, rawDescription.length - 1);
  }
  return rawDescription;
}

String _fileText(String path) => File(path).readAsStringSync();
