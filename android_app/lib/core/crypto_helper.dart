// crypto_helper.dart for zero-knowledge decryption

import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';

class CryptoHelper {
  /// Derives a 32-byte key from a passphrase using SHA-256
  static Key deriveKey(String passphrase) {
    final bytes = utf8.encode(passphrase);
    final digest = sha256.convert(bytes);
    return Key(Uint8List.fromList(digest.bytes));
  }

  /// Derives a 32-character channel ID from a passphrase (useful for mapping relay mailboxes)
  static String deriveChannelId(String passphrase) {
    final bytes = utf8.encode(passphrase);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 32); // Return 32 hex chars
  }

  /// Decrypts a base64-encoded encrypted envelope containing:
  /// IV (12 bytes) + Ciphertext + Auth Tag (16 bytes)
  static String decryptPayload(String base64Payload, String passphrase) {
    try {
      final key = deriveKey(passphrase);
      final rawBytes = base64.decode(base64Payload);

      if (rawBytes.length < 28) {
        throw ArgumentError('Encrypted payload too short (must contain at least IV + Tag).');
      }

      // Extract 12-byte IV (nonce)
      final ivBytes = rawBytes.sublist(0, 12);
      // Extract remaining bytes (ciphertext + 16-byte auth tag)
      final cipherTextBytes = rawBytes.sublist(12);

      final encrypter = Encrypter(AES(key, mode: AESMode.gcm));
      
      // PointyCastle's AEAD Decrypter expects the IV and handles the tag at the end of ciphertext
      final decrypted = encrypter.decryptBytes(
        Encrypted(cipherTextBytes),
        iv: IV(ivBytes),
      );

      return utf8.decode(decrypted);
    } catch (e) {
      throw SecurityException('Decryption failed. Please verify your pairing key/passphrase: $e');
    }
  }
}

class SecurityException implements Exception {
  final String message;
  SecurityException(this.message);
  @override
  String toString() => message;
}
