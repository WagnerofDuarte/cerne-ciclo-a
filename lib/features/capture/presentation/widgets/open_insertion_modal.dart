import 'package:cerne/core/di/service_locator.dart';
import 'package:cerne/features/capture/presentation/bloc/insertion_modal_bloc.dart';
import 'package:cerne/features/capture/presentation/pages/insertion_modal_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Shared by Home/Chat's "+" button and "Meus Registros"'s empty-state CTA
/// (research.md R10) — `showModalBottomSheet` always pops back onto
/// whichever screen presented it, so calling this from either call site
/// already returns to that same screen with zero new routing.
Future<void> openInsertionModal(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => BlocProvider(
      create: (_) => getIt<InsertionModalBloc>(),
      child: const InsertionModalPage(),
    ),
  );
}
