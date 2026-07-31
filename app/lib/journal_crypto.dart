// Encryption for the journal, so the notes are unreadable both to someone who
// opens todo.db directly and to anyone glancing at the screen (the low-key UI
// carries that second half).
//
// The model:
//
//   - A password the user sets. It is never stored. From it and a random salt
//     we derive a 256-bit key with PBKDF2-HMAC-SHA256; that key lives only in
//     memory, only while the journal is unlocked, and is dropped on lock and on
//     every app restart.
//   - Each entry's title and body are encrypted with AES-GCM under that key,
//     each with its own random nonce, and stored base64 in the ordinary text
//     columns. The database - and therefore the sync server, which only ever
//     stores and relays rows - sees ciphertext and nothing else.
//   - A `verifier` (a known constant encrypted at setup) lets us tell a correct
//     password from a wrong one without keeping the password around: the wrong
//     key fails AES-GCM's authentication tag.
//
// The salt and verifier are device-local settings (they live in `sync_state`,
// which is not synced). A second device therefore needs its own setup with the
// same password to read entries synced to it - the entries travel as ciphertext,
// but the key material to open them does not. That is the price of the server
// staying zero-knowledge, and it is a deliberate trade, not an oversight.
//
// Forgetting the password means the entries cannot be recovered. That is the
// point of encryption; it is surfaced plainly in the setup UI.

import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'sync/local_store.dart';

class JournalCrypto {
  JournalCrypto(this._store);

  final LocalStore _store;

  // Settings keys. Device-local, deliberately not synced.
  static const _kSalt = 'journal:salt';
  static const _kVerifier = 'journal:verifier';
  static const _kIters = 'journal:kdf-iters';

  /// PBKDF2 work factor. High enough to make guessing a weak password slow, low
  /// enough that one unlock is imperceptible. Stored per-vault so it can be
  /// raised later without stranding existing vaults.
  static const _defaultIters = 120000;

  /// The plaintext the verifier encrypts. Its only job is to be recognisable
  /// after a correct decrypt; the value is not secret.
  static const _verifierPlaintext = 'journal-vault-v1';

  final _aes = AesGcm.with256bits();

  /// The derived key, held only while unlocked. Null means locked.
  SecretKey? _key;

  bool _configured = false;

  /// Reads whether a vault has ever been set up on this device. Call once at
  /// startup, before the journal UI decides between "set a password" and
  /// "unlock".
  Future<void> load() async {
    _configured = (await _store.setting(_kSalt)) != null;
  }

  bool get isConfigured => _configured;

  bool get isUnlocked => _key != null;

  /// First-time setup: pick a salt, derive the key, store the verifier. Leaves
  /// the vault unlocked, since the user has just proven they know the password.
  Future<void> setup(String password) async {
    final salt = _randomBytes(16);
    const iters = _defaultIters;
    final key = await _deriveKey(password, salt, iters);
    final verifier = await _encryptWith(key, utf8.encode(_verifierPlaintext));

    await _store.setSetting(_kSalt, base64.encode(salt));
    await _store.setSetting(_kIters, '$iters');
    await _store.setSetting(_kVerifier, verifier);

    _key = key;
    _configured = true;
  }

  /// Verify [password] against the stored verifier and, if it matches, hold the
  /// derived key for the session. Returns false on a wrong password rather than
  /// throwing - a wrong password is an expected outcome, not an error.
  Future<bool> unlock(String password) async {
    final saltB64 = await _store.setting(_kSalt);
    final verifier = await _store.setting(_kVerifier);
    if (saltB64 == null || verifier == null) return false;

    final iters =
        int.tryParse(await _store.setting(_kIters) ?? '') ?? _defaultIters;
    final key = await _deriveKey(password, base64.decode(saltB64), iters);

    try {
      final plain = await _decryptWith(key, verifier);
      if (utf8.decode(plain) != _verifierPlaintext) return false;
    } catch (_) {
      // AES-GCM's tag check failed: the key, and therefore the password, is
      // wrong.
      return false;
    }

    _key = key;
    return true;
  }

  /// Drop the in-memory key. The vault stays configured; it just needs the
  /// password again to open.
  void lock() {
    _key = null;
  }

  /// Tear the vault down entirely: forget the salt and verifier so the journal
  /// is no longer password-protected. The caller is responsible for having
  /// decrypted every entry back to plaintext first - this only removes the key
  /// material, it does not touch the rows.
  Future<void> disable() async {
    await _store.clearSetting(_kSalt);
    await _store.clearSetting(_kVerifier);
    await _store.clearSetting(_kIters);
    _key = null;
    _configured = false;
  }

  Future<String> encrypt(String plaintext) async {
    final key = _requireKey();
    return _encryptWith(key, utf8.encode(plaintext));
  }

  Future<String> decrypt(String blob) async {
    final key = _requireKey();
    return utf8.decode(await _decryptWith(key, blob));
  }

  SecretKey _requireKey() {
    final key = _key;
    if (key == null) throw StateError('journal is locked');
    return key;
  }

  Future<SecretKey> _deriveKey(String password, List<int> salt, int iters) {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iters,
      bits: 256,
    );
    return pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
  }

  /// Pack nonce + ciphertext + tag into one base64 string, so an entry is a
  /// single self-contained blob in one column.
  Future<String> _encryptWith(SecretKey key, List<int> data) async {
    final box = await _aes.encrypt(data, secretKey: key);
    return base64.encode([...box.nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  Future<List<int>> _decryptWith(SecretKey key, String blob) async {
    final bytes = base64.decode(blob);
    final nonceLen = _aes.nonceLength; // 12 for AES-GCM
    const macLen = 16;
    final nonce = bytes.sublist(0, nonceLen);
    final mac = Mac(bytes.sublist(bytes.length - macLen));
    final cipher = bytes.sublist(nonceLen, bytes.length - macLen);
    return _aes.decrypt(
      SecretBox(cipher, nonce: nonce, mac: mac),
      secretKey: key,
    );
  }

  List<int> _randomBytes(int n) {
    final r = Random.secure();
    return List<int>.generate(n, (_) => r.nextInt(256));
  }
}
