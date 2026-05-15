#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint vlc_player.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'vlc_player'
  s.version          = '0.3.0'
  s.summary          = 'A Flutter plugin for video playback using VLCKit.'
  s.description      = <<-DESC
A Flutter plugin for video playback using VideoLAN VLCKit.
                       DESC
  s.homepage         = 'https://flutter.dev'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'OpenCode' => 'noreply@example.com' }

  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'

  s.dependency 'Flutter'
  s.dependency 'MobileVLCKit'

  s.platform = :ios, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
