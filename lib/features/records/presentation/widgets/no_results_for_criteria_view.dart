import 'package:cerne/core/design_tokens.dart';
import 'package:flutter/material.dart';

/// FR-009 — distinct from `records_empty_state.dart`'s account-wide "Nenhum
/// registro ainda": shown only when a search/filter combination narrows a
/// non-empty account down to zero results.
class NoResultsForCriteriaView extends StatelessWidget {
  const NoResultsForCriteriaView({super.key, required this.onAdjustPressed});

  final VoidCallback onAdjustPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.search_off,
              size: DesignTokens.spacing2xl,
              color: DesignTokens.colorTextSecondary,
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            Text(
              'Nenhum resultado para esta busca/filtro',
              style: DesignTokens.textTitleSm,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            ElevatedButton(
              onPressed: onAdjustPressed,
              child: const Text('Limpar filtros'),
            ),
          ],
        ),
      ),
    );
  }
}
