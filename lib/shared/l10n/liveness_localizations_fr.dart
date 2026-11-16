import 'package:liveness/shared/l10n/liveness_localizations.dart';
import 'package:liveness/shared/models/enums.dart';

/// The screen's words in French.
class LivenessLocalizationsFr extends LivenessLocalizations {
  const LivenessLocalizationsFr();

  @override
  String get title => 'Vérification faciale';

  @override
  String get initializingCamera => 'Démarrage de la caméra…';

  @override
  String get preparingTitle => 'Préparation de la vérification';

  @override
  String get preparingSubtitle =>
      'La vérification commencera automatiquement dans quelques secondes…';

  @override
  String get successTitle => 'Vérification réussie !';

  @override
  String get successSubtitle =>
      'Tous les gestes ont été validés. Traitement du résultat…';

  @override
  String secondsRemaining(num seconds) => '$seconds s restantes';

  @override
  String gestureName(LivenessGesture gesture) => switch (gesture) {
    LivenessGesture.blink => 'Clignez des yeux',
    LivenessGesture.mouthOpen => 'Ouvrez la bouche',
    LivenessGesture.headShake => 'Secouez la tête',
    LivenessGesture.smile => 'Souriez',
    LivenessGesture.turnLeft => 'Tournez à gauche',
    LivenessGesture.turnRight => 'Tournez à droite',
    LivenessGesture.nod => 'Hochez la tête',
  };

  @override
  String gestureInstruction(LivenessGesture gesture) => switch (gesture) {
    LivenessGesture.blink => 'Clignez nettement des yeux plusieurs fois',
    LivenessGesture.mouthOpen => 'Ouvrez grand la bouche pendant 2 secondes',
    LivenessGesture.headShake => 'Tournez lentement la tête de gauche à droite',
    LivenessGesture.smile => 'Faites un grand sourire pendant 2 secondes',
    LivenessGesture.turnLeft => 'Tournez la tête vers la gauche et maintenez',
    LivenessGesture.turnRight => 'Tournez la tête vers la droite et maintenez',
    LivenessGesture.nod => 'Baissez puis relevez lentement la tête',
  };

  @override
  String hintTitle(LivenessCaptureHint hint) => switch (hint) {
    LivenessCaptureHint.noFace => 'Visage non détecté',
    LivenessCaptureHint.moveCloser => 'Rapprochez-vous',
    LivenessCaptureHint.moveBack => 'Éloignez-vous',
    LivenessCaptureHint.centerFace => 'Centrez votre visage',
    LivenessCaptureHint.lookLevel => 'Téléphone à hauteur des yeux',
    LivenessCaptureHint.faceStraight => 'Regardez droit devant',
    LivenessCaptureHint.tooDark => 'Trop sombre',
    LivenessCaptureHint.tooBright => 'Trop lumineux',
    LivenessCaptureHint.holdStill => 'Ne bougez plus',
    LivenessCaptureHint.multipleFaces => 'Un seul visage',
  };

  @override
  String hintInstruction(LivenessCaptureHint hint) => switch (hint) {
    LivenessCaptureHint.noFace =>
      'Placez votre visage dans le cercle et regardez la caméra',
    LivenessCaptureHint.moveCloser =>
      'Rapprochez un peu votre visage de la caméra',
    LivenessCaptureHint.moveBack => 'Éloignez un peu le téléphone',
    LivenessCaptureHint.centerFace => 'Placez votre visage au centre du cercle',
    LivenessCaptureHint.lookLevel =>
      'Levez le téléphone pour que la caméra soit à hauteur de vos yeux',
    LivenessCaptureHint.faceStraight =>
      'Regardez la caméra de face, sans tourner la tête',
    LivenessCaptureHint.tooDark =>
      'Placez-vous dans un endroit plus éclairé ou face à la lumière',
    LivenessCaptureHint.tooBright => 'Éloignez-vous de la lumière directe',
    LivenessCaptureHint.holdStill =>
      'Ne bougez plus et regardez directement la caméra',
    LivenessCaptureHint.multipleFaces =>
      'Assurez-vous que seul votre visage est dans le cadre',
  };

  @override
  String error(LivenessErrorKind kind) => switch (kind) {
    LivenessErrorKind.noCamera => 'Aucune caméra disponible',
    LivenessErrorKind.cameraFailed => 'Impossible de démarrer la caméra',
  };
}
