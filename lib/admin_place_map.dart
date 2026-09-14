import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class DedaAdminPlaceMapPage extends StatefulWidget {
  final bool isArabic;
  final double latitude;
  final double longitude;
  final String placeName;

  const DedaAdminPlaceMapPage({
    super.key,
    required this.isArabic,
    required this.latitude,
    required this.longitude,
    required this.placeName,
  });

  @override
  State<DedaAdminPlaceMapPage> createState() => _DedaAdminPlaceMapPageState();
}

class _DedaAdminPlaceMapPageState extends State<DedaAdminPlaceMapPage> {
  bool _opening = false;
  String? _error;

  String t(String ar, String en) => widget.isArabic ? ar : en;

  Uri get _googleMapsUri => Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${widget.latitude},${widget.longitude}',
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openGoogleMaps());
  }

  Future<void> _openGoogleMaps() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });

    try {
      final opened = await launchUrl(
        _googleMapsUri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        setState(() {
          _error = t(
            'تعذر فتح خرائط Google على هذا الهاتف.',
            'Could not open Google Maps on this device.',
          );
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = t(
            'تعذر فتح خرائط Google على هذا الهاتف.',
            'Could not open Google Maps on this device.',
          );
        });
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final placeLabel = widget.placeName.trim().isEmpty
        ? t('موقع المكان المطلوب', 'Requested place location')
        : widget.placeName.trim();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: Text(t('موقع الطلب - DEDA', 'Request location - DEDA')),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.map_outlined,
                    size: 72,
                    color: Color(0xFF17652F),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    placeLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      '${widget.latitude.toStringAsFixed(6)}, ${widget.longitude.toStringAsFixed(6)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    t(
                      'يتم فتح الإحداثيات نفسها التي أرسلها صاحب المكان مباشرة في خرائط Google للمراجعة.',
                      'The exact coordinates submitted by the place owner are opened directly in Google Maps for review.',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF5A655D),
                      height: 1.45,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: _opening ? null : _openGoogleMaps,
                    icon: _opening
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.open_in_new),
                    label: Text(
                      _opening
                          ? t('جاري فتح خرائط Google...', 'Opening Google Maps...')
                          : t('فتح في خرائط Google', 'Open in Google Maps'),
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      backgroundColor: const Color(0xFF17652F),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                    label: Text(t('العودة إلى المراجعة', 'Back to review')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
