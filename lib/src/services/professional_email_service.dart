import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ProfessionalEmailService {
  static const String _appName = "Realtig";
  static const String _companyName = "Realtig Real Estate";
  static const String _supportEmail = "support@realtig.com";
  static const String _websiteUrl = "https://realtig.com";

  /// Send professional email verification using Firebase with custom settings
  static Future<void> sendProfessionalVerificationEmail(User user) async {
    try {
      // For now, use basic email verification without custom ActionCodeSettings
      // This avoids domain allowlist issues during development

      await user.sendEmailVerification();

    
    } catch (e) {

      // Check for specific error types
      if (e.toString().contains('too-many-requests')) {
        throw 'Too many email requests. Please wait a few minutes before trying again.';
      } else if (e.toString().contains('unauthorized-domain')) {
        await user.sendEmailVerification();
      } else {
        throw e;
      }
    }
  }

  /// Send completely custom email verification using external service
  static Future<void> sendCustomVerificationEmail({
    required String toEmail,
    required String userName,
    required String verificationToken,
  }) async {
    try {
      // Create professional email template
      final emailTemplate = _createProfessionalEmailTemplate(
        userName: userName,
        verificationToken: verificationToken,
        toEmail: toEmail,
      );

      // Option 1: Use EmailJS (free tier available)
      await _sendViaEmailJS(
        toEmail: toEmail,
        subject: 'Welcome to $_appName - Verify Your Email',
        htmlContent: emailTemplate,
      );

    } catch (e) {
      throw 'Failed to send verification email';
    }
  }

  /// Create professional HTML email template
  static String _createProfessionalEmailTemplate({
    required String userName,
    required String verificationToken,
    required String toEmail,
  }) {
    final verificationUrl =
        'https://realtig.com/verify-email?token=$verificationToken&email=${Uri.encodeComponent(toEmail)}';

    return '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome to $_appName</title>
    <style>
        body {
            margin: 0;
            padding: 0;
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background-color: #f8f9fa;
            color: #333333;
        }
        .container {
            max-width: 600px;
            margin: 0 auto;
            background-color: #ffffff;
            border-radius: 12px;
            overflow: hidden;
            box-shadow: 0 4px 20px rgba(0, 0, 0, 0.1);
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 40px 20px;
            text-align: center;
            color: white;
        }
        .logo {
            font-size: 32px;
            font-weight: bold;
            margin-bottom: 10px;
        }
        .tagline {
            font-size: 16px;
            opacity: 0.9;
            margin: 0;
        }
        .content {
            padding: 40px 30px;
        }
        .welcome-text {
            font-size: 24px;
            font-weight: 600;
            color: #2c3e50;
            margin-bottom: 20px;
        }
        .message {
            font-size: 16px;
            line-height: 1.6;
            color: #555;
            margin-bottom: 30px;
        }
        .verify-button {
            display: inline-block;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 15px 30px;
            border-radius: 8px;
            text-decoration: none;
            font-weight: 600;
            font-size: 16px;
            text-align: center;
            margin: 20px 0;
            transition: transform 0.2s ease;
        }
        .verify-button:hover {
            transform: translateY(-2px);
        }
        .features {
            background-color: #f8f9fa;
            border-radius: 8px;
            padding: 25px;
            margin: 30px 0;
        }
        .feature-item {
            display: flex;
            align-items: center;
            margin-bottom: 15px;
        }
        .feature-icon {
            width: 24px;
            height: 24px;
            background-color: #667eea;
            border-radius: 50%;
            margin-right: 15px;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-weight: bold;
        }
        .footer {
            background-color: #2c3e50;
            color: #ecf0f1;
            padding: 30px;
            text-align: center;
        }
        .footer-links {
            margin: 20px 0;
        }
        .footer-link {
            color: #3498db;
            text-decoration: none;
            margin: 0 15px;
        }
        .social-links {
            margin: 20px 0;
        }
        .social-link {
            display: inline-block;
            margin: 0 10px;
            padding: 8px;
            background-color: #34495e;
            border-radius: 50%;
            color: white;
            text-decoration: none;
        }
        .disclaimer {
            font-size: 12px;
            color: #95a5a6;
            margin-top: 20px;
            line-height: 1.4;
        }
        @media (max-width: 600px) {
            .content {
                padding: 30px 20px;
            }
            .header {
                padding: 30px 20px;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <!-- Header -->
        <div class="header">
            <div class="logo">🏢 $_appName</div>
            <p class="tagline">Your Professional Real Estate Toolkit</p>
        </div>

        <!-- Main Content -->
        <div class="content">
            <h1 class="welcome-text">Welcome to $_appName, $userName! 🎉</h1>
            
            <p class="message">
                Thank you for joining $_companyName. We're excited to help you streamline your real estate business with our comprehensive toolkit.
            </p>

            <p class="message">
                To get started and secure your account, please verify your email address by clicking the button below:
            </p>

            <div style="text-align: center;">
                <a href="$verificationUrl" class="verify-button">
                    ✅ Verify My Email Address
                </a>
            </div>

            <div class="features">
                <h3 style="margin-top: 0; color: #2c3e50;">What you'll get with $_appName:</h3>
                
                <div class="feature-item">
                    <div class="feature-icon">🏠</div>
                    <div>
                        <strong>Property Management:</strong> Organize and track all your properties in one place
                    </div>
                </div>
                
                <div class="feature-item">
                    <div class="feature-icon">👥</div>
                    <div>
                        <strong>Contact Management:</strong> Keep track of clients, brokers, and property owners
                    </div>
                </div>
                
                <div class="feature-item">
                    <div class="feature-icon">📄</div>
                    <div>
                        <strong>Document Tools:</strong> PDF tools, scanner, and digital signatures
                    </div>
                </div>
                
                <div class="feature-item">
                    <div class="feature-icon">📊</div>
                    <div>
                        <strong>Analytics & Reports:</strong> Track your business performance and growth
                    </div>
                </div>
            </div>

            <p class="message">
                <strong>Security Note:</strong> This verification link will expire in 24 hours for your security. 
                If you didn't create this account, please ignore this email.
            </p>
        </div>

        <!-- Footer -->
        <div class="footer">
            <p><strong>$_companyName</strong></p>
            <p>Empowering Real Estate Professionals Worldwide</p>
            
            <div class="footer-links">
                <a href="$_websiteUrl" class="footer-link">Website</a>
                <a href="$_websiteUrl/support" class="footer-link">Support</a>
                <a href="$_websiteUrl/privacy" class="footer-link">Privacy Policy</a>
                <a href="$_websiteUrl/terms" class="footer-link">Terms of Service</a>
            </div>

            <div class="social-links">
                <a href="#" class="social-link">📘</a>
                <a href="#" class="social-link">📷</a>
                <a href="#" class="social-link">🐦</a>
                <a href="#" class="social-link">💼</a>
            </div>

            <div class="disclaimer">
                <p>This email was sent to $toEmail because you signed up for $_appName.</p>
                <p>© 2025 $_companyName. All rights reserved.</p>
                <p>If you no longer wish to receive emails from us, you can <a href="$_websiteUrl/unsubscribe" style="color: #3498db;">unsubscribe</a>.</p>
            </div>
        </div>
    </div>
</body>
</html>
''';
  }

  /// Send email via EmailJS (free service)
  static Future<void> _sendViaEmailJS({
    required String toEmail,
    required String subject,
    required String htmlContent,
  }) async {
    // You'll need to set up EmailJS account and get these values
    const serviceId = 'YOUR_EMAILJS_SERVICE_ID';
    const templateId = 'YOUR_EMAILJS_TEMPLATE_ID';
    const publicKey = 'YOUR_EMAILJS_PUBLIC_KEY';

    final url = Uri.parse('https://api.emailjs.com/api/v1.0/email/send');

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'service_id': serviceId,
        'template_id': templateId,
        'user_id': publicKey,
        'template_params': {
          'to_email': toEmail,
          'subject': subject,
          'html_content': htmlContent,
          'from_name': _appName,
          'reply_to': _supportEmail,
        },
      }),
    );

    if (response.statusCode == 200) {
    } else {
      throw 'Failed to send email: ${response.body}';
    }
  }

  /// Generate custom verification token
  static String generateVerificationToken(String email, String uid) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final data = '$email:$uid:$timestamp';
    // In production, use proper encryption/signing
    return base64Encode(utf8.encode(data));
  }

  /// Verify custom token
  static Map<String, String>? verifyToken(String token) {
    try {
      final decoded = utf8.decode(base64Decode(token));
      final parts = decoded.split(':');

      if (parts.length == 3) {
        final email = parts[0];
        final uid = parts[1];
        final timestamp = int.parse(parts[2]);

        // Check if token is not expired (24 hours)
        final now = DateTime.now().millisecondsSinceEpoch;
        final age = now - timestamp;
        final maxAge = 24 * 60 * 60 * 1000; // 24 hours in milliseconds

        if (age <= maxAge) {
          return {'email': email, 'uid': uid};
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
