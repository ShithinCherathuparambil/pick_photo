import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pick_photo/pick_photo.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('clearCache completes without error', (
    WidgetTester tester,
  ) async {
    // Verifies that clearCache channel call succeeds against native platform.
    await expectLater(PickPhoto.clearCache(), completes);
  });
}
