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
          const Text(
            'Nenhum registro nesse período.',
            style: DesignTokens.textBodyMd,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: DesignTokens.spacingSm),
          Text(
            'Ajuste o filtro de período e tente de novo.',
            style: DesignTokens.textBodyMd.copyWith(color: DesignTokens.colorTextSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: DesignTokens.spacingMd),
          TextButton(
            onPressed: onClosePressed,
            child: Text(
              'Fechar',
              style: DesignTokens.textMonoCaption.copyWith(
                fontSize: 11,
                color: DesignTokens.colorTextSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
