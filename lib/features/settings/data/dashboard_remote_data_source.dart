import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/settings/domain/entities/dashboard_aggregate.dart';
import 'package:cerne/features/settings/domain/entities/dashboard_narrative.dart';
import 'package:fpdart/fpdart.dart';

const _malformedAggregateFailure = ValidationFailure(
  message: 'Malformed dashboard aggregate response',
  requestId: '',
);

const _malformedNarrativeFailure = ValidationFailure(
  message: 'Malformed dashboard narrative response',
  requestId: '',
);

/// Calls `dashboard-aggregate-get` (`GET /dashboard/aggregate?period=all`)
/// and `dashboard-narrative-get` (`GET /dashboard/narrative?period=all`),
/// decoding each response per `docs/input/backend/api/openapi.yaml`'s
/// schema (contracts/dashboard-repository.md). Both internally fixed to
/// `period=all` (FR-002) — no parameter exposed.
class DashboardRemoteDataSource {
  const DashboardRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<Either<Failure, DashboardAggregate>> fetchAggregate() async {
    final result = await _apiClient.call(
      'dashboard-aggregate-get',
      method: 'GET',
      queryParameters: const {'period': 'all'},
    );
    return result.flatMap(_parseAggregate);
  }

  Future<Either<Failure, DashboardNarrative>> fetchNarrative() async {
    final result = await _apiClient.call(
      'dashboard-narrative-get',
      method: 'GET',
      queryParameters: const {'period': 'all'},
    );
    return result.flatMap(_parseNarrative);
  }

  Either<Failure, DashboardAggregate> _parseAggregate(Map<String, dynamic> data) {
    try {
      final buckets = (data['buckets'] as List<dynamic>)
          .map((b) => _parseBucket(b as Map<String, dynamic>))
          .toList();
      final totals = _parseTotals(data['totals'] as Map<String, dynamic>);
      return Right(DashboardAggregate(buckets: buckets, totals: totals));
    } on TypeError {
      return const Left(_malformedAggregateFailure);
    } on FormatException {
      return const Left(_malformedAggregateFailure);
    }
  }

  AggregateBucket _parseBucket(Map<String, dynamic> data) => AggregateBucket(
    date: DateTime.parse(data['date'] as String),
    count: data['count'] as int,
    sources: _parseSources(data['sources'] as Map<String, dynamic>),
  );

  DashboardTotals _parseTotals(Map<String, dynamic> data) => DashboardTotals(
    count: data['count'] as int,
    sources: _parseSources(data['sources'] as Map<String, dynamic>),
  );

  DashboardSourceCounts _parseSources(Map<String, dynamic> data) =>
      DashboardSourceCounts(
        manual: data['manual'] as int,
        audio: data['audio'] as int,
        photo: data['photo'] as int,
        chat: data['chat'] as int,
      );

  Either<Failure, DashboardNarrative> _parseNarrative(Map<String, dynamic> data) {
    try {
      return Right(
        DashboardNarrative(
          text: data['text'] as String,
          generatedAt: DateTime.parse(data['generatedAt'] as String),
        ),
      );
    } on TypeError {
      return const Left(_malformedNarrativeFailure);
    } on FormatException {
      return const Left(_malformedNarrativeFailure);
    }
  }
}
