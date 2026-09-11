import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';
import 'package:weathergpt_app/core/audio/audio_playback_device.dart';
import 'package:weathergpt_app/core/audio/voice_recorder.dart';
import 'package:weathergpt_app/core/clipboard/clipboard_service.dart';
import 'package:weathergpt_app/core/location/device_location.dart';
import 'package:weathergpt_app/core/network/app_error.dart';
import 'package:weathergpt_app/core/permissions/mic_permission.dart';
import 'package:weathergpt_app/core/voice_language_prefs.dart';
import 'package:weathergpt_app/data/advisory_api.dart';
import 'package:weathergpt_app/data/air_quality_api.dart';
import 'package:weathergpt_app/data/geocoding_api.dart';
import 'package:weathergpt_app/data/alerts_api.dart';
import 'package:weathergpt_app/data/alerts_socket.dart';
import 'package:weathergpt_app/data/historical_api.dart';
import 'package:weathergpt_app/data/marine_api.dart';
import 'package:weathergpt_app/data/metar_api.dart';
import 'package:weathergpt_app/data/nwp_api.dart';
import 'package:weathergpt_app/data/voice_api.dart';
import 'package:weathergpt_app/data/weather_api.dart';
import 'package:weathergpt_app/features/aviation/aviation_controller.dart';
import 'package:weathergpt_app/features/advisory/advisory_controller.dart';
import 'package:weathergpt_app/features/historical/historical_controller.dart';
import 'package:weathergpt_app/features/marine/marine_controller.dart';
import 'package:weathergpt_app/features/chat/conversation_store.dart';
import 'package:weathergpt_app/features/home/home_controller.dart';
import 'package:weathergpt_app/features/saved/saved_places_controller.dart';

/// Offline stand-ins for the network layer.
///
/// `HomeScreen` calls `loadInitial()` on its first frame, so any test that
/// pumps the real app — router tests, boot tests — makes a live HTTP call
/// unless these are overridden. flutter_test blocks real sockets, so the
/// failure is a confusing HttpClient error rather than an obvious one.
/// Anything that mounts `HomeScreen` should use [fakeApiOverrides].

class FakeWeatherApi implements WeatherApi {
  @override
  Future<CurrentWeather> fetchCurrent(double lat, double lon) async {
    return const CurrentWeather(
      temperatureC: 24.4,
      humidityPct: 78,
      weatherCode: 1,
      windSpeedKmh: 18.2,
      windDirectionDeg: 247,
      observedAt: '2026-09-09T14:00',
      timezone: 'Asia/Kolkata',
    );
  }

