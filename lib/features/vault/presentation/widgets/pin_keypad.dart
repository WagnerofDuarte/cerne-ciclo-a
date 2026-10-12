import 'package:cerne/core/design_tokens.dart';
import 'package:flutter/material.dart';

/// Shared 3×4 numeric keypad with backspace and 4 progress dots (FR-005),
/// reused by first-time PIN create/confirm and every PIN-entry unlock
/// state. Dumb widget — the entered-digit buffer lives in `VaultBloc`;
/// this only renders [enteredDigits]' length as progress dots and reports
/// taps upward.
class PinKeypad extends StatelessWidget {
  const PinKeypad({
    super.key,
    required this.enteredDigits,
    required this.onDigitPressed,
    required this.onBackspacePressed,
  });

  final String enteredDigits;
  final ValueChanged<String> onDigitPressed;
  final VoidCallback onBackspacePressed;

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['', '0', '⌫'],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ProgressDots(filled: enteredDigits.length),
        const SizedBox(height: DesignTokens.spacingXl),
        for (final row in _rows)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final key in row)
                Padding(
                  padding: const EdgeInsets.all(DesignTokens.spacingSm),
                  child: key.isEmpty
                      ? const SizedBox(
                          width: DesignTokens.sizeKeypadTapTarget,
                          height: DesignTokens.sizeKeypadTapTarget,
                        )
                      : key == '⌫'
                          ? _KeypadKey(
                              label: key,
                              onTap: onBackspacePressed,
                            )
                          : _KeypadKey(
                              label: key,
                              onTap: () => onDigitPressed(key),
                            ),
                ),
            ],
          ),
      ],
    );
  }
}

class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.filled});

  final int filled;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(4, (index) {
        final isFilled = index < filled;
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacingSm,
          ),
          child: Container(
            width: DesignTokens.sizeProgressDot,
            height: DesignTokens.sizeProgressDot,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isFilled ? DesignTokens.colorPrimary : Colors.transparent,
              border: Border.all(
                color: DesignTokens.colorPrimary,
                width: DesignTokens.borderWidthFocused,
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _KeypadKey extends StatelessWidget {
  const _KeypadKey({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: DesignTokens.sizeKeypadTapTarget,
      height: DesignTokens.sizeKeypadTapTarget,
      child: Material(
        color: DesignTokens.colorSurfaceElevated,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Center(
            child: label == '⌫'
                ? const Icon(
                    Icons.backspace,
                    color: DesignTokens.colorTextPrimary,
                  )
                : Text(label, style: DesignTokens.textTitleLg),
          ),
        ),
      ),
    );
  }
}
