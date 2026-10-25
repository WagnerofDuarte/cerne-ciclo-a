import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/features/settings/domain/entities/account_profile.dart';
import 'package:cerne/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:cerne/features/settings/presentation/bloc/settings_event.dart';
import 'package:cerne/features/settings/presentation/bloc/settings_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// 52px (`DesignTokens.sizeAvatarSettings`) initials avatar, the current
/// `displayName` with an inline pencil-to-check control, and the read-only
/// `email` text with no edit affordance beside it (FR-009).
class ProfileHeader extends StatefulWidget {
  const ProfileHeader({super.key});

  @override
  State<ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends State<ProfileHeader> {
  final _controller = TextEditingController();
  bool _wasEditing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, state) {
        final isEditing =
            state.nameEditStatus == NameEditStatus.editing ||
            state.nameEditStatus == NameEditStatus.saving;
        // Seed the controller's text only on the transition into editing —
        // never on every rebuild, which would otherwise clobber the
        // cursor/selection on each keystroke.
        if (isEditing && !_wasEditing) {
          _controller
            ..text = state.nameDraft
            ..selection = TextSelection.collapsed(offset: state.nameDraft.length);
        }
        _wasEditing = isEditing;

        final profile = AccountProfile(displayName: state.displayName, email: state.email);

        final emailText = Text(
          state.email,
          style: DesignTokens.textBodyMd.copyWith(color: DesignTokens.colorTextSecondary),
        );

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                // Default (center) cross-axis alignment is load-bearing here:
                // name+email are one column next to the avatar, so the
                // avatar centers against their combined height, not just
                // the name's — matching the prototype's single `align-items:
                // center` row (name/e-mail never sit in a block of their own
                // below it).
                children: [
                  CircleAvatar(
                    radius: DesignTokens.sizeAvatarSettings / 2,
                    backgroundColor: DesignTokens.colorPrimary,
                    child: Text(
                      profile.initials,
                      style: DesignTokens.textTitleLg.copyWith(
                        color: DesignTokens.colorOnPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: DesignTokens.spacingMd),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        isEditing
                            ? TextField(
                                autofocus: true,
                                controller: _controller,
                                enabled: state.nameEditStatus == NameEditStatus.editing,
                                onChanged: (value) => context
                                    .read<SettingsBloc>()
                                    .add(NameDraftChanged(value)),
                                decoration: const InputDecoration(isDense: true),
                              )
                            : Text(
                                state.displayName,
                                style: DesignTokens.textTitleSm,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                        const SizedBox(height: DesignTokens.spacingXs),
                        emailText,
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(isEditing ? Icons.check : Icons.edit_outlined, size: 20),
                    onPressed: state.nameEditStatus == NameEditStatus.saving
                        ? null
                        : () => context.read<SettingsBloc>().add(
                            isEditing ? const NameEditSubmitted() : const NameEditStarted(),
                          ),
                  ),
                ],
              ),
              if (isEditing && state.nameEditFailureMessage != null)
                Padding(
                  padding: const EdgeInsets.only(
                    top: DesignTokens.spacingXs,
                    left: DesignTokens.sizeAvatarSettings + DesignTokens.spacingMd,
                  ),
                  child: Text(
                    state.nameEditFailureMessage!,
                    style: DesignTokens.textBodyMd.copyWith(color: DesignTokens.colorError),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