  @override
  Future<List<ForecastDay>> fetchForecast(double lat, double lon,
      {int days = 5}) async {
    return const [
      ForecastDay(
        forecastDate: '2026-09-09',
        weatherCode: 1,
        tempMaxC: 31.2,
        tempMinC: 24.1,
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class FakeAirQualityApi implements AirQualityApi {
  @override
  Future<AirQuality> fetchCurrent(double lat, double lon) async {
    return const AirQuality(
      observedAt: '2026-09-09T14:00',
      usAqi: 156,
      pm25: 64.8,
      pm10: 118.2,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// Stands in for `NwpApi`. Returns the single sample point from the
/// verified backend contract (`.superpowers/sdd/nwp-brief.md`) — a
/// realistic, common shape, not a placeholder — since `HomeController`
/// now fetches NWP alongside weather/forecast/alerts on every load.
/// Without this override, an unmocked `nwpApiProvider` builds a real Dio
/// against AppEnv's unreachable default host, and Home's exemption for a
/// failed NWP call (see `HomeController._load`) means the load succeeds
/// anyway — but only after sitting on a doomed socket for the full
/// connect timeout.
class FakeNwpApi implements NwpApi {
  @override
  Future<List<NwpPoint>> fetchForecast(double lat, double lon) async {
    return const [
      NwpPoint(
        runDate: '20260909',
        runHour: '18',
        forecastHour: 0,
        validTime: '2026-09-09T18:00:00Z',
        temp2mC: 32.09,
        relativeHumidity2mPct: 40.9,
        windSpeed10mKmh: 5.8,
        windDirection10mDeg: 233.67,
        windGustKmh: 9.42,
        precipRateMmh: 0.0,
        capeJPerKg: 0.0,
        cinJPerKg: -0.29,
        cloudCoverPct: 0.0,
        mslpHpa: 1005.99,
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class FakeAlertsApi implements AlertsApi {
  @override
  Future<List<AlertSummary>> fetchAlerts() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// Stands in for `AdvisoryApi`, so any test that mounts `AdvisoryScreen`
/// (or a route tree that could reach it) does not make a live HTTP call.
/// Both responses default to "everything normal, nothing to report" —
/// LOW risk and no advisory text — which is itself a realistic, common
/// outcome for this endpoint, not a placeholder to gloss over.
class FakeAdvisoryApi implements AdvisoryApi {
  @override
  Future<AgricultureAdvisory> fetchAgriculture(
    double lat,
    double lon, {
    String? crop,
    int days = 5,
  }) async {
    return AgricultureAdvisory(
      latitude: lat,
      longitude: lon,
      crop: crop,
      generatedAt: '2026-09-09T14:00',
      advisories: const [],
      activeAlerts: const [],
      forecastBasis: const [],
    );
  }

  @override
  Future<UrbanAdvisory> fetchUrban(double lat, double lon, {int days = 5}) async {
    return UrbanAdvisory(
      latitude: lat,
      longitude: lon,
      generatedAt: '2026-09-09T14:00',
      riskSummary: const UrbanRiskSummary(
        waterloggingRisk: 'LOW',
        heatRisk: 'LOW',
        windRisk: 'LOW',
      ),
      advisories: const [],
      activeAlerts: const [],
      forecastBasis: const [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// Stands in for `MetarApi`, so any test that mounts `AviationScreen` (or a
/// route tree that could reach it) does not make a live HTTP call. Returns
/// a realistic, fixed reading for whatever ICAO is asked for — VIDP Delhi
/// MVFR, the exact shape verified live in `.superpowers/sdd/aviation-brief.md`
/// — rather than a placeholder.
class FakeMetarApi implements MetarApi {
  FakeMetarApi([this.reading]) : _fixed = reading != null;

  /// When set, always returned regardless of the requested ICAO. When
  /// null, a default VIDP-shaped reading is synthesised for the requested
  /// code so a test can distinguish which airport was actually asked for.
  MetarReading? reading;
  final bool _fixed;

  @override
  Future<MetarReading?> fetch(String icao) async {
    if (_fixed) return reading;
    return MetarReading(
      icaoId: icao,
      rawMetar: 'METAR $icao 100230Z 26009KT 4000 HZ NSC 29/22 Q1009 NOSIG',
      observedAt: '2026-09-10T02:30:00.000Z',
      stationName: 'Test Station, $icao',
      temperatureC: 29.0,
      dewpointC: 22.0,
      windDirDeg: 260.0,
      windSpeedKt: 9.0,
      visibilitySm: 2.49,
      flightCategory: 'MVFR',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// Stands in for `MarineApi`, so any test that mounts `MarineScreen` (or a
/// route tree that could reach it) does not make a live HTTP call. Defaults
/// to a single zone shaped like the verified live contract
/// (`.superpowers/sdd/marine-brief.md`) — a real coordinate pair from the
/// live PFZ data, not a placeholder.
class FakeMarineApi implements MarineApi {
  FakeMarineApi([
    this.zones = const [
      PfzZone(
        id: 1,
        externalId: 'pfzlines.1',
        category: 'ghrsst',
        sectorBoundary: 3,
        julianDay: '252',
        year: 2026,
        lengthKm: 58.3588654526,
        lines: [
          [LatLng(20.1663, 72.4817), LatLng(20.1653, 72.4819)],
        ],
      ),
    ],
  ]);

  List<PfzZone> zones;

  @override
  Future<List<PfzZone>> fetchPfzZones() async => zones;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// Stands in for `HistoricalApi`, so any test that mounts `HistoricalScreen`
/// (or a route tree that could reach it) does not make a live HTTP call.
/// Defaults to a fixed New Delhi archive reading with no year-over-year
/// comparison — a real, common shape, not a placeholder — so tests that
/// don't care about Historical specifically get a harmless loaded state
/// rather than a screen left spinning.
class FakeHistoricalApi implements HistoricalApi {
  FakeHistoricalApi({
    this.archives = const {},
    this.defaultArchive = const HistoricalArchive(
      latitude: 28.61,
      longitude: 77.21,
      locationName: 'New Delhi, India',
      reading: ArchiveReading(
        date: '2024-07-15',
        tempMaxC: 31.2,
        tempMinC: 24.1,
        tempMeanC: 27.4,
        precipSumMm: 12.0,
        windSpeedMaxKmh: 18.2,
        windDirectionDominantDeg: 247,
      ),
    ),
    this.failFetch = false,
  });

  /// "lat,lon,date" -> archive result, keyed exactly. A missing key falls
  /// back to [defaultArchive] — set that to null to make every request 404
  /// (mirroring the backend's "no data for this exact date" outcome)
  /// regardless of the date `HistoricalController` happens to pick.
  final Map<String, HistoricalArchive?> archives;
  final HistoricalArchive? defaultArchive;
  final bool failFetch;

  @override
  Future<HistoricalArchive?> fetchArchive({
    required double latitude,
    required double longitude,
    required String date,
    String? name,
  }) async {
    if (failFetch) throw const NetworkConnectionError();
    final key = '$latitude,$longitude,$date';
    if (archives.containsKey(key)) return archives[key];
    return defaultArchive;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// Device location that reports no fix, so tests exercise the default-city
/// path without touching the geolocator plugin — which is not available in
/// a widget test and throws MissingPluginException if reached.
class FakeDeviceLocation implements DeviceLocation {
  const FakeDeviceLocation([this.result = const LocationFixed(28.6139, 77.2090)]);

  final LocationResult result;

  @override
  Future<LocationResult> current() async => result;
}

/// Names any coordinate as the default city, so Home's hero renders a
/// stable place name without a network call.
class FakeGeocodingApi implements GeocodingApi {
  const FakeGeocodingApi();

  @override
  Future<GeocodeResult?> reverse(double lat, double lon) async =>
      const GeocodeResult(
        displayName: 'New Delhi, India',
        latitude: 28.6139,
        longitude: 77.2090,
        country: 'India',
        state: 'Delhi',
      );

  @override
  Future<GeocodeResult?> search(String query) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// A socket that never emits, so tests do not open a real connection.
/// `HomeScreen` subscribes on its first frame, and without this every
/// widget test would try to reach ws://127.0.0.1:8000.
class FakeAlertsSocket implements AlertsSocket {
  final controller = StreamController<List<AlertSummary>>.broadcast();

  @override
  Stream<List<AlertSummary>> get newAlerts => controller.stream;

  @override
  void dispose() => controller.close();
}


/// In-memory saved places, so tests do not need the shared_preferences
/// plugin — which has no implementation in a widget test and throws
/// MissingPluginException the moment Home's chrome reads the provider.
class FakeSavedPlacesStore implements SavedPlacesStore {
  FakeSavedPlacesStore([this.places = const []]);

  List<GeocodeResult> places;

  @override
  Future<List<GeocodeResult>> load() async => places;

  @override
  Future<void> save(List<GeocodeResult> next) async => places = next;
}

/// In-memory chat history, so the drawer's Recents list does not reach
/// for shared_preferences in a widget test.
class FakeConversationStore implements ConversationStore {
  FakeConversationStore([this.conversations = const []]);

  List<Conversation> conversations;

  @override
  Future<List<Conversation>> load() async => conversations;

  @override
  Future<void> save(List<Conversation> next) async => conversations = next;
}

/// In-memory voice-language preference, so `voiceLanguageProvider`'s
/// `build()` does not reach for shared_preferences in a widget test.
class FakeVoiceLanguagePrefs implements VoiceLanguagePrefs {
  FakeVoiceLanguagePrefs([this.languageCode = defaultVoiceLanguageCode]);

  String languageCode;

  @override
  Future<String> load() async => languageCode;

  @override
  Future<void> save(String code) async => languageCode = code;
}

/// In-memory language-settings prefs (auto-detect + read-aloud mode).
class FakeLanguageSettingsPrefs implements LanguageSettingsPrefs {
  FakeLanguageSettingsPrefs({
    this.autoDetect = true,
    this.readAloudMode = ReadAloudMode.message,
  });

  bool autoDetect;
  ReadAloudMode readAloudMode;

  @override
  Future<bool> loadAutoDetect() async => autoDetect;

  @override
  Future<void> saveAutoDetect(bool value) async => autoDetect = value;

  @override
  Future<ReadAloudMode> loadReadAloudMode() async => readAloudMode;

  @override
  Future<void> saveReadAloudMode(ReadAloudMode mode) async =>
      readAloudMode = mode;
}

/// In-memory clipboard — no platform channel in tests.
class FakeClipboardService implements ClipboardService {
  final List<String> copied = [];

  @override
  Future<void> copy(String text) async {
    copied.add(text);
  }
}

/// A fixed permission outcome — no real microphone, no plugin.
class FakeMicPermission implements MicPermission {
  FakeMicPermission([this.result = MicPermissionResult.granted]);

  MicPermissionResult result;

  @override
  Future<MicPermissionResult> request() async => result;
}

/// A recorder that never touches the microphone or a platform channel.
/// `stop()` returns [fixedStopPath] every time, standing in for "the
/// file that was recorded" without ever writing one.
class FakeVoiceRecorder implements VoiceRecorder {
  FakeVoiceRecorder({this.fixedStopPath = '/tmp/fake_voice_message.wav'});

  final String fixedStopPath;
  final List<String> startCalls = [];
  int stopCalls = 0;
  int cancelCalls = 0;
  final StreamController<double> _amplitudeController = StreamController.broadcast();

  @override
  Future<void> start() async {
    startCalls.add(fixedStopPath);
  }

  @override
  Future<String?> stop() async {
    stopCalls++;
    return fixedStopPath;
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
  }

  @override
  Stream<double> get amplitude => _amplitudeController.stream;

  @override
  Future<void> dispose() async {
    await _amplitudeController.close();
  }
}

/// Wraps `VoiceApi`'s public interface with fixed/injectable responses.
class FakeVoiceApi implements VoiceApi {
  FakeVoiceApi({
    this.languages = const [],
    this.languagesError,
    this.chatResult,
    this.chatError,
    this.synthesizeResult,
    this.synthesizeError,
  });

  List<VoiceLanguage> languages;
  AppError? languagesError;
  VoiceChatResult? chatResult;
  AppError? chatError;
  SynthesizedSpeech? synthesizeResult;
  AppError? synthesizeError;
  final List<String> languagesRequestedForChat = [];
  final List<bool> autoDetectFlags = [];
  final List<String> textsRequestedForSynthesis = [];
  final List<String> synthLanguages = [];

  @override
  Future<List<VoiceLanguage>> fetchLanguages() async {
    if (languagesError != null) throw languagesError!;
    return languages;
  }

  @override
  Future<VoiceChatResult> sendVoiceMessage({
    required File audioFile,
    required String language,
    List<dynamic>? history,
    bool autoDetect = false,
    double? latitude,
    double? longitude,
    String? placeName,
  }) async {
    languagesRequestedForChat.add(language);
    autoDetectFlags.add(autoDetect);
    if (chatError != null) throw chatError!;
    return chatResult!;
  }

  @override
  Future<SynthesizedSpeech> synthesize({required String text, required String language}) async {
    textsRequestedForSynthesis.add(text);
    synthLanguages.add(language);
    if (synthesizeError != null) throw synthesizeError!;
    return synthesizeResult!;
  }
}

/// A playback device that never touches real audio hardware. `playBytes`
/// resolves immediately by default (`autoComplete: true`) — enough for
/// tests that only care an active playback was requested and finished;
/// tests that need to inspect the in-between "playing" state should pass
/// `autoComplete: false` and complete `pendingPlays` themselves.
class FakeAudioPlaybackDevice implements AudioPlaybackDevice {
  FakeAudioPlaybackDevice({this.autoComplete = true});

  final bool autoComplete;
  final List<Uint8List> playedBytes = [];
  final List<Completer<void>> pendingPlays = [];
  int stopCalls = 0;

  @override
  Future<void> playBytes(Uint8List bytes) {
    playedBytes.add(bytes);
    final completer = Completer<void>();
    pendingPlays.add(completer);
    if (autoComplete) completer.complete();
    return completer.future;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    for (final p in pendingPlays.where((p) => !p.isCompleted)) {
      p.complete();
    }
  }

  @override
  Future<void> dispose() async {}
}

/// Drop-in overrides for any `ProviderScope` mounting `HomeScreen`.
///
/// The return type is inferred rather than written out: Riverpod 3 does
/// not export a public name for it. The fakes are stateless, so one
/// shared list is safe across tests.
final fakeApiOverrides = [
  weatherApiProvider.overrideWithValue(FakeWeatherApi()),
  alertsApiProvider.overrideWithValue(FakeAlertsApi()),
  airQualityApiProvider.overrideWithValue(FakeAirQualityApi()),
  nwpApiProvider.overrideWithValue(FakeNwpApi()),
  advisoryApiProvider.overrideWithValue(FakeAdvisoryApi()),
  metarApiProvider.overrideWithValue(FakeMetarApi()),
  marineApiProvider.overrideWithValue(FakeMarineApi()),
  historicalApiProvider.overrideWithValue(FakeHistoricalApi()),
  deviceLocationProvider.overrideWithValue(const FakeDeviceLocation()),
  geocodingApiProvider.overrideWithValue(const FakeGeocodingApi()),
  alertsSocketProvider.overrideWithValue(FakeAlertsSocket()),
  savedPlacesStoreProvider.overrideWithValue(FakeSavedPlacesStore()),
  conversationStoreProvider.overrideWithValue(FakeConversationStore()),
];
