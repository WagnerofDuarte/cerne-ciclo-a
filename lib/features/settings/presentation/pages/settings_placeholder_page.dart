import 'package:cerne/core/design_tokens.dart';
import 'package:flutter/material.dart';

/// "Configurações" — the same static placeholder pattern as
/// RecordsPlaceholderPage (FR-012).
class SettingsPlaceholderPage extends StatelessWidget {
  const SettingsPlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.colorSurfaceBg,
      appBar: AppBar(title: const Text('Configurações')),
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
