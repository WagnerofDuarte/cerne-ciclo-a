import 'package:cerne/core/di/service_locator.dart';
import 'package:cerne/core/routing/app_router.dart';
import 'package:cerne/core/theme.dart';
import 'package:cerne/features/session/domain/entities/session_status.dart';
import 'package:cerne/features/session/presentation/bloc/session_bloc.dart';
import 'package:cerne/features/session/presentation/widgets/session_expired_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  setupServiceLocator();

  runApp(const CerneApp());
}

class CerneApp extends StatelessWidget {
  const CerneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<SessionBloc>(
      create: (_) => getIt<SessionBloc>(),
      child: MaterialApp.router(
        title: 'Cerne',
        theme: AppTheme.theme,
        routerConfig: appRouter,
        builder: (context, child) {
          return BlocListener<SessionBloc, SessionStatus>(
            listenWhen: (previous, current) =>
                current is SessionStatusExpiredRenewable,
            listener: (context, status) =>
                showSessionExpiredOverlay(rootNavigatorKey),
            child: child,
          );
        },
      ),
    );
  }
}
