import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/core/storage/secure_token_storage.dart';
import 'package:cerne/features/auth/data/auth_remote_data_source.dart';
import 'package:cerne/features/auth/data/auth_repository_impl.dart';
import 'package:cerne/features/auth/domain/repositories/auth_repository.dart';
import 'package:cerne/features/auth/domain/usecases/login_usecase.dart';
import 'package:cerne/features/auth/domain/usecases/sign_up_usecase.dart';
import 'package:cerne/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:cerne/features/session/data/session_remote_data_source.dart';
import 'package:cerne/features/session/data/session_repository_impl.dart';
import 'package:cerne/features/session/domain/repositories/session_repository.dart';
import 'package:cerne/features/session/domain/usecases/check_session_usecase.dart';
import 'package:cerne/features/session/presentation/bloc/session_bloc.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get_it/get_it.dart';

final GetIt getIt = GetIt.instance;

/// Manual `get_it` registration, no code generation (research.md R4).
void setupServiceLocator() {
  getIt.registerLazySingleton<Dio>(() {
    final dio = Dio();
    if (kDebugMode) {
      // ApiClient maps every DioException to a Failure and never rethrows,
      // so without this nothing about a failed call reaches the terminal.
      dio.interceptors.add(
        LogInterceptor(requestBody: true, responseBody: true, error: true),
      );
    }
    return dio;
  });

  getIt.registerLazySingleton<SecureTokenStorage>(SecureTokenStorage.new);

  getIt.registerLazySingleton<ApiClient>(
    () => ApiClient(
      dio: getIt<Dio>(),
      tokenStorage: getIt<SecureTokenStorage>(),
      anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
    ),
  );

  // Auth
  getIt.registerLazySingleton<AuthRemoteDataSource>(
    () => AuthRemoteDataSource(getIt<ApiClient>()),
  );
  getIt.registerLazySingleton<AuthRepository>(
    () => AuthRepositoryImpl(
      remoteDataSource: getIt<AuthRemoteDataSource>(),
      tokenStorage: getIt<SecureTokenStorage>(),
    ),
  );
  getIt.registerLazySingleton<LoginUseCase>(
    () => LoginUseCase(getIt<AuthRepository>()),
  );
  getIt.registerLazySingleton<SignUpUseCase>(
    () => SignUpUseCase(getIt<AuthRepository>()),
  );
  getIt.registerFactory<AuthBloc>(
    () => AuthBloc(
      loginUseCase: getIt<LoginUseCase>(),
      signUpUseCase: getIt<SignUpUseCase>(),
    ),
  );

  // Session
  getIt.registerLazySingleton<SessionRemoteDataSource>(
    () => SessionRemoteDataSource(getIt<ApiClient>()),
  );
  getIt.registerLazySingleton<SessionRepository>(
    () => SessionRepositoryImpl(
      remoteDataSource: getIt<SessionRemoteDataSource>(),
      tokenStorage: getIt<SecureTokenStorage>(),
    ),
  );
  getIt.registerLazySingleton<CheckSessionUseCase>(
    () => CheckSessionUseCase(getIt<SessionRepository>()),
  );
  getIt.registerFactory<SessionBloc>(
    () => SessionBloc(
      checkSessionUseCase: getIt<CheckSessionUseCase>(),
      sessionRepository: getIt<SessionRepository>(),
    ),
  );
}
