import '../exceptions/app_exception.dart';

/// Result wrapper every repository method returns, so controllers never
/// need try/catch around a repository call — just pattern-match on `when`.
sealed class ApiResult<T> {
  const ApiResult();

  const factory ApiResult.success(T data) = ApiSuccess<T>;
  const factory ApiResult.failure(AppFailure failure) = ApiFailure<T>;

  R when<R>({
    required R Function(T data) success,
    required R Function(AppFailure failure) failure,
  }) {
    final self = this;
    if (self is ApiSuccess<T>) return success(self.data);
    if (self is ApiFailure<T>) return failure(self.failure);
    throw StateError('Unreachable');
  }

  bool get isSuccess => this is ApiSuccess<T>;
}

class ApiSuccess<T> extends ApiResult<T> {
  final T data;
  const ApiSuccess(this.data);
}

class ApiFailure<T> extends ApiResult<T> {
  final AppFailure failure;
  const ApiFailure(this.failure);
}
