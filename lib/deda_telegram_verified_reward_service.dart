import 'package:cloud_functions/cloud_functions.dart';

/// Server-trusted Telegram identity flow. The client NEVER chooses a Telegram
/// user ID, modifies a wallet or claims a bonus by opening a URL.
///
/// On the future fully deployed build, the server returns a one-use bot
/// deep link. Telegram proves identity in a secret-verified private /start
/// webhook; a separate callable checks membership and atomically credits the
/// existing spendable personal gifted-diamond wallet.
class DedaTelegramVerifiedRewardService {
  const DedaTelegramVerifiedRewardService();

  Future<Map<String, dynamic>> beginTelegramLink() async {
    final response = await FirebaseFunctions.instance
        .httpsCallable('dedaStartTelegramVerification')
        .call(<String, dynamic>{});
    return _result(response.data);
  }

  Future<Map<String, dynamic>> claimAfterMembershipCheck() async {
    final response = await FirebaseFunctions.instance
        .httpsCallable('dedaClaimVerifiedTelegramFollow')
        .call(<String, dynamic>{});
    return _result(response.data);
  }

  static Map<String, dynamic> _result(dynamic value) {
    if (value is! Map) {
      throw const FormatException('deda-telegram-invalid-server-response');
    }
    return value.map((key, value) => MapEntry('$key', value));
  }
}
