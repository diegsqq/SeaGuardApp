import 'dart:async';

const Duration appLoadingDelay = Duration(seconds: 3);

Future<T> withMinimumLoadingTime<T>(
  Future<T> future, {
  Duration duration = appLoadingDelay,
}) async {
  final timer = Stopwatch()..start();

  try {
    return await future;
  } finally {
    timer.stop();
    final remaining = duration - timer.elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
  }
}

