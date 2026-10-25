import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/settings/domain/entities/dashboard_aggregate.dart';
import 'package:cerne/features/settings/domain/entities/dashboard_narrative.dart';
import 'package:fpdart/fpdart.dart';

/// `GET /dashboard/aggregate`/`GET /dashboard/narrative`, both internally
/// fixed to `period=all` (no parameter exposed, FR-002). Both retry exactly
/// once via `SessionRepository.refresh()` on `AuthExpiredFailure`
/// (contracts/dashboard-repository.md).
abstract class DashboardRepository {
  Future<Either<Failure, DashboardAggregate>> fetchAggregate();
  Future<Either<Failure, DashboardNarrative>> fetchNarrative();
}
