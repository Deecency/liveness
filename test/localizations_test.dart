// The liveness screen's words follow the host app's language.
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveness/liveness.dart';
import 'package:material_ui/material_ui.dart';

/// An app's own wording, keeping the rest of the English.
class _AppWords extends LivenessLocalizationsEn {
  const _AppWords();

  @override
  String gestureName(LivenessGesture gesture) =>
      'Please ${super.gestureName(gesture).toLowerCase()}';
}

/// A phone whose camera won't start.
class _BrokenCamera extends CameraPlatform {
  @override
  Future<List<CameraDescription>> availableCameras() async =>
      throw CameraException('cameraBroken', 'The camera would not start');
}

Future<void> _show(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('fr'), Locale('de')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(body: child),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
}

Widget _gesture(LivenessGesture gesture, [LivenessConfig? config]) =>
    LivenessInstructionWidget(
      config: config ?? const LivenessConfig(),
      waiting: false,
      currentStep: gesture,
    );

void main() {
  testWidgets('a gesture is named in English by default', (tester) async {
    await _show(tester, _gesture(LivenessGesture.blink));

    expect(find.text('Blink'), findsOneWidget);
    expect(find.text('Blink your eyes clearly a few times'), findsOneWidget);
  });

  testWidgets('a French app gets French, with no setup', (tester) async {
    await _show(
      tester,
      _gesture(LivenessGesture.blink),
      locale: const Locale('fr'),
    );

    expect(find.text('Clignez des yeux'), findsOneWidget);
    expect(
      find.text('Clignez nettement des yeux plusieurs fois'),
      findsOneWidget,
    );
  });

  testWidgets('a language the package lacks falls back to English', (
    tester,
  ) async {
    await _show(
      tester,
      _gesture(LivenessGesture.smile),
      locale: const Locale('de'),
    );

    expect(find.text('Smile'), findsOneWidget);
  });

  testWidgets('an app can pass its own words', (tester) async {
    await _show(
      tester,
      _gesture(
        LivenessGesture.nod,
        const LivenessConfig(localizations: _AppWords()),
      ),
      locale: const Locale('fr'),
    );

    expect(find.text('Please nod'), findsOneWidget);
    expect(find.text('Slowly nod your head down and up'), findsOneWidget);
  });

  testWidgets('capture hints and the timer follow the language', (
    tester,
  ) async {
    await _show(
      tester,
      const Column(
        children: [
          LivenessInstructionWidget(
            config: LivenessConfig(),
            waiting: false,
            capturing: true,
            captureHint: LivenessCaptureHint.moveCloser,
          ),
          ProgressTimer(config: LivenessConfig(), timeRemaining: 12),
        ],
      ),
      locale: const Locale('fr'),
    );

    expect(find.text('Rapprochez-vous'), findsOneWidget);
    expect(find.text('12 s restantes'), findsOneWidget);
  });

  testWidgets('the screen and a camera that will not start speak French', (
    tester,
  ) async {
    CameraPlatform.instance = _BrokenCamera();
    await _show(
      tester,
      Builder(
        builder: (context) => Center(
          child: GestureDetector(
            onTap: () => FaceLiveness.show(context),
            child: const Text('open'),
          ),
        ),
      ),
      locale: const Locale('fr'),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Vérification faciale'), findsOneWidget);
    expect(find.text('Démarrage de la caméra…'), findsOneWidget);
    expect(find.text('Impossible de démarrer la caméra'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  test('the English getters on the enums still work', () {
    expect(LivenessGesture.turnLeft.displayName, 'Turn Left');
    expect(LivenessCaptureHint.tooDark.title, 'Too Dark');
    expect(
      LivenessLocalizations.forLocale(const Locale('fr', 'CA')).title,
      'Vérification faciale',
    );
  });
}
