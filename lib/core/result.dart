sealed class AppResult<T> {
  const AppResult();

  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;

  R when<R>({
    required R Function(T value) ok,
    required R Function(Object error, StackTrace stackTrace) err,
  }) {
    final self = this;
    if (self is Ok<T>) {
      return ok(self.value);
    }
    final failure = self as Err<T>;
    return err(failure.error, failure.stackTrace);
  }
}

final class Ok<T> extends AppResult<T> {
  const Ok(this.value);

  final T value;
}

final class Err<T> extends AppResult<T> {
  const Err(this.error, [StackTrace? stackTrace])
    : stackTrace = stackTrace ?? StackTrace.empty;

  final Object error;
  final StackTrace stackTrace;
}
