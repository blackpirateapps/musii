import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musii/app/app.dart';

void main() {
  testWidgets('MusiiApp launches and renders primary tabs', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: MusiiApp()));

    // Initial frame
    await tester.pump();

    // Verify Cupertino tab labels
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    // Switch to Library tab
    await tester.tap(find.text('Library'));
    await tester.pump();

    // Switch to Search tab
    await tester.tap(find.text('Search'));
    await tester.pump();

    // Switch to Settings tab
    await tester.tap(find.text('Settings'));
    await tester.pump();

    expect(find.text('Settings'), findsWidgets);

    // Unmount and flush pending cleanup timers from stream query cancellation
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
