import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/voice_language_prefs.dart';
import '../data/translate_api.dart';
import 'strings.g.dart';

/// Strongly-typed string access with fallback to English.
class AppStrings {
  AppStrings(this.languageCode, [Map<String, String>? bundle])
      : _bundle = bundle ?? appStringsByLocale[languageCode] ?? const {};

  final String languageCode;
  final Map<String, String> _bundle;

  factory AppStrings.forLanguage(String code) => AppStrings(code);

  /// Retrieves the localized string for [key], falling back to English,
  /// and finally to [key] itself if missing.
  String get(String key) {
    final val = _bundle[key];
    if (val != null && val.isNotEmpty) return val;
    return appStringsEn[key] ?? key;
  }

  // Navigation & Shell
  String get weatherGpt => get('weatherGpt');
  String get searchChats => get('searchChats');
  String get home => get('home');
  String get newChat => get('newChat');
  String get advisories => get('advisories');
  String get aviation => get('aviation');
  String get fishingZones => get('fishingZones');
  String get historical => get('historical');
  String get discover => get('discover');
  String get alerts => get('alerts');
  String get savedPlaces => get('savedPlaces');
  String get recents => get('recents');
  String get emptyRecentsHint => get('emptyRecentsHint');
  String get delete => get('delete');
  String get yourAccount => get('yourAccount');
  String get openMenu => get('openMenu');

  // Home & Header
  String get searchLocation => get('searchLocation');
  String get searchCityOrDistrict => get('searchCityOrDistrict');
  String get useMyLocation => get('useMyLocation');
  String get couldNotGetLocation => get('couldNotGetLocation');
  String get couldNotLoadWeather => get('couldNotLoadWeather');
  String get tryAgain => get('tryAgain');
  String get retry => get('retry');

  // Weather Condition Details
  String get feelsLike => get('feelsLike');
  String get hourlyForecast => get('hourlyForecast');
  String get dailyTotal => get('dailyTotal');
  String get humidity => get('humidity');
  String get dewPoint => get('dewPoint');
  String get pressure => get('pressure');
  String get visibility => get('visibility');
  String get uvIndex => get('uvIndex');
  String get wind => get('wind');
  String get sunrise => get('sunrise');
  String get sunset => get('sunset');
  String get pm25 => get('pm25');
  String get now => get('now');
  String get sun => get('sun');
  String get riskVeryHigh => get('riskVeryHigh');
  String get peak => get('peak');

  // Severe Weather
  String get severeWeather => get('severeWeather');
  String get basedOnForecast => get('basedOnForecast');
  String get convectiveRisk => get('convectiveRisk');
  String get urbanRisk => get('urbanRisk');
  String get maxWind => get('maxWind');
  String get waterlogging => get('waterlogging');
  String get gale => get('gale');
  String get heat => get('heat');

  // WMO Weather Labels
  String weatherLabel(int code) {
    final key = 'weather_$code';
    final val = get(key);
    if (val != key) return val;
    return get('weather_unknown');
  }

  // Advisories Screen
  String get askQuestion => get('askQuestion');
  String get noAdvisoriesArea => get('noAdvisoriesArea');
  String get couldNotLoadAdvisories => get('couldNotLoadAdvisories');
  String get filterCropAdvice => get('filterCropAdvice');
  String get sectorBoundary => get('sectorBoundary');
  String get changeLocation => get('changeLocation');
  String get allCrops => get('allCrops');
  String get rice => get('rice');
  String get wheat => get('wheat');
  String get cotton => get('cotton');
  String get sugarcane => get('sugarcane');
  String get riskLow => get('riskLow');
  String get riskModerate => get('riskModerate');
  String get riskHigh => get('riskHigh');
  String get riskExtreme => get('riskExtreme');

  // Alerts Screen
  String get alertsNotice => get('alertsNotice');
  String get noAlertsNearby => get('noAlertsNearby');
  String get noAlertsAffecting => get('noAlertsAffecting');
  String get couldNotLoadAlertHistory => get('couldNotLoadAlertHistory');

  // Aviation Screen
  String get flightCategory => get('flightCategory');
  String get chooseAirport => get('chooseAirport');
  String get chooseDifferentAirport => get('chooseDifferentAirport');
  String get rawReport => get('rawReport');
  String get noCurrentObservation => get('noCurrentObservation');
  String get couldNotLoadObservation => get('couldNotLoadObservation');

  // Marine Screen
  String get basemapUnavailable => get('basemapUnavailable');
  String get couldNotLoadFishingZones => get('couldNotLoadFishingZones');
  String get distance => get('distance');
  String get direction => get('direction');
  String get depth => get('depth');

