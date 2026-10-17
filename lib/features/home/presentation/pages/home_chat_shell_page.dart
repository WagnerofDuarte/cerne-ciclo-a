import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/features/capture/presentation/widgets/open_insertion_modal.dart';
import 'package:cerne/features/home/presentation/widgets/app_drawer.dart';
import 'package:flutter/material.dart';

/// Fixed dark-green header (☰ + "Cerne" wordmark) and an empty conversation
/// area, plus a composer bar that is rendered but fully disabled — no fake
/// messages, no RF04 wiring (FR-016; research.md R10). Scaffold's `drawer`
/// gives the ☰ icon its tap target for free (User Story 4).
class HomeChatShellPage extends StatelessWidget {
  const HomeChatShellPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.colorSurfaceBg,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: DesignTokens.colorPrimary,
        foregroundColor: DesignTokens.colorOnPrimary,
        title: Text(
          'Cerne',
          style: DesignTokens.textTitleLg.copyWith(
            color: DesignTokens.colorOnPrimary,
          ),
        ),
      ),
      body: Column(
        children: [
          const Expanded(child: SizedBox.expand()),
          _ComposerBar(),
        ],
      ),
    );
  }
}

class _ComposerBar extends StatelessWidget {
  const _ComposerBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      decoration: const BoxDecoration(
        color: DesignTokens.colorSurfaceElevated,
        border: Border(top: BorderSide(color: DesignTokens.colorBorder)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => openInsertionModal(context),
            icon: const Icon(Icons.add, color: DesignTokens.colorPrimary),
          ),
          Expanded(
            child: TextField(
              enabled: false,
              decoration: const InputDecoration(
                hintText: 'Escreva uma mensagem...',
              ),
            ),
          ),
          const SizedBox(width: DesignTokens.spacingSm),
          IconButton(
            onPressed: null,
            icon: const Icon(Icons.send, color: DesignTokens.colorTextSecondary),
          ),
        ],
      ),
    );
  }
}
