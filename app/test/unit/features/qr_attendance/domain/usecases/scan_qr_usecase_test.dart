import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:logicclass/core/errors/failures.dart';
import 'package:logicclass/core/errors/result.dart';
import 'package:logicclass/features/qr_attendance/domain/entities/attendance_record.dart';
import 'package:logicclass/features/qr_attendance/domain/entities/qr_scan_result.dart';
import 'package:logicclass/features/qr_attendance/domain/repositories/qr_attendance_repository.dart';
import 'package:logicclass/features/qr_attendance/domain/usecases/scan_qr_usecase.dart';

class MockQrAttendanceRepository extends Mock implements QrAttendanceRepository {}

void main() {
  late MockQrAttendanceRepository repository;

  setUp(() {
    repository = MockQrAttendanceRepository();
  });

  group('ScanQrUseCase', () {
    test('rejects an empty token without calling the repository', () async {
      final useCase = ScanQrUseCase(repository);
      final result = await useCase(qrToken: '   ');

      expect((result as Error).failure, isA<ValidationFailure>());
      verifyNever(() => repository.scanQrCode(
            qrToken: any(named: 'qrToken'),
            location: any(named: 'location'),
          ));
    });

    test('trims the token and delegates to the repository', () async {
      final scanResult = QrScanResult(
        personId: 'student_1',
        personName: 'Juan Dela Cruz',
        personRole: 'student',
        action: ScanAction.timeIn,
        status: AttendanceStatus.present,
        timestamp: DateTime(2026, 7, 21, 7, 15),
      );
      when(() => repository.scanQrCode(qrToken: 'abc123', location: null))
          .thenAnswer((_) async => Success(scanResult));

      final useCase = ScanQrUseCase(repository);
      final result = await useCase(qrToken: '  abc123  ');

      expect(result, isA<Success<QrScanResult>>());
      verify(() => repository.scanQrCode(qrToken: 'abc123', location: null)).called(1);
    });
  });
}
