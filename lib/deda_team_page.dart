import 'package:flutter/material.dart';

class DedaTeamPage extends StatelessWidget {
  const DedaTeamPage({super.key});

  static const Color _cream = Color(0xFFF8FAF2);
  static const Color _green = Color(0xFF17652F);

  static const List<_DedaTeamMember> _members = [
    _DedaTeamMember(
      number: 1,
      role: 'المدير والمنفذ للتطبيق',
      name: 'سالم حسن',
      icon: Icons.engineering_rounded,
      avatarIcon: Icons.face_6_rounded,
      color: Color(0xFF188848),
      darkColor: Color(0xFF106A37),
      softColor: Color(0xFFE9F6EC),
    ),
    _DedaTeamMember(
      number: 2,
      role: 'المدقق والمراقب',
      name: 'امجد صالح',
      icon: Icons.fact_check_rounded,
      avatarIcon: Icons.face_rounded,
      color: Color(0xFF2F8FE5),
      darkColor: Color(0xFF216EB5),
      softColor: Color(0xFFEAF4FE),
    ),
    _DedaTeamMember(
      number: 3,
      role: 'المصمم التنفيذي',
      name: 'امير جاسم',
      icon: Icons.design_services_rounded,
      avatarIcon: Icons.face_2_rounded,
      color: Color(0xFFF2A21F),
      darkColor: Color(0xFFD48300),
      softColor: Color(0xFFFFF4DF),
    ),
    _DedaTeamMember(
      number: 4,
      role: 'الإداري الأول',
      name: 'حسين نجاح',
      icon: Icons.admin_panel_settings_rounded,
      avatarIcon: Icons.face_4_rounded,
      color: Color(0xFF8453D6),
      darkColor: Color(0xFF6439AD),
      softColor: Color(0xFFF2ECFC),
    ),
    _DedaTeamMember(
      number: 5,
      role: 'المختبر الأول',
      name: 'ماجد حميد',
      icon: Icons.science_rounded,
      avatarIcon: Icons.face_3_rounded,
      color: Color(0xFFE64B4F),
      darkColor: Color(0xFFB83135),
      softColor: Color(0xFFFDEBEC),
    ),
    _DedaTeamMember(
      number: 6,
      role: 'المختبر الثاني',
      name: 'يونس ادريس',
      icon: Icons.biotech_rounded,
      avatarIcon: Icons.face_5_rounded,
      color: Color(0xFF22A9C7),
      darkColor: Color(0xFF16849D),
      softColor: Color(0xFFE7F7FB),
    ),
    _DedaTeamMember(
      number: 7,
      role: 'منفذ الألوان',
      name: 'سكرتيرة هيام',
      icon: Icons.palette_rounded,
      avatarIcon: Icons.face_3_rounded,
      color: Color(0xFF45A844),
      darkColor: Color(0xFF337F33),
      softColor: Color(0xFFEBF7EA),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _cream,
        appBar: AppBar(
          backgroundColor: Colors.white.withOpacity(0.97),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          title: const Text(
            'فريق DEDA',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: Color(0xFF1F2A22),
              fontSize: 25,
            ),
          ),
          actions: const [
            Padding(
              padding: EdgeInsetsDirectional.only(end: 14),
              child: Icon(
                Icons.groups_2_rounded,
                color: _green,
                size: 30,
              ),
            ),
          ],
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
                color: _cream.withOpacity(0.88),
              ),
            ),
            SafeArea(
              top: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final horizontalPadding =
                      constraints.maxWidth >= 700 ? 28.0 : 12.0;
                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      14,
                      horizontalPadding,
                      30,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 780),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 11,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.91),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFFD9E5DA),
                                ),
                              ),
                              child: const Text(
                                'معًا نصنع تجربة أفضل لمدينة أجمل',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF5D685F),
                                  fontSize: 15,
                                  height: 1.3,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 13),
                            ..._members.map(
                              (member) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _TeamRowCard(member: member),
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'معًا العراق أجمل',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF55715D),
                                fontWeight: FontWeight.w900,
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
}

class _TeamRowCard extends StatelessWidget {
  final _DedaTeamMember member;

  const _TeamRowCard({required this.member});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 380;

    return Container(
      constraints: BoxConstraints(
        minHeight: compact ? 126 : 138,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [member.color, member.darkColor],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: Colors.white.withOpacity(0.82),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: member.darkColor.withOpacity(0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Container(
            width: compact ? 49 : 56,
            constraints: const BoxConstraints(minHeight: 138),
            alignment: Alignment.center,
            color: Colors.black.withOpacity(0.09),
            child: Text(
              '${member.number}',
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 34 : 40,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          SizedBox(width: compact ? 8 : 11),
          _AvatarBadge(
            member: member,
            compact: compact,
          ),
          SizedBox(width: compact ? 8 : 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(
                vertical: compact ? 12 : 14,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    member.role,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 16.5 : 19,
                      height: 1.18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: compact ? 10 : 12),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 9 : 12,
                      vertical: compact ? 8 : 9,
                    ),
                    decoration: BoxDecoration(
                      color: member.softColor.withOpacity(0.97),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.75),
                      ),
                    ),
                    child: Text(
                      member.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: const Color(0xFF183725),
                        fontSize: compact ? 15 : 16.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(width: compact ? 7 : 10),
          Container(
            width: compact ? 48 : 56,
            height: compact ? 48 : 56,
            margin: EdgeInsetsDirectional.only(
              end: compact ? 9 : 12,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.12),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.20),
              ),
            ),
            child: Icon(
              member.icon,
              color: Colors.white,
              size: compact ? 27 : 31,
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarBadge extends StatelessWidget {
  final _DedaTeamMember member;
  final bool compact;

  const _AvatarBadge({
    required this.member,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final size = compact ? 64.0 : 75.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: member.softColor,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white,
          width: 3,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            member.avatarIcon,
            color: member.darkColor,
            size: compact ? 42 : 49,
          ),
          Positioned(
            bottom: compact ? 2 : 4,
            right: compact ? 1 : 3,
            child: Container(
              width: compact ? 23 : 27,
              height: compact ? 23 : 27,
              decoration: BoxDecoration(
                color: member.darkColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 1.5,
                ),
              ),
              child: Icon(
                member.icon,
                color: Colors.white,
                size: compact ? 13 : 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DedaTeamMember {
  final int number;
  final String role;
  final String name;
  final IconData icon;
  final IconData avatarIcon;
  final Color color;
  final Color darkColor;
  final Color softColor;

  const _DedaTeamMember({
    required this.number,
    required this.role,
    required this.name,
    required this.icon,
    required this.avatarIcon,
    required this.color,
    required this.darkColor,
    required this.softColor,
  });
}
