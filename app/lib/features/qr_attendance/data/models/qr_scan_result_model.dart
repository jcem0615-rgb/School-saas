import '../../domain/entities/attendance_record.dart';
import '../../domain/entities/qr_scan_result.dart';

class QrScanResultModel extends QrScanResult {
  const QrScanResultModel({
    required super.personId,
    required super.personName,
    required super.personRole,
    required super.action,
    required super.status,
    required super.timestamp,
  });

  /// Built from the raw map returned by the markAttendance callable
  /// (`HttpsCallableResult.data`).
  factory QrScanResultModel.fromCallableData(Map<String, dynamic> data) {
    return QrScanResultModel(
      personId: data['personId'] as String,
      personName: data['personName'] as String,
      personRole: data['personRole'] as String,
      action: ScanAction.fromString(data['action'] as String),
      status: AttendanceStatus.fromString(data['status'] as String),
      timestamp: DateTime.parse(data['timestamp'] as String),
    );
  }
}
