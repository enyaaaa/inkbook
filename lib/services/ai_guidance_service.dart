import 'dart:async';
import 'dart:math' as math;

import '../models/drawing_guide.dart';

/// The AI-assisted drawing feature from objective 7 of the project plan,
/// expressed as an interface so the UI never depends on a particular provider.
///
/// [MockAiGuidanceService] below returns hand-written guides so the prototype
/// can be demonstrated and user-tested offline. To go live, implement this
/// interface against a real model API:
///
/// ```dart
/// class RemoteAiGuidanceService implements AiGuidanceService {
///   @override
///   Future<DrawingGuide> guideFor(String subject) async {
///     final response = await http.post(
///       Uri.parse('https://<your-endpoint>'),
///       headers: {'content-type': 'application/json', 'x-api-key': key},
///       body: jsonEncode({'subject': subject, 'format': 'steps'}),
///     );
///     return DrawingGuide.fromJson(jsonDecode(response.body));
///   }
/// }
/// ```
///
/// Keep the API key out of the client in the final build - proxy the call
/// through a Cloud Function so the key is never shipped in the app bundle.
abstract class AiGuidanceService {
  /// A step-by-step walkthrough for drawing [subject].
  Future<DrawingGuide> guideFor(String subject);

  /// A few short creative prompts, optionally themed around [theme].
  Future<List<DrawingPrompt>> prompts({String? theme});

  /// A contextual suggestion for the drawing currently on the page.
  /// [strokeCount] lets the mock give sensible advice for an empty vs busy
  /// page; the real implementation would send a downscaled PNG instead.
  Future<String> critique({required String subject, required int strokeCount});
}

class MockAiGuidanceService implements AiGuidanceService {
  MockAiGuidanceService({this.latency = const Duration(milliseconds: 700)});

  final Duration latency;
  final math.Random _random = math.Random();

  @override
  Future<DrawingGuide> guideFor(String subject) async {
    await Future<void>.delayed(latency);
    final key = subject.trim().toLowerCase();
    final template = _library.entries
        .firstWhere(
          (entry) => key.contains(entry.key),
          orElse: () => MapEntry<String, DrawingGuide>('', _generic(subject)),
        )
        .value;
    if (template.subject.isEmpty) return _generic(subject);
    return template;
  }

  @override
  Future<List<DrawingPrompt>> prompts({String? theme}) async {
    await Future<void>.delayed(latency);
    final pool = List<DrawingPrompt>.of(_prompts);
    if (theme != null && theme.isNotEmpty) {
      pool.retainWhere(
        (p) => p.category.toLowerCase() == theme.toLowerCase(),
      );
      if (pool.isEmpty) pool.addAll(_prompts);
    }
    pool.shuffle(_random);
    return pool.take(4).toList(growable: false);
  }

  @override
  Future<String> critique({
    required String subject,
    required int strokeCount,
  }) async {
    await Future<void>.delayed(latency);
    if (strokeCount == 0) {
      return 'The page is still blank. Start with light construction shapes - '
          'a circle for the main mass and a line for the axis - before '
          'committing to any detail.';
    }
    if (strokeCount < 25) {
      return 'Good start. Keep the whole drawing at the same level of finish '
          'for now: block in the large shapes everywhere before you refine '
          'any one area, so the proportions stay easy to correct.';
    }
    return 'There is plenty on the page. Try varying your pressure more - '
        'press harder on the contours closest to the viewer and ease off on '
        'the edges that fall away, and the drawing will read as three '
        'dimensional rather than flat.';
  }

  static DrawingGuide _generic(String subject) {
    final name = subject.trim().isEmpty ? 'your subject' : subject.trim();
    return DrawingGuide(
      subject: name,
      summary: 'A four-step construction approach that works for almost any '
          'subject: big shapes first, detail last.',
      steps: <GuideStep>[
        GuideStep(
          index: 1,
          title: 'Block in the big shape',
          instruction:
              'Look at $name and reduce it to one or two simple shapes. Draw '
              'them very lightly, filling most of the page.',
          tip: 'Hold the stylus lightly - low pressure gives you a thin line '
              'you can draw over later.',
        ),
        const GuideStep(
          index: 2,
          title: 'Find the proportions',
          instruction:
              'Mark where the main divisions fall - halfway points, the widest '
              'part, the longest axis. Compare distances by eye before you '
              'commit to them.',
        ),
        const GuideStep(
          index: 3,
          title: 'Refine the contour',
          instruction:
              'Work around the outline, replacing the straight construction '
              'lines with the real curves. Press harder where the form turns '
              'towards you so the line carries weight.',
          tip: 'Vary line weight rather than pressing evenly everywhere.',
        ),
        const GuideStep(
          index: 4,
          title: 'Add value and detail',
          instruction:
              'Decide where the light comes from, shade the opposite side, '
              'and add only the details that help the drawing read. Stop '
              'earlier than you think you should.',
        ),
      ],
    );
  }

