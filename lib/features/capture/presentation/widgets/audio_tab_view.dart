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
/// permission-denied message; a spinner over the frozen waveform for
/// [InsertionModalAudioProcessing] (FR-001); an editable review field for
/// [InsertionModalAudioTranscribed]/[InsertionModalAudioSaveFailure]
/// (FR-002/FR-009); the plain generic loading indicator for
/// [InsertionModalAudioSaving]; and [RecognitionErrorView] for
/// [InsertionModalAudioFailure] (FR-003).
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
            InsertionModalAudioProcessing(duration: final duration) =>
              _ProcessingView(duration: duration),
            InsertionModalAudioTranscribed(
              text: final text,
              duration: final duration,
            ) =>
              _ReviewView(
                text: text,
                duration: duration,
                message: null,
                onTextChanged: (value) =>
                    bloc.add(AudioReviewTextChanged(value)),
                onSave: () => bloc.add(const AudioSaveConfirmed()),
              ),
            InsertionModalAudioSaveFailure(
              text: final text,
              duration: final duration,
              message: final message,
            ) =>
              _ReviewView(
                text: text,
                duration: duration,
                message: message,
                onTextChanged: (value) =>
                    bloc.add(AudioReviewTextChanged(value)),
                onSave: () => bloc.add(const AudioSaveConfirmed()),
              ),
            InsertionModalAudioSaving() => const CaptureLoadingIndicator(),
            InsertionModalAudioFailure(message: final message) =>
              RecognitionErrorView(
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

class _ProcessingView extends StatelessWidget {
  const _ProcessingView({required this.duration});

  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CaptureLoadingIndicator(),
        const SizedBox(height: DesignTokens.spacingMd),
        Text(
          'Transcrevendo...',
          style: DesignTokens.textLabelMd.copyWith(
            color: DesignTokens.colorTextSecondary,
          ),
        ),
        const SizedBox(height: DesignTokens.spacingMd),
        const Opacity(opacity: 0.35, child: AudioWaveform()),
        const SizedBox(height: DesignTokens.spacingSm),
        Text(
          '$minutes:$seconds de áudio',
          style: DesignTokens.textMonoCaption.copyWith(
            color: DesignTokens.colorTextSecondary,
          ),
        ),
      ],
    );
  }
}

class _ReviewView extends StatelessWidget {
  const _ReviewView({
    required this.text,
    required this.duration,
    required this.message,
    required this.onTextChanged,
    required this.onSave,
  });

  final String text;
  final Duration duration;
  final String? message;
  final ValueChanged<String> onTextChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextFormField(
          key: const ValueKey('audioReviewField'),
          initialValue: text,
          maxLines: 6,
          minLines: 3,
          onChanged: onTextChanged,
        ),
        const SizedBox(height: DesignTokens.spacingSm),
        Text(
          'áudio original · $minutes:$seconds',
          style: DesignTokens.textMonoCaption.copyWith(
            color: DesignTokens.colorTextSecondary,
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: DesignTokens.spacingSm),
          Text(
            message!,
            style: DesignTokens.textBodyMd.copyWith(
              color: DesignTokens.colorError,
            ),
          ),
        ],
        const SizedBox(height: DesignTokens.spacingMd),
        ElevatedButton(
          onPressed: text.trim().isNotEmpty ? onSave : null,
          child: const Text('Salvar'),
        ),
      ],
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
