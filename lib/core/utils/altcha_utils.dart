import 'dart:convert';
import 'package:crypto/crypto.dart';

/// ALTCHA challenge response from server.
/// The server sends `maxnumber` (upper bound), not `number`.
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
    return AltchaChallenge(
      algorithm: json['algorithm'] as String,
      challenge: json['challenge'] as String,
      salt: json['salt'] as String,
      signature: json['signature'] as String,
      maxnumber: json['maxNumber'] as int,
    );
  }
}

/// Utility to solve ALTCHA proof-of-work challenges.
class AltchaUtils {
  /// Solve the ALTCHA challenge by finding a `number` where
  /// SHA-256(salt + number) equals the challenge hex string.
  ///
  /// The salt is used as-is (including query params like `?expires=...&`);
  /// it is NOT base64-decoded. The hash input is simply the UTF-8 bytes of
  /// `salt + number.toString()`, matching the official altcha-lib-go impl.
  static Future<String> solveChallenge(AltchaChallenge challenge) async {
    for (var i = 0; i <= challenge.maxnumber; i++) {
      // Yield to event loop every 1000 iterations to keep UI responsive.
      if (i % 1000 == 0) {
        await Future.delayed(Duration.zero);
      }

      final payload = utf8.encode(challenge.salt + i.toString());
      final hash = sha256.convert(payload);
      final hashHex = hash.toString();

      // The correct number is the one where the hash EQUALS the challenge.
      if (hashHex == challenge.challenge) {
        // Found solution — build the payload exactly as ALTCHA expects.
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
