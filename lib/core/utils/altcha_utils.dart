import 'dart:convert';
import 'package:crypto/crypto.dart';

class AltchaChallenge {
  final String algorithm;
  final String challenge;
  final String salt;
  final String signature;
  final int maxnumber;

  AltchaChallenge({
    required this.algorithm,
    required this.challenge,
    required this.salt,
    required this.signature,
    required this.maxnumber,
  });

  factory AltchaChallenge.fromJson(Map<String, dynamic> json) {
    final rawMaxNumber = json['maxNumber'] ?? json['maxnumber'];

    final maxNumberInt = rawMaxNumber is int
        ? rawMaxNumber
        : rawMaxNumber is num
        ? rawMaxNumber.toInt()
        : int.tryParse(rawMaxNumber?.toString() ?? '') ?? 0;

    return AltchaChallenge(
      algorithm: (json['algorithm'] ?? '').toString(),
      challenge: (json['challenge'] ?? '').toString(),
      salt: (json['salt'] ?? '').toString(),
      signature: (json['signature'] ?? '').toString(),
      maxnumber: maxNumberInt,
    );
  }
}

/// Utility to solve ALTCHA proof-of-work challenges.
class AltchaUtils {
  static Future<String> solveChallenge(AltchaChallenge challenge) async {
    for (var i = 0; i <= challenge.maxnumber; i++) {
      if (i % 1000 == 0) {
        await Future.delayed(Duration.zero);
      }

      final payload = utf8.encode(challenge.salt + i.toString());
      final hash = sha256.convert(payload);
      final hashHex = hash.toString();

      if (hashHex == challenge.challenge) {
        final solution = {
          'algorithm': challenge.algorithm,
          'challenge': challenge.challenge,
          'number': i,
          'salt': challenge.salt,
          'signature': challenge.signature,
        };
        final jsonStr = jsonEncode(solution);
        final base64Str = base64Encode(utf8.encode(jsonStr));
        return base64Str;
      }
    }

    throw Exception('Failed to solve ALTCHA challenge within maxnumber limit');
  }
}
