import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/features/capture/presentation/bloc/insertion_modal_bloc.dart';
import 'package:cerne/features/capture/presentation/bloc/insertion_modal_event.dart';
import 'package:cerne/features/capture/presentation/bloc/insertion_modal_state.dart';
import 'package:cerne/features/capture/presentation/widgets/audio_waveform.dart';
import 'package:cerne/features/capture/presentation/widgets/capture_status_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

const _permissionDeniedMessage =
    'Permita o acesso ao microfone para gravar um áudio.';

/// A round start control with the "Toque para gravar" caption for
/// [InsertionModalAudioIdle] (FR-004); a stop control, [AudioWaveform], and
/// a running `mm:ss` timer for [InsertionModalAudioRecording]; the
/// permission-denied message; the plain generic loading indicator for
/// [InsertionModalAudioSaving] (FR-007); a plain failure message plus one
/// generic retry action for [InsertionModalAudioFailure], deliberately not
/// reproducing the prototype's named "Áudio — Erro" styling/copy
/// (research.md R11).
class AudioTabView extends StatelessWidget {
  const AudioTabView({required this.state, super.key});

  final InsertionModalState state;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<InsertionModalBloc>();
    return Padding(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _minTabContentHeight),
        child: Center(
          child: switch (state) {
            InsertionModalAudioIdle() => _IdleView(
              onStart: () => bloc.add(const AudioStartRequested()),
            ),
            InsertionModalAudioPermissionDenied() =>
              const CapturePermissionDeniedMessage(
                message: _permissionDeniedMessage,
              ),
            InsertionModalAudioRecording(elapsed: final elapsed) =>
              _RecordingView(
                elapsed: elapsed,
                onStop: () => bloc.add(const AudioStopRequested()),
              ),
            InsertionModalAudioSaving() => const CaptureLoadingIndicator(),
            InsertionModalAudioFailure(message: final message) =>
              CaptureFailureBand(
                message: message,
                onRetry: () => bloc.add(const RetryRequested()),
              ),
            _ => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }
}

const _minTabContentHeight = 200.0;

class _IdleView extends StatelessWidget {
  const _IdleView({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onStart,
          child: Container(
            width: DesignTokens.sizeAudioRecordButton,
            height: DesignTokens.sizeAudioRecordButton,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: DesignTokens.colorPrimary,
            ),
            child: const Icon(
              Icons.mic_none,
              size: DesignTokens.sizeAudioRecordIcon,
              color: DesignTokens.colorOnPrimary,
            ),
          ),
        ),
        const SizedBox(height: DesignTokens.spacingMd),
        Text(
          'Toque para gravar',
          style: DesignTokens.textLabelMd.copyWith(
            color: DesignTokens.colorTextSecondary,
          ),
        ),
      ],
    );
  }
}

class _RecordingView extends StatelessWidget {
  const _RecordingView({required this.elapsed, required this.onStop});

  final Duration elapsed;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PulsingStopButton(onStop: onStop),
        const SizedBox(height: DesignTokens.spacingMd),
        const AudioWaveform(),
        const SizedBox(height: DesignTokens.spacingMd),
        Text(
          '$minutes:$seconds',
          style: DesignTokens.textMonoCaption.copyWith(
            color: DesignTokens.colorError,
          ),
        ),
      ],
    );
  }
}

/// A stop control sized and shaped like [_IdleView]'s start button, with a
/// soft ring that pulses outward to signal that recording is live.
class _PulsingStopButton extends StatefulWidget {
  const _PulsingStopButton({required this.onStop});

  final VoidCallback onStop;

  @override
  State<_PulsingStopButton> createState() => _PulsingStopButtonState();
}

class _PulsingStopButtonState extends State<_PulsingStopButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onStop,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = _controller.value;
          return SizedBox(
            width: DesignTokens.sizeAudioRecordButton,
            height: DesignTokens.sizeAudioRecordButton,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: (1 - t) * 0.5,
                  child: Transform.scale(
                    scale: 1 + t * 0.5,
                    child: const _StopButtonCircle(),
                  ),
                ),
                child!,
              ],
            ),
          );
        },
        child: const _StopButtonCircle(
          icon: Icons.stop_outlined,
          iconColor: DesignTokens.colorOnPrimary,
        ),
      ),
    );
  }
}

class _StopButtonCircle extends StatelessWidget {
  const _StopButtonCircle({this.icon, this.iconColor});

  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: DesignTokens.sizeAudioRecordButton,
      height: DesignTokens.sizeAudioRecordButton,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: DesignTokens.colorError,
      ),
      child: icon == null
          ? null
          : Icon(icon, size: DesignTokens.sizeAudioRecordIcon, color: iconColor),
    );
  }
}
