import 'dart:math' as math;

import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/core/di/service_locator.dart';
import 'package:cerne/features/capture/domain/repositories/audio_capture_repository.dart';
import 'package:flutter/material.dart';

const _barCount = 12;
const _staggerPerBar = math.pi / 6;

/// Reads `AudioCaptureRepository.amplitudeStream` directly via `get_it` —
/// the one sanctioned bypass of "always through the bloc" for this unit,
/// since the amplitude signal is too high-frequency to belong in bloc event
/// history (contracts/audio-capture-repository.md). The live amplitude sets
/// the bars' overall scale; a looping, per-bar phase offset staggers their
/// motion into a traveling wave instead of all 12 moving in lockstep.
class AudioWaveform extends StatefulWidget {
  const AudioWaveform({super.key});

  @override
  State<AudioWaveform> createState() => _AudioWaveformState();
}

class _AudioWaveformState extends State<AudioWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = getIt<AudioCaptureRepository>();
    return StreamBuilder<double>(
      stream: repository.amplitudeStream,
      builder: (context, snapshot) {
        final amplitudeDbfs = snapshot.data ?? -45.0;
        final normalized = ((amplitudeDbfs + 60) / 60).clamp(0.0, 1.0);
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final phase = _controller.value * 2 * math.pi;
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_barCount, (index) {
                final wave =
                    (math.sin(phase - index * _staggerPerBar) + 1) / 2;
                final height =
                    DesignTokens.spacingSm +
                    (0.25 + 0.75 * wave) * normalized * DesignTokens.spacingXl;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignTokens.spacingXs,
                  ),
                  child: Container(
                    width: DesignTokens.spacingXs,
                    height: height,
                    decoration: BoxDecoration(
                      color: DesignTokens.colorSecondary,
                      borderRadius: BorderRadius.circular(
                        DesignTokens.radiusSm,
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        );
      },
    );
  }
}
