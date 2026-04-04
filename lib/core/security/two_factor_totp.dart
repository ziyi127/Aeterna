import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:aeterna/core/config/config_manager.dart';
import 'package:crypto/crypto.dart';

class TwoFactorTotp {
  static const String _base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  static String generateSecret({int length = 32}) {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.write(_base32Alphabet[random.nextInt(_base32Alphabet.length)]);
    }
    return buffer.toString();
  }

  static bool isValidSecret(String secret) {
    final normalized = _normalizeSecret(secret);
    if (normalized.length < 16) {
      return false;
    }
    return RegExp(r'^[A-Z2-7]+$').hasMatch(normalized);
  }

  static bool verifyCode({
    required String code,
    required List<TwoFactorEntry> factors,
    DateTime? at,
    int digits = 6,
    int periodSeconds = 30,
    int allowedSkewWindows = 1,
  }) {
    final normalizedCode = code.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(normalizedCode)) {
      return false;
    }
    final now = at ?? DateTime.now();
    final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
    final currentCounter = nowSeconds ~/ periodSeconds;

    for (final factor in factors) {
      for (var offset = -allowedSkewWindows; offset <= allowedSkewWindows; offset++) {
        final candidate = _generateForCounter(
          secret: factor.secret,
          counter: currentCounter + offset,
          digits: digits,
        );
        if (candidate == normalizedCode) {
          return true;
        }
      }
    }
    return false;
  }

  static String currentCode(
    String secret, {
    DateTime? at,
    int digits = 6,
    int periodSeconds = 30,
  }) {
    final now = at ?? DateTime.now();
    final counter = (now.millisecondsSinceEpoch ~/ 1000) ~/ periodSeconds;
    return _generateForCounter(secret: secret, counter: counter, digits: digits);
  }

  static String _generateForCounter({
    required String secret,
    required int counter,
    required int digits,
  }) {
    final key = _base32Decode(_normalizeSecret(secret));
    final counterBytes = ByteData(8)..setInt64(0, counter);
    final hash = Hmac(sha1, key).convert(counterBytes.buffer.asUint8List()).bytes;
    final offset = hash.last & 0x0F;

    final binary = ((hash[offset] & 0x7F) << 24) |
        ((hash[offset + 1] & 0xFF) << 16) |
        ((hash[offset + 2] & 0xFF) << 8) |
        (hash[offset + 3] & 0xFF);

    final mod = pow(10, digits).toInt();
    final otp = binary % mod;
    return otp.toString().padLeft(digits, '0');
  }

  static String _normalizeSecret(String secret) {
    return secret.toUpperCase().replaceAll(RegExp(r'[^A-Z2-7]'), '');
  }

  static Uint8List _base32Decode(String input) {
    if (input.isEmpty) {
      return Uint8List(0);
    }
    final cleaned = input.replaceAll('=', '');
    var bits = 0;
    var value = 0;
    final output = <int>[];

    for (final codeUnit in utf8.encode(cleaned)) {
      final ch = String.fromCharCode(codeUnit);
      final idx = _base32Alphabet.indexOf(ch);
      if (idx < 0) {
        continue;
      }
      value = (value << 5) | idx;
      bits += 5;
      if (bits >= 8) {
        output.add((value >> (bits - 8)) & 0xFF);
        bits -= 8;
      }
    }
    return Uint8List.fromList(output);
  }
}
