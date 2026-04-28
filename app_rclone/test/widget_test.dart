import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_rclone/app.dart';

void main() {
  testWidgets('app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: RcloneApp()),
    );
    expect(find.byType(RcloneApp), findsOneWidget);
  });
}
