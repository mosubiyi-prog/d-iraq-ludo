from pathlib import Path

path = Path("lib/main.dart")
text = path.read_text()


def replace_once(source: str, target: str, description: str) -> None:
    global text
    count = text.count(source)
    if count != 1:
        raise SystemExit(
            f"{description}: expected exactly one match, found {count}"
        )
    text = text.replace(source, target, 1)


old_phone = """                              ).copyWith(
                                prefixText: '+964  ',
                                prefixStyle: const TextStyle(
                                  color: Color(0xFF1F2D23),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
"""
new_phone = """                              ).copyWith(
                                prefix: DedaLanguageState.isArabic
                                    ? null
                                    : const Directionality(
                                        textDirection: TextDirection.ltr,
                                        child: Text(
                                          '+964  ',
                                          style: TextStyle(
                                            color: Color(0xFF1F2D23),
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                suffix: DedaLanguageState.isArabic
                                    ? const Directionality(
                                        textDirection: TextDirection.ltr,
                                        child: Text(
                                          '+964  ',
                                          style: TextStyle(
                                            color: Color(0xFF1F2D23),
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      )
                                    : null,
                              ),
"""
replace_once(old_phone, new_phone, "DEDA phone prefix patch")

owner_start = text.find(
    "class _OwnerPlacePageState extends State<OwnerPlacePage> {"
)
owner_end = text.find("\nclass DedaPersonalPlace {", owner_start)
if owner_start < 0 or owner_end < 0:
    raise SystemExit("Owner place section was not found")
owner = text[owner_start:owner_end]


def owner_replace(source: str, target: str, description: str) -> None:
    global owner
    count = owner.count(source)
    if count != 1:
        raise SystemExit(
            f"{description}: expected exactly one owner match, found {count}"
        )
    owner = owner.replace(source, target, 1)


owner_replace(
    "  static const String _draftKey = 'deda_owner_place_draft_v1';\n",
    "  static const String _draftKey = 'deda_owner_place_draft_v1';\n"
    "  static const String _availabilityKey = 'deda_owner_availability_v1';\n",
    "owner availability key patch",
)

owner_replace(
    """      }
    } catch (_) {
      // Keep the form usable even if an old draft cannot be decoded.
    }

    for (final controller in [
""",
    """      }

      final savedAvailability = prefs.getBool(_availabilityKey);
      if (savedAvailability != null) {
        _isAvailableNow = savedAvailability;
      }
    } catch (_) {
      // Keep the form usable even if an old draft cannot be decoded.
    }

    for (final controller in [
""",
    "owner availability load patch",
)

owner_replace(
    """  Future<void> _saveDraft() async {
""",
    """  Future<void> _setAvailabilityNow(bool value) async {
    if (_isAvailableNow == value) return;
    setState(() => _isAvailableNow = value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_availabilityKey, value);
    } catch (_) {
      // Keep the selection responsive even if local persistence fails.
    }
  }

  Future<void> _saveDraft() async {
""",
    "owner availability setter patch",
)

owner_replace(
    "onTap: () => setState(() => _isAvailableNow = true),",
    "onTap: () => _setAvailabilityNow(true),",
    "available-now tap patch",
)
owner_replace(
    "onTap: () => setState(() => _isAvailableNow = false),",
    "onTap: () => _setAvailabilityNow(false),",
    "not-available tap patch",
)

text = text[:owner_start] + owner + text[owner_end:]
path.write_text(text)

# Build 111+ uses the first-class team/permissions system and its central
# administrative audit log. Keep the legacy release-only admin-history patch
# disabled there; the owner-side fixes above still apply normally.
if Path("lib/admin_team_pages.dart").exists():
    print("DEDA admin team system detected; skipped legacy admin-history patch.")
    raise SystemExit(0)

# Keep the admin source stable in the repository and apply the release-only
# audit improvements in one controlled build step, just like the owner fix.
admin_path = Path("lib/admin_pages.dart")
admin_text = admin_path.read_text()


def admin_insert_before(marker: str, addition: str, description: str) -> None:
    global admin_text
    count = admin_text.count(marker)
    if count != 1:
        raise SystemExit(
            f"{description}: expected exactly one marker, found {count}"
        )
    admin_text = admin_text.replace(marker, addition + marker, 1)


