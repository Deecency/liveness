import 'package:flutter/widgets.dart';
import 'package:liveness/shared/l10n/liveness_localizations_en.dart';
import 'package:liveness/shared/l10n/liveness_localizations_fr.dart';
import 'package:liveness/shared/models/config.dart';
import 'package:liveness/shared/models/enums.dart';

/// The words the liveness screen shows.
///
/// English and French are built in, and the screen follows the app's
/// locale on its own: with French selected it speaks French, with no setup.
/// A language the package lacks falls back to English.
///
/// To change the wording or add a language, pass your own through
/// `LivenessConfig.localizations`, for example a subclass of
/// [LivenessLocalizationsEn] that reads the app's own translations.
abstract class LivenessLocalizations {
  const LivenessLocalizations();

  /// The built-in translations, by language code.
  static const Map<String, LivenessLocalizations> builtIn = {
    'en': LivenessLocalizationsEn(),
    'fr': LivenessLocalizationsFr(),
  };

  /// The built-in translation for [locale]'s language, or English.
  static LivenessLocalizations forLocale(Locale locale) =>
      builtIn[locale.languageCode] ?? const LivenessLocalizationsEn();

  /// The app's own words from [config] when it set them, otherwise the
  /// built-in ones for the app's locale.
  static LivenessLocalizations of(
    BuildContext context, [
    LivenessConfig? config,
  ]) =>
      config?.localizations ??
      forLocale(Localizations.maybeLocaleOf(context) ?? const Locale('en'));

  /// The app bar title, unless `LivenessConfig.title` is set.
  String get title;

  /// Shown while the camera starts.
  String get initializingCamera;

  /// The short wait before the first gesture.
  String get preparingTitle;
  String get preparingSubtitle;

  /// Once every gesture is done, while the result is prepared.
  String get successTitle;
  String get successSubtitle;

  /// The countdown, as in "12s remaining".
  String secondsRemaining(num seconds);

  /// A gesture's short name, as in "Blink".
  String gestureName(LivenessGesture gesture);

  /// How to do a gesture, as in "Blink your eyes clearly a few times".
  String gestureInstruction(LivenessGesture gesture);

  /// What to fix before the final photo, as in "Move Closer".
  String hintTitle(LivenessCaptureHint hint);

  /// How to fix it, as in "Move your face a little closer to the camera".
  String hintInstruction(LivenessCaptureHint hint);

  /// Why the session is stopping early.
  String error(LivenessErrorKind kind);
}