  static final Map<String, DrawingGuide> _library = <String, DrawingGuide>{
    'hand': const DrawingGuide(
      subject: 'a hand',
      difficulty: 'Intermediate',
      summary: 'Hands are easier when you treat them as a box plus five '
          'jointed cylinders rather than as an outline.',
      steps: <GuideStep>[
        GuideStep(
          index: 1,
          title: 'Draw the palm as a flat box',
          instruction:
              'Sketch a slightly tapered box for the palm. Its width is about '
              'the length of the middle finger.',
        ),
        GuideStep(
          index: 2,
          title: 'Mark the knuckle arc',
          instruction:
              'Draw a curved line across the top of the box. The knuckles sit '
              'on an arc, never on a straight line.',
          tip: 'The index knuckle is highest, the little finger lowest.',
        ),
        GuideStep(
          index: 3,
          title: 'Add the fingers as cylinders',
          instruction:
              'From each point on the arc, draw three short segments for the '
              'finger bones. Keep them all bending in the same direction.',
        ),
        GuideStep(
          index: 4,
          title: 'Place the thumb on its own',
          instruction:
              'The thumb joins lower down, at the side of the palm, and moves '
              'on a different plane. Draw it as a wedge plus two segments.',
        ),
        GuideStep(
          index: 5,
          title: 'Wrap the contour and shade',
          instruction:
              'Join the construction with a flowing outline, then shade the '
              'underside of each finger so they sit in front of one another.',
          tip: 'Use heavier pressure on the fingers nearest the viewer.',
        ),
      ],
    ),
    'face': const DrawingGuide(
      subject: 'a face',
      difficulty: 'Beginner',
      summary: 'A sphere, a jaw and three horizontal guides will get the '
          'features in the right places every time.',
      steps: <GuideStep>[
        GuideStep(
          index: 1,
          title: 'Sphere and jaw',
          instruction:
              'Draw a circle for the cranium, then hang a tapering jaw from '
              'its lower third.',
        ),
        GuideStep(
          index: 2,
          title: 'Centre line and eye line',
          instruction:
              'Draw a vertical centre line following the tilt of the head, '
              'then a horizontal eye line halfway down the whole head.',
          tip: 'Beginners almost always place the eyes too high.',
        ),
        GuideStep(
          index: 3,
          title: 'Nose and mouth guides',
          instruction:
              'Halfway between the eye line and the chin is the base of the '
              'nose; a third of the way below that is the mouth.',
        ),
        GuideStep(
          index: 4,
          title: 'Block the features',
          instruction:
              'Place simple shapes - almonds for eyes, a wedge for the nose, '
              'a flattened bow for the lips - and check the spacing: about '
              'one eye width between the eyes.',
        ),
        GuideStep(
          index: 5,
          title: 'Hair as a mass, then shade',
          instruction:
              'Draw the hair as one silhouette sitting away from the skull, '
              'then shade under the brow, nose and lower lip.',
        ),
      ],
    ),
    'tree': const DrawingGuide(
      subject: 'a tree',
      difficulty: 'Beginner',
      summary: 'Draw the gesture of the trunk first and the leaves as a few '
          'big clumps, never leaf by leaf.',
      steps: <GuideStep>[
        GuideStep(
          index: 1,
          title: 'Trunk gesture',
          instruction:
              'One flowing line for the direction of growth, thicker at the '
              'base. Let it curve - straight trunks look artificial.',
        ),
        GuideStep(
          index: 2,
          title: 'Branch structure',
          instruction:
              'Split the trunk into progressively thinner branches, each one '
              'thinner than its parent, spreading outwards and upwards.',
        ),
        GuideStep(
          index: 3,
          title: 'Foliage clumps',
          instruction:
              'Draw three to five irregular cloud shapes over the branch ends, '
              'leaving gaps of sky between them.',
          tip: 'Uneven clump sizes look far more natural than even ones.',
        ),
        GuideStep(
          index: 4,
          title: 'Shade and ground',
          instruction:
              'Darken the underside of each clump and the shadow side of the '
              'trunk, then anchor the tree with a soft shadow on the ground.',
        ),
      ],
    ),
    'cat': const DrawingGuide(
      subject: 'a cat',
      difficulty: 'Beginner',
      summary: 'Two circles and a line of action carry the whole pose.',
      steps: <GuideStep>[
        GuideStep(
          index: 1,
          title: 'Line of action',
          instruction:
              'Draw a single curved line for the spine, from the top of the '
              'head to the tip of the tail.',
        ),
        GuideStep(
          index: 2,
          title: 'Two masses',
          instruction:
              'Add a small circle for the head and a larger oval for the '
              'ribcage and hips along that line.',
        ),
        GuideStep(
          index: 3,
          title: 'Legs and tail',
          instruction:
              'Attach simple tapered shapes for the legs, bending at the '
              'ankle and knee, and let the tail continue the spine curve.',
        ),
        GuideStep(
          index: 4,
          title: 'Head features',
          instruction:
              'Triangular ears wide apart, eyes on the horizontal midline of '
              'the head, a small wedge nose and a wide muzzle.',
          tip: 'Cat eyes sit lower on the skull than you expect.',
        ),
        GuideStep(
          index: 5,
          title: 'Fur and finish',
          instruction:
              'Break the outline with short strokes only where the fur is '
              'longest - chest, cheeks and tail - and leave the rest smooth.',
        ),
      ],
    ),
  };

  static const List<DrawingPrompt> _prompts = <DrawingPrompt>[
    DrawingPrompt(
      text: 'Draw the view from a window you know well, from memory.',
      category: 'Observation',
    ),
    DrawingPrompt(
      text: 'Fill a page with the same object drawn ten times, each in under '
          'thirty seconds.',
      category: 'Practice',
    ),
    DrawingPrompt(
      text: 'A creature that lives entirely underwater but breathes air.',
      category: 'Imagination',
    ),
    DrawingPrompt(
      text: 'Draw your hand without lifting the stylus off the page.',
      category: 'Practice',
    ),
    DrawingPrompt(
      text: 'A quiet street at the exact moment the rain starts.',
      category: 'Imagination',
    ),
    DrawingPrompt(
      text: 'The most cluttered corner of the room you are in.',
      category: 'Observation',
    ),
    DrawingPrompt(
      text: 'Redraw yesterday\'s sketch using only three values: light, mid, '
          'dark.',
      category: 'Practice',
    ),
    DrawingPrompt(
      text: 'A building that has been slowly taken over by a plant.',
      category: 'Imagination',
    ),
  ];
}
