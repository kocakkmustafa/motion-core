import 'dart:async';
import 'dart:typed_data';

abstract interface class ContentAssetReader {
  Future<Uint8List> read(String logicalPath);
}

abstract interface class ContentTimeoutRunner {
  Future<T> run<T>(Future<T> operation, Duration timeout);
}

final class FutureContentTimeoutRunner implements ContentTimeoutRunner {
  const FutureContentTimeoutRunner();

  @override
  Future<T> run<T>(Future<T> operation, Duration timeout) =>
      operation.timeout(timeout);
}

final class ContentLoadPolicy {
  const ContentLoadPolicy({
    this.readTimeout = const Duration(seconds: 5),
    this.timeoutRunner = const FutureContentTimeoutRunner(),
  });

  final Duration readTimeout;
  final ContentTimeoutRunner timeoutRunner;
}

Future<T> runBounded<T>(
  Future<T> Function() operation,
  ContentLoadPolicy policy,
) {
  return policy.timeoutRunner.run(
    Future<T>.sync(operation),
    policy.readTimeout,
  );
}
