import 'package:flutter/foundation.dart';

@immutable
sealed class AppFailure {
  final String message;
  final String? technicalDetails;
  final Object? cause;

  const AppFailure(this.message, {this.technicalDetails, this.cause});

  @override
  String toString() =>
      '$runtimeType: $message${technicalDetails != null ? ' ($technicalDetails)' : ''}';
}

final class AuthenticationFailure extends AppFailure {
  const AuthenticationFailure(
    super.message, {
    super.technicalDetails,
    super.cause,
  });
}

final class AuthorizationFailure extends AppFailure {
  const AuthorizationFailure(
    super.message, {
    super.technicalDetails,
    super.cause,
  });
}

final class NetworkFailure extends AppFailure {
  const NetworkFailure(super.message, {super.technicalDetails, super.cause});
}

final class DriveApiFailure extends AppFailure {
  final int? statusCode;

  const DriveApiFailure(
    super.message, {
    this.statusCode,
    super.technicalDetails,
    super.cause,
  });
}

final class DriveFileNotFoundFailure extends AppFailure {
  final String fileId;

  const DriveFileNotFoundFailure(
    this.fileId, {
    String message = 'Google Drive file not found',
    super.technicalDetails,
    super.cause,
  }) : super(message);
}

final class MetadataExtractionFailure extends AppFailure {
  final String? filePath;

  const MetadataExtractionFailure(
    super.message, {
    this.filePath,
    super.technicalDetails,
    super.cause,
  });
}

final class UnsupportedFormatFailure extends AppFailure {
  final String format;

  const UnsupportedFormatFailure(
    this.format, {
    String message = 'Audio format is not supported',
    super.technicalDetails,
    super.cause,
  }) : super(message);
}

final class PlaybackFailure extends AppFailure {
  const PlaybackFailure(super.message, {super.technicalDetails, super.cause});
}

final class CacheFailure extends AppFailure {
  const CacheFailure(super.message, {super.technicalDetails, super.cause});
}

final class DatabaseFailure extends AppFailure {
  const DatabaseFailure(super.message, {super.technicalDetails, super.cause});
}

final class ValidationFailure extends AppFailure {
  const ValidationFailure(super.message, {super.technicalDetails, super.cause});
}
