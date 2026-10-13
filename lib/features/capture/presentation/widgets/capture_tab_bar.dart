import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/features/capture/presentation/bloc/insertion_modal_event.dart';
import 'package:flutter/material.dart';

/// Exactly three capture modes as tabs, with the active tab visually
/// distinguished (FR-002).
class CaptureTabBar extends StatelessWidget {
  const CaptureTabBar({
    required this.activeTab,
    required this.onTabSelected,
    super.key,
  });

  final CaptureTab activeTab;
  final ValueChanged<CaptureTab> onTabSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignTokens.spacingXs),
      decoration: BoxDecoration(
        color: DesignTokens.colorSurfaceBg,
        borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TabButton(
              label: 'Texto',
              tab: CaptureTab.texto,
              activeTab: activeTab,
              onTabSelected: onTabSelected,
            ),
          ),
          const SizedBox(width: DesignTokens.spacingXs),
          Expanded(
            child: _TabButton(
              label: 'Áudio',
              tab: CaptureTab.audio,
              activeTab: activeTab,
              onTabSelected: onTabSelected,
            ),
          ),
          const SizedBox(width: DesignTokens.spacingXs),
          Expanded(
            child: _TabButton(
              label: 'Foto',
              tab: CaptureTab.foto,
              activeTab: activeTab,
              onTabSelected: onTabSelected,
            ),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.tab,
    required this.activeTab,
    required this.onTabSelected,
  });

  final String label;
  final CaptureTab tab;
  final CaptureTab activeTab;
  final ValueChanged<CaptureTab> onTabSelected;

  @override
  Widget build(BuildContext context) {
    final isActive = tab == activeTab;
    return GestureDetector(
      onTap: () => onTabSelected(tab),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingSm),
        decoration: BoxDecoration(
          color: isActive ? DesignTokens.colorPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: DesignTokens.textLabelMd.copyWith(
            color: isActive
                ? DesignTokens.colorOnPrimary
                : DesignTokens.colorTextSecondary,
          ),
        ),
      ),
    );
  }
}
