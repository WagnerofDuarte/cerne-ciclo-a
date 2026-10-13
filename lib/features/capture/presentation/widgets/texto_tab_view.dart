import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/features/capture/presentation/bloc/insertion_modal_bloc.dart';
import 'package:cerne/features/capture/presentation/bloc/insertion_modal_event.dart';
import 'package:cerne/features/capture/presentation/bloc/insertion_modal_state.dart';
import 'package:cerne/features/capture/presentation/widgets/capture_status_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// A free multiline text field and a "Salvar" action unavailable while the
/// field is empty (FR-003). Renders the plain generic loading indicator
/// while saving and a plain failure message on failure (FR-007/FR-009) —
/// tapping "Salvar" again is the retry, no dedicated retry affordance
/// needed for this tab.
class TextoTabView extends StatelessWidget {
  const TextoTabView({required this.state, super.key});

  final InsertionModalState state;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<InsertionModalBloc>();
    final text = switch (state) {
      InsertionModalTexto(text: final t) => t,
      InsertionModalTextoSaving(text: final t) => t,
      InsertionModalTextoFailure(text: final t) => t,
      _ => '',
    };
    final isSaving = state is InsertionModalTextoSaving;
    final failure = state;
    final failureMessage = failure is InsertionModalTextoFailure
        ? failure.message
        : null;

    return Padding(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _minTabContentHeight),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const ValueKey('textoTabField'),
              initialValue: text,
              enabled: !isSaving,
              maxLines: 6,
              minLines: 3,
              decoration: const InputDecoration(
                hintText: 'Escreva livremente...',
              ),
              onChanged: (value) => bloc.add(TextDraftChanged(value)),
            ),
            if (failureMessage != null) ...[
              const SizedBox(height: DesignTokens.spacingSm),
              Text(
                failureMessage,
                style: DesignTokens.textBodyMd.copyWith(
                  color: DesignTokens.colorError,
                ),
              ),
            ],
            const SizedBox(height: DesignTokens.spacingLg),
            if (isSaving)
              const CaptureLoadingIndicator()
            else
              ElevatedButton(
                onPressed: text.trim().isNotEmpty
                    ? () => bloc.add(const SaveTextSubmitted())
                    : null,
                child: const Text('Salvar'),
              ),
          ],
        ),
      ),
    );
  }
}

const _minTabContentHeight = 180.0;
