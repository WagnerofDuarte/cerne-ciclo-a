import 'package:cerne/core/design_tokens.dart';
import 'package:flutter/material.dart';

/// "Tela 4 — Vazio" (prototype-extract.md): a notebook icon, "Nenhum
/// registro ainda", and a "Criar primeiro registro" CTA whose behavior is
/// supplied by the caller (data-model.md).
class RecordsEmptyState extends StatelessWidget {
  const RecordsEmptyState({super.key, required this.onCreatePressed});

  final VoidCallback onCreatePressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.menu_book_outlined,
              size: DesignTokens.spacing2xl,
              color: DesignTokens.colorTextSecondary,
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            Text(
              'Nenhum registro ainda',
              style: DesignTokens.textTitleSm,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            ElevatedButton(
              onPressed: onCreatePressed,
              child: const Text('Criar primeiro registro'),
            ),
          ],
        ),
      ),
    );
  }
}
