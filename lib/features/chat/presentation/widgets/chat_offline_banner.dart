import 'package:cerne/core/design_tokens.dart';
import 'package:flutter/material.dart';

/// Shown whenever `ChatReady.isOffline` is `true` (FR-011,
/// prototype-extract.md §2.2).
class ChatOfflineBanner extends StatelessWidget {
  const ChatOfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: DesignTokens.colorInfoOffline,
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingMd,
        vertical: DesignTokens.spacingSm,
      ),
      child: Text(
        'Sem conexão — histórico disponível, novas mensagens bloqueadas',
        style: DesignTokens.textLabelMd.copyWith(color: DesignTokens.colorOnPrimary),
        textAlign: TextAlign.center,
      ),
    );
  }
}
