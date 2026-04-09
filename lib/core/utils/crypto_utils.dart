import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:crypto/crypto.dart';

/// AES-256 加密工具类
/// 使用家庭ID派生密钥，确保同一家庭ID在不同设备上能正确加解密
class CryptoUtils {
  CryptoUtils._();

  static const String _salt = String.fromEnvironment('CRYPTO_SALT', defaultValue: 'FamilyFinance_DefaultSalt_ChangeMeInProd');

  /// 从 familyId 派生 AES-256 密钥（32字节）
  static encrypt.Key deriveKey(String familyId) {
    final hash = sha256.convert(utf8.encode('$familyId$_salt'));
    return encrypt.Key.fromBase64(base64.encode(hash.bytes.sublist(0, 32)));
  }

  /// 从 familyId 派生 IV（16字节）
  static encrypt.IV deriveIV(String familyId) {
    final hash = sha256.convert(utf8.encode('${_salt}_iv_$familyId'));
    return encrypt.IV.fromBase64(base64.encode(hash.bytes.sublist(0, 16)));
  }

  /// 加密 JSON 字符串为 Base64
  static String encryptData(String plainText, String familyId) {
    final key = deriveKey(familyId);
    final iv = deriveIV(familyId);
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    return encrypted.base64;
  }

  /// 解密 Base64 为 JSON 字符串
  static String decryptData(String encryptedBase64, String familyId) {
    final key = deriveKey(familyId);
    final iv = deriveIV(familyId);
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
    return encrypter.decrypt64(encryptedBase64, iv: iv);
  }

  /// 密码哈希（SHA-256 + salt），用于云端存储和验证
  static String hashPassword(String password, String familyId) {
    final combined = '$familyId:$password:$_salt';
    return sha256.convert(utf8.encode(combined)).toString();
  }

  /// 验证密码
  static bool verifyPassword(String password, String familyId, String storedHash) {
    return hashPassword(password, familyId) == storedHash;
  }
}
