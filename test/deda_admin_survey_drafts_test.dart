import 'package:d_iraq_ludo/deda_admin_survey_drafts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const mapRating = DedaSurveyQuestion(
    type: 'rating_5',
    promptAr: 'ما رأيك باستخدام خارطة DEDA؟',
    promptEn: 'What do you think about the DEDA map?',
  );
  const tasksRating = DedaSurveyQuestion(
    type: 'rating_5',
    promptAr: 'ما رأيك بالمهام اليومية؟',
    promptEn: 'What do you think about daily tasks?',
  );
  const trafficRating = DedaSurveyQuestion(
    type: 'rating_5',
    promptAr: 'ما رأيك بالأسئلة المرورية؟',
    promptEn: 'What do you think about traffic quizzes?',
  );

  const survey = DedaAdminSurveyDraft(
    titleAr: 'آراء مستخدمي DEDA',
    titleEn: 'DEDA user opinions',
    questions: [mapRating, tasksRating, trafficRating],
  );

  test('Example survey supports all three requested questions', () {
    final data = survey.toEditableMap();
    expect(data['questions'], hasLength(3));
    expect(data['status'], 'draft');
    expect(data['rewardUnit'], 'none');
    expect(data['rewardAmount'], 0);
    expect(data['rewardPolicy'],
        'once_per_account_on_verified_submission');
    expect(data.keys, isNot(contains('published')));
    expect(data.keys, isNot(contains('userUid')));
    expect(data.keys, isNot(contains('claimReward')));
    expect(data.keys, isNot(contains('userAnswer')));
    expect(data.keys, isNot(contains('userLocation')));
  });

  test('Survey may mix rating, choices and a free-text suggestion', () {
    const response = DedaAdminSurveyDraft(
      titleAr: 'تحسينات تطبيق DEDA',
      titleEn: 'Improve the DEDA app',
      questions: [
        mapRating,
        DedaSurveyQuestion(
          type: 'choice',
          promptAr: 'شنو أكثر شي تحتاج تطويره؟',
          promptEn: 'What most needs improvement?',
          optionsAr: ['الخارطة', 'المهام', 'الاختبارات'],
          optionsEn: ['Map', 'Tasks', 'Quizzes'],
        ),
        DedaSurveyQuestion(
          type: 'text',
          promptAr: 'شنو اقتراحك القادم؟',
          promptEn: 'What would you suggest next?',
          required: false,
        ),
      ],
    );
    final questions = response.toEditableMap()['questions'] as List;
    expect(questions, hasLength(3));
    expect((questions[1] as Map)['optionsAr'], hasLength(3));
    expect((questions[2] as Map)['required'], false);
  });

  test('Optional reward settings never make a survey payable or published', () {
    const points = DedaAdminSurveyDraft(
      titleAr: 'رأيك يهمنا',
      titleEn: 'Your opinion matters',
      questions: [tasksRating],
      rewardUnit: 'points',
      rewardAmount: 25,
    );
    final data = points.toEditableMap();
    expect(data['status'], 'draft');
    expect(data['rewardUnit'], 'points');
    expect(data['rewardAmount'], 25);
    expect(data['rewardPolicy'],
        'once_per_account_on_verified_submission');
    expect(data.keys, isNot(contains('claimAvailable')));
  });

  test('One survey completion can define arbitrary coin or diamond amounts', () {
    for (final kind in ['coins', 'diamonds']) {
      final draft = DedaAdminSurveyDraft(
        titleAr: 'ملاحظات مستخدمي ديدا',
        titleEn: 'ملاحظات مستخدمي ديدا',
        questions: const [
          DedaSurveyQuestion(
            type: 'rating_5',
            promptAr: 'ما رأيك بالخارطة؟',
            promptEn: 'ما رأيك بالخارطة؟',
          ),
        ],
        rewardUnit: kind,
        rewardAmount: 15000,
      );
      final saved = draft.toEditableMap();
      expect(saved['rewardUnit'], kind);
      expect(saved['rewardAmount'], 15000);
      expect(saved['rewardPolicy'],
          'once_per_account_on_verified_submission');
      expect(saved['status'], 'draft');
      expect(saved.keys, isNot(contains('claimAvailable')));
      expect(saved.keys, isNot(contains('userAnswer')));
    }
  });

  test('Legacy points drafts stay editable but no client payout is possible', () {
    const draft = DedaAdminSurveyDraft(
      titleAr: 'ملاحظات على الخدمات',
      titleEn: 'Old draft title',
      questions: [mapRating],
      rewardUnit: 'points',
      rewardAmount: 25,
    );
    expect(draft.toEditableMap()['rewardUnit'], 'points');
    expect(draft.toEditableMap()['status'], 'draft');
  });

  test('Question prompts, unsupported types and answer options checked', () {
    final problems = [
      const DedaSurveyQuestion(
        type: 'unknown',
        promptAr: 'سؤال مقبول',
        promptEn: 'Valid question',
      ),
      const DedaSurveyQuestion(
        type: 'rating_5',
        promptAr: 'ما رأيك؟',
        promptEn: 'How do you rate this?',
        optionsAr: ['oops'],
      ),
      const DedaSurveyQuestion(
        type: 'choice',
        promptAr: 'ما رأيك؟',
        promptEn: 'How do you rate this?',
        optionsAr: ['نعم', 'لا'],
        optionsEn: ['Yes'],
      ),
      const DedaSurveyQuestion(
        type: 'choice',
        promptAr: 'ما رأيك؟',
        promptEn: 'How do you rate this?',
        optionsAr: ['نعم'],
        optionsEn: ['Yes'],
      ),
      const DedaSurveyQuestion(
        type: 'text',
        promptAr: 'لا',
        promptEn: 'Your thoughts?',
      ),
    ];
    for (final question in problems) {
      expect(() => question.validate(), throwsArgumentError);
    }
  });

  test('Bound to one through six questions; no unlimited fields', () {
    final missing = DedaAdminSurveyDraft(
      titleAr: survey.titleAr,
      titleEn: survey.titleEn,
      questions: const [],
    );
    final tooMany = DedaAdminSurveyDraft(
      titleAr: survey.titleAr,
      titleEn: survey.titleEn,
      questions: List<DedaSurveyQuestion>.filled(7, mapRating),
    );
    expect(() => missing.validate(), throwsArgumentError);
    expect(() => tooMany.validate(), throwsArgumentError);
  });

  test('Reject invalid award amount, timing and inconsistent no-reward mode', () {
    for (final amount in [-1, 1000001]) {
      final bad = DedaAdminSurveyDraft(
        titleAr: survey.titleAr,
        titleEn: survey.titleEn,
        questions: const [mapRating],
        rewardUnit: 'points',
        rewardAmount: amount,
      );
      expect(() => bad.validate(), throwsArgumentError);
    }
    expect(
      () => const DedaAdminSurveyDraft(
        titleAr: 'مهم رأيك جدًا',
        titleEn: 'Your opinion matters',
        questions: [mapRating],
        rewardUnit: 'none',
        rewardAmount: 50,
      ).validate(),
      throwsArgumentError,
    );
    expect(
      () => const DedaAdminSurveyDraft(
        titleAr: 'مهم رأيك جدًا',
        titleEn: 'Your opinion matters',
        questions: [mapRating],
        durationDays: 91,
      ).validate(),
      throwsArgumentError,
    );
  });

  test('Question roundtrip does not change answer type, values or order', () {
    const q = DedaSurveyQuestion(
      type: 'choice',
      promptAr: 'شنو الأفضل؟',
      promptEn: 'Which is better?',
      optionsAr: ['الخارطة', 'المهام'],
      optionsEn: ['Maps', 'Tasks'],
      required: false,
    );
    final clone = DedaSurveyQuestion.fromMap(q.toMap());
    expect(clone.type, 'choice');
    expect(clone.optionsAr, ['الخارطة', 'المهام']);
    expect(clone.optionsEn, ['Maps', 'Tasks']);
    expect(clone.required, false);
  });
}
