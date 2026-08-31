import 'dart:io';
import 'package:broker_wallet/src/Views/Screens/home/quotation/quotation_model.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class PdfGenerationService {
  // Font cache to avoid loading fonts multiple times
  static late final pw.Font _arabicFont;
  static late final pw.Font _arabicBoldFont;
  static late final pw.Font _latinFont;
  static late final pw.Font _latinBoldFont;

  // Load fonts from assets
  static Future<void> _loadFonts() async {
    // Load static Arabic fonts (more reliable for PDF than variable fonts)
    final arabicFontData = await rootBundle.load(
        'assets/fonts/Noto_Naskh_Arabic/static/NotoNaskhArabic-Regular.ttf');
    _arabicFont = pw.Font.ttf(arabicFontData);

    final arabicBoldFontData = await rootBundle
        .load('assets/fonts/Noto_Naskh_Arabic/static/NotoNaskhArabic-Bold.ttf');
    _arabicBoldFont = pw.Font.ttf(arabicBoldFontData);

    // Load static Latin fonts for fallback
    final latinFontData = await rootBundle
        .load('assets/fonts/Noto_Sans/static/NotoSans-Regular.ttf');
    _latinFont = pw.Font.ttf(latinFontData);

    final latinBoldFontData = await rootBundle
        .load('assets/fonts/Noto_Sans/static/NotoSans-Bold.ttf');
    _latinBoldFont = pw.Font.ttf(latinBoldFontData);
  }

  // Get appropriate font based on locale and style
  static pw.Font _getFont(Locale? locale, bool isBold) {
    if (locale?.languageCode == 'ar') {
      return isBold ? _arabicBoldFont : _arabicFont;
    } else {
      return isBold ? _latinBoldFont : _latinFont;
    }
  }

  // Create TextStyle with proper font for locale
  static pw.TextStyle _createTextStyle({
    double fontSize = 12,
    bool isBold = false,
    PdfColor? color,
    Locale? locale,
    double? lineSpacing,
  }) {
    return pw.TextStyle(
      fontSize: fontSize,
      fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: color ?? PdfColors.black,
      font: _getFont(locale, isBold),
      lineSpacing: lineSpacing,
    );
  }

  // Date formatting helper
  static String _formatDate(String? dateString, Locale locale) {
    if (dateString == null || dateString.isEmpty) {
      return locale.languageCode == 'ar' ? 'غير محدد' : 'Not specified';
    }

    try {
      // Try to parse the date if it's in a specific format
      DateTime? date;

      // Try different date formats
      List<DateFormat> formats = [
        DateFormat('yyyy-MM-dd'),
        DateFormat('dd/MM/yyyy'),
        DateFormat('MM/dd/yyyy'),
        DateFormat('dd-MM-yyyy'),
        DateFormat('yyyy/MM/dd'),
      ];

      for (DateFormat format in formats) {
        try {
          date = format.parse(dateString);
          break;
        } catch (e) {
          continue;
        }
      }

      if (date != null) {
        // Always format in English numbers for consistency in PDFs
        return DateFormat('dd/MM/yyyy', 'en').format(date);
      } else {
        // If parsing fails, return the original string
        return dateString;
      }
    } catch (e) {
      // If any error occurs, return the original string
      return dateString;
    }
  }

  // Helper function to ensure numbers stay in English format
  static String _formatNumber(dynamic number) {
    if (number == null) return '';
    // Convert any Arabic-Indic numerals to standard Latin numerals
    return number.toString().replaceAllMapped(
      RegExp(r'[٠-٩]'),
      (match) {
        const arabicToLatin = {
          '٠': '0',
          '١': '1',
          '٢': '2',
          '٣': '3',
          '٤': '4',
          '٥': '5',
          '٦': '6',
          '٧': '7',
          '٨': '8',
          '٩': '9'
        };
        return arabicToLatin[match.group(0)] ?? match.group(0)!;
      },
    );
  }

  // Helper function for properly aligned section titles
  static pw.Widget _sectionTitle(String text, bool isRtl, {Locale? locale}) {
    return pw.Container(
      width: double.infinity,
      child: pw.Text(
        text,
        textAlign: isRtl ? pw.TextAlign.right : pw.TextAlign.left,
        textDirection: isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        style: _createTextStyle(
          fontSize: 16,
          isBold: true,
          locale: locale,
        ),
      ),
    );
  }

  static Future<String> generateQuotationPdf(QuotationModel quotation,
      {Locale? locale}) async {
    final pdf = pw.Document();

    // Load fonts first
    await _loadFonts();

    // Load localization strings
    final localizedStrings =
        await _loadLocalizedStrings(locale ?? const Locale('en'));

    // Determine if this is RTL language
    final isRtl = locale?.languageCode == 'ar';

    // Load logo if available
    pw.ImageProvider? logoImage;
    if (quotation.officeLogoUrl != null &&
        quotation.officeLogoUrl!.isNotEmpty) {
      try {
        logoImage = await _loadImageFromUrl(quotation.officeLogoUrl!);
      } catch (e) {
        // Continue without logo
      }
    }

    // Create PDF content with theme-based font handling
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        theme: pw.ThemeData.withFont(
          base: isRtl ? _arabicFont : _latinFont,
          bold: isRtl ? _arabicBoldFont : _latinBoldFont,
        ),
        build: (pw.Context context) {
          final content = _buildAllContent(
              quotation, logoImage, localizedStrings, isRtl, locale);

          // If the whole page is Arabic, wrap in Directionality
          if (isRtl) {
            return [
              pw.Directionality(
                textDirection: pw.TextDirection.rtl,
                child: pw.Column(children: content),
              ),
            ];
          } else {
            return [pw.Column(children: content)];
          }
        },
        footer: (pw.Context context) {
          return pw.Container(
            width: double.infinity,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                // Left side: Office name
                pw.Text(
                  quotation.officeName.trim().isNotEmpty
                      ? quotation.officeName.trim()
                      : '',
                  style: _createTextStyle(
                    fontSize: 10,
                    color: PdfColors.grey600,
                    locale: locale,
                  ),
                  textAlign: isRtl ? pw.TextAlign.right : pw.TextAlign.left,
                  textDirection:
                      isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
                ),
                // Right side: Page numbers
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: _createTextStyle(
                    fontSize: 10,
                    color: PdfColors.grey600,
                    locale: locale,
                  ),
                  textAlign: isRtl ? pw.TextAlign.left : pw.TextAlign.right,
                  textDirection:
                      isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
                ),
              ],
            ),
          );
        },
      ),
    );

    // Save PDF locally first
    final output = await getApplicationDocumentsDirectory();
    final fileName =
        'quotation_${quotation.id ?? DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File('${output.path}/$fileName');
    await file.writeAsBytes(await pdf.save());

    return file.path;
  }

  // Extract all content building logic into a separate method
  static List<pw.Widget> _buildAllContent(
    QuotationModel quotation,
    pw.ImageProvider? logoImage,
    Map<String, String> localizedStrings,
    bool isRtl,
    Locale? locale,
  ) {
    return [
      // Header with logo
      _buildHeader(quotation, logoImage, localizedStrings, isRtl, locale),
      pw.SizedBox(height: 15),

      // Welcome message (conditionally include)
      ...(() {
        final welcomeWidget =
            _buildWelcomeMessage(quotation, localizedStrings, locale);
        if (welcomeWidget != null) {
          return [welcomeWidget, pw.SizedBox(height: 20)];
        } else {
          return <pw.Widget>[]; // Empty list if welcome is hidden
        }
      })(),

      // Property details section
      _buildPropertyDetailsSection(quotation, localizedStrings, isRtl, locale),

      // Financial details section
      if (quotation.totalAmount != null ||
          quotation.professionalFee != null ||
          quotation.numberOfInstallments != null)
        _buildFinancialDetailsSection(
            quotation, localizedStrings, isRtl, locale),

      // Downpayments section
      if (quotation.downpayments.isNotEmpty)
        _buildDownpaymentsSection(quotation, localizedStrings, isRtl, locale),

      // Government fees section
      if (_hasGovernmentFees(quotation.governmentFees))
        _buildGovernmentFeesCompleteSection(
            quotation, localizedStrings, isRtl, locale),

      // Administrative fees section
      if (_hasAdministrativeFees(quotation.administrativeFees))
        _buildAdministrativeFeesCompleteSection(
            quotation, localizedStrings, isRtl, locale),

      // Additional notes section
      if (quotation.customNote != null && quotation.customNote!.isNotEmpty)
        _buildAdditionalNotesSection(
            quotation, localizedStrings, isRtl, locale),
    ];
  }

  static pw.Widget _buildHeader(
      QuotationModel quotation,
      pw.ImageProvider? logoImage,
      Map<String, String> localizedStrings,
      bool isRtl,
      Locale? locale) {
    return pw.Column(
      children: [
        // Logo centered at top
        if (logoImage != null) ...[
          pw.Center(
            child: pw.Container(
              height: 80,
              width: 80,
              child: pw.Image(logoImage, fit: pw.BoxFit.contain),
            ),
          ),
          pw.SizedBox(height: 12), // Space after logo
        ],

        // Row containing quotation title, office name, and date
        pw.Container(
          width: double.infinity,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // Left side: Quotation title (or right side in RTL)
              pw.Expanded(
                flex: 2,
                child: pw.Text(
                  localizedStrings['quotation']?.toUpperCase() ??
                      (isRtl ? 'عرض السعر' : 'QUOTATION'),
                  style: _createTextStyle(
                    fontSize: 20,
                    isBold: true,
                    color: PdfColors.blue800,
                    locale: locale,
                  ),
                  textAlign: isRtl ? pw.TextAlign.right : pw.TextAlign.left,
                ),
              ),

              // Center: Office name (below the logo)
              if (quotation.officeName.trim().isNotEmpty)
                pw.Expanded(
                  flex: 3,
                  child: pw.Center(
                    child: pw.Text(
                      quotation.officeName.trim(),
                      style: _createTextStyle(
                        fontSize: 20,
                        isBold: true,
                        locale: locale,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                )
              else
                pw.Expanded(
                    flex: 3,
                    child: pw.SizedBox()), // Empty space if no office name

              // Right side: Date (or left side in RTL)
              pw.Expanded(
                flex: 2,
                child: pw.Text(
                  '${localizedStrings['date'] ?? (isRtl ? 'التاريخ' : 'Date')}: ${_formatDate(quotation.date, locale ?? const Locale('en'))}',
                  style: _createTextStyle(fontSize: 12, locale: locale),
                  textAlign: isRtl ? pw.TextAlign.left : pw.TextAlign.right,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Load localized strings for PDF generation
  static Future<Map<String, String>> _loadLocalizedStrings(
      Locale locale) async {
    try {
      String jsonString = await rootBundle.loadString(
          'lib/src/common/localization/app_${locale.languageCode}.arb');
      Map<String, dynamic> jsonMap = json.decode(jsonString);
      return jsonMap.map((key, value) => MapEntry(key, value.toString()));
    } catch (e) {
      // Fallback to English
      String jsonString =
          await rootBundle.loadString('lib/src/common/localization/app_en.arb');
      Map<String, dynamic> jsonMap = json.decode(jsonString);
      return jsonMap.map((key, value) => MapEntry(key, value.toString()));
    }
  }

  static pw.Widget? _buildWelcomeMessage(QuotationModel quotation,
      Map<String, String> localizedStrings, Locale? locale) {
    // Check welcome message mode
    switch (quotation.welcomeMessageMode) {
      case WelcomeMessageMode.hidden:
        // Return null to completely hide the welcome section
        return null;

      case WelcomeMessageMode.custom:
        // Use custom message if provided, otherwise fall back to auto
        final welcomeText =
            quotation.customWelcomeMessage?.trim().isNotEmpty == true
                ? quotation.customWelcomeMessage!
                : _generateLocalizedWelcomeText(
                    quotation, localizedStrings, locale);
        return _buildWelcomeMessageWidget(welcomeText, locale);

      case WelcomeMessageMode.auto:
        // Generate localized welcome text automatically
        final welcomeText =
            _generateLocalizedWelcomeText(quotation, localizedStrings, locale);
        return _buildWelcomeMessageWidget(welcomeText, locale);
    }
  }

  static pw.Widget _buildWelcomeMessageWidget(
      String welcomeText, Locale? locale) {
    final isArabic = locale?.languageCode == 'ar';

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColors.blue200, width: 1),
      ),
      child: pw.Text(
        welcomeText,
        style: _createTextStyle(
          fontSize: 12,
          color: PdfColors.blue900,
          lineSpacing: 1.4,
          locale: locale,
        ),
        textAlign: isArabic ? pw.TextAlign.right : pw.TextAlign.left,
        textDirection: isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      ),
    );
  }

  static String _generateLocalizedWelcomeText(QuotationModel quotation,
      Map<String, String> localizedStrings, Locale? locale) {
    final officeName =
        quotation.officeName.isNotEmpty ? quotation.officeName : 'our office';
    final propertyType = quotation.propertyType?.isNotEmpty == true
        ? quotation.propertyType!.toLowerCase()
        : 'property';

    final hasParking = quotation.parking == true;
    final hasAmount = quotation.totalAmount != null;
    final hasInstallments = quotation.numberOfInstallments != null &&
        quotation.numberOfInstallments! > 0;

    // Helper function to get localized string with fallback
    String getLocalizedString(String key, [Map<String, String>? replacements]) {
      String text = localizedStrings[key] ?? key;
      if (replacements != null) {
        replacements.forEach((placeholder, value) {
          text = text.replaceAll('{$placeholder}', value);
        });
      }
      return text;
    }

    // Build dynamic localized message
    String message =
        getLocalizedString('welcomeToOffice', {'officeName': officeName});
    message += ' ';
    message += getLocalizedString('quotationIntro');
    message += ' ';

    if (quotation.propertyTitle.isNotEmpty) {
      message += getLocalizedString('namedPremiumProperty', {
        'propertyTitle': quotation.propertyTitle,
        'propertyType': propertyType
      });
    } else {
      message +=
          getLocalizedString('premiumProperty', {'propertyType': propertyType});
    }

    if (hasParking) {
      message += ' ';
      message += getLocalizedString('withParkingFacilities');
    }

    if (quotation.startDate?.isNotEmpty == true &&
        quotation.endDate?.isNotEmpty == true) {
      message += ' ';
      message += getLocalizedString('availableFromTo', {
        'startDate':
            _formatDate(quotation.startDate, locale ?? const Locale('en')),
        'endDate': _formatDate(quotation.endDate, locale ?? const Locale('en'))
      });
    }

    message += '. ';

    if (hasAmount) {
      message += getLocalizedString('competitivePricing');
      if (hasInstallments) {
        message += ' ';
        message += getLocalizedString('flexibleInstallments');
      }
      message += '. ';
    }

    message += getLocalizedString('exceptionalService');

    return message;
  }

  static pw.Widget _buildPropertyDetailsSection(QuotationModel quotation,
      Map<String, String> localizedStrings, bool isRtl, Locale? locale) {
    return pw.Wrap(
      children: [
        pw.Column(
          crossAxisAlignment:
              isRtl ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start,
          children: [
            _buildPropertyDetails(quotation, localizedStrings, isRtl, locale),
            pw.SizedBox(height: 20),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildFinancialDetailsSection(QuotationModel quotation,
      Map<String, String> localizedStrings, bool isRtl, Locale? locale) {
    return pw.Wrap(
      children: [
        pw.Column(
          crossAxisAlignment:
              isRtl ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start,
          children: [
            _buildFinancialDetails(quotation, localizedStrings, isRtl, locale),
            pw.SizedBox(height: 20),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildDownpaymentsSection(QuotationModel quotation,
      Map<String, String> localizedStrings, bool isRtl, Locale? locale) {
    return pw.Wrap(
      children: [
        pw.Column(
          crossAxisAlignment:
              isRtl ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start,
          children: [
            _sectionTitle(
              localizedStrings['downpaymentsSchedule'] ?? 'Downpayments',
              isRtl,
              locale: locale,
            ),
            pw.SizedBox(height: 10),
            _buildDownpaymentsTable(quotation, localizedStrings, isRtl, locale),
            pw.SizedBox(height: 20),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildGovernmentFeesCompleteSection(QuotationModel quotation,
      Map<String, String> localizedStrings, bool isRtl, Locale? locale) {
    return pw.Wrap(
      children: [
        pw.Column(
          crossAxisAlignment:
              isRtl ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start,
          children: [
            _sectionTitle(
              localizedStrings['governmentFeesBreakdown'] ?? 'Government Fees',
              isRtl,
              locale: locale,
            ),
            pw.SizedBox(height: 10),
            pw.SizedBox(height: 10),
            _buildGovernmentFeesSection(
                quotation, localizedStrings, isRtl, locale),
            pw.SizedBox(height: 20),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildAdministrativeFeesCompleteSection(
      QuotationModel quotation,
      Map<String, String> localizedStrings,
      bool isRtl,
      Locale? locale) {
    return pw.Wrap(
      children: [
        pw.Column(
          crossAxisAlignment:
              isRtl ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start,
          children: [
            _sectionTitle(
              localizedStrings['administrativeFeesBreakdown'] ??
                  'Administrative Fees',
              isRtl,
              locale: locale,
            ),
            pw.SizedBox(height: 10),
            _buildAdministrativeFeesSection(quotation, localizedStrings, isRtl),
            pw.SizedBox(height: 20),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildAdditionalNotesSection(QuotationModel quotation,
      Map<String, String> localizedStrings, bool isRtl, Locale? locale) {
    return pw.Wrap(
      children: [
        pw.Column(
          crossAxisAlignment:
              isRtl ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start,
          children: [
            _sectionTitle(
              localizedStrings['notes'] ?? 'Additional Notes',
              isRtl,
              locale: locale,
            ),
            pw.SizedBox(height: 10),
            pw.Container(
              width: double.infinity,
              child: pw.Text(
                quotation.customNote!,
                style: pw.TextStyle(fontSize: 11),
                textAlign: isRtl ? pw.TextAlign.right : pw.TextAlign.left,
                textDirection:
                    isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
              ),
            ),
            pw.SizedBox(height: 20),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildPropertyDetails(QuotationModel quotation,
      Map<String, String> localizedStrings, bool isRtl, Locale? locale) {
    return pw.Column(
      crossAxisAlignment:
          isRtl ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          localizedStrings['propertyDetails'] ?? 'Property Details',
          isRtl,
          locale: locale,
        ),
        pw.SizedBox(height: 10),
        _buildDetailRow(localizedStrings['propertyTitle'] ?? 'Property Title:',
            quotation.propertyTitle, isRtl),
        if (quotation.propertyType != null)
          _buildDetailRow(localizedStrings['propertyType'] ?? 'Property Type:',
              quotation.propertyType!, isRtl),
        if (quotation.subtitle != null)
          _buildDetailRow(localizedStrings['subtitle'] ?? 'Subtitle:',
              quotation.subtitle!, isRtl),
        if (quotation.parking == true)
          _buildDetailRow(localizedStrings['parking'] ?? 'Parking:',
              localizedStrings['yes'] ?? 'Yes', isRtl),
        if (quotation.startDate != null)
          _buildDetailRow(
              localizedStrings['startDate'] ?? 'Starting Date:',
              _formatDate(quotation.startDate, locale ?? const Locale('en')),
              isRtl),
        if (quotation.endDate != null)
          _buildDetailRow(
              localizedStrings['endDate'] ?? 'Ending Date:',
              _formatDate(quotation.endDate, locale ?? const Locale('en')),
              isRtl),
      ],
    );
  }

  static pw.Widget _buildFinancialDetails(QuotationModel quotation,
      Map<String, String> localizedStrings, bool isRtl, Locale? locale) {
    final currency = quotation.currencyCode ?? 'AED';

    return pw.Column(
      crossAxisAlignment:
          isRtl ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          localizedStrings['financialDetails'] ?? 'Financial Details',
          isRtl,
          locale: locale,
        ),
        pw.SizedBox(height: 10),
        if (quotation.totalAmount != null)
          _buildDetailRow(localizedStrings['totalAmount'] ?? 'Total Amount:',
              '$currency ${_formatNumber(quotation.totalAmount)}', isRtl),
        if (quotation.professionalFee != null)
          _buildDetailRow(
              localizedStrings['professionalFee'] ?? 'Professional Fee:',
              '$currency ${_formatNumber(quotation.professionalFee)}',
              isRtl),
        if (quotation.numberOfInstallments != null)
          _buildDetailRow(
              localizedStrings['numberOfInstallments'] ??
                  'Number of Installments:',
              _formatNumber(quotation.numberOfInstallments),
              isRtl),
        if (quotation.paymentType != null && quotation.paymentType!.isNotEmpty)
          _buildDetailRow(
              localizedStrings['paymentType'] ?? 'Payment Type:',
              _formatPaymentType(quotation.paymentType!, localizedStrings),
              isRtl),
        if (quotation.insuranceAmount != null)
          _buildDetailRow(localizedStrings['insurance'] ?? 'Insurance Amount:',
              '$currency ${_formatNumber(quotation.insuranceAmount)}', isRtl),
        if (quotation.insuranceAmount != null &&
            quotation.insuranceReturnable != null)
          _buildDetailRow(
              localizedStrings['insuranceReturnable'] ??
                  'Insurance Returnable:',
              quotation.insuranceReturnable!
                  ? (localizedStrings['yes'] ?? 'Yes')
                  : (localizedStrings['no'] ?? 'No'),
              isRtl),
      ],
    );
  }

  static pw.Widget _buildDetailRow(String label, String value, bool isRtl) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 150,
            child: pw.Text(
              label,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              textAlign: isRtl ? pw.TextAlign.right : pw.TextAlign.left,
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              // In Arabic keep right; in English keep left
              textAlign: isRtl ? pw.TextAlign.right : pw.TextAlign.left,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildDownpaymentsTable(QuotationModel quotation,
      Map<String, String> localizedStrings, bool isRtl, Locale? locale) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      columnWidths: const {
        0: pw.FlexColumnWidth(2), // Payment Method
        1: pw.FlexColumnWidth(1), // No.
        2: pw.FlexColumnWidth(2), // Date
        3: pw.FlexColumnWidth(2), // Amount
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            _tableCell(localizedStrings['paymentMethod'] ?? 'Payment Method',
                isHeader: true, isRtl: isRtl),
            _tableCell(localizedStrings['number'] ?? 'No.',
                isHeader: true, isRtl: isRtl, align: pw.TextAlign.center),
            _tableCell(localizedStrings['date'] ?? 'Date',
                isHeader: true, isRtl: isRtl),
            _tableCell(localizedStrings['amount'] ?? 'Amount',
                isHeader: true, isRtl: isRtl, align: pw.TextAlign.right),
          ],
        ),
        ...quotation.downpayments.map((row) => pw.TableRow(children: [
              _tableCell(_formatPaymentMethod(row.method, localizedStrings),
                  isRtl: isRtl),
              _tableCell(_formatNumber(row.number),
                  isRtl: isRtl, align: pw.TextAlign.center),
              _tableCell(
                  row.date?.toString().split(' ').first ??
                      (localizedStrings['tbd'] ?? 'TBD'),
                  isRtl: isRtl),
              _tableCell(
                  '${quotation.currencyCode ?? 'AED'} ${_formatNumber(row.amount)}',
                  isRtl: isRtl,
                  align: pw.TextAlign.right),
            ])),
      ],
    );
  }

  // Generic cell with locale-aware defaults
  static pw.Widget _tableCell(
    String text, {
    bool isHeader = false,
    bool isRtl = false,
    pw.TextAlign? align, // optional override
  }) {
    final resolved = align ?? (isRtl ? pw.TextAlign.right : pw.TextAlign.left);
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        textAlign: resolved,
        style: pw.TextStyle(
          fontSize: isHeader ? 10 : 9,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  static String _formatPaymentMethod(
      PaymentMethod method, Map<String, String> localizedStrings) {
    switch (method) {
      case PaymentMethod.cash:
        return localizedStrings['cash'] ?? 'Cash';
      case PaymentMethod.cheque:
        return localizedStrings['cheque'] ?? 'Cheque';
      case PaymentMethod.bankTransfer:
        return localizedStrings['bankTransfer'] ?? 'Bank Transfer';
      case PaymentMethod.other:
        return localizedStrings['other'] ?? 'Other';
    }
  }

  // Helper method to format payment type strings (for quotation.paymentType)
  static String _formatPaymentType(
      String code, Map<String, String> localizedStrings) {
    switch (code) {
      case 'cash':
        return localizedStrings['cash'] ?? 'Cash';
      case 'cheque':
        return localizedStrings['cheque'] ?? 'Cheque';
      case 'bankTransfer':
        return localizedStrings['bankTransfer'] ?? 'Bank Transfer';
      case 'other':
        return localizedStrings['other'] ?? 'Other';
      default:
        return code; // fallback to the original code
    }
  }

  static pw.Widget _buildGovernmentFeesSection(QuotationModel quotation,
      Map<String, String> localizedStrings, bool isRtl, Locale? locale) {
    final gov = quotation.governmentFees;
    final currency = quotation.currencyCode ?? 'AED';

    return pw.Column(
      crossAxisAlignment:
          isRtl ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start,
      children: [
        if (gov.percentOfTotalRent != null)
          _buildDetailRow(
              localizedStrings['percentOfTotalRent'] ??
                  'Percentage of Total Rent:',
              '${_formatNumber(gov.percentOfTotalRent)}%',
              isRtl),
        // Add the calculated amount from percentage if available
        if (gov.percentOfTotalRent != null && quotation.totalAmount != null)
          _buildDetailRow(
              localizedStrings['calculatedAmount'] ?? 'Calculated Amount:',
              '$currency ${_formatNumber((quotation.totalAmount! * gov.percentOfTotalRent! / 100).toStringAsFixed(2))}',
              isRtl),
        if (gov.municipality != null)
          _buildDetailRow(localizedStrings['municipality'] ?? 'Municipality:',
              '$currency ${_formatNumber(gov.municipality)}', isRtl),
        if (gov.electricity != null)
          _buildDetailRow(localizedStrings['electricity'] ?? 'Electricity:',
              '$currency ${_formatNumber(gov.electricity)}', isRtl),
        if (gov.sewerage != null)
          _buildDetailRow(localizedStrings['sewerage'] ?? 'Sewerage:',
              '$currency ${_formatNumber(gov.sewerage)}', isRtl),
        if (gov.total != null)
          _buildDetailRow(localizedStrings['total'] ?? 'Total Gov. Fees:',
              '$currency ${_formatNumber(gov.total)}', isRtl),
      ],
    );
  }

  static pw.Widget _buildAdministrativeFeesSection(QuotationModel quotation,
      Map<String, String> localizedStrings, bool isRtl) {
    final adm = quotation.administrativeFees;
    final currency = quotation.currencyCode ?? 'AED';

    return pw.Column(
      crossAxisAlignment:
          isRtl ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start,
      children: [
        // Display each administrative fee dynamically
        for (final fee in adm.fees)
          _buildDetailRow(
              fee.title, '$currency ${_formatNumber(fee.amount)}', isRtl),
        if (adm.total != null)
          _buildDetailRow(localizedStrings['total'] ?? 'Total Admin. Fees:',
              '$currency ${_formatNumber(adm.total)}', isRtl),
      ],
    );
  }

  static bool _hasGovernmentFees(GovernmentFees fees) {
    return fees.percentOfTotalRent != null ||
        fees.municipality != null ||
        fees.electricity != null ||
        fees.sewerage != null ||
        fees.total != null;
  }

  static bool _hasAdministrativeFees(AdministrativeFees fees) {
    return fees.fees.isNotEmpty || fees.total != null;
  }

  // Load image from URL or local file for PDF
  static Future<pw.ImageProvider> _loadImageFromUrl(String url) async {
    try {
      // Handle file:// scheme
      if (url.startsWith('file://')) {
        final file = File(Uri.parse(url).toFilePath());
        final bytes = await file.readAsBytes();
        return pw.MemoryImage(bytes);
      }

      // Handle raw absolute paths (/data/user/0/... or /storage/...)
      if (url.startsWith('/')) {
        final file = File(url);
        final bytes = await file.readAsBytes();
        return pw.MemoryImage(bytes);
      }

      // Handle local URLs (temporary files)
      if (url.startsWith('local://')) {
        // Get the actual local file path from the OfflineMediaService (synchronous call)
        final localPath = OfflineMediaService.instance.getLocalFilePath(url);
        if (localPath != null) {
          final file = File(localPath);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            return pw.MemoryImage(bytes);
          }
        }
        throw Exception('Local file not found for URL: $url');
      }

      // Handle regular HTTP/HTTPS URLs
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return pw.MemoryImage(response.bodyBytes);
      } else {
        throw Exception(
            'Failed to load image from URL: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  // Upload PDF to Firebase Storage and return download URL
  static Future<String> uploadPdfToStorage(
      String localPath, String quotationId) async {
    try {
      final file = File(localPath);
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        throw Exception('User not authenticated');
      }

      final ref = FirebaseStorage.instance
          .ref()
          .child('quotations')
          .child(user.uid)
          .child('$quotationId.pdf');

      await ref.putFile(file);
      return await ref.getDownloadURL();
    } catch (e) {
      rethrow;
    }
  }
}
