import '../domain/game_engine.dart';

/// Explicit, non-crashing persistence outcomes. A newer schema is not silently
/// treated as a valid older save.
enum LoadStatus {
  empty,
  loaded,
  recovered,
  corrupt,
  unsupportedVersion,
  unavailable,
}

class LoadResult {
  const LoadResult(this.status, [this.state]);

  final LoadStatus status;
  final GameState? state;
}

/// Persistence seam; engine and widgets do not know OS filesystem paths.
abstract class GameRepository {
  Future<LoadResult> load();
  Future<void> save(GameState snapshot);
  Future<void> clear();
}
