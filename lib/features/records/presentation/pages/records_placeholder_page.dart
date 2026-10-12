import 'package:cerne/core/design_tokens.dart';
import 'package:flutter/material.dart';

/// "Meus Registros" — a navigable placeholder with no behavior of its own in
/// this unit (FR-012; data-model.md Placeholder Destination). No entity/list
/// data is fetched.
class RecordsPlaceholderPage extends StatelessWidget {
  const RecordsPlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.colorSurfaceBg,
      appBar: AppBar(title: const Text('Meus Registros')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingLg),
          child: Text(
            'Ainda não disponível.',
            style: DesignTokens.textBodyLg.copyWith(
              color: DesignTokens.colorTextSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
