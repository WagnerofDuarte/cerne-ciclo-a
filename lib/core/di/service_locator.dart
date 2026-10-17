import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/core/network/connectivity_checker.dart';
import 'package:cerne/core/storage/secure_token_storage.dart';
import 'package:cerne/features/auth/data/auth_remote_data_source.dart';
import 'package:cerne/features/auth/data/auth_repository_impl.dart';
import 'package:cerne/features/auth/domain/repositories/auth_repository.dart';
import 'package:cerne/features/auth/domain/usecases/login_usecase.dart';
import 'package:cerne/features/auth/domain/usecases/sign_up_usecase.dart';
import 'package:cerne/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:cerne/features/capture/data/audio_capture_repository_impl.dart';
import 'package:cerne/features/capture/data/audio_recorder_data_source.dart';
import 'package:cerne/features/capture/data/audio_transcription_repository_impl.dart';
import 'package:cerne/features/capture/data/image_picker_data_source.dart';
import 'package:cerne/features/capture/data/media_ocr_remote_data_source.dart';
import 'package:cerne/features/capture/data/photo_capture_repository_impl.dart';
import 'package:cerne/features/capture/data/photo_recognition_repository_impl.dart';
import 'package:cerne/features/capture/data/whisper_transcription_data_source.dart';
import 'package:cerne/features/capture/domain/repositories/audio_capture_repository.dart';
import 'package:cerne/features/capture/domain/repositories/audio_transcription_repository.dart';
import 'package:cerne/features/capture/domain/repositories/photo_capture_repository.dart';
import 'package:cerne/features/capture/domain/repositories/photo_recognition_repository.dart';
import 'package:cerne/features/capture/domain/usecases/confirm_entry_save_usecase.dart';
import 'package:cerne/features/capture/domain/usecases/recognize_photo_usecase.dart';
import 'package:cerne/features/capture/domain/usecases/save_text_entry_usecase.dart';
import 'package:cerne/features/capture/presentation/bloc/insertion_modal_bloc.dart';
import 'package:cerne/features/entries/data/entries_remote_data_source.dart';
import 'package:cerne/features/entries/data/entries_repository_impl.dart';
import 'package:cerne/features/entries/domain/repositories/entries_repository.dart';
import 'package:cerne/features/entries/domain/usecases/create_entry_usecase.dart';
import 'package:cerne/features/session/data/session_remote_data_source.dart';
import 'package:cerne/features/session/data/session_repository_impl.dart';
import 'package:cerne/features/session/domain/repositories/session_repository.dart';
import 'package:cerne/features/session/domain/usecases/check_session_usecase.dart';
import 'package:cerne/features/session/presentation/bloc/session_bloc.dart';
import 'package:cerne/features/vault/data/account/biometrics_preference_remote_data_source.dart';
import 'package:cerne/features/vault/data/account/biometrics_preference_repository_impl.dart';
import 'package:cerne/features/vault/data/local_auth_biometric_data_source.dart';
import 'package:cerne/features/vault/data/vault_repository_impl.dart';
import 'package:cerne/features/vault/data/vault_secure_storage.dart';
import 'package:cerne/features/vault/domain/repositories/biometrics_preference_repository.dart';
import 'package:cerne/features/vault/domain/repositories/vault_repository.dart';
import 'package:cerne/features/vault/domain/usecases/determine_vault_entry_usecase.dart';
import 'package:cerne/features/vault/domain/usecases/save_biometrics_preference_usecase.dart';
import 'package:cerne/features/vault/domain/usecases/save_pin_usecase.dart';
import 'package:cerne/features/vault/domain/usecases/verify_pin_usecase.dart';
import 'package:cerne/features/vault/presentation/bloc/vault_bloc.dart';
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

  // Vault (P-RF03)
  getIt.registerLazySingleton<VaultSecureStorage>(VaultSecureStorage.new);
  getIt.registerLazySingleton<LocalAuthBiometricDataSource>(
    LocalAuthBiometricDataSource.new,
  );
  getIt.registerLazySingleton<VaultRepository>(
    () => VaultRepositoryImpl(
      secureStorage: getIt<VaultSecureStorage>(),
      biometricDataSource: getIt<LocalAuthBiometricDataSource>(),
    ),
  );
  getIt.registerLazySingleton<BiometricsPreferenceRemoteDataSource>(
    () => BiometricsPreferenceRemoteDataSource(getIt<ApiClient>()),
  );
  getIt.registerLazySingleton<BiometricsPreferenceRepository>(
    () => BiometricsPreferenceRepositoryImpl(
      getIt<BiometricsPreferenceRemoteDataSource>(),
    ),
  );
  getIt.registerLazySingleton<DetermineVaultEntryUseCase>(
    () => DetermineVaultEntryUseCase(getIt<VaultRepository>()),
  );
  getIt.registerLazySingleton<VerifyPinUseCase>(
    () => VerifyPinUseCase(getIt<VaultRepository>()),
  );
  getIt.registerLazySingleton<SavePinUseCase>(
    () => SavePinUseCase(getIt<VaultRepository>()),
  );
  getIt.registerLazySingleton<SaveBiometricsPreferenceUseCase>(
    () => SaveBiometricsPreferenceUseCase(
      vaultRepository: getIt<VaultRepository>(),
      biometricsPreferenceRepository: getIt<BiometricsPreferenceRepository>(),
    ),
  );
  getIt.registerFactory<VaultBloc>(
    () => VaultBloc(
      determineVaultEntryUseCase: getIt<DetermineVaultEntryUseCase>(),
      verifyPinUseCase: getIt<VerifyPinUseCase>(),
      savePinUseCase: getIt<SavePinUseCase>(),
      saveBiometricsPreferenceUseCase: getIt<SaveBiometricsPreferenceUseCase>(),
      repository: getIt<VaultRepository>(),
    ),
  );

  // Entries (P-RF01, research.md R8 — the shared entry-creation seam)
  getIt.registerLazySingleton<ConnectivityChecker>(ConnectivityChecker.new);
  getIt.registerLazySingleton<EntriesRemoteDataSource>(
    () => EntriesRemoteDataSource(getIt<ApiClient>()),
  );
  getIt.registerLazySingleton<EntriesRepository>(
    () => EntriesRepositoryImpl(getIt<EntriesRemoteDataSource>()),
  );
  getIt.registerLazySingleton<CreateEntryUseCase>(
    () => CreateEntryUseCase(getIt<EntriesRepository>()),
  );

  // Capture (P-RF01)
  getIt.registerLazySingleton<AudioRecorderDataSource>(
    AudioRecorderDataSource.new,
  );
  getIt.registerLazySingleton<AudioCaptureRepository>(
    () => AudioCaptureRepositoryImpl(getIt<AudioRecorderDataSource>()),
  );
  getIt.registerLazySingleton<WhisperTranscriptionDataSource>(
    WhisperTranscriptionDataSource.new,
  );
  getIt.registerLazySingleton<AudioTranscriptionRepository>(
    () => AudioTranscriptionRepositoryImpl(getIt<WhisperTranscriptionDataSource>()),
  );
  getIt.registerLazySingleton<ImagePickerDataSource>(ImagePickerDataSource.new);
  getIt.registerLazySingleton<PhotoCaptureRepository>(
    () => PhotoCaptureRepositoryImpl(getIt<ImagePickerDataSource>()),
  );
  getIt.registerLazySingleton<MediaOcrRemoteDataSource>(
    () => MediaOcrRemoteDataSource(getIt<ApiClient>()),
  );
  getIt.registerLazySingleton<PhotoRecognitionRepository>(
    () => PhotoRecognitionRepositoryImpl(getIt<MediaOcrRemoteDataSource>()),
  );
  getIt.registerLazySingleton<SaveTextEntryUseCase>(
    () => SaveTextEntryUseCase(
      createEntryUseCase: getIt<CreateEntryUseCase>(),
      connectivityChecker: getIt<ConnectivityChecker>(),
    ),
  );
  getIt.registerLazySingleton<ConfirmEntrySaveUseCase>(
    () => ConfirmEntrySaveUseCase(
      createEntryUseCase: getIt<CreateEntryUseCase>(),
      connectivityChecker: getIt<ConnectivityChecker>(),
    ),
  );
  getIt.registerLazySingleton<RecognizePhotoUseCase>(
    () => RecognizePhotoUseCase(
      recognitionRepository: getIt<PhotoRecognitionRepository>(),
      connectivityChecker: getIt<ConnectivityChecker>(),
    ),
  );
  getIt.registerFactory<InsertionModalBloc>(
    () => InsertionModalBloc(
      saveTextEntryUseCase: getIt<SaveTextEntryUseCase>(),
      audioCaptureRepository: getIt<AudioCaptureRepository>(),
      audioTranscriptionRepository: getIt<AudioTranscriptionRepository>(),
      confirmEntrySaveUseCase: getIt<ConfirmEntrySaveUseCase>(),
      photoCaptureRepository: getIt<PhotoCaptureRepository>(),
      recognizePhotoUseCase: getIt<RecognizePhotoUseCase>(),
    ),
  );
}
