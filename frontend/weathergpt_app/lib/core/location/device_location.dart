import 'package:geolocator/geolocator.dart';

/// Why a device-location request did not produce a fix.
///
/// Modelled as an outcome rather than an exception because none of these
/// are errors — a user declining location is a normal choice, and Home
/// must fall back to its default city rather than showing an error page.
enum LocationFailure {
  /// The user denied the permission this time. Asking again is allowed.
  permissionDenied,

  /// Denied permanently ("Don't ask again"). Only the OS settings screen
  /// can change this, so the UI must send the user there rather than
  /// re-prompting, which silently no-ops.
  permissionDeniedForever,

  /// Location services are switched off device-wide.
  serviceDisabled,

  /// Permission granted but no fix arrived (indoors, cold start, airplane
  /// mode). Retrying later may work.
  unavailable,
}

/// A resolved device position, or the reason there isn't one.
sealed class LocationResult {
  const LocationResult();
}

class LocationFixed extends LocationResult {
  final double latitude;
  final double longitude;

  const LocationFixed(this.latitude, this.longitude);
}

class LocationUnavailable extends LocationResult {
  final LocationFailure reason;

  const LocationUnavailable(this.reason);
}

/// Wraps `geolocator` so the rest of the app never imports it directly,
/// and so tests can substitute a fake without a plugin.
abstract class DeviceLocation {
  Future<LocationResult> current();
}

class GeolocatorDeviceLocation implements DeviceLocation {
  const GeolocatorDeviceLocation();

  /// Give up rather than hang: a GPS cold start indoors can otherwise
  /// leave Home spinning indefinitely, and a stale-but-present default
  /// city beats a screen that never resolves.
  static const _timeout = Duration(seconds: 10);

  @override
  Future<LocationResult> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationUnavailable(LocationFailure.serviceDisabled);
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      return const LocationUnavailable(LocationFailure.permissionDeniedForever);
    }
    if (permission == LocationPermission.denied) {
      return const LocationUnavailable(LocationFailure.permissionDenied);
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          // City-level weather does not need best-available precision,
          // and a lower accuracy setting gets a fix far faster.
          accuracy: LocationAccuracy.medium,
          timeLimit: _timeout,
        ),
      );
      return LocationFixed(position.latitude, position.longitude);
    } catch (_) {
      // Timeouts and platform errors are the same outcome for the UI:
      // no fix right now, try again later.
      return const LocationUnavailable(LocationFailure.unavailable);
    }
  }
}
