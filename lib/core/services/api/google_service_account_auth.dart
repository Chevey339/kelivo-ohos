import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:jose/jose.dart';

/// Minimal Service Account credentials parsed from a JSON string.
class GoogleServiceAccountCredentials {
  final String clientEmail;
  final String privateKey; // PKCS#8 PEM with header/footer
  final String tokenUri; // defaults to https://oauth2.googleapis.com/token
  final String? projectId; // optional; Vertex API path may need it

  GoogleServiceAccountCredentials({
    required this.clientEmail,
    required this.privateKey,
    required this.tokenUri,
    this.projectId,
  });

  static GoogleServiceAccountCredentials fromJsonString(String jsonStr) {
    final obj = json.decode(jsonStr) as Map<String, dynamic>;
    final email = (obj['client_email'] ?? '').toString();
    final key = (obj['private_key'] ?? '').toString();
    final uri = ((obj['token_uri'] ?? '') as String).isNotEmpty
        ? (obj['token_uri'] as String)
        : 'https://oauth2.googleapis.com/token';
    final proj = (obj['project_id'] as String?)?.trim();
    if (email.isEmpty || key.isEmpty) {
      throw ArgumentError('Invalid service account JSON: missing client_email/private_key');
    }
    return GoogleServiceAccountCredentials(
      clientEmail: email,
      privateKey: key,
      tokenUri: uri,
      projectId: proj,
    );
  }
}

class _CachedToken {
  final String token;
  final int expiresAt; // epoch seconds
  _CachedToken(this.token, this.expiresAt);
}

/// Exchanges a service account JWT for an OAuth2 access token and caches it in-memory.
class GoogleServiceAccountAuth {
  static final Map<String, _CachedToken> _cache = <String, _CachedToken>{};

  /// Returns an access token using a service account JSON string.
  /// Default scope is cloud-platform which covers Vertex AI.
  static Future<String> getAccessTokenFromJson(
    String serviceAccountJson, {
    List<String> scopes = const ['https://www.googleapis.com/auth/cloud-platform'],
  }) async {
    final creds = GoogleServiceAccountCredentials.fromJsonString(serviceAccountJson);
    return getAccessToken(creds, scopes: scopes);
  }

  static Future<String> getAccessToken(
    GoogleServiceAccountCredentials creds, {
    List<String> scopes = const ['https://www.googleapis.com/auth/cloud-platform'],
  }) async {
    final key = _cacheKey(creds.clientEmail, scopes, creds.tokenUri);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final cached = _cache[key];
    if (cached != null && cached.expiresAt > now + 300) {
      return cached.token;
    }

    final claims = <String, Object?>{
      'iss': creds.clientEmail,
      'scope': scopes.join(' '),
      'aud': creds.tokenUri,
      'iat': now,
      'exp': now + 3600, // max 1 hour
    };

    // Sign with RS256 using PEM private key
    final jwk = JsonWebKey.fromPem(creds.privateKey);
    final builder = JsonWebSignatureBuilder()
      ..jsonContent = claims
      ..addRecipient(jwk, algorithm: 'RS256')
      ..setProtectedHeader('typ', 'JWT');
    final jws = builder.build();
    final assertion = jws.toCompactSerialization();

    final res = await http.post(
      Uri.parse(creds.tokenUri),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        'assertion': assertion,
      },
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('Token endpoint ${res.statusCode}: ${res.body}');
    }
    final obj = json.decode(res.body) as Map<String, dynamic>;
    final token = (obj['access_token'] ?? '').toString();
    final expiresIn = (obj['expires_in'] is int)
        ? obj['expires_in'] as int
        : int.tryParse((obj['expires_in'] ?? '').toString()) ?? 3600;
    if (token.isEmpty) throw StateError('No access_token in response');
    _cache[key] = _CachedToken(token, now + expiresIn);
    return token;
  }

  static String _cacheKey(String email, List<String> scopes, String tokenUri) {
    final s = List<String>.from(scopes)..sort();
    return '$email|${s.join(',')}|$tokenUri';
  }
}
