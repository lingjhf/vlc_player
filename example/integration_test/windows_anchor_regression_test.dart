// Run reference-video and concurrent-player checks in one process.
import 'windows_concurrent_players_test.dart' as concurrent;
import 'windows_public_samples_test.dart' as samples;

void main() {
  samples.main();
  concurrent.main();
}
