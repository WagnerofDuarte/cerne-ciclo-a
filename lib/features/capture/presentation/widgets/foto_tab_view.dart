import 'dart:io';

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

/// Two compact tiles, "Câmera" and "Galeria", with no image selected yet,
/// for [InsertionModalFotoCaptura] (FR-005); the permission-denied message;
/// a thumbnail with a spinner for [InsertionModalFotoProcessing]; a
/// thumbnail next to an editable review field for
/// [InsertionModalFotoReconhecido]/[InsertionModalFotoSaveFailure]
/// (FR-006/FR-009); the plain generic loading indicator for
/// [InsertionModalFotoSaving]; and [RecognitionErrorView] with its second
/// action, "Salvar só a foto", for [InsertionModalFotoFailure] (FR-007/
/// FR-008).
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
            InsertionModalFotoProcessing(imagePath: final imagePath) =>
              _ProcessingView(imagePath: imagePath),
            InsertionModalFotoReconhecido(
              imagePath: final imagePath,
              text: final text,
            ) =>
              _ReviewView(
                imagePath: imagePath,
                text: text,
                message: null,
                onTextChanged: (value) =>
                    bloc.add(PhotoReviewTextChanged(value)),
                onSave: () => bloc.add(const PhotoSaveConfirmed()),
              ),
            InsertionModalFotoSaveFailure(
              imagePath: final imagePath,
              text: final text,
              message: final message,
            ) =>
              _ReviewView(
                imagePath: imagePath,
                text: text,
                message: message,
                onTextChanged: (value) =>
                    bloc.add(PhotoReviewTextChanged(value)),
                onSave: () => bloc.add(const PhotoSaveConfirmed()),
              ),
            InsertionModalFotoSaving() => const CaptureLoadingIndicator(),
            InsertionModalFotoFailure(
              imagePath: final imagePath,
              message: final message,
            ) =>
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Thumbnail.wide(imagePath: imagePath),
                  const SizedBox(height: DesignTokens.spacingMd),
                  RecognitionErrorView(
                    message: message,
                    onRetry: () => bloc.add(const RetryRequested()),
                    secondaryAction: (
                      'Salvar só a foto',
                      () => bloc.add(const PhotoSaveWithoutTextRequested()),
                    ),
                  ),
                ],
              ),
            _ => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.imagePath})
    : width = DesignTokens.sizePhotoThumbnail,
      height = DesignTokens.sizePhotoThumbnail;

  const _Thumbnail.wide({required this.imagePath})
    : width = DesignTokens.sizePhotoThumbnailWideWidth,
      height = DesignTokens.sizePhotoThumbnailWideHeight;

  final String imagePath;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
      child: Image.file(
        File(imagePath),
        width: width,
        height: height,
        fit: BoxFit.cover,
      ),
    );
  }
}

class _ProcessingView extends StatelessWidget {
  const _ProcessingView({required this.imagePath});

  final String imagePath;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Thumbnail.wide(imagePath: imagePath),
        const SizedBox(height: DesignTokens.spacingMd),
        const CaptureLoadingIndicator(),
        const SizedBox(height: DesignTokens.spacingSm),
        Text(
          'Reconhecendo texto...',
          style: DesignTokens.textLabelMd.copyWith(
            color: DesignTokens.colorTextSecondary,
          ),
        ),
      ],
    );
  }
}

class _ReviewView extends StatelessWidget {
  const _ReviewView({
    required this.imagePath,
    required this.text,
    required this.message,
    required this.onTextChanged,
    required this.onSave,
  });

  final String imagePath;
  final String text;
  final String? message;
  final ValueChanged<String> onTextChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Thumbnail(imagePath: imagePath),
            const SizedBox(width: DesignTokens.spacingMd),
            Expanded(
              child: TextFormField(
                key: const ValueKey('photoReviewField'),
                initialValue: text,
                maxLines: 6,
                minLines: 3,
                onChanged: onTextChanged,
              ),
            ),
          ],
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
