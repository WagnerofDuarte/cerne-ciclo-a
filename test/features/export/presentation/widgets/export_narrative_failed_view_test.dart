import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/export/presentation/widgets/export_narrative_failed_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    bool isDownloadingRaw = false,
    Failure? rawDownloadFailure,
    VoidCallback? onRawDataDownloadPressed,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportNarrativeFailedView(
            isDownloadingRaw: isDownloadingRaw,
            rawDownloadFailure: rawDownloadFailure,
            onRawDataDownloadPressed: onRawDataDownloadPressed ?? () {},
            onClosePressed: () {},
          ),
        ),
      ),
    );
  }

  testWidgets('shows the red warning icon and the narrative-failed copy', (tester) async {
    await pump(tester);

    expect(find.byIcon(Icons.warning_amber), findsOneWidget);
    expect(find.textContaining('Não foi possível gerar o resumo com IA'), findsOneWidget);
  });

  testWidgets('exactly one enabled "Baixar dados brutos" button, no PDF control', (tester) async {
    await pump(tester);

    expect(find.widgetWithText(OutlinedButton, 'Baixar dados brutos'), findsOneWidget);
    expect(find.textContaining('PDF'), findsNothing);
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Baixar dados brutos'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('the button disables while isDownloadingRaw is true', (tester) async {
    await pump(tester, isDownloadingRaw: true);

    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Baixar dados brutos'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('the inline retry affordance appears when rawDownloadFailure is set', (tester) async {
    await pump(tester);
    expect(find.text('Tentar novamente'), findsNothing);

    await pump(
      tester,
      rawDownloadFailure: const NetworkTimeoutFailure(message: 'falhou', requestId: 'r1'),
    );
    expect(find.text('Tentar novamente'), findsOneWidget);
  });
}