def admin_replace_section(
    start_marker: str,
    end_marker: str,
    replacement: str,
    description: str,
) -> None:
    global admin_text
    start = admin_text.find(start_marker)
    if start < 0:
        raise SystemExit(f"{description}: start marker not found")
    end = admin_text.find(end_marker, start)
    if end < 0:
        raise SystemExit(f"{description}: end marker not found")
    admin_text = admin_text[:start] + replacement + admin_text[end:]


admin_helpers = r"""  int _timestampMillis(dynamic value) {
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is DateTime) return value.millisecondsSinceEpoch;
    if (value != null) {
      return DateTime.tryParse(value.toString())?.millisecondsSinceEpoch ?? 0;
    }
    return 0;
  }

  List<Map<String, dynamic>> _adminHistory(Map<String, dynamic> data) {
    final raw = data['adminHistory'];
    if (raw is! Map) return const <Map<String, dynamic>>[];

    final items = <Map<String, dynamic>>[];
    for (final value in raw.values) {
      if (value is Map) {
        items.add(Map<String, dynamic>.from(value));
      }
    }
    items.sort(
      (a, b) => _timestampMillis(a['at']).compareTo(_timestampMillis(b['at'])),
    );
    return items;
  }

  String _historyActionLabel(String action) {
    switch (action) {
      case 'approved':
        return t('تم الاعتماد بواسطة', 'Approved by');
      case 'rejected':
        return t('تم الرفض بواسطة', 'Rejected by');
      case 'returned_to_review':
        return t('أُعيد للمراجعة بواسطة', 'Returned to review by');
      case 'reviewing':
        return t('بدأت المراجعة بواسطة', 'Review started by');
      default:
        return t('إجراء إداري بواسطة', 'Administrative action by');
    }
  }

  Widget _historyEntry(Map<String, dynamic> event) {
    final action = _text(event['action']);
    final byName = _text(event['byName']);
    final byRole = _roleLabel(event['byRole']);
    final at = _formatTimestamp(event['at']);
    final note = _text(event['note']);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD8E1D6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _detailRow(
            _historyActionLabel(action),
            byName.isEmpty ? byRole : '$byRole • $byName',
          ),
          if (at.isNotEmpty)
            _detailRow(
              t('الوقت', 'Time'),
              at,
              ltr: true,
            ),
          if (note.isNotEmpty)
            _detailRow(
              t('الملاحظة', 'Note'),
              note,
            ),
        ],
      ),
    );
  }

"""
admin_insert_before(
    "  Widget _detailRow(String label, dynamic value, {bool ltr = false}) {\n",
    admin_helpers,
    "admin history helper patch",
)

new_audit_details = r"""  Widget _auditDetails(Map<String, dynamic> data) {
    final firstViewedAt = _formatTimestamp(data['firstViewedAt']);
    final firstViewedByName = _text(data['firstViewedByName']);
    final firstViewedByRole = _roleLabel(data['firstViewedByRole']);
    final status = _text(data['status']);
    final decisionAt = _formatTimestamp(data['decisionAt']);
    final hasLegacyDecision = decisionAt.isNotEmpty ||
        status == 'approved' ||
        status == 'rejected';
    final decisionByName = _text(data['decisionByName']);
    final decisionByRole = _roleLabel(data['decisionByRole']);
    final decisionNote = _text(data['decisionNote']);
    final history = _adminHistory(data);

    if (firstViewedAt.isEmpty && !hasLegacyDecision && history.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5EF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFC9D5C7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.verified_user_outlined,
                color: Color(0xFF17652F),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t('السجل الإداري', 'Administrative record'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (firstViewedAt.isNotEmpty) ...[
            _detailRow(
              t('أول مشاهدة بواسطة', 'First viewed by'),
              firstViewedByName.isEmpty
                  ? firstViewedByRole
                  : '$firstViewedByRole • $firstViewedByName',
            ),
            _detailRow(
              t('وقت أول مشاهدة', 'First viewed at'),
              firstViewedAt,
              ltr: true,
            ),
          ],
          if (history.isNotEmpty) ...[
            const Divider(height: 18),
            Text(
              t('سجل الإجراءات', 'Action history'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            for (final event in history) _historyEntry(event),
          ] else if (hasLegacyDecision) ...[
            _detailRow(
              status == 'rejected'
                  ? t('قرار الرفض', 'Rejection decision')
                  : t('الاعتماد الإلكتروني', 'Electronic approval'),
              decisionByName.isEmpty
                  ? decisionByRole
                  : '$decisionByRole • $decisionByName',
            ),
            if (decisionAt.isNotEmpty)
              _detailRow(
                t('وقت القرار', 'Decision time'),
                decisionAt,
                ltr: true,
              ),
            if (decisionNote.isNotEmpty)
              _detailRow(
                t('ملاحظة الإدارة', 'Admin note'),
                decisionNote,
              ),
          ],
        ],
      ),
    );
  }

"""
admin_replace_section(
    "  Widget _auditDetails(Map<String, dynamic> data) {",
    "  Future<void> _openMap({",
    new_audit_details,
    "admin audit panel patch",
)

