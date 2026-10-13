import 'dart:async';

import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/features/capture/presentation/bloc/insertion_modal_bloc.dart';
import 'package:cerne/features/capture/presentation/bloc/insertion_modal_event.dart';
import 'package:cerne/features/capture/presentation/bloc/insertion_modal_state.dart';
import 'package:cerne/features/capture/presentation/widgets/audio_tab_view.dart';
import 'package:cerne/features/capture/presentation/widgets/capture_tab_bar.dart';
import 'package:cerne/features/capture/presentation/widgets/foto_tab_view.dart';
import 'package:cerne/features/capture/presentation/widgets/texto_tab_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Shown via `showModalBottomSheet` as an overlay above Home/Chat (with a
/// darkened scrim) without discarding or navigating away from Home/Chat's
/// state underneath (FR-001) — `showModalBottomSheet` gives the scrim and
/// overlay semantics for free. An exhaustive `BlocBuilder` switch over
/// [InsertionModalState] drives the three tab bodies, plus a listener on
/// the bloc's one-shot [InsertionModalBloc.closeRequests] that pops the
/// sheet on a successful save (FR-011).
class InsertionModalPage extends StatefulWidget {
  const InsertionModalPage({super.key});

  @override
  State<InsertionModalPage> createState() => _InsertionModalPageState();
}

class _InsertionModalPageState extends State<InsertionModalPage> {
  late final StreamSubscription<void> _closeSubscription;

  @override
  void initState() {
    super.initState();
    _closeSubscription = context
        .read<InsertionModalBloc>()
        .closeRequests
        .listen((_) {
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        });
  }

  @override
  void dispose() {
    _closeSubscription.cancel();
    super.dispose();
  }

  CaptureTab _tabOf(InsertionModalState state) => switch (state) {
    InsertionModalTexto() ||
    InsertionModalTextoSaving() ||
    InsertionModalTextoFailure() => CaptureTab.texto,
    InsertionModalAudioIdle() ||
    InsertionModalAudioPermissionDenied() ||
    InsertionModalAudioRecording() ||
    InsertionModalAudioSaving() ||
    InsertionModalAudioFailure() => CaptureTab.audio,
    InsertionModalFotoCaptura() ||
    InsertionModalFotoPermissionDenied() ||
    InsertionModalFotoSaving() ||
    InsertionModalFotoFailure() => CaptureTab.foto,
  };

  @override
  Widget build(BuildContext context) {
    return AnimatedPadding(
      duration: const Duration(milliseconds: 100),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BlocBuilder<InsertionModalBloc, InsertionModalState>(
                builder: (context, state) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              context.read<InsertionModalBloc>().add(
                                const ModalClosed(),
                              );
                              Navigator.of(context).pop();
                            },
                            child: const Icon(
                              Icons.close,
                              size: 20,
                              color: DesignTokens.colorTextPrimary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: CaptureTabBar(
                              activeTab: _tabOf(state),
                              onTabSelected: (tab) => context
                                  .read<InsertionModalBloc>()
                                  .add(TabSelected(tab)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: DesignTokens.spacingMd),
                      switch (state) {
                        InsertionModalTexto() ||
                        InsertionModalTextoSaving() ||
                        InsertionModalTextoFailure() => TextoTabView(
                          state: state,
                        ),
                        InsertionModalAudioIdle() ||
                        InsertionModalAudioPermissionDenied() ||
                        InsertionModalAudioRecording() ||
                        InsertionModalAudioSaving() ||
                        InsertionModalAudioFailure() => AudioTabView(
                          state: state,
                        ),
                        InsertionModalFotoCaptura() ||
                        InsertionModalFotoPermissionDenied() ||
                        InsertionModalFotoSaving() ||
                        InsertionModalFotoFailure() => FotoTabView(
                          state: state,
                        ),
                      },
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
