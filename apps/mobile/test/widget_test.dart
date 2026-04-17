import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dems_mobile/app.dart';

void main() {
  testWidgets('App boots to login screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: DemsApp()));
    await tester.pumpAndSettle();
    expect(find.text('DEMS'), findsOneWidget);
  });
}
