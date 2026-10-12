/// Named route path constants — the single source of truth for every
/// `go_router` path and every `context.push`/`context.go` call site.
class AppRoutes {
  const AppRoutes._();

  static const String splash = '/';
  static const String login = '/login';
  static const String home = '/home';
  static const String records = '/records';
  static const String settings = '/settings';
  static const String vault = '/vault';
}
