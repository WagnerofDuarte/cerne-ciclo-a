import 'package:cerne/core/design_tokens.dart';
import 'package:flutter/material.dart';

/// FR-003 — reached immediately from `create()`'s own `EXPORT_EMPTY_PERIOD`
/// failure; the sheet never shows "Pendente"/"Processando" first.
class ExportEmptyPeriodView extends StatelessWidget {
  const ExportEmptyPeriodView({super.key, required this.onClosePressed});

  final VoidCallback onClosePressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(DesignTokens.spacingLg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.inbox_outlined,
            size: DesignTokens.spacing2xl,
            color: DesignTokens.colorTextSecondary,
          ),
          const SizedBox(height: DesignTokens.spacingMd),
          const Text(
            'Nenhum registro nesse período.',
            style: DesignTokens.textTitleSm,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: DesignTokens.spacingSm),
          const Text(
            'Ajuste o filtro de período em "Meus Registros" e tente novamente.',
            style: DesignTokens.textBodyMd,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: DesignTokens.spacingLg),
          TextButton(onPressed: onClosePressed, child: const Text('Fechar')),
        ],
      ),
    );
  }
}
