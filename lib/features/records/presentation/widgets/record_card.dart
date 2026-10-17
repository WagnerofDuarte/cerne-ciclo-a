import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/records/domain/entities/sync_badge_state.dart';
import 'package:cerne/features/records/presentation/widgets/sync_badge_dot.dart';
import 'package:flutter/material.dart';

const _originColors = {
  EntrySource.manual: DesignTokens.colorPrimary,
  EntrySource.audio: DesignTokens.colorSecondary,
  EntrySource.photo: DesignTokens.colorTextSecondary,
  EntrySource.chat: DesignTokens.colorAccent,
};

const _originIcons = {
  EntrySource.manual: Icons.edit_outlined,
  EntrySource.audio: Icons.mic_none,
  EntrySource.photo: Icons.image_outlined,
  EntrySource.chat: Icons.chat_bubble_outline,
};

/// One entry: spine + icon colored by origin, a monospace time, a sync
/// badge, a text excerpt, and tag chips when present (data-model.md's
/// origin marker mapping table, FR-002).
class RecordCard extends StatelessWidget {
  const RecordCard({super.key, required this.entry});

  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final color = _originColors[entry.source]!;
    final time = entry.occurredAt.toLocal();
    final timeLabel =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingMd,
        vertical: DesignTokens.spacingXs,
      ),
      decoration: BoxDecoration(
        color: DesignTokens.colorSurfaceElevated,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_originIcons[entry.source]!, color: color, size: DesignTokens.spacingMd),
              const SizedBox(width: DesignTokens.spacingSm),
              Text(timeLabel, style: DesignTokens.textMonoCaption),
              const Spacer(),
              SyncBadgeDot(state: SyncBadge.derive(null)),
            ],
          ),
          const SizedBox(height: DesignTokens.spacingSm),
          Text(entry.content, style: DesignTokens.textBodyMd),
          if (entry.tags.isNotEmpty) ...[
            const SizedBox(height: DesignTokens.spacingSm),
            Wrap(
              spacing: DesignTokens.spacingXs,
              runSpacing: DesignTokens.spacingXs,
              children: entry.tags
                  .map(
                    (tag) => Chip(
                      label: Text(tag.name, style: DesignTokens.textLabelMd),
                      backgroundColor: DesignTokens.colorSurfaceBg,
                      side: const BorderSide(color: DesignTokens.colorBorder),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}
