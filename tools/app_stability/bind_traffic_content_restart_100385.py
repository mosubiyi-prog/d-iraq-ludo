"""DEDA 100385: remove answers from sign prompts and one-time owner QA task reset.

Runs after 100384. Preserves all wallet awards, ledger entries, account
data and other tasks. Only the QA APK can enable reset, with verified GM role.
"""
from pathlib import Path


def one(s, old, new, label):
    n = s.count(old)
    if n != 1:
        raise ValueError(f"100385 {label}: expected one anchor; found {n}")
    return s.replace(old, new, 1)


SIGN_PROMPTS = {
    "0001": "ما التصرف الصحيح عند رؤية هذه العلامة على مدخل الشارع؟",
    "0002": "ما التصرف المطلوب من السائق عند رؤية هذه اللوحة؟",
    "0003": "كيف يتعامل السائق مع حركة المركبات عند هذه العلامة؟",
    "0004": "ما القاعدة التي يجب مراعاتها عند رؤية هذه العلامة؟",
    "0005": "ما الذي تمنعه العلامة الموضحة في الصورة؟",
    "0006": "ما الذي تمنعه العلامة الموضحة في الصورة؟",
    "0007": "ما الاتجاه الذي تفرضه هذه العلامة على السائق؟",
    "0015": "ما السلوك الذي تحدده هذه العلامة؟",
    "0018": "ما الاستخدام الذي تشير إليه هذه اللوحة؟",
    "0020": "كيف يجب السير وفق اللوحة الظاهرة؟",
    "0026": "ما الاحتياط المناسب عند الاقتراب من هذا التحذير؟",
    "0027": "ما الاحتياط المناسب عند رؤية هذه العلامة التحذيرية؟",
    "0028": "ما التصرف الآمن المطلوب عند رؤية هذا التحذير؟",
    "0029": "ما الخطر الذي ينبغي الانتباه إليه بعد هذه العلامة؟",
    "0030": "كيف تقود بأمان بعد رؤية هذه العلامة التحذيرية؟",
    "0032": "كيف تستعد للطريق عند رؤية هذا التحذير؟",
    "0052": "ما المكان الذي تشير إليه هذه اللوحة؟",
    "0076": "عندما يضيء المصباح الأحمر الثابت في إشارة المرور، ما التصرف الآمن؟",
    "0077": "عندما يضيء المصباح الأخضر في الإشارة، متى يجوز العبور؟",
    "0078": "إذا كان الضوء الأصفر ثابتاً ويمكن التوقف بأمان، فما الإجراء الصحيح؟",
    "0080": "ما الغرض من الخط الأبيض المرسوم قبل إشارة المرور؟",
    "0103": "إذا كان التقاطع خالياً ورأيت هذه اللوحة، فما الإجراء الصحيح؟",
    "0108": "ما السلوك المناسب عند تقاطع منظم بهذه اللوحات من جميع الجهات؟",
}
LEGACY_SEMANTIC_IDS = {
    "sign_no_entry": "0001", "sign_stop": "0002", "sign_yield": "0003",
    "sign_speed_60": "0004", "sign_no_parking": "0005",
    "sign_no_stopping": "0006", "sign_turn_right": "0007",
    "sign_horn_prohibited": "0015", "sign_bicycle_path": "0018",
    "sign_one_way": "0020", "sign_bend_right": "0026",
    "sign_slippery": "0027", "sign_pedestrian_crossing": "0028",
    "sign_school": "0029", "sign_road_works": "0030",
    "sign_crossroad": "0032", "sign_parking": "0052",
    "sign_traffic_light": "0076",
}


def dart_string(s):
    return "'" + s.replace("\\", "\\\\").replace("'", "\\'") + "'"


