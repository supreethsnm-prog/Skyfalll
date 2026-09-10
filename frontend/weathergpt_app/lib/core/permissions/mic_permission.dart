import 'package:record/record.dart';

/// Whether the microphone is available to record from.
///
/// Modelled as an outcome rather than an exception, mirroring
/// `device_location.dart`'s `LocationResult` — a user declining the
/// microphone is a normal choice, not an error, and the composer must
/// fall back to a working text input rather than a broken mic button.
///
/// Unlike `LocationFailure`, this has no `permissionDeniedForever` case:
/// the underlying `record` package's `hasPermission()` reports only
/// granted/denied, with no way to distinguish "denied, can ask again"
/// from "denied permanently" the way `geolocator` can. The single
/// `denied` outcome below points to system settings regardless — a
/// correct instruction either way, just not the most specific one always
/// available for location.
enum MicPermissionResult { granted, denied }

/// Wraps the `record` package's permission check so the rest of the app
/// never imports it directly, and so tests can substitute a fake without
/// a plugin — mirrors `DeviceLocation`'s role for `geolocator`.
abstract class MicPermission {
  Future<MicPermissionResult> request();
}

class RecordMicPermission implements MicPermission {
  const RecordMicPermission();

  @override
  Future<MicPermissionResult> request() async {
    final recorder = AudioRecorder();
    try {
      final granted = await recorder.hasPermission();
      return granted ? MicPermissionResult.granted : MicPermissionResult.denied;
    } finally {
      await recorder.dispose();
    }
  }
}
