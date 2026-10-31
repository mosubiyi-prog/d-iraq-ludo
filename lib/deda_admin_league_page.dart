import 'package:flutter/material.dart';

import 'deda_backend.dart';
import 'deda_admin_league_live_widgets.dart';
import 'deda_admin_league_control_widgets.dart';

/// Isolated management entry for a FUTURE real weekly league.
///
/// Access to this page is re-checked using the original administration
/// backend. All visible league information is explicitly a NON-LIVE
/// placeholder: no participants, points, balances or award transactions are
/// read/written and the launch/stop actions remain disabled until real
/// server-owned receipts, ranking and wallet settlement are audited.
class DedaAdminLeaguePage extends StatefulWidget {
  const DedaAdminLeaguePage({super.key, required this.isArabic});

  final bool isArabic;

  @override
  State<DedaAdminLeaguePage> createState() => _DedaAdminLeaguePageState();
}

class _DedaAdminLeaguePageState extends State<DedaAdminLeaguePage>
    with WidgetsBindingObserver {
  bool _checking = true;
  bool _allowed = false;
  int _accessRevision = 0;

  String t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAccess();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkAccess();
  }

  Future<void> _checkAccess() async {
    final revision = ++_accessRevision;
    if (mounted) setState(() => _checking = true);
    var permitted = false;
    try {
      final profile = await DedaBackend.currentAdminProfile(
        forceRefresh: true,
      );
      permitted = DedaBackend.normalizeAdminRole(profile['role']) ==
              'general_manager' &&
          DedaBackend.normalizeAdminStatus(profile) == 'active';
    } catch (_) {
      // No stale admin data is trusted if the backend cannot re-authorize.
    }
    if (!mounted || revision != _accessRevision) return;
    setState(() {
      _allowed = permitted;
      _checking = false;
    });
  }

  @override
  void dispose() {
    ++_accessRevision;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F9),
      appBar: AppBar(
        title: Text(t('إدارة الدوري', 'League administration')),
        actions: [
          IconButton(
            tooltip: t('تحقق من الصلاحية', 'Recheck permission'),
            onPressed: _checkAccess,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _checking
          ? const Center(child: CircularProgressIndicator())
          : !_allowed
              ? Center(
                  key: const Key('deda_league_admin_access_denied'),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      t('هذه البطاقة للمدير العام النشط فقط. تعذر تأكيد الصلاحية.',
                        'This page is only for the active general manager. '
                        'Permission could not be verified.'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : DedaAdminLeagueOverview(isArabic: widget.isArabic, liveDataEnabled: true),
    );
  }
}

/// Read-only QA surface. NOT a league management backend or a real data feed.
///
/// Keep actual controls disabled until the genuine DEDA original task +20 XP
/// issuer, server calendar, top-ten ranker, authenticated profile/friend
/// links, owned frames, earned-diamond wallet and admin-only rules exist.
class DedaAdminLeagueOverview extends StatelessWidget {
  const DedaAdminLeagueOverview({super.key, required this.isArabic, this.liveDataEnabled = false});

  final bool isArabic;
  final bool liveDataEnabled;

  String t(String ar, String en) => isArabic ? ar : en;

  static const Color navy = Color(0xFF10263F);
  static const Color gold = Color(0xFFB8903D);

  Widget _panel({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Card(
      color: Colors.white,
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFDDE2E8)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: navy),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: navy,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _notice(String message) {
    return Text(
      message,
      style: const TextStyle(height: 1.5, color: Color(0xFF536273)),
    );
  }

  Widget _prizeRow(String label, String diamonds) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            diamonds,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: navy,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('deda_league_admin_overview'),
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  key: const Key('deda_league_admin_private_status'),
                  padding: const EdgeInsets.all(17),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [navy, Color(0xFF1B3D5B)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.workspace_premium_outlined,
                          color: gold, size: 32),
                      const SizedBox(height: 9),
                      Text(
                        t('دوري DEDA — إدارة خاصة',
                          'DEDA League — private administration'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        liveDataEnabled
                          ? t('ترتيب الدوري مرتبط بقاعدة Firebase الحقيقية — الجوائز والتحكم قيد الإكمال',
                              'Live standings connected; rewards and controls not enabled yet')
                          : t('مرحلة اختبار — لم يُفعّل الدوري الحقيقي بعد',
                          'QA preview — real league not yet enabled'),
                        style: const TextStyle(
                          color: Color(0xFFFFDC9B),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 15),
                _panel(
                  icon: Icons.toggle_off_outlined,
                  title: t('التحكم بالدوري', 'League controls'),
                  child: liveDataEnabled
                    ? const DedaAdminLeagueControlPanel()
                    : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _notice(t(
                        'التشغيل والإيقاف مقفولان لحين اعتماد الحماية والربط بالخادم.',
                        'Start and stop are locked until backend security '
                        'and server verification are approved.',
                      )),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            key: const Key('deda_league_admin_start_disabled'),
                            onPressed: null,
                            icon: const Icon(Icons.play_arrow),
                            label: Text(t('تشغيل الدوري', 'Start league')),
                          ),
                          OutlinedButton.icon(
                            key: const Key('deda_league_admin_stop_disabled'),
                            onPressed: null,
                            icon: const Icon(Icons.pause_circle_outline),
                            label: Text(t('إيقاف الدوري', 'Stop league')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _panel(
                  icon: Icons.leaderboard_outlined,
                  title: t('المتصدرون العشرة', 'Top ten competitors'),
                  child: liveDataEnabled
                    ? DedaAdminLeagueLiveStandings(isArabic: isArabic)
                    : _notice(t(
                    'لا توجد نتائج خادم موثوقة للعرض. ستظهر المراكز 1–10 '
                    'ونقاط XP الأسبوعية بعد الربط الحقيقي، بدون أسماء تجريبية.',
                    'No trusted server standings yet. Ranks 1–10 and '
                    'weekly XP will appear only from the real backend.',
                  )), 
                ),
                _panel(
                  icon: Icons.emoji_events_outlined,
                  title: t('المراكز الثلاثة الأولى', 'Top three podium'),
                  child: liveDataEnabled
                    ? DedaAdminLeagueLivePodium(isArabic: isArabic)
                    : _notice(t(
                    'الذهبي والفضي والبرونزي سيُعرضون من ترتيب الأسبوع '
                    'المؤكد، وليس من بيانات هاتف المدير.',
                    'Gold, silver and bronze will come from verified '
                    'weekly standings, never the manager phone.',
                  )), 
                ),
                _panel(
                  icon: Icons.calendar_month_outlined,
                  title: t('السجل الأسبوعي والأرشيف الشهري',
                    'Weekly history and monthly archive'),
                  child: liveDataEnabled
                    ? DedaAdminLeagueLiveArchive(isArabic: isArabic)
                    : _notice(t(
                    'هيكل السجل الشهري خضع لاختبارات معزولة. الأرشيف '
                    'الحقيقي وصلاحية المدير العام للخادم ما زالا غير مربوطين.',
                    'The monthly archive model passed isolated tests. '
                    'Real history and server-enforced manager access '
                    'are not connected yet.',
                  )), 
                ),
                if (liveDataEnabled)
                  _panel(
                    icon: Icons.lock_clock_outlined,
                    title: t('مراجعة نقاط المستخدمين', 'Review participant XP'),
                    child: const DedaAdminLeagueFreezePanel(),
                  ),
                _panel(
                  icon: Icons.diamond_outlined,
                  title: t('خطة الجوائز الأسبوعية', 'Weekly prize plan'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _notice(t(
                        'قيم مقررة للأسبوع المكتمل فقط؛ لم تُصرف أي جوائز.',
                        'Planned rewards for a completed week only; '
                        'no rewards have been paid.',
                      )),
                      const SizedBox(height: 9),
                      _prizeRow(t('الأول', 'First'), t('150 ماسة', '150 diamonds')),
                      _prizeRow(t('الثاني', 'Second'), t('100 ماسة', '100 diamonds')),
                      _prizeRow(t('الثالث', 'Third'), t('50 ماسة', '50 diamonds')),
                      _prizeRow(t('من الرابع إلى العاشر • لكل واحد',
                        'Fourth through tenth • each'),
                        t('10 ماسات', '10 diamonds')),
                      const Divider(),
                      _prizeRow(t('إجمالي الأسبوع عند اكتمال 10 فائزين',
                        'Total per full 10-winner week'),
                        t('370 ماسة', '370 diamonds')),
                      const SizedBox(height: 7),
                      _notice(t(
                        'صرف الجوائز مقفول إلى أن يُربط برصيد الماسات '
                        'المكتسبة الحقيقي مع منع التكرار.',
                        'Payout is locked until an audited earned-diamond '
                        'wallet is connected with duplicate prevention.',
                      )),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
