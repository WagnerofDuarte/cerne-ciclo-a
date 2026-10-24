import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/export/presentation/widgets/export_concluded_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    bool isDownloadingPdf = false,
    bool isDownloadingRaw = false,
    Failure? pdfDownloadFailure,
    Failure? rawDownloadFailure,
    VoidCallback? onPdfDownloadPressed,
    VoidCallback? onRawDataDownloadPressed,
    VoidCallback? onClosePressed,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportConcludedView(
            isDownloadingPdf: isDownloadingPdf,
            isDownloadingRaw: isDownloadingRaw,
            pdfDownloadFailure: pdfDownloadFailure,
            rawDownloadFailure: rawDownloadFailure,
            onPdfDownloadPressed: onPdfDownloadPressed ?? () {},
            onRawDataDownloadPressed: onRawDataDownloadPressed ?? () {},
            onClosePressed: onClosePressed ?? () {},
          ),
        ),
      ),
    );
  }

  testWidgets('green check + "Resumo pronto" render', (tester) async {
    await pump(tester);

    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(find.text('Resumo pronto'), findsOneWidget);
  });

  testWidgets('"Baixar PDF" and "Baixar dados brutos" are both enabled by default', (tester) async {
    await pump(tester);

    final pdfButton = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Baixar PDF'));
    final rawButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Baixar dados brutos'),
    );
    expect(pdfButton.onPressed, isNotNull);
    expect(rawButton.onPressed, isNotNull);
  });

  testWidgets('each button disables while its own isDownloadingX flag is true', (tester) async {
    await pump(tester, isDownloadingPdf: true, isDownloadingRaw: true);

    final pdfButton = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Baixar PDF'));
    final rawButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Baixar dados brutos'),
    );
    expect(pdfButton.onPressed, isNull);
    expect(rawButton.onPressed, isNull);
  });

  testWidgets('the inline retry affordance appears only when its own '
      'DownloadFailure is set', (tester) async {
    await pump(tester);
    expect(find.text('Tentar novamente'), findsNothing);

    await pump(
      tester,
      pdfDownloadFailure: const NetworkTimeoutFailure(message: 'falhou', requestId: 'r1'),
    );
    expect(find.text('Tentar novamente'), findsOneWidget);
    expect(find.text('falhou'), findsOneWidget);
  });

  testWidgets('tapping each button invokes its own callback', (tester) async {
    var pdfTapped = false;
    var rawTapped = false;
    await pump(
      tester,
      onPdfDownloadPressed: () => pdfTapped = true,
      onRawDataDownloadPressed: () => rawTapped = true,
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Baixar PDF'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Baixar dados brutos'));

    expect(pdfTapped, isTrue);
    expect(rawTapped, isTrue);
  });
}
