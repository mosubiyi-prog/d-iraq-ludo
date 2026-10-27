"""DEDA 100386: restore all five answers and 500 Arabic questions in PRIVATE QA.

No claim of official Iraqi traffic-sign certification. Only use existing
pre-matched glyphs as traffic signs; display clearly labeled *educational*
subject symbols for rules without verified sign artwork. No wallet mutation.
Runs after the isolated 100385 candidate visual/content bindings.
"""
from pathlib import Path


def once(s, old, new, label):
    n=s.count(old)
    if n!=1: raise ValueError(f"100386 {label}: matches={n}")
    return s.replace(old,new,1)


TOPIC_LABELS = [
    "العلامات الإلزامية والمنع",
    "علامات التحذير",
    "العلامات الإرشادية",
    "الإشارات والخطوط الأرضية",
    "التقاطعات وأولوية المرور",
    "المشاة وعبور الطريق",
    "السرعة والمسافة والكبح",
    "المسارات والتجاوز",
    "الدوارات والانعطاف",
    "الوقوف والركن",
    "القيادة الليلية",
    "الطقس والطرق",
    "الطرق الريفية",
    "الدراجات",
    "الشاحنات والحافلات",
    "سلامة الركاب",
    "صيانة المركبة",
    "التركيز والانتباه",
    "الحوادث والطوارئ",
    "القيادة المسؤولة",
]
TOPIC_ICON_NAMES = [
    "Icons.not_interested_rounded",
    "Icons.warning_amber_rounded",
    "Icons.signpost_rounded",
    "Icons.traffic_rounded",
    "Icons.alt_route_rounded",
    "Icons.directions_walk_rounded",
    "Icons.speed_rounded",
    "Icons.merge_type_rounded",
    "Icons.turn_right_rounded",
    "Icons.local_parking_rounded",
    "Icons.nights_stay_rounded",
    "Icons.cloud_rounded",
    "Icons.agriculture_rounded",
    "Icons.two_wheeler_rounded",
    "Icons.local_shipping_rounded",
    "Icons.airline_seat_recline_normal_rounded",
    "Icons.build_rounded",
    "Icons.visibility_rounded",
    "Icons.medical_services_rounded",
    "Icons.rule_rounded",
]


