import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quick_pos/app.dart';
import 'package:quick_pos/core/storage/local_prefs.dart';

void main() {
  testWidgets('muestra pantalla enlazar tienda sin store guardado', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(QuickPosApp(localPrefs: LocalPrefs(prefs)));
    await tester.pumpAndSettle();
    expect(find.text('Enlazar tienda'), findsOneWidget);
  });
}
