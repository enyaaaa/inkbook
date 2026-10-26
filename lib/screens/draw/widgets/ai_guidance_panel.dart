import 'package:flutter/material.dart';

import '../../../controllers/app_state.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/scrapbook.dart';

/// The AI-assisted drawing surface (objective 7): prompts for when the user
/// does not know what to draw, and a step-by-step guide for when they do but
/// do not know how.
class AiGuidancePanel extends StatefulWidget {
  const AiGuidancePanel({
    super.key,
    required this.ai,
    required this.strokeCount,
    required this.onClose,
  });

  final AiController ai;
  final int strokeCount;
  final VoidCallback onClose;

  @override
  State<AiGuidancePanel> createState() => _AiGuidancePanelState();
}

class _AiGuidancePanelState extends State<AiGuidancePanel> {
  final TextEditingController _subject = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.ai.prompts.isEmpty) widget.ai.refreshPrompts();
  }

  @override
  void dispose() {
    _subject.dispose();
    super.dispose();
  }

  void _ask() {
    final text = _subject.text.trim();
    if (text.isEmpty) return;
    widget.ai.requestGuide(text);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 330,
      margin: const EdgeInsets.fromLTRB(0, 8, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        boxShadow: paperShadow(lift: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: GrainSurface(
        color: InkbookColors.folderCream,
        grain: InkbookColors.inkSoft,
        density: 0.5,
        child: ListenableBuilder(
          listenable: widget.ai,
          builder: (context, _) {
            final ai = widget.ai;
            final guide = ai.guide;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 8, 10),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text('YOUR DRAWING ASSISTANT',
                                style: InkbookType.eyebrow()),
                            const SizedBox(height: 4),
                            Text('Stuck?', style: InkbookType.title(size: 24)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: widget.onClose,
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _subject,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _ask(),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      hintText: 'how do I draw...',
                      hintStyle: InkbookType.body(
                        size: 14,
                        color: InkbookColors.inkSoft,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.arrow_forward, size: 18),
                        onPressed: _ask,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (ai.isBusy) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: guide == null
                      ? _PromptList(
                          ai: ai,
                          onPick: (text) {
                            _subject.text = text;
                            _ask();
                          })
                      : _GuideView(ai: ai),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: FilledButton.icon(
                    onPressed: ai.isBusy
                        ? null
                        : () => ai.requestCritique(
                              subject: _subject.text.trim().isEmpty
                                  ? 'this drawing'
                                  : _subject.text.trim(),
                              strokeCount: widget.strokeCount,
                            ),
                    icon: const Icon(Icons.tips_and_updates_outlined, size: 18),
                    label: const Text('Suggest a next step'),
                  ),
                ),
                if (ai.critique != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text(
                      ai.critique!,
                      style: InkbookType.body(size: 14),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

const List<Color> _stickyNotes = <Color>[
  Color(0xFFF7E3A1),
  Color(0xFFDDE2F8),
  Color(0xFFF2D3CF),
  Color(0xFFDDE6D3),
];

class _PromptList extends StatelessWidget {
  const _PromptList({required this.ai, required this.onPick});

  final AiController ai;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              'need an idea?',
              style: InkbookType.title(size: 16),
            ),
            TextButton(
              onPressed: ai.isBusy ? null : () => ai.refreshPrompts(),
              child: const Text('Shuffle'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (final (i, prompt) in ai.prompts.indexed)
          Transform.rotate(
            angle: i.isEven ? -0.015 : 0.02,
            child: Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
              decoration: BoxDecoration(
                color: _stickyNotes[i % _stickyNotes.length],
                borderRadius: BorderRadius.circular(2),
                boxShadow: paperShadow(lift: 0.45),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    prompt.category.toUpperCase(),
                    style: InkbookType.eyebrow(),
                  ),
                  const SizedBox(height: 6),
                  Text(prompt.text, style: InkbookType.body(size: 14)),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        const Text(
          'Or ask for a walkthrough: try "a hand", "a face", "a tree" or '
          '"a cat".',
          style: TextStyle(fontSize: 12, color: InkbookColors.inkSoft),
        ),
      ],
    );
  }
}

class _GuideView extends StatelessWidget {
  const _GuideView({required this.ai});

  final AiController ai;

  @override
  Widget build(BuildContext context) {
    final guide = ai.guide!;
    final step = guide.steps[ai.activeStep];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'How to draw ${guide.subject}',
                  style: InkbookType.title(size: 18),
                ),
              ),
              TextButton(
                onPressed: ai.clearGuide,
                child: const Text('Back'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            guide.summary,
            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
              color: InkbookColors.inkSoft,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: <Widget>[
              TornPaper(
                color: Colors.white,
                seed: step.index,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Step ${step.index} of ${guide.stepCount}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                        color: InkbookColors.toolOrange,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      step.title,
                      style: InkbookType.title(size: 18),
                    ),
                    const SizedBox(height: 8),
                    Text(step.instruction,
                        style: const TextStyle(height: 1.45)),
                    if (step.tip != null) ...<Widget>[
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Icon(Icons.lightbulb_outline,
                              size: 15, color: InkbookColors.sage),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              step.tip!,
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.35,
                                color: InkbookColors.sage,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              for (final other in guide.steps)
                if (other.index - 1 != ai.activeStep)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 12,
                      backgroundColor: InkbookColors.paperToned,
                      child: Text(
                        '${other.index}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: InkbookColors.ink,
                        ),
                      ),
                    ),
                    title: Text(
                      other.title,
                      style: const TextStyle(fontSize: 13),
                    ),
                    onTap: () => ai.setActiveStep(other.index - 1),
                  ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: ai.activeStep == 0 ? null : ai.previousStep,
                  child: const Text('Previous'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed:
                      ai.activeStep >= guide.stepCount - 1 ? null : ai.nextStep,
                  child: const Text('Next step'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
