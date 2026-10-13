import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/features/capture/domain/repositories/photo_capture_repository.dart';
import 'package:cerne/features/capture/presentation/bloc/insertion_modal_bloc.dart';
import 'package:cerne/features/capture/presentation/bloc/insertion_modal_event.dart';
import 'package:cerne/features/capture/presentation/bloc/insertion_modal_state.dart';
import 'package:cerne/features/capture/presentation/widgets/capture_status_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

const _permissionDeniedMessage =
    'Permita o acesso à câmera ou às fotos para continuar.';

/// Two compact tiles, "Câmera" and "Galeria", with no image selected yet, for
/// [InsertionModalFotoCaptura] (FR-005); the permission-denied message; the
/// plain generic loading indicator for [InsertionModalFotoSaving] (FR-007);
/// a plain failure message plus one generic retry action for
/// [InsertionModalFotoFailure], deliberately not reproducing the
/// prototype's named "Foto — Erro" styling/copy or its "Salvar só a foto"
/// action (research.md R11).
class FotoTabView extends StatelessWidget {
  const FotoTabView({required this.state, super.key});

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
            InsertionModalFotoCaptura() => _CapturaView(
              onSourceSelected: (source) =>
                  bloc.add(PhotoSourceSelected(source)),
            ),
            InsertionModalFotoPermissionDenied() =>
              const CapturePermissionDeniedMessage(
                message: _permissionDeniedMessage,
              ),
            InsertionModalFotoSaving() => const CaptureLoadingIndicator(),
            InsertionModalFotoFailure(message: final message) =>
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

class _CapturaView extends StatelessWidget {
  const _CapturaView({required this.onSourceSelected});

  final ValueChanged<PhotoSource> onSourceSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PhotoSourceTile(
          icon: Icons.camera_alt_outlined,
          label: 'Câmera',
          onTap: () => onSourceSelected(PhotoSource.camera),
        ),
        const SizedBox(width: 12),
        _PhotoSourceTile(
          icon: Icons.photo_library_outlined,
          label: 'Galeria',
          onTap: () => onSourceSelected(PhotoSource.gallery),
        ),
      ],
    );
  }
}

class _PhotoSourceTile extends StatelessWidget {
  const _PhotoSourceTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacingLg,
          vertical: DesignTokens.spacingMd,
        ),
        decoration: BoxDecoration(
          color: DesignTokens.colorSurfaceBg,
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: DesignTokens.sizePhotoTileIcon,
              color: DesignTokens.colorPrimary,
            ),
            const SizedBox(height: DesignTokens.spacingSm),
            Text(label, style: DesignTokens.textLabelMd),
          ],
        ),
      ),
    );
  }
}
