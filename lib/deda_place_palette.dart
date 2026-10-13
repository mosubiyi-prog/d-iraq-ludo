import 'package:flutter/material.dart';

/// Exactly seven primary colors, each followed by a pastel variant.
class DedaPlacePalette {
  static const List<Color> colors = [
    Color(0xFFD83C46), Color(0xFFFAD7DB),
    Color(0xFF2075CD), Color(0xFFD8E9FF),
    Color(0xFF13824E), Color(0xFFD7F1E2),
    Color(0xFFE88722), Color(0xFFFFE7CC),
    Color(0xFF8045C9), Color(0xFFEADBFA),
    Color(0xFFCE9A22), Color(0xFFFAECC0),
    Color(0xFF009C9B), Color(0xFFCCF4EF),
  ];

  static int safeIndex(Object? raw) {
    final index = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
    return index == null || index < 0 || index >= colors.length ? 4 : index;
  }

  static Color forIndex(Object? index) => colors[safeIndex(index)];

  static Color foreground(int index) =>
      index.isOdd ? const Color(0xFF203326) : Colors.white;
}

class DedaPlaceColorChooser extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;
  const DedaPlaceColorChooser({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int column = 0; column < 7; column++)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final index in [column * 2, column * 2 + 1])
                Padding(
                  padding: const EdgeInsets.all(3),
                  child: Semantics(
                    label: 'لون المكان ' + (index + 1).toString(),
                    selected: selected == index,
                    button: true,
                    child: InkWell(
                      onTap: () => onChanged(index),
                      borderRadius: BorderRadius.circular(7),
                      child: Container(
                        width: 31,
                        height: 31,
                        decoration: BoxDecoration(
                          color: DedaPlacePalette.forIndex(index),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: selected == index
                                ? const Color(0xFF123C29)
                                : const Color(0xFFBFC9C0),
                            width: selected == index ? 2.5 : 1,
                          ),
                        ),
                        child: selected == index
                            ? Icon(Icons.check, size: 21,
                                color: DedaPlacePalette.foreground(index))
                            : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
