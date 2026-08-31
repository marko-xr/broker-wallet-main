/// Professional Email Configuration
/// Update these values to match your brand and domain
class EmailConfig {
  // Brand Information
  static const String appName = "Broker Wallet";
  static const String companyName = "Broker Wallet";
  static const String tagline = "Your Professional Real Estate Toolkit";

  // Contact Information
  static const String supportEmail = "support@brokerwallet.com";
  static const String websiteUrl = "https://brokerwallet.com";
  static const String fromEmail = "noreply@brokerwallet.com";

  // App Configuration
  static const String iosBundleId = "com.brokerwallet.broker_wallet";
  static const String androidPackageName = "com.brokerwallet.broker_wallet";

  // Email Service Configuration
  // Choose your preferred email service:

  // Option 1: EmailJS (Free tier available, easy setup)
  static const String emailJSServiceId = "YOUR_EMAILJS_SERVICE_ID";
  static const String emailJSTemplateId = "YOUR_EMAILJS_TEMPLATE_ID";
  static const String emailJSPublicKey = "YOUR_EMAILJS_PUBLIC_KEY";

  // Option 2: SendGrid (More reliable, requires paid plan)
  static const String sendGridApiKey = "YOUR_SENDGRID_API_KEY";

  // Option 3: Mailgun (Alternative service)
  static const String mailgunApiKey = "YOUR_MAILGUN_API_KEY";
  static const String mailgunDomain = "YOUR_MAILGUN_DOMAIN";

  // Email Features
  static const List<EmailFeature> features = [
    EmailFeature(
      icon: "🏠",
      title: "Property Management",
      description: "Organize and track all your properties in one place",
    ),
    EmailFeature(
      icon: "👥",
      title: "Contact Management",
      description: "Keep track of clients, brokers, and property owners",
    ),
    EmailFeature(
      icon: "📄",
      title: "Document Tools",
      description: "PDF tools, scanner, and digital signatures",
    ),
    EmailFeature(
      icon: "📊",
      title: "Analytics & Reports",
      description: "Track your business performance and growth",
    ),
  ];

  // Social Media Links (optional)
  static const Map<String, String> socialLinks = {
    'facebook': 'https://facebook.com/brokerwallet',
    'instagram': 'https://instagram.com/brokerwallet',
    'twitter': 'https://twitter.com/brokerwallet',
    'linkedin': 'https://linkedin.com/company/brokerwallet',
  };

  // Email Settings
  static const Duration tokenExpiryDuration = Duration(hours: 24);
  static const bool enableClickTracking = false;
  static const bool enableOpenTracking = false;
}

class EmailFeature {
  final String icon;
  final String title;
  final String description;

  const EmailFeature({
    required this.icon,
    required this.title,
    required this.description,
  });
}

/// Email Service Provider Options
enum EmailProvider {
  firebase, // Basic Firebase emails (may go to spam)
  firebaseEnhanced, // Firebase with ActionCodeSettings
  emailJS, // EmailJS service (free tier)
  sendGrid, // SendGrid service (paid)
  mailgun, // Mailgun service (paid)
}

/// Email Template Styles
class EmailTheme {
  // Primary Colors
  static const String primaryColor = "#667eea";
  static const String secondaryColor = "#764ba2";
  static const String accentColor = "#3498db";

  // Background Colors
  static const String backgroundColor = "#f8f9fa";
  static const String cardBackground = "#ffffff";
  static const String footerBackground = "#2c3e50";

  // Text Colors
  static const String primaryText = "#333333";
  static const String secondaryText = "#555555";
  static const String lightText = "#95a5a6";

  // Button Styles
  static const String buttonRadius = "8px";
  static const String cardRadius = "12px";

  // Fonts
  static const String fontFamily =
      "'Segoe UI', Tahoma, Geneva, Verdana, sans-serif";
}
