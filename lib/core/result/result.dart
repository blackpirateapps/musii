import 'package:flutter/foundation.dart';

@immutable
sealed class Result<S, F> {
  const Result();

  const factory Result.success(S data) = Success<S, F>;
  const factory Result.failure(F failure) = Failure<S, F>;

  bool get isSuccess => this is Success<S, F>;
  bool get isFailure => this is Failure<S, F>;

  S? get dataOrNull => switch (this) {
    Success(data: final d) => d,
    Failure() => null,
  };

  F? get failureOrNull => switch (this) {
    Success() => null,
    Failure(failure: final f) => f,
  };

  R fold<R>({
    required R Function(S data) onSuccess,
    required R Function(F failure) onFailure,
  }) {
    return switch (this) {
      Success(data: final d) => onSuccess(d),
      Failure(failure: final f) => onFailure(f),
    };
  }

  Result<R, F> map<R>(R Function(S data) transform) {
    return switch (this) {
      Success(data: final d) => Result.success(transform(d)),
      Failure(failure: final f) => Result.failure(f),
    };
  }

  Result<S, R> mapFailure<R>(R Function(F failure) transform) {
    return switch (this) {
      Success(data: final d) => Result.success(d),
      Failure(failure: final f) => Result.failure(transform(f)),
    };
  }
}

class Success<S, F> extends Result<S, F> {
  final S data;
  const Success(this.data);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Success<S, F> && other.data == data);

  @override
  int get hashCode => data.hashCode;

  @override
  String toString() => 'Result.success($data)';
}

class Failure<S, F> extends Result<S, F> {
  final F failure;
  const Failure(this.failure);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Failure<S, F> && other.failure == failure);

  @override
  int get hashCode => failure.hashCode;

  @override
  String toString() => 'Result.failure($failure)';
}
