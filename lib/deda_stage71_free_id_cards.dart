import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart' show DedaPremiumIdCard, DedaPremiumIdCardColor;

/// DEDA Stage71: the four EXISTING original full-art ID-card designs are FREE.
/// This is a cosmetic selection only. It never grants an ID, modifies a wallet,
/// calls billing, or pretends to own any premium identifier.
class DedaStage71FreeCards {
  DedaStage71FreeCards._();

  static final RegExp originalIdPattern = RegExp(r'^@DEDA-[A-Z0-9]{6}$');
  static final Map<String, ValueNotifier<DedaPremiumIdCardColor?>> _states = {};
  static final Map<String, int> _versions = {};

  static String _key(String originalId) {
    if (!originalIdPattern.hasMatch(originalId)) {
      throw ArgumentError('verified-original-deda-id-format-required');
    }
    return 'deda_stage71_free_card_choice_v1_$originalId';
  }

  static ValueNotifier<DedaPremiumIdCardColor?> notifier(String originalId) {
    _key(originalId);
    return _states.putIfAbsent(
      originalId,
      () => ValueNotifier<DedaPremiumIdCardColor?>(null),
    );
  }

  static Future<void> restore(String originalId) async {
    final key = _key(originalId);
    final state = notifier(originalId);
    final previousVersion = _versions[originalId] ?? 0;
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(key);
    if ((_versions[originalId] ?? 0) != previousVersion) return;
    for (final color in DedaPremiumIdCardColor.values) {
      if (color.name == value) {
        state.value = color;
        return;
      }
    }
    state.value = null;
  }

  static Future<void> use(
    String originalId, DedaPremiumIdCardColor choice,
  ) async {
    final key = _key(originalId);
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(key, choice.name);
    if (!saved) throw StateError('could-not-save-free-card');
    _versions[originalId] = (_versions[originalId] ?? 0) + 1;
    notifier(originalId).value = choice;
  }

  // Explicit account teardown for UI observers. Stored preference is retained,
  // like existing free avatar/frame choices, for the SAME original ID only.
  static void clearView(String originalId) {
    if (!originalIdPattern.hasMatch(originalId)) return;
    _versions[originalId] = (_versions[originalId] ?? 0) + 1;
    _states[originalId]?.value = null;
  }
}

/// Store action. Free from first install, so show Use / In use; NEVER Buy.
class DedaStage71FreeCardAction extends StatefulWidget {
  final String originalId;
  final DedaPremiumIdCardColor color;
  const DedaStage71FreeCardAction({
    super.key, required this.originalId, required this.color,
  });

  @override
  State<DedaStage71FreeCardAction> createState() =>
      _DedaStage71FreeCardActionState();
}

class _DedaStage71FreeCardActionState extends State<DedaStage71FreeCardAction> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void didUpdateWidget(covariant DedaStage71FreeCardAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.originalId != widget.originalId) _restore();
  }

  Future<void> _restore() async {
    try {
      await DedaStage71FreeCards.restore(widget.originalId);
    } catch (_) {
      // Invalid/unavailable local choice does not impact any existing wallet.
    }
  }

  Future<void> _use() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await DedaStage71FreeCards.use(widget.originalId, widget.color);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تعذّر حفظ البطاقة المجانية. حاول مرة ثانية.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<DedaPremiumIdCardColor?>(
        valueListenable: DedaStage71FreeCards.notifier(widget.originalId),
        builder: (context, active, child) => SizedBox(
          height: 34,
          child: OutlinedButton(
            key: ValueKey<String>('deda_stage71_free_card_use_${widget.color.name}'),
            onPressed: _busy || active == widget.color ? null : _use,
            child: Text(
              active == widget.color ? 'مستخدمة حاليًا' : 'استخدام مجاني',
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ),
      );
}

/// Keep original ID and its Copy callback. Only the decorative foil changes.
class DedaStage71FreeProfileFoil extends StatefulWidget {
  final String originalId;
  final VoidCallback onCopy;
  final Widget fallback;
  const DedaStage71FreeProfileFoil({
    super.key, required this.originalId, required this.onCopy,
    required this.fallback,
  });

  @override
  State<DedaStage71FreeProfileFoil> createState() =>
      _DedaStage71FreeProfileFoilState();
}

class _DedaStage71FreeProfileFoilState
    extends State<DedaStage71FreeProfileFoil> {
  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void didUpdateWidget(covariant DedaStage71FreeProfileFoil oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.originalId != widget.originalId) _restore();
  }

  Future<void> _restore() async {
    try {
      await DedaStage71FreeCards.restore(widget.originalId);
    } catch (_) {
      // Fall back to the original verified profile widget.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!DedaStage71FreeCards.originalIdPattern.hasMatch(widget.originalId)) {
      return widget.fallback;
    }
    return ValueListenableBuilder<DedaPremiumIdCardColor?>(
      valueListenable: DedaStage71FreeCards.notifier(widget.originalId),
      builder: (context, color, child) => color == null
          ? widget.fallback
          : GestureDetector(
              key: const Key('deda_stage71_profile_free_foil'),
              onTap: widget.onCopy,
              child: DedaPremiumIdCard(
                identifier: widget.originalId,
                color: color,
                height: 50,
              ),
            ),
    );
  }
}
