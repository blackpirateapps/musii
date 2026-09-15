import 'package:flutter_test/flutter_test.dart';
import 'package:musii/core/error/failures.dart';
import 'package:musii/core/result/result.dart';

void main() {
  group('Result and Failures', () {
    test('Success returns data and folds correctly', () {
      const result = Result<int, AppFailure>.success(42);

      expect(result.isSuccess, isTrue);
      expect(result.isFailure, isFalse);
      expect(result.dataOrNull, equals(42));
      expect(result.failureOrNull, isNull);

      final val = result.fold(onSuccess: (d) => d * 2, onFailure: (_) => 0);
      expect(val, equals(84));
    });

    test('Failure returns failure object and folds correctly', () {
      const failure = DriveApiFailure('Quota exceeded', statusCode: 403);
      const result = Result<String, AppFailure>.failure(failure);

      expect(result.isSuccess, isFalse);
      expect(result.isFailure, isTrue);
      expect(result.dataOrNull, isNull);
      expect(result.failureOrNull, isA<DriveApiFailure>());

      final failureMsg = result.fold(
        onSuccess: (_) => '',
        onFailure: (f) => f.message,
      );
      expect(failureMsg, equals('Quota exceeded'));
    });

    test('DriveFileNotFoundFailure contains fileId and default message', () {
      const failure = DriveFileNotFoundFailure('file_123');
      expect(failure.fileId, equals('file_123'));
      expect(failure.message, equals('Google Drive file not found'));
    });
  });
}
