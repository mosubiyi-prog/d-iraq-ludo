import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Offline copy of DEDA's existing signed APK launcher icon (72×72).
/// The user can see the original application emblem in gift notifications,
/// rather than a generic gift icon or a network-dependent placeholder.
class DedaOfficialGiftLogo extends StatelessWidget {
  const DedaOfficialGiftLogo({super.key, this.size = 52});

  final double size;

  static final Uint8List _logoBytes = base64Decode(
    'UklGRkwFAABXRUJQVlA4IEAFAADQFwCdASpIAEgAPlEokEYjoqGhIooYcAoJZAC5zAlXS6Lk1vAx3Nur3gHvRehHeMd6Hl0OQp/oZqz/luNjS9Y2PPu+e/Ql9F+wT/Kf7B/zeBV/WsYVvMvxNuPrFXp/3JU9oH6Tq3vz3T2xtFG3C5JyCKGLiNWQnXf8Wf1nlDBTG4ZoP8RvVBX4VQBlXge5K5NY0zV2nfhmblf2vZkVvEOTtXPzO5O+q36ajeG2zoc9LIFsGjIxJ7wHkAi23f+PhgzRJDY2lAAAAP7/T//W3uWD/5KjgoIr8vCC7SKo3BCFHcppC/WijLkU3uofOyNRbr/4hdFLUaXEq72lb+25au+CxHTDiKd3JHOEtydKfaB4g3Ngf+fyjfXvNinSnhc04oD9UdN7Q1nQYY9F1SYKmK89hxxwxGcZD54qV5yiG2PRrX2hzz2ZXnR557AEPAKC1txMn45UHS9ICn/gubihInEBNBYQ3pQI1aTzRpc6n0dOfRj/wmh/G+NjHvNPBvyZPZIB3/nal0lwC0lpNK3dHzYF0FyOxDYu8Hdbw6R7Bk31+uNIyBK+e3kyBtxrmUXUlUbolfHud7lw161c28FM5tZqJ6V5HPjaUzNTk3tXBL5PbuEW7j55R/rQMT9hbzRq7dzx3DUof5he14xPoQ8fzDh219go+lo4yfOr4yf/FP95/JGX7oz+RhMPlgZILfjAQbsBRlZ/LsHqBo3Uq78gv5Vf+4RrF8cfzj/bXlO+bvMPuzeDSd96SBeEHoCfOz1exUVNzNUNUxKkK9IJRs345hCehbMmG4gnudP9xHUKsoMj/iNhFgoc9c+S0OfhTVl/XxjiTvKh9HmqmXi/qeumHNBho1emOZv8e2D4Fp2IGCq0D+toWt37FF/l4Oz3iFgZkL5Yc+hcYguP3pUIs6InjtTeTC5KHlP/MVXXCbYXJuNcvXb5RqoC2jGeJfG0cemq3oSrpOqu8E6sMzEHVuhSeF42nH9kBRaMmmo3FbbpvdzNM76VyCNfHzxlixRtw9u5xBBK3cF/TuKNB3XwO8BqhoBu8lVVxxgppwNmSItIxFG+QJD/QFweVuyS1HUXdrDp/T0a55R9+Qv+JrxP+i669N6hfLZJViHaG83wki5Lc8voaT/9VyJh41le152q63BXsvITvOXLmIRX4BzFtXNUo8iu6vuqwYqA/gf4DYOcM9s1yScYApuLgW+V0beM8ciID2hEEhZIt6JVpHUGPmFy4WRrxV4FOSD95pfzMEaAVWEqMQ7/Np2sHfm5uX1pRfDm4G1fdJXbTxl9Ybs0+3s5jUQ8LXbSZeV5c21JPVYzQV6Mmm7/wbXz/vF/t13T8f/lAFU3r8km828fMkd0kxehVFXjnhw95Hd9/NGM9fcla1JCCdc28ucwb39/29Z/bcsbdwWu/S28YTWIt3/+r+mqB/VlyQfjzWe6FKi9EAhL9AmUGYQHuHcIu9aNvzQt342bowZQfhU8lt/sBg3vC7A4Nfm8XROSB/ZECP4pTIt8EAfRnU+hMaaEIrXw+fX3GQcoQe6WrQ2oV9niX78aipX5f0qO9SlZYZv9t5HkO8rncSHV4Z2bFhG81+OYvRntIPzPdHQNW3EpORIiF3sq06+7WlKr1z9n/8L5cGgYwNcwUXh3FA9HqLguhn+88Ua0XvHr03sssohMS7lxDGNUXrfMrrzKiLcPCxpgbLWJVUnDjzb5kvyimMsHX9KNOPapnX5PPlyR8rUSF0np2E3JfQ8HZgx+M+t8Sa0vTypk5+6qQ09bQxhXr5EgR++agJ9AEa0QAAA=',
  );

  @override
  Widget build(BuildContext context) => Semantics(
        image: true,
        label: 'DEDA - الدليل الدقيق',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.23),
          child: Image.memory(
            _logoBytes,
            key: const Key('dedaOfficialGiftLogo'),
            width: size,
            height: size,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) => Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              color: const Color(0xFF075C39),
              child: const Text(
                'DEDA',
                style: TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w900, fontSize: 12),
              ),
            ),
          ),
        ),
      );
}
