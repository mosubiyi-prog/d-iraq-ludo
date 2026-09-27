import 'package:flutter/material.dart';

class DedaTeamPage extends StatelessWidget {
  const DedaTeamPage({super.key});

  static const Color _cream = Color(0xFFF8FAF2);
  static const Color _green = Color(0xFF17652F);

  static const List<_DedaTeamMember> _members = [
    _DedaTeamMember(
      role: 'المدقق والمراقب',
      name: 'امجد صالح',
      icon: Icons.fact_check_rounded,
      color: Color(0xFF2F73B9),
      softColor: Color(0xFFE7F1FB),
    ),
    _DedaTeamMember(
      role: 'المصمم التنفيذي',
      name: 'امير جاسم',
      icon: Icons.design_services_rounded,
      color: Color(0xFFE89A2F),
      softColor: Color(0xFFFFF1DC),
    ),
    _DedaTeamMember(
      role: 'الإداري الأول',
      name: 'حسين نجاح',
      icon: Icons.admin_panel_settings_rounded,
      color: Color(0xFF7759B8),
      softColor: Color(0xFFF0EBFB),
    ),
    _DedaTeamMember(
      role: 'المختبر الأول',
      name: 'ماجد حميد',
      icon: Icons.science_rounded,
      color: Color(0xFFC95757),
      softColor: Color(0xFFFBEAEA),
    ),
    _DedaTeamMember(
      role: 'المختبر الثاني',
      name: 'يونس ادريس',
      icon: Icons.biotech_rounded,
      color: Color(0xFF3B8996),
      softColor: Color(0xFFE5F4F6),
    ),
    _DedaTeamMember(
      role: 'منفذ الألوان',
      name: 'سكرتيرة هيام',
      icon: Icons.palette_rounded,
      color: Color(0xFF4B8F62),
      softColor: Color(0xFFE8F5EB),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _cream,
        appBar: AppBar(
          backgroundColor: Colors.white.withOpacity(0.96),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          title: const Text(
            'فريق تطبيق DEDA',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: Color(0xFF1F2A22),
            ),
          ),
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/deda_home_bg.jpg',
                fit: BoxFit.cover,
              ),
            ),
            Positioned.fill(
              child: ColoredBox(
                color: _cream.withOpacity(0.91),
              ),
            ),
            SafeArea(
              top: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final horizontalPadding =
                      constraints.maxWidth >= 700 ? 28.0 : 16.0;
                  return SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      18,
                      horizontalPadding,
                      30,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildIntro(),
                            const SizedBox(height: 14),
                            _buildManagerCard(),
                            const SizedBox(height: 14),
                            _buildMembersGrid(),
                            const SizedBox(height: 16),
                            const Text(
                              'معًا العراق أجمل',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF55715D),
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntro() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.90),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD6E4D7)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: const Row(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: Color(0xFFE1F0E2),
            child: Icon(
              Icons.groups_2_rounded,
              color: _green,
              size: 30,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'فريق DEDA',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF223127),
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'طاقم العمل الذي ساهم في تنفيذ ومراجعة واختبار التطبيق',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.35,
                    color: Color(0xFF607064),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManagerCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF17652F), Color(0xFF2F8148)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2A17652F),
            blurRadius: 22,
            offset: Offset(0, 9),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.38),
                width: 1.4,
              ),
            ),
            child: const Icon(
              Icons.engineering_rounded,
              color: Colors.white,
              size: 37,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'المدير والمنفذ للتطبيق',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    height: 1.2,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 11),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.94),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    'سالم حسن',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF17652F),
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const Icon(
            Icons.workspace_premium_rounded,
            color: Color(0xFFFFE7A6),
            size: 31,
          ),
        ],
      ),
    );
  }

  Widget _buildMembersGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final twoColumns = constraints.maxWidth >= 340;
        final cardWidth = twoColumns
            ? (constraints.maxWidth - gap) / 2
            : constraints.maxWidth;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: _members
              .map(
                (member) => SizedBox(
                  width: cardWidth,
                  child: _TeamMemberCard(member: member),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _TeamMemberCard extends StatelessWidget {
  final _DedaTeamMember member;

  const _TeamMemberCard({required this.member});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 214),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 13),
      decoration: BoxDecoration(
        color: member.softColor.withOpacity(0.97),
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: member.color.withOpacity(0.24)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                  color: member.color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: member.color.withOpacity(0.26),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  member.icon,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const Spacer(),
              Container(
                width: 41,
                height: 41,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.72),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.person_rounded,
                  color: member.color,
                  size: 25,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 54,
            child: Center(
              child: Text(
                member.role,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: member.color,
                  fontSize: 16.5,
                  height: 1.25,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(height: 11),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.92),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: member.color.withOpacity(0.12)),
            ),
            child: Text(
              member.name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: member.color,
                fontSize: 15.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DedaTeamMember {
  final String role;
  final String name;
  final IconData icon;
  final Color color;
  final Color softColor;

  const _DedaTeamMember({
    required this.role,
    required this.name,
    required this.icon,
    required this.color,
    required this.softColor,
  });
}
