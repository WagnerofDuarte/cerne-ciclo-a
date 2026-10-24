import 'dart:async';

import 'package:cerne/core/di/service_locator.dart';
import 'package:cerne/features/export/presentation/bloc/export_bloc.dart';
import 'package:cerne/features/export/presentation/bloc/export_event.dart';
import 'package:cerne/features/export/presentation/bloc/export_state.dart';
import 'package:cerne/features/export/presentation/widgets/export_concluded_view.dart';
import 'package:cerne/features/export/presentation/widgets/export_empty_period_view.dart';
import 'package:cerne/features/export/presentation/widgets/export_failed_view.dart';
import 'package:cerne/features/export/presentation/widgets/export_narrative_failed_view.dart';
import 'package:cerne/features/export/presentation/widgets/export_pending_view.dart';
import 'package:cerne/features/export/presentation/widgets/export_processing_view.dart';
import 'package:cerne/features/session/presentation/bloc/session_bloc.dart';
import 'package:cerne/features/session/presentation/bloc/session_event.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The `StatefulWidget` `showModalBottomSheet` builds from "Meus
/// Registros"' download icon (data-model.md, research.md R7/R8,
/// contracts/export-bloc.md). Exhaustively switches on `ExportState`'s six
/// variants from the moment it compiles.
class ExportSheet extends StatefulWidget {
  const ExportSheet({super.key, required this.periodStart, required this.periodEnd});

  final DateTime? periodStart;
  final DateTime? periodEnd;

  @override
  State<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<ExportSheet> {
  late final ExportBloc _bloc;
  late final StreamSubscription<void> _reauthSubscription;

  @override
  void initState() {
    super.initState();
    _bloc = getIt<ExportBloc>()..add(ExportRequested(widget.periodStart, widget.periodEnd));
    _reauthSubscription = _bloc.reauthRequired.listen((_) {
      if (!mounted) return;
      context.read<SessionBloc>().add(const AuthExpiredDetected());
    });
  }

  @override
  void dispose() {
    _reauthSubscription.cancel();
    _bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ExportBloc>.value(
      value: _bloc,
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: BlocBuilder<ExportBloc, ExportState>(
            builder: (context, state) => switch (state) {
              ExportPending() => ExportPendingView(onClosePressed: () => _close(context)),
              ExportProcessing() => ExportProcessingView(onClosePressed: () => _close(context)),
              ExportConcluded() => ExportConcludedView(
                isDownloadingPdf: state.isDownloadingPdf,
                isDownloadingRaw: state.isDownloadingRaw,
                pdfDownloadFailure: state.pdfDownloadFailure,
                rawDownloadFailure: state.rawDownloadFailure,
                onPdfDownloadPressed: () =>
                    context.read<ExportBloc>().add(const PdfDownloadRequested()),
                onRawDataDownloadPressed: () =>
                    context.read<ExportBloc>().add(const RawDataDownloadRequested()),
                onClosePressed: () => _close(context),
              ),
              ExportNarrativeFailed() => ExportNarrativeFailedView(
                isDownloadingRaw: state.isDownloadingRaw,
                rawDownloadFailure: state.rawDownloadFailure,
                onRawDataDownloadPressed: () =>
                    context.read<ExportBloc>().add(const RawDataDownloadRequested()),
                onClosePressed: () => _close(context),
              ),
              ExportFailed() => ExportFailedView(onClosePressed: () => _close(context)),
              ExportEmptyPeriod() => ExportEmptyPeriodView(onClosePressed: () => _close(context)),
            },
          ),
        ),
      ),
    );
  }

  void _close(BuildContext context) => Navigator.of(context).pop();
}
