import 'package:flutter/widgets.dart';

/// Mount a section only on its first visit, preserving its State thereafter.
/// No account/permission cache, network operation, timer or currency mutation.
class DedaLazySectionStack extends StatefulWidget {
  const DedaLazySectionStack({
    super.key,
    required this.index,
    required this.children,
    required this.enabled,
  }) : assert(index >= 0 && index < children.length);

  final int index;
  final List<Widget> children;
  final bool enabled;

  @override
  State<DedaLazySectionStack> createState() => _DedaLazySectionStackState();
}

class _DedaLazySectionStackState extends State<DedaLazySectionStack> {
  final Set<int> _visited = <int>{};

  void _visit() {
    _visited.removeWhere((index) => index >= widget.children.length);
    if (widget.enabled) {
      _visited.add(widget.index);
    } else {
      // Preserve all mounted sections if the review flag changes at runtime.
      _visited.addAll(List<int>.generate(widget.children.length, (i) => i));
    }
  }

  @override
  void initState() {
    super.initState();
    _visit();
  }

  @override
  void didUpdateWidget(covariant DedaLazySectionStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _visit();
  }

  @override
  Widget build(BuildContext context) => IndexedStack(
    index: widget.index,
    children: <Widget>[
      for (var i = 0; i < widget.children.length; i++)
        _visited.contains(i) ? widget.children[i] : const SizedBox.shrink(),
    ],
  );
}

/// Review opt-in; requires the exact-source --lazy-sections binding.
const dedaStabilityLazySections = bool.fromEnvironment(
  'DEDA_STABILITY_LAZY_SECTIONS', defaultValue: false,
);
