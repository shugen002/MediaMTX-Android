import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mediamtx_manager/core/utils/formatters.dart';

void main() {
  test('formats bytes and rates for the dashboard', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(1024), '1.0 KB');
    expect(formatRate(125000), '1.0 Mbps');
  });

  testWidgets('smoke test renders a Material app', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('MTX'))),
    );
    expect(find.text('MTX'), findsOneWidget);
  });
}
