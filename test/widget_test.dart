import 'package:flutter_test/flutter_test.dart';

import 'package:comic_realm/app.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // 验证应用可以正常构建
    await tester.pumpWidget(const ComicRealmApp());
    expect(find.text('漫境 ComicRealm'), findsOneWidget);
  });
}