def bind(root):
    root = Path(root)
    quiz_file = root / "lib/traffic_quiz_page.dart"
    q = quiz_file.read_text()
    mapping = "\n".join(
        "  'DEDA-TRF-" + key + "': " + dart_string(prompt) + ","
        for key, prompt in SIGN_PROMPTS.items()
    )
    q = one(q, """      questionAr: question,
      questionEn: question, // Arabic-only candidate; not an English release.""",
            """      questionAr: _dedaReviewedSignQuestion[id] ?? question,
      questionEn: question, // Arabic-only candidate; not an English release.""",
            "no answer leaks in pictorial question")
    q += ("\n// Human-reviewed sign question display; all 500 bank items retained.\n"
          "const Map<String, String> _dedaReviewedSignQuestion = <String, String>{\n"
          + mapping + "\n};\n")
    legacy = "\n".join(
        "        " + dart_string(old) + ": " +
        dart_string("DEDA-TRF-" + new) + ","
        for old, new in LEGACY_SEMANTIC_IDS.items()
    )
    q = one(q, "      final seen = priorIds.where(byId.containsKey).toSet();",
            """      const legacyEquivalent = <String, String>{
""" + legacy + """
      };
      final seen = <String>{
        for (final oldId in priorIds)
          if (byId.containsKey(oldId)) oldId
          else if (legacyEquivalent.containsKey(_trafficBaseQuestionId(oldId)))
            legacyEquivalent[_trafficBaseQuestionId(oldId)]!,
      };""", "honor legacy answers with same subject")
    q = one(q, "'إعادة فحص الأسئلة دون نقاط'", "'إعادة حل الأسئلة'",
            "remove misleading QA word")
    q = one(q, "'Replay quiz without points'", "'Replay questions'",
            "replay English button")
    quiz_file.write_text(q)

    main_file = root / "lib/main.dart"
    m = main_file.read_text()
    reset = """  /// Owner-QA one-time restart: only today's traffic completion resets.
  /// Earned points, original award IDs and every other task stay unchanged.
  static Future<bool> qaRestartTrafficOnlyOnce() async {
    const ownerQa = bool.fromEnvironment(
        'DEDA_TRAFFIC_QA_REPLAY', defaultValue: false);
    if (!ownerQa) return false;
    final accountKey = _accountKey();
    if (accountKey.isEmpty) return false;
    final permitted = await DedaBackend.currentDedaAccountIsGeneralManager(
      phone: DedaPreferences.phone,
    );
    if (!permitted) return false;
    final cycle = currentLocalCycleId();
    final prefs = await SharedPreferences.getInstance();
    final marker = 'deda_100385_traffic_qa_once_' + accountKey + '_' + cycle;
    if (prefs.getBool(marker) ?? false) return false;
    final state = await _readState(prefs, accountKey);
    final completions = Map<String, dynamic>.from(
      state['completions'] as Map);
    final key = cycle + '|' + DedaTaskIds.trafficSkills;
    if (!completions.containsKey(key)) return false;
    final safeAccount = accountKey.replaceAll(
      RegExp(r'[^A-Za-z0-9]'), '_');
    final suffix = safeAccount + '_' + cycle;
    await DedaPrivateDataBridge.write(
        prefs, 'deda_traffic_quiz_progress_v1_' + suffix, '');
    await DedaPrivateDataBridge.write(
        prefs, 'deda_traffic_quiz_daily_ids_v1_' + suffix, <String>[]);
    await DedaPrivateDataBridge.write(
        prefs, 'deda_traffic_quiz_completed_v1_' + suffix, false);
    completions.remove(key);
    state['completions'] = completions;
    await _writeState(prefs, accountKey, state);
    await prefs.setBool(marker, true);
    revisionNotifier.value++;
    return true;
  }

"""
    m = one(m, "  static Future<bool> isTaskCompleted(\n",
            reset + "  static Future<bool> isTaskCompleted(\n",
            "QA reset method")
    m = one(m, """      case 6:
        final alreadyCompleted = await DedaTaskEngine.isTaskCompleted(
          DedaTaskIds.trafficSkills,
        );""",
            """      case 6:
        // First QA revisit after daily completion starts a fresh normal quiz.
        await DedaTaskEngine.qaRestartTrafficOnlyOnce();
        final alreadyCompleted = await DedaTaskEngine.isTaskCompleted(
          DedaTaskIds.trafficSkills,
        );""",
            "open real fresh task")
    m = one(m, """                label: trafficQaReplay
                    ? dedaText('فحص', 'Review')""",
            """                label: trafficQaReplay
                    ? dedaText('إعادة', 'Retry')""",
            "correct task label")
    main_file.write_text(m)
    return {"editedVisualQuestions": len(SIGN_PROMPTS),
            "historicIdsBridged": len(LEGACY_SEMANTIC_IDS),
            "financialAwardsCleared": False,
            "otherTasksReset": False}
