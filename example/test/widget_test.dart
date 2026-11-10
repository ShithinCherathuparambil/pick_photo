import 'package:flutter_test/flutter_test.dart';
import 'package:pick_photo_example/main.dart';

void main() {
  testWidgets('Renders PickPhotoExampleApp without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const PickPhotoExampleApp());

    expect(find.text('PickPhoto Plugin'), findsOneWidget);
    expect(find.text('Gallery'), findsOneWidget);
    expect(find.text('Multi-Pick'), findsOneWidget);
    expect(find.text('Camera'), findsOneWidget);
  });
}
