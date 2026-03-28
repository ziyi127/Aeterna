import 'package:aeterna/app/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Home launcher renders', (tester) async {
    await tester.pumpWidget(const AeternaApp());

    expect(find.text('恒时 Aeterna'), findsOneWidget);
    expect(find.text('放映 Projector'), findsOneWidget);
    expect(find.text('计划 Schedule'), findsOneWidget);
  });
}
