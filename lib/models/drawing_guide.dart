/// A single step in an AI-generated drawing walkthrough.
class GuideStep {
  const GuideStep({
    required this.index,
    required this.title,
    required this.instruction,
    this.tip,
  });

  final int index;
  final String title;
  final String instruction;
  final String? tip;
}

/// A complete step-by-step guide returned by [AiGuidanceService].
class DrawingGuide {
  const DrawingGuide({
    required this.subject,
    required this.summary,
    required this.steps,
    this.difficulty = 'Beginner',
  });

  final String subject;
  final String summary;
  final List<GuideStep> steps;
  final String difficulty;

  int get stepCount => steps.length;
}

/// A short creative prompt shown on the "inspire me" surface.
class DrawingPrompt {
  const DrawingPrompt({
    required this.text,
    required this.category,
  });

  final String text;
  final String category;
}
