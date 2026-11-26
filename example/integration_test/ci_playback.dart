import 'dart:io';

import 'package:integration_test/integration_test.dart';

import 'android_lifecycle_test.dart' as android_lifecycle;
import 'format_compatibility_test.dart' as format_compatibility;
import 'plugin_integration_test.dart' as plugin;
import 'session_lifecycle_test.dart' as session_lifecycle;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  plugin.main();
  if (Platform.isAndroid) {
    android_lifecycle.main();
  }
  session_lifecycle.main();
  if (Platform.isWindows) {
    format_compatibility.main();
  }
}