append_history_method = r"""  Future<void> _appendAdminHistory({
    required String id,
    required String targetStatus,
    String? note,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final request = firestore.collection(widget.collection).doc(id);

    await firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(request);
      if (!snapshot.exists) return;
      final data = snapshot.data() ?? <String, dynamic>{};

      final rawHistory = data['adminHistory'];
      final history = <String, dynamic>{};
      if (rawHistory is Map) {
        for (final entry in rawHistory.entries) {
          history[entry.key.toString()] = entry.value;
        }
      }

      final previousDecision = _text(data['decisionAction']);
      final isDecision =
          targetStatus == 'approved' || targetStatus == 'rejected';
      final isReturnToReview = targetStatus == 'reviewing' &&
          (previousDecision == 'approved' || previousDecision == 'rejected');

      if (isReturnToReview && data['decisionAt'] != null) {
        final previousDecisionAt = _timestampMillis(data['decisionAt']);
        final alreadyStored = history.values.any((value) {
          if (value is! Map) return false;
          return _text(value['action']) == previousDecision &&
              _timestampMillis(value['at']) == previousDecisionAt;
        });

        if (!alreadyStored) {
          history['legacy_decision_$previousDecisionAt'] = <String, dynamic>{
            'action': previousDecision,
            'at': data['decisionAt'],
            'byUid': _text(data['decisionByUid']),
            'byName': _text(data['decisionByName']),
            'byRole': _text(data['decisionByRole']),
            'note': _text(data['decisionNote']),
          };
        }
      }

      final action = isReturnToReview ? 'returned_to_review' : targetStatus;
      final eventAt = isDecision ? data['decisionAt'] : data['updatedAt'];
      final eventByUid = isDecision ? data['decisionByUid'] : data['reviewedBy'];
      final eventByName =
          isDecision ? data['decisionByName'] : data['reviewedByName'];
      final eventByRole =
          isDecision ? data['decisionByRole'] : data['reviewedByRole'];
      final eventKey = 'event_${DateTime.now().microsecondsSinceEpoch}';

      history[eventKey] = <String, dynamic>{
        'action': action,
        'at': eventAt is Timestamp ? eventAt : Timestamp.now(),
        'byUid': _text(eventByUid),
        'byName': _text(eventByName),
        'byRole': _text(eventByRole),
        'note': note?.trim() ?? '',
      };

      transaction.update(request, <String, dynamic>{
        'adminHistory': history,
      });
    });
  }

"""
admin_insert_before(
    "  Future<void> _changeStatus({\n",
    append_history_method,
    "admin history writer patch",
)

old_status_update = r"""      await DedaBackend.updateRequestStatus(
        collection: widget.collection,
        id: id,
        status: status,
        note: note,
      );
      if (!mounted) return;
      setState(() => _expandedId = null);
"""
new_status_update = r"""      await DedaBackend.updateRequestStatus(
        collection: widget.collection,
        id: id,
        status: status,
        note: note,
      );

      try {
        await _appendAdminHistory(
          id: id,
          targetStatus: status,
          note: note,
        );
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                t(
                  'تم تحديث الحالة، لكن تعذر حفظ سجل الإجراء. حاول مرة أخرى قبل متابعة الطلب.',
                  'The status changed, but the action history could not be saved. Try again before continuing.',
                ),
              ),
            ),
          );
        }
      }

      if (!mounted) return;
      setState(() => _expandedId = null);
"""
status_count = admin_text.count(old_status_update)
if status_count != 1:
    raise SystemExit(
        f"admin status history hook: expected exactly one match, found {status_count}"
    )
admin_text = admin_text.replace(old_status_update, new_status_update, 1)

admin_path.write_text(admin_text)
