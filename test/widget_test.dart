import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:device_inspector/main.dart';

void main() {
  testWidgets('renders the inspector screen and surfaces check failures',
      (WidgetTester tester) async {
    await tester.pumpWidget(const DeviceInspectorApp());

    expect(find.text('DeviceInspector'), findsOneWidget);

    // Platform plugins never answer under flutter_test, so the initial check
    // runs into the app's own timeouts (3s permission + 10s data fetch) and
    // must land on the error state instead of hanging on the spinner.
    final errorText = find.text("Couldn't read device state");
    for (var i = 0; i < 14 && !tester.any(errorText); i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(errorText, findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    // Dispose the screen so the periodic re-check timer is cancelled.
    await tester.pumpWidget(const SizedBox());
  });
}