  // Historical Screen
  String get sameDayDifferentYear => get('sameDayDifferentYear');
  String get sourceEra5 => get('sourceEra5');
  String get meanTemp => get('meanTemp');
  String get maxTemp => get('maxTemp');
  String get minTemp => get('minTemp');
  String get precipitation => get('precipitation');
  String get noArchiveReading => get('noArchiveReading');
  String get tryDifferentDate => get('tryDifferentDate');
  String get couldNotLoadHistorical => get('couldNotLoadHistorical');
  String get changeDate => get('changeDate');

  // Saved Places Screen
  String get noSavedPlacesYet => get('noSavedPlacesYet');
  String get tapBookmarkHint => get('tapBookmarkHint');

  // Discover Screen
  String get noHeadlines => get('noHeadlines');
  String get checkBackSoonNews => get('checkBackSoonNews');
  String get couldNotLoadNews => get('couldNotLoadNews');

  // Language Settings Sheet
  String get languageSettings => get('languageSettings');
  String get voiceInputDesc => get('voiceInputDesc');
  String get micRecognitionTitle => get('micRecognitionTitle');
  String get autoDetectLabel => get('autoDetectLabel');
  String get autoDetectSubtitle => get('autoDetectSubtitle');
  String get fixedLanguageLabel => get('fixedLanguageLabel');
  String get fixedLanguageSubtitle => get('fixedLanguageSubtitle');
  String get globalVoiceLanguage => get('globalVoiceLanguage');
  String get speakerReadMode => get('speakerReadMode');
  String get messageLanguage => get('messageLanguage');
  String get messageLanguageDesc => get('messageLanguageDesc');
  String get globalLanguage => get('globalLanguage');
  String get globalLanguageDesc => get('globalLanguageDesc');
  String get change => get('change');

  // Chat Composer & General
  String get micDisabled => get('micDisabled');
  String get micAccessNeeded => get('micAccessNeeded');
  String get micTooltip => get('micTooltip');
  String get cancelRecording => get('cancelRecording');
  String get stopAndSend => get('stopAndSend');
  String get sendMessage => get('sendMessage');
  String get sending => get('sending');
  String get copiedToClipboard => get('copiedToClipboard');
  String get copy => get('copy');
  String get share => get('share');
  String get more => get('more');
  String get moreOptions => get('moreOptions');
  String get addAttachment => get('addAttachment');
  String get attachMenu => get('attachMenu');
  String get camera => get('camera');
  String get photos => get('photos');
  String get files => get('files');
  String get pin => get('pin');
  String get findInChat => get('findInChat');
  String get thisConversation => get('thisConversation');
  String get settings => get('settings');
  String get overflowMenu => get('overflowMenu');
}

/// Provides the current [AppStrings] responding to the user's global language selection.
final uiStringsProvider = Provider<AppStrings>((ref) {
  final lang = ref.watch(voiceLanguageProvider);
  return AppStrings.forLanguage(lang);
});

/// In-memory cache for translated dynamic text.
final _dynamicCache = <String, String>{};

/// Translates dynamic backend text using [TranslateApi] with in-memory caching.
final dynamicTranslationProvider =
    FutureProvider.family<String, ({String text, String target})>((ref, arg) async {
  if (arg.target == 'en' || arg.target.isEmpty || arg.text.isEmpty) {
    return arg.text;
  }
  final cacheKey = '${arg.target}:${arg.text}';
  if (_dynamicCache.containsKey(cacheKey)) {
    return _dynamicCache[cacheKey]!;
  }
  try {
    final api = ref.watch(translateApiProvider);
    final result = await api.translate(
      text: arg.text,
      source: 'en',
      target: arg.target,
    );
    _dynamicCache[cacheKey] = result.translatedText;
    return result.translatedText;
  } catch (_) {
    // Graceful fallback to original text on rate limit or network error
    return arg.text;
  }
});

/// A text widget that automatically translates its content into the current
/// global language via Bhashini NMT when non-English, with English fallback.
class DynamicText extends ConsumerWidget {
  const DynamicText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(voiceLanguageProvider);
    if (lang == 'en' || text.isEmpty) {
      return Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
      );
    }
    final asyncVal = ref.watch(
      dynamicTranslationProvider((text: text, target: lang)),
    );
    final displayed = asyncVal.when(
      data: (val) => val,
      loading: () => text,
      error: (_, __) => text,
    );
    return Text(
      displayed,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    );
  }
}
