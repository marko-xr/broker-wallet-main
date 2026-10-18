import 'dart:convert';
import 'dart:typed_data';

/// A throwaway self-signed certificate (CN "Broker Wallet Test Only") made for
/// these tests only. It protects nothing and is trusted by nothing; it exists
/// so a test can produce a PDF that carries a real digital signature.
const String testCertificatePassword = 'testonly';

Uint8List testCertificateBytes() => base64Decode(_pfxBase64);

const String _pfxBase64 =
    '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';
