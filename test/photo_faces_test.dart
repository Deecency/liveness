// Finding the faces in a photo, with ML Kit's platform side faked.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveness/liveness.dart';

const _channel = MethodChannel('google_mlkit_face_detector');

/// One face as ML Kit's platform side reports it.
Map<String, Object?> _face({
  required List<double> ltrb,
  double? yaw,
  double? pitch,
  double? roll,
  double? leftEye,
  double? rightEye,
}) => {
  'rect': {
    'left': ltrb[0],
    'top': ltrb[1],
    'right': ltrb[2],
    'bottom': ltrb[3],
  },
  'headEulerAngleX': pitch,
  'headEulerAngleY': yaw,
  'headEulerAngleZ': roll,
  'leftEyeOpenProbability': leftEye,
  'rightEyeOpenProbability': rightEye,
  'landmarks': <String, Object?>{},
  'contours': <String, Object?>{},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;
  late Object? Function(MethodCall call) answer;

  setUp(() {
    calls = [];
    answer = (_) => <Object?>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          if (call.method == 'vision#closeFaceDetector') return null;
          final reply = answer(call);
          if (reply is PlatformException) throw reply;
          return reply;
        });
  });

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );

  Map<Object?, Object?> argsOf(String method) =>
      calls.firstWhere((c) => c.method == method).arguments as Map;

  test('reads each face: where it is, its pose and its eyes', () async {
    answer = (_) => [
      _face(
        ltrb: [100, 150, 400, 500],
        yaw: 4,
        pitch: -3,
        roll: 1.5,
        leftEye: 0.9,
        rightEye: 0.8,
      ),
      _face(ltrb: [10, 20, 60, 90]),
    ];

    final faces = await LivenessPhotoFaces.find('/photos/selfie.jpg');

    expect(faces, hasLength(2));
    final face = faces.first;
    expect(face.bounds, const Rect.fromLTRB(100, 150, 400, 500));
    expect(face.yaw, 4);
    expect(face.pitch, -3);
    expect(face.roll, 1.5);
    expect(face.leftEyeOpen, 0.9);
    expect(face.rightEyeOpen, 0.8);
    expect(faces.last.yaw, isNull);
    expect(faces.last.leftEyeOpen, isNull);
  });

  test('looks at the file, with eyes measured and accuracy first', () async {
    await LivenessPhotoFaces.find('/photos/selfie.jpg', minFaceSize: 0.2);

    final args = argsOf('vision#startFaceDetector');
    final image = args['imageData']! as Map;
    expect(image['type'], 'file');
    expect(image['path'], '/photos/selfie.jpg');
    final options = args['options']! as Map;
    expect(options['enableClassification'], isTrue);
    expect(options['mode'], 'accurate');
    expect(options['minFaceSize'], 0.2);
  });

  test('a photo without a face has none', () async {
    expect(await LivenessPhotoFaces.find('/photos/wall.jpg'), isEmpty);
  });

  test('closes the detector, even when the photo cannot be read', () async {
    answer = (_) => PlatformException(code: 'unreadable');

    await expectLater(
      LivenessPhotoFaces.find('/photos/missing.jpg'),
      throwsA(isA<PlatformException>()),
    );
    final started = argsOf('vision#startFaceDetector')['id'];
    expect(argsOf('vision#closeFaceDetector')['id'], started);
  });
}