def bind(root):
    root=Path(root)
    f=root/"lib/traffic_quiz_page.dart"
    s=f.read_text()
    s=once(s, """      final bank = widget.isArabic
          ? fullBank.where((q) => q.visual != null).toList(growable: false)
          : fullBank;""",
          """      // All 500 need independent traffic review; enable ONLY for private QA.
      const full500Qa = bool.fromEnvironment(
        'DEDA_TRAFFIC_FULL500_QA', defaultValue: false);
      final bank = widget.isArabic && !full500Qa
          ? fullBank.where((q) => q.visual != null).toList(growable: false)
          : fullBank;""",
          "restore all 500 as candidates")
    s=once(s, """      answersAr: shownAnswers,
      answersEn: shownAnswers,
      correctIndex: shownIndexes.indexOf(answer),""",
          """      answersAr: options,
      answersEn: options,
      correctIndex: answer,""",
          "restore all five original answer choices and correct index")
    # No source rewrites: the original options remain byte-for-byte.
    # Remove the unused three-choice conversion block so it cannot reappear.
    start=s.index("    // Preserve the original five source choices")
    end=s.index("    result.add(_TrafficQuestion(",start)
    s=s[:start]+"""    // Use the original five distinct options with the original answer index.
"""+s[end:]

    start=s.index("  Widget _buildQuestion()")
    end=s.index("  Widget _buildResult()",start)
    section=s[start:end]
    section=once(section, """Column(
                    children: [
                      Text(
                        t('العلامة المرتبطة بالسؤال',
                          'Road sign for this question'),
                        style: const TextStyle(
                          color: Color(0xFF0A4675),
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 5),
                      _TrafficSignCard(kind: q.visual!),
                    ],
                  )""",
                  """_DedaTrafficQuestionVisual(
                    questionId: q.id, verifiedSign: q.visual)""",
                  "visually specific sign vs educational icon")

    # Compact screen responsibly; keep scrolling as a fallback when screen
    # height, text scaling or answer-length cannot fit without clipping.
    section=once(section,
       """isPortrait ? 12 : 18,
                isPortrait ? 9 : 18,
                isPortrait ? 12 : 18,
                isPortrait ? 12 : 24,""",
       """isPortrait ? 10 : 18,
                isPortrait ? 5 : 18,
                isPortrait ? 10 : 18,
                isPortrait ? 6 : 24,""",
       "compact content padding")
    gap = "SizedBox(height: isPortrait ? 9 : 16),"
    if section.count(gap) != 2:
        raise ValueError("100386 expected exactly two layout gaps")
    section=section.replace(gap, "SizedBox(height: isPortrait ? 5 : 16),")
    section=once(section, "fontSize: isPortrait ? 19.5 : 22,",
                 "fontSize: isPortrait ? 16.7 : 22,",
                 "compact question font")
    section=once(section, "height: isPortrait ? 1.18 : 1.0,",
                 "height: isPortrait ? 1.12 : 1.0,",
                 "compact question leading")
    section=once(section, "padding: EdgeInsets.only(bottom: isPortrait ? 7 : 10),",
                 "padding: EdgeInsets.only(bottom: isPortrait ? 4 : 10),",
                 "compact answer spacing")
    section=once(section, """horizontal: isPortrait ? 12 : 14,
                              vertical: isPortrait ? 9 : 14,""",
                 """horizontal: isPortrait ? 10 : 14,
                              vertical: isPortrait ? 6 : 14,""",
                 "compact answer padding")
    section=once(section, "fontSize: isPortrait ? 16.5 : 18,",
                 "fontSize: isPortrait ? 14.7 : 18,",
                 "five choice readable type")
    section=once(section, "height: isPortrait ? 50 : 56,",
                 "height: isPortrait ? 44 : 56,",
                 "confirm action height")
    section=once(section, "SizedBox(height: isPortrait ? 9 : 14),",
                 "SizedBox(height: isPortrait ? 5 : 14),",
                 "answer explanation gap")
    # Must not forbid scrolling on small devices or with text scaling.
    s=s[:start]+section+s[end:]
    s=once(s, "height: isPortrait ? 185 : 240,",
           "height: isPortrait ? 105 : 178,", "compact sign card")
    s=once(s, "child: _TrafficSign(kind: kind, size: isPortrait ? 152 : 185),",
           "child: _TrafficSign(kind: kind, size: isPortrait ? 88 : 150),",
           "compact true sign")

    topic_labels="\n".join("      "+repr(label)+"," for label in TOPIC_LABELS)
    icons="\n".join("      "+name+"," for name in TOPIC_ICON_NAMES)
    extra = """
/// QA illustrations: these are NOT certified Iraqi traffic signs.
class _DedaTrafficQuestionVisual extends StatelessWidget {
  final String questionId;
  final _TrafficVisual? verifiedSign;
  const _DedaTrafficQuestionVisual({
    required this.questionId,
    required this.verifiedSign,
  });

  @override
  Widget build(BuildContext context) {
    final n = int.tryParse(questionId.split('-').last) ?? 1;
    final topicIndex = ((n - 1) ~/ 25).clamp(0, 19);
    const topicLabels = <String>[
""" + topic_labels + """
    ];
    const topicIcons = <IconData>[
""" + icons + """
    ];
    // For these IDs the stock three-lamp icon was factually ambiguous.
    // Draw ONLY the relevant lit lamp or the actual stop-line concept.
    if (n == 80) {
      return const _DedaTrafficStopLineIllustration();
    }
    if (n == 76 || n == 77 || n == 78) {
      return _DedaTrafficPhaseIllustration(phase: n == 76 ? 0 : n == 78 ? 1 : 2);
    }
    if (verifiedSign != null) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('رسم العلامة المتعلقة بالسؤال',
            style: TextStyle(color: Color(0xFF0A4675),
              fontWeight: FontWeight.w800, fontSize: 12)),
        const SizedBox(height: 3),
        _TrafficSignCard(kind: verifiedSign!),
      ]);
    }
    // Category-matched educational icon, never labelled an official sign.
    return Container(
      width: double.infinity,
      height: 105,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: const Color(0xFFE0D3B4)),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(topicIcons[topicIndex],
          size: 47, color: const Color(0xFF126795)),
        const SizedBox(height: 3),
        Text(topicLabels[topicIndex], textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w800,
            color: Color(0xFF194267), fontSize: 12.5)),
        const Text('رمز توضيحي للموضوع وليس علامة مرور رسمية',
          style: TextStyle(fontSize: 9.5, color: Color(0xFF677687))),
      ]),
    );
  }
}

class _DedaTrafficPhaseIllustration extends StatelessWidget {
  final int phase; // 0 red, 1 amber, 2 green.
  const _DedaTrafficPhaseIllustration({required this.phase});

  @override
  Widget build(BuildContext context) {
    const colors = <Color>[
      Color(0xFFFF3636), Color(0xFFFFC02D), Color(0xFF20BD61),
    ];
    return Container(
      width: double.infinity, height: 125,
      decoration: BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: const Color(0xFFE0D3B4))),
      alignment: Alignment.center,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 53, height: 110,
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(color: const Color(0xFF232323),
            borderRadius: BorderRadius.circular(13)),
          child: Column(mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(3, (i) => Container(
              width: 27, height: 27,
              decoration: BoxDecoration(shape: BoxShape.circle,
                color: i == phase ? colors[i] : colors[i].withOpacity(0.14)),
            ))),
        ),
        const SizedBox(width: 14),
        const Text('الضوء الفعّال فقط\\nرسم تعليمي',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
            color: Color(0xFF194267))),
      ]),
    );
  }
}

class _DedaTrafficStopLineIllustration extends StatelessWidget {
  const _DedaTrafficStopLineIllustration();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity, height: 118,
      decoration: BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: const Color(0xFFE0D3B4))),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 170, height: 56,
          decoration: BoxDecoration(color: const Color(0xFF51575D),
            borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.center,
          child: Container(width: 145, height: 9, color: Colors.white)),
        const SizedBox(height: 5),
        const Text('خط التوقف قبل الإشارة • رسم تعليمي',
          style: TextStyle(fontSize: 11, color: Color(0xFF194267),
            fontWeight: FontWeight.w800)),
      ]),
    );
  }
}
"""
    if "_DedaTrafficQuestionVisual extends" in s:
        raise ValueError("100386 double visual widget binding")
    f.write_text(s+"\n"+extra)
    # 100385's one-time owner replay marker may already have been consumed
    # during yesterday's build review. Give the 100386 QA candidate its own
    # one-time same-day refresh; keep awards and ledger untouched.
    main_file=root/"lib/main.dart"
    main=main_file.read_text()
    main=once(main, "deda_100385_traffic_qa_once_",
                    "deda_100386_traffic_qa_once_",
                    "new owner-only QA cycle marker for this build")
    main_file.write_text(main)
    return {"qaBankCount": 500, "visibleAnswersPerQuestion":5,
            "topicIllustrationClasses":20, "specializedIllustrations":4,
            "productionClaims":False}
