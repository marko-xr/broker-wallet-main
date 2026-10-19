import 'package:broker_wallet/src/data/models/uae_links_model.dart';

const String _checked = '2026-10-19';

const String _fetched =
    'Fetched 2026-10-19: HTTP 200; page title and heading match the service.';
const String _rendered =
    'Opened in a browser 2026-10-19: rendered content matches the service.';

const String _dldEn = 'Dubai Land Department (DLD)';
const String _dldAr = 'دائرة الأراضي والأملاك في دبي';
const String _adrecEn = 'Abu Dhabi Real Estate Centre (ADREC)';
const String _adrecAr = 'مركز أبوظبي العقاري';
const String _srerdEn = 'Sharjah Real Estate Registration Department (SRERD)';
const String _srerdAr = 'دائرة التسجيل العقاري في الشارقة';
const String _ajmanLandEn =
    'Department of Land and Real Estate Regulation, Ajman';
const String _ajmanLandAr = 'دائرة الأراضي والتنظيم العقاري في عجمان';
const String _ajmanMunEn = 'Ajman Municipality and Planning Department';
const String _ajmanMunAr = 'دائرة البلدية والتخطيط في عجمان';
const String _rakMunEn = 'Ras Al Khaimah Municipality';
const String _rakMunAr = 'بلدية رأس الخيمة';
const String _fujMunEn = 'Fujairah Municipality';
const String _fujMunAr = 'بلدية الفجيرة';

/// The one curated directory of official UAE real-estate services.
///
/// Rules every entry follows (the tests enforce them):
///  * the authority is a government body, or the one payment platform that is
///    labelled as a payment platform;
///  * the URL is HTTPS on an official domain, verified by observation, not by
///    its `.gov.ae` ending;
///  * an entry whose destination could not be fully confirmed says so
///    ([UaeLinkVerification.officialManualCheckRequired]);
///  * `docs/toolbox/uae-links-verification.md` records the evidence.
class UAELinksData {
  const UAELinksData._();

  /// Everything that may be shown to the user.
  static List<UaeLinkEntry> get published => [
        for (final entry in entries)
          if (entry.verification.isPublishable) entry,
      ];

  static const List<UaeLinkEntry> entries = [
    // ---------------------------------------------------------------- UAE
    UaeLinkEntry(
      id: 'uae-uae-pass',
      emirates: {UaeLinkEmirate.uae},
      tasks: {UaeLinkTask.digitalIdentity},
      type: UaeLinkType.portal,
      url: 'https://www.uaepass.ae/',
      titleEn: 'UAE PASS',
      titleAr: 'الهوية الرقمية الإماراتية (UAE PASS)',
      descriptionEn:
          'The national digital identity used to sign in to most government '
          'real-estate services and to sign and verify documents.',
      descriptionAr:
          'الهوية الرقمية الوطنية التي تُستخدم لتسجيل الدخول إلى معظم الخدمات '
          'العقارية الحكومية وتوقيع المستندات والتحقق منها.',
      authorityEn: 'UAE PASS (UAE national digital identity)',
      authorityAr: 'الهوية الرقمية الإماراتية (UAE PASS)',
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _rendered,
      keywords: ['uaepass', 'uae pass', 'digital identity', 'الهوية الرقمية'],
    ),
    UaeLinkEntry(
      id: 'uae-leasing-guide',
      emirates: {UaeLinkEmirate.uae},
      tasks: {UaeLinkTask.tenancy, UaeLinkTask.disputesLegal},
      type: UaeLinkType.information,
      url:
          'https://u.ae/en/information-and-services/moving-to-the-uae/leasing-a-property-in-the-uae',
      titleEn: 'Leasing a property in the UAE (guide)',
      titleAr: 'دليل استئجار عقار في الإمارات',
      descriptionEn:
          'The UAE Government guide to renting a property, with the steps '
          'and the authority for each emirate.',
      descriptionAr:
          'دليل حكومة الإمارات لاستئجار العقارات، يوضح الخطوات والجهة '
          'المختصة في كل إمارة.',
      authorityEn: 'UAE Government Portal (u.ae)',
      authorityAr: 'البوابة الرسمية لحكومة دولة الإمارات',
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['u.ae', 'lease', 'rent', 'tenancy', 'إيجار', 'ايجار'],
    ),
    UaeLinkEntry(
      id: 'uae-housing-guide',
      emirates: {UaeLinkEmirate.uae},
      tasks: {UaeLinkTask.salesTitle, UaeLinkTask.tenancy},
      type: UaeLinkType.information,
      url: 'https://u.ae/en/information-and-services/housing',
      titleEn: 'Housing and property (guide)',
      titleAr: 'دليل الإسكان والعقارات',
      descriptionEn:
          'The UAE Government overview of buying, owning and renting '
          'property, with links to the competent authorities.',
      descriptionAr:
          'نظرة عامة من حكومة الإمارات حول شراء العقارات وتملكها واستئجارها '
          'مع روابط للجهات المختصة.',
      authorityEn: 'UAE Government Portal (u.ae)',
      authorityAr: 'البوابة الرسمية لحكومة دولة الإمارات',
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['u.ae', 'housing', 'ownership', 'تملك', 'إسكان'],
    ),
    UaeLinkEntry(
      id: 'uae-legislation',
      emirates: {UaeLinkEmirate.uae},
      tasks: {UaeLinkTask.disputesLegal},
      type: UaeLinkType.information,
      url: 'https://www.uaelegislation.gov.ae/en',
      titleEn: 'UAE Legislation portal',
      titleAr: 'بوابة التشريعات الإماراتية',
      descriptionEn:
          'Official text of UAE federal laws and decrees, including the '
          'laws that govern real estate.',
      descriptionAr:
          'النصوص الرسمية للقوانين والمراسيم الاتحادية في الإمارات، ومنها '
          'القوانين المنظمة للعقارات.',
      authorityEn: 'UAE Federal Government',
      authorityAr: 'حكومة دولة الإمارات الاتحادية',
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence:
          'Fetched 2026-10-19: HTTP 200; page title "United Arab Emirates '
          'Legislations". The bare domain without "www" did not respond.',
      keywords: ['laws', 'legislation', 'decree', 'قانون', 'تشريعات'],
    ),

    // -------------------------------------------------------------- Dubai
    UaeLinkEntry(
      id: 'dubai-dld-home',
      emirates: {UaeLinkEmirate.dubai},
      tasks: {UaeLinkTask.verification, UaeLinkTask.salesTitle},
      type: UaeLinkType.portal,
      url: 'https://dubailand.gov.ae/en/',
      titleEn: 'Dubai Land Department',
      titleAr: 'دائرة الأراضي والأملاك في دبي',
      descriptionEn:
          'The land and real-estate regulator of Dubai (including RERA): '
          'services, news, laws and market data.',
      descriptionAr:
          'الجهة المنظمة للأراضي والعقارات في دبي (ومنها مؤسسة التنظيم '
          'العقاري ريرا): الخدمات والأخبار والقوانين وبيانات السوق.',
      authorityEn: _dldEn,
      authorityAr: _dldAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['dld', 'rera', 'دلد', 'ريرا', 'دائرة الاراضي'],
    ),
    UaeLinkEntry(
      id: 'dubai-dld-services',
      emirates: {UaeLinkEmirate.dubai},
      tasks: {UaeLinkTask.tenancy, UaeLinkTask.salesTitle},
      type: UaeLinkType.portal,
      url: 'https://dubailand.gov.ae/en/eservices/all-services/',
      titleEn: 'DLD e-services directory',
      titleAr: 'دليل الخدمات الإلكترونية لدائرة الأراضي',
      descriptionEn:
          'Every DLD online service in one list: tenancy, sales, permits, '
          'verification, projects and valuation.',
      descriptionAr:
          'جميع الخدمات الإلكترونية للدائرة في قائمة واحدة: الإيجار والبيع '
          'والتصاريح والتحقق والمشاريع والتقييم.',
      authorityEn: _dldEn,
      authorityAr: _dldAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['dld', 'eservices', 'services', 'خدمات'],
    ),
    UaeLinkEntry(
      id: 'dubai-ejari-register-renew',
      emirates: {UaeLinkEmirate.dubai},
      tasks: {UaeLinkTask.tenancy, UaeLinkTask.renewalCancellation},
      type: UaeLinkType.action,
      url:
          'https://dubailand.gov.ae/en/eservices/register-renew-ejari-contract/',
      titleEn: 'Register or renew a tenancy contract (Ejari)',
      titleAr: 'تسجيل أو تجديد عقد إيجار (إيجاري)',
      descriptionEn:
          'Register a new tenancy contract or renew one in Dubai. Sign-in is '
          'needed to apply online.',
      descriptionAr:
          'تسجيل عقد إيجار جديد أو تجديد عقد قائم في دبي. يتطلب تسجيل الدخول '
          'للتقديم إلكترونياً.',
      authorityEn: _dldEn,
      authorityAr: _dldAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      requiresLogin: true,
      keywords: ['ejari', 'ايجاري', 'إيجاري', 'tenancy', 'rent', 'عقد ايجار'],
    ),
    UaeLinkEntry(
      id: 'dubai-ejari-cancel',
      emirates: {UaeLinkEmirate.dubai},
      tasks: {UaeLinkTask.renewalCancellation, UaeLinkTask.tenancy},
      type: UaeLinkType.action,
      url: 'https://dubailand.gov.ae/en/eservices/cancel-tenancy-contract/',
      titleEn: 'Cancel a tenancy contract (Ejari)',
      titleAr: 'إلغاء عقد إيجار (إيجاري)',
      descriptionEn: 'Request the cancellation of a registered Dubai tenancy '
          'contract.',
      descriptionAr: 'طلب إلغاء عقد إيجار مسجل في دبي.',
      authorityEn: _dldEn,
      authorityAr: _dldAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      requiresLogin: true,
      keywords: ['ejari', 'ايجاري', 'إيجاري', 'cancel', 'termination'],
    ),
    UaeLinkEntry(
      id: 'dubai-ejari-certificate',
      emirates: {UaeLinkEmirate.dubai},
      tasks: {UaeLinkTask.tenancy, UaeLinkTask.verification},
      type: UaeLinkType.action,
      url: 'https://dubailand.gov.ae/en/eservices/download-ejari-certificate/',
      titleEn: 'Download the rental certificate (Ejari)',
      titleAr: 'تنزيل شهادة الإيجار (إيجاري)',
      descriptionEn:
          'Get the Ejari certificate of a registered Dubai tenancy contract '
          'with the contract and DEWA premise numbers. No sign-in form.',
      descriptionAr:
          'الحصول على شهادة إيجاري لعقد إيجار مسجل في دبي برقم العقد ورقم '
          'المبنى لدى ديوا. دون تسجيل دخول.',
      authorityEn: _dldEn,
      authorityAr: _dldAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['ejari', 'ايجاري', 'إيجاري', 'certificate', 'شهادة'],
    ),
    UaeLinkEntry(
      id: 'dubai-rental-index',
      emirates: {UaeLinkEmirate.dubai},
      tasks: {UaeLinkTask.valuationIndex, UaeLinkTask.tenancy},
      type: UaeLinkType.verification,
      url: 'https://dubailand.gov.ae/en/eservices/rental-index/rental-index/',
      titleEn: 'Rental Index',
      titleAr: 'المؤشر الإيجاري',
      descriptionEn:
          'Check the rental index for a Dubai property by DEWA premise '
          'number, Ejari contract number or area. Public, no sign-in.',
      descriptionAr:
          'الاطلاع على المؤشر الإيجاري لعقار في دبي برقم المبنى لدى ديوا أو '
          'رقم عقد إيجاري أو المنطقة. متاح دون تسجيل دخول.',
      authorityEn: _dldEn,
      authorityAr: _dldAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['rera', 'rental index', 'rent calculator', 'ريرا', 'مؤشر'],
    ),
    UaeLinkEntry(
      id: 'dubai-title-deed-verification',
      emirates: {UaeLinkEmirate.dubai},
      tasks: {UaeLinkTask.verification, UaeLinkTask.salesTitle},
      type: UaeLinkType.verification,
      url:
          'https://dubailand.gov.ae/en/eservices/title-deed-verification-overview/title-deed-verification/',
      titleEn: 'Verify a title deed',
      titleAr: 'التحقق من سند الملكية',
      descriptionEn:
          'Validate a Dubai title deed and its owner by title deed number, '
          'year and property type. Public, no sign-in.',
      descriptionAr:
          'التحقق من سند ملكية في دبي ومن مالكه برقم السند والسنة ونوع '
          'العقار. متاح دون تسجيل دخول.',
      authorityEn: _dldEn,
      authorityAr: _dldAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['title deed', 'سند', 'ملكية', 'verify'],
    ),
    UaeLinkEntry(
      id: 'dubai-property-status',
      emirates: {UaeLinkEmirate.dubai},
      tasks: {UaeLinkTask.verification, UaeLinkTask.salesTitle},
      type: UaeLinkType.verification,
      url:
          'https://dubailand.gov.ae/en/eservices/property-status-overview/property-status/',
      titleEn: 'Property status enquiry',
      titleAr: 'الاستعلام عن حالة العقار',
      descriptionEn: 'Look up the registered status of a Dubai property.',
      descriptionAr: 'الاستعلام عن الحالة المسجلة لعقار في دبي.',
      authorityEn: _dldEn,
      authorityAr: _dldAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['property status', 'حالة العقار', 'mortgage', 'رهن'],
    ),
    UaeLinkEntry(
      id: 'dubai-real-estate-ad-permit',
      emirates: {UaeLinkEmirate.dubai},
      tasks: {UaeLinkTask.brokerPermits},
      type: UaeLinkType.action,
      url: 'https://dubailand.gov.ae/en/eservices/real-estate-ad-permit/',
      titleEn: 'Real estate advertising permit (Trakheesi)',
      titleAr: 'تصريح الإعلان العقاري (ترخيصي)',
      descriptionEn:
          'Apply for the permit required to advertise Dubai real estate: '
          'listings, outdoor, SMS, events and promotions.',
      descriptionAr:
          'التقديم على التصريح المطلوب للإعلان عن العقارات في دبي: القوائم '
          'العقارية والإعلانات الخارجية والرسائل والفعاليات والعروض.',
      authorityEn: _dldEn,
      authorityAr: _dldAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: '$_fetched The Trakheesi name is the permit\'s common name; '
          'the DLD page is titled "Real Estate Ad Permit".',
      requiresLogin: true,
      keywords: [
        'trakheesi',
        'ترخيصي',
        'ad permit',
        'advertisement',
        'rera',
        'ريرا',
        'تصريح اعلان',
      ],
    ),
    UaeLinkEntry(
      id: 'dubai-validate-licences-permits',
      emirates: {UaeLinkEmirate.dubai},
      tasks: {UaeLinkTask.brokerPermits, UaeLinkTask.verification},
      type: UaeLinkType.verification,
      url:
          'https://dubailand.gov.ae/en/eservices/validate-real-estate-licenses-and-permits/',
      titleEn: 'Verify real estate licences and permits',
      titleAr: 'التحقق من التراخيص والتصاريح العقارية',
      descriptionEn:
          'Check that a Dubai broker licence or advertising permit is '
          'valid before relying on it.',
      descriptionAr:
          'التأكد من صلاحية رخصة وسيط أو تصريح إعلان عقاري في دبي قبل '
          'الاعتماد عليه.',
      authorityEn: _dldEn,
      authorityAr: _dldAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['trakheesi', 'ترخيصي', 'permit', 'licence', 'license', 'rera'],
    ),
    UaeLinkEntry(
      id: 'dubai-licensed-brokerages',
      emirates: {UaeLinkEmirate.dubai},
      tasks: {UaeLinkTask.brokerPermits, UaeLinkTask.verification},
      type: UaeLinkType.verification,
      url:
          'https://dubailand.gov.ae/en/eservices/licensed-real-estate-brokers-offices/licensed-real-estate-brokers-offices-list/',
      titleEn: 'Licensed real estate brokerage companies',
      titleAr: 'شركات الوساطة العقارية المرخصة',
      descriptionEn: 'Search the register of licensed brokerage companies in '
          'Dubai.',
      descriptionAr: 'البحث في سجل شركات الوساطة العقارية المرخصة في دبي.',
      authorityEn: _dldEn,
      authorityAr: _dldAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['broker office', 'brokerage', 'rera', 'مكتب وساطة', 'ريرا'],
    ),
    UaeLinkEntry(
      id: 'dubai-licensed-brokers',
      emirates: {UaeLinkEmirate.dubai},
      tasks: {UaeLinkTask.brokerPermits, UaeLinkTask.verification},
      type: UaeLinkType.verification,
      url:
          'https://dubailand.gov.ae/en/eservices/licensed-real-estate-brokers/licensed-real-estate-brokers-list/',
      titleEn: 'Licensed real estate brokers',
      titleAr: 'الوسطاء العقاريون المرخصون',
      descriptionEn: 'Search the register of licensed individual brokers in '
          'Dubai.',
      descriptionAr: 'البحث في سجل الوسطاء العقاريين المرخصين في دبي.',
      authorityEn: _dldEn,
      authorityAr: _dldAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['broker', 'agent', 'rera', 'وسيط', 'ريرا'],
    ),
    UaeLinkEntry(
      id: 'dubai-broker-ecard',
      emirates: {UaeLinkEmirate.dubai},
      tasks: {UaeLinkTask.brokerPermits, UaeLinkTask.verification},
      type: UaeLinkType.verification,
      url: 'https://dubailand.gov.ae/en/eservices/validate-e-card-overview/',
      titleEn: 'E-card verification',
      titleAr: 'التحقق من البطاقة الإلكترونية',
      descriptionEn: 'Validate a real estate professional\'s DLD e-card.',
      descriptionAr: 'التحقق من البطاقة الإلكترونية لمهني عقاري لدى الدائرة.',
      authorityEn: _dldEn,
      authorityAr: _dldAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['e-card', 'ecard', 'broker card', 'بطاقة'],
    ),
    UaeLinkEntry(
      id: 'dubai-project-status',
      emirates: {UaeLinkEmirate.dubai},
      tasks: {UaeLinkTask.developersOffPlan, UaeLinkTask.verification},
      type: UaeLinkType.verification,
      url:
          'https://dubailand.gov.ae/en/eservices/real-estate-project-status-landing/real-estate-project-status/',
      titleEn: 'Project status enquiry',
      titleAr: 'الاستعلام عن حالة المشروع',
      descriptionEn: 'Check the registered status and progress of a Dubai '
          'real-estate project.',
      descriptionAr: 'الاستعلام عن الحالة المسجلة وتقدم مشروع عقاري في دبي.',
      authorityEn: _dldEn,
      authorityAr: _dldAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: [
        'project status',
        'off plan',
        'off-plan',
        'مشروع',
        'على الخارطة'
      ],
    ),
    UaeLinkEntry(
      id: 'dubai-licensed-developers',
      emirates: {UaeLinkEmirate.dubai},
      tasks: {UaeLinkTask.developersOffPlan, UaeLinkTask.verification},
      type: UaeLinkType.verification,
      url:
          'https://dubailand.gov.ae/en/eservices/approved-real-estate-developers/approved-developers/',
      titleEn: 'Licensed developers',
      titleAr: 'المطورون العقاريون المرخصون',
      descriptionEn: 'Check whether a developer is licensed in Dubai.',
      descriptionAr: 'التحقق من أن المطور العقاري مرخص في دبي.',
      authorityEn: _dldEn,
      authorityAr: _dldAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['developer', 'مطور', 'rera', 'ريرا'],
    ),
    UaeLinkEntry(
      id: 'dubai-escrow-trustees',
      emirates: {UaeLinkEmirate.dubai},
      tasks: {UaeLinkTask.developersOffPlan, UaeLinkTask.verification},
      type: UaeLinkType.verification,
      url: 'https://dubailand.gov.ae/en/eservices/certified-escrow-agents/',
      titleEn: 'Approved escrow account trustees',
      titleAr: 'أمناء حسابات الضمان المعتمدون',
      descriptionEn: 'Find the escrow account trustees approved by DLD for '
          'off-plan projects.',
      descriptionAr:
          'الاطلاع على أمناء حسابات الضمان المعتمدين لدى الدائرة للمشاريع '
          'على الخارطة.',
      authorityEn: _dldEn,
      authorityAr: _dldAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['escrow', 'trustee', 'ضمان', 'off plan'],
    ),
    UaeLinkEntry(
      id: 'dubai-oqood',
      emirates: {UaeLinkEmirate.dubai},
      tasks: {UaeLinkTask.developersOffPlan, UaeLinkTask.salesTitle},
      type: UaeLinkType.action,
      url: 'https://oqood.dubailand.gov.ae/',
      titleEn: 'Oqood: off-plan sales registration',
      titleAr: 'عقود: تسجيل البيع على الخارطة',
      descriptionEn:
          'DLD\'s off-plan registration service. Opens the My DLD sign-in '
          'page, where Oqood is listed.',
      descriptionAr:
          'خدمة الدائرة لتسجيل البيع على الخارطة. تفتح صفحة الدخول إلى '
          '«دائرتي» حيث تظهر خدمة عقود.',
      authorityEn: _dldEn,
      authorityAr: _dldAr,
      verification: UaeLinkVerification.officialManualCheckRequired,
      lastVerified: _checked,
      evidence:
          'Official DLD subdomain. The request redirected (HTTP 200) to the '
          'Arabic My DLD sign-in page; the DLD e-services page lists Oqood as '
          'a My DLD application. Sign-in not tested.',
      requiresLogin: true,
      keywords: ['oqood', 'عقود', 'off plan', 'off-plan', 'spa', 'على الخارطة'],
    ),
    UaeLinkEntry(
      id: 'dubai-mollak',
      emirates: {UaeLinkEmirate.dubai},
      tasks: {UaeLinkTask.feesPayments, UaeLinkTask.developersOffPlan},
      type: UaeLinkType.portal,
      url: 'https://mollak.dubailand.gov.ae/publicpages/home.html',
      titleEn: 'Mollak: jointly owned property',
      titleAr: 'ملاك: إدارة العقارات المشتركة',
      descriptionEn:
          'DLD\'s system for owners associations and jointly owned property: '
          'service charges, management companies and registration.',
      descriptionAr:
          'نظام الدائرة لجمعيات الملاك والعقارات المشتركة: رسوم الخدمات '
          'وشركات الإدارة والتسجيل.',
      authorityEn: _dldEn,
      authorityAr: _dldAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: 'Fetched 2026-10-19: the root address redirects by script to '
          'home.html, title "Mollak"; the DLD site links to Mollak.',
      keywords: ['mollak', 'ملاك', 'jop', 'service charge', 'رسوم الخدمات'],
    ),
    UaeLinkEntry(
      id: 'dubai-service-charge-index',
      emirates: {UaeLinkEmirate.dubai},
      tasks: {UaeLinkTask.valuationIndex, UaeLinkTask.feesPayments},
      type: UaeLinkType.verification,
      url:
          'https://dubailand.gov.ae/en/eservices/service-charge-index-overview/',
      titleEn: 'Service charge index',
      titleAr: 'مؤشر رسوم الخدمات',
      descriptionEn:
          'Look up the approved service charges of Dubai buildings and '
          'communities.',
      descriptionAr:
          'الاطلاع على رسوم الخدمات المعتمدة للمباني والمجتمعات السكنية في '
          'دبي.',
      authorityEn: _dldEn,
      authorityAr: _dldAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['service charge', 'mollak', 'رسوم الخدمات', 'مؤشر'],
    ),
    UaeLinkEntry(
      id: 'dubai-property-sale-registration',
      emirates: {UaeLinkEmirate.dubai},
      tasks: {UaeLinkTask.salesTitle},
      type: UaeLinkType.information,
      url: 'https://dubailand.gov.ae/en/eservices/property-sale-registration/',
      titleEn: 'Property sale registration',
      titleAr: 'تسجيل بيع عقار',
      descriptionEn:
          'How a property sale is registered with DLD, with the channels '
          'and documents.',
      descriptionAr:
          'كيفية تسجيل بيع عقار لدى الدائرة، مع القنوات والمستندات المطلوبة.',
      authorityEn: _dldEn,
      authorityAr: _dldAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['sale', 'transfer', 'بيع', 'نقل ملكية'],
    ),
    UaeLinkEntry(
      id: 'dubai-rest',
      emirates: {UaeLinkEmirate.dubai},
      tasks: {UaeLinkTask.salesTitle, UaeLinkTask.valuationIndex},
      type: UaeLinkType.action,
      url: 'https://dubailand.gov.ae/en/eservices/dubai-rest/',
      titleEn: 'Dubai REST app',
      titleAr: 'تطبيق دبي ريست',
      descriptionEn: 'DLD\'s real-estate app for owners, tenants, brokers and '
          'valuers: property wallet, map and certificate requests.',
      descriptionAr:
          'تطبيق الدائرة للخدمات العقارية للملاك والمستأجرين والوسطاء '
          'والمثمنين: محفظة العقارات وطلبات الخرائط والشهادات.',
      authorityEn: _dldEn,
      authorityAr: _dldAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      requiresLogin: true,
      keywords: ['dubai rest', 'rest', 'دبي ريست', 'app'],
    ),
    UaeLinkEntry(
      id: 'dubai-rental-disputes-centre',
      emirates: {UaeLinkEmirate.dubai},
      tasks: {UaeLinkTask.disputesLegal},
      type: UaeLinkType.portal,
      url: 'https://rdc.gov.ae/',
      titleEn: 'Rental Disputes Centre',
      titleAr: 'مركز فض المنازعات الإيجارية',
      descriptionEn:
          'Dubai\'s rental disputes court: file or track a case and see '
          'session schedules and the rules.',
      descriptionAr:
          'محكمة المنازعات الإيجارية في دبي: رفع الدعاوى ومتابعتها وجدول '
          'الجلسات والأنظمة.',
      authorityEn: 'Rental Disputes Centre, Dubai',
      authorityAr: 'مركز فض المنازعات الإيجارية في دبي',
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['rdc', 'dispute', 'court', 'eviction', 'نزاع', 'محكمة'],
    ),
    UaeLinkEntry(
      id: 'dubai-noqodi',
      emirates: {UaeLinkEmirate.dubai},
      tasks: {UaeLinkTask.feesPayments},
      type: UaeLinkType.payment,
      url: 'https://www.noqodi.com/',
      titleEn: 'Noqodi payment platform',
      titleAr: 'منصة نقودي للمدفوعات',
      descriptionEn:
          'The payment platform the DLD website points to for paying DLD '
          'service fees. It is a payment platform, not a government '
          'department or regulator.',
      descriptionAr:
          'منصة الدفع التي يشير إليها موقع الدائرة لسداد رسوم خدماتها. هي '
          'منصة دفع وليست جهة حكومية أو جهة تنظيمية.',
      authorityEn: 'Noqodi (payment platform used by DLD)',
      authorityAr: 'نقودي (منصة دفع تستخدمها الدائرة)',
      verification: UaeLinkVerification.officialManualCheckRequired,
      lastVerified: _checked,
      evidence:
          'Fetched 2026-10-19: HTTP 200, title "noqodi". The DLD site links '
          'to Noqodi payment support, which establishes its use with DLD; '
          'who owns the platform was not established.',
      keywords: ['noqodi', 'نقودي', 'payment', 'pay', 'دفع'],
    ),
    UaeLinkEntry(
      id: 'dubai-dewa-move-in',
      emirates: {UaeLinkEmirate.dubai},
      tasks: {UaeLinkTask.utilities, UaeLinkTask.tenancy},
      type: UaeLinkType.action,
      url:
          'https://www.dewa.gov.ae/en/consumer/supply-management/activation-of-electricity-water-move-in',
      titleEn: 'DEWA: activate electricity and water (move-in)',
      titleAr: 'ديوا: تفعيل الكهرباء والماء (الانتقال للسكن)',
      descriptionEn: 'Activate a DEWA electricity and water account for a '
          'new tenant or owner.',
      descriptionAr:
          'تفعيل حساب الكهرباء والماء لدى ديوا لمستأجر أو مالك جديد.',
      authorityEn: 'Dubai Electricity and Water Authority (DEWA)',
      authorityAr: 'هيئة كهرباء ومياه دبي (ديوا)',
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence:
          'Opened in a browser 2026-10-19; page and heading match, linked '
          'from the DEWA home page. Automated requests receive HTTP 403.',
      requiresLogin: true,
      keywords: ['dewa', 'ديوا', 'move in', 'activation', 'electricity'],
    ),
    UaeLinkEntry(
      id: 'dubai-dewa-move-out',
      emirates: {UaeLinkEmirate.dubai},
      tasks: {UaeLinkTask.utilities, UaeLinkTask.renewalCancellation},
      type: UaeLinkType.action,
      url:
          'https://www.dewa.gov.ae/en/consumer/supply-management/deactivation-of-electricity-water-move-out',
      titleEn: 'DEWA: deactivate electricity and water (move-out)',
      titleAr: 'ديوا: إيقاف الكهرباء والماء (الانتقال من السكن)',
      descriptionEn: 'Close a DEWA account when a tenant moves out.',
      descriptionAr: 'إغلاق حساب ديوا عند انتقال المستأجر من العقار.',
      authorityEn: 'Dubai Electricity and Water Authority (DEWA)',
      authorityAr: 'هيئة كهرباء ومياه دبي (ديوا)',
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence:
          'Opened in a browser 2026-10-19; page and heading match, linked '
          'from the DEWA home page. Automated requests receive HTTP 403.',
      requiresLogin: true,
      keywords: ['dewa', 'ديوا', 'move out', 'deactivation', 'electricity'],
    ),

    // ---------------------------------------------------------- Abu Dhabi
    UaeLinkEntry(
      id: 'abudhabi-adrec-home',
      emirates: {UaeLinkEmirate.abuDhabi},
      tasks: {UaeLinkTask.verification, UaeLinkTask.salesTitle},
      type: UaeLinkType.portal,
      url: 'https://adrec.gov.ae/en/',
      titleEn: 'Abu Dhabi Real Estate Centre',
      titleAr: 'مركز أبوظبي العقاري',
      descriptionEn:
          'The real-estate regulator of Abu Dhabi: services, market data, '
          'laws and the Madhmoun listing platform.',
      descriptionAr:
          'الجهة المنظمة للقطاع العقاري في أبوظبي: الخدمات وبيانات السوق '
          'والقوانين ومنصة مضمون للإعلانات.',
      authorityEn: _adrecEn,
      authorityAr: _adrecAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['adrec', 'أدريك', 'مركز ابوظبي العقاري', 'madhmoun'],
    ),
    UaeLinkEntry(
      id: 'abudhabi-adrec-services',
      emirates: {UaeLinkEmirate.abuDhabi},
      tasks: {UaeLinkTask.tenancy, UaeLinkTask.salesTitle},
      type: UaeLinkType.portal,
      url: 'https://adrec.gov.ae/en/services',
      titleEn: 'ADREC services',
      titleAr: 'خدمات مركز أبوظبي العقاري',
      descriptionEn:
          'The ADREC service catalogue: lease, transactions, certificates, '
          'mortgages, professional licences and Madhmoun.',
      descriptionAr:
          'دليل خدمات المركز: الإيجار والمعاملات والشهادات والرهون وتراخيص '
          'المهن ومضمون.',
      authorityEn: _adrecEn,
      authorityAr: _adrecAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence:
          'Rendered in a browser 2026-10-19: the page loads its catalogue '
          'with scripts, so a plain download shows only the page frame.',
      keywords: ['adrec', 'أدريك', 'services', 'خدمات'],
    ),
    UaeLinkEntry(
      id: 'abudhabi-verify-document',
      emirates: {UaeLinkEmirate.abuDhabi},
      tasks: {UaeLinkTask.verification},
      type: UaeLinkType.verification,
      url: 'https://adrec.gov.ae/en/verify-document',
      titleEn: 'Verify an ADREC document',
      titleAr: 'التحقق من وثيقة صادرة عن المركز',
      descriptionEn: 'Check that a document issued by ADREC is genuine.',
      descriptionAr: 'التحقق من صحة وثيقة صادرة عن مركز أبوظبي العقاري.',
      authorityEn: _adrecEn,
      authorityAr: _adrecAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['verify', 'document', 'تحقق', 'وثيقة'],
    ),
    UaeLinkEntry(
      id: 'abudhabi-market-data',
      emirates: {UaeLinkEmirate.abuDhabi},
      tasks: {UaeLinkTask.valuationIndex},
      type: UaeLinkType.information,
      url: 'https://adrec.gov.ae/en/property_and_index',
      titleEn: 'Abu Dhabi market data and indices',
      titleAr: 'بيانات ومؤشرات سوق أبوظبي العقاري',
      descriptionEn:
          'Official prices, trends, interactive map and dashboards for the '
          'Abu Dhabi property market.',
      descriptionAr:
          'الأسعار والاتجاهات والخريطة التفاعلية ولوحات المعلومات الرسمية '
          'لسوق العقارات في أبوظبي.',
      authorityEn: _adrecEn,
      authorityAr: _adrecAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['market data', 'index', 'prices', 'مؤشر', 'أسعار'],
    ),
    UaeLinkEntry(
      id: 'abudhabi-laws',
      emirates: {UaeLinkEmirate.abuDhabi},
      tasks: {UaeLinkTask.disputesLegal},
      type: UaeLinkType.information,
      url: 'https://adrec.gov.ae/en/rules_and_regulations',
      titleEn: 'Abu Dhabi real estate laws and regulations',
      titleAr: 'قوانين وأنظمة العقارات في أبوظبي',
      descriptionEn: 'The rules for ownership, leasing and investment in Abu '
          'Dhabi.',
      descriptionAr: 'الأنظمة المتعلقة بالتملك والإيجار والاستثمار في أبوظبي.',
      authorityEn: _adrecEn,
      authorityAr: _adrecAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['law', 'regulation', 'قانون', 'أنظمة'],
    ),
    UaeLinkEntry(
      id: 'abudhabi-dispute-settlement-centre',
      emirates: {UaeLinkEmirate.abuDhabi},
      tasks: {UaeLinkTask.disputesLegal},
      type: UaeLinkType.information,
      url: 'https://adrec.gov.ae/en/adrec-drc',
      titleEn: 'Real Estate Dispute Settlement Centre (Taswea)',
      titleAr: 'مركز تسوية المنازعات العقارية (تسوية)',
      descriptionEn: 'ADREC\'s centre for resolving real-estate disputes by '
          'agreement.',
      descriptionAr: 'مركز المركز العقاري لتسوية المنازعات العقارية بالتراضي.',
      authorityEn: _adrecEn,
      authorityAr: _adrecAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['taswea', 'تسوية', 'dispute', 'settlement', 'نزاع'],
    ),
    UaeLinkEntry(
      id: 'abudhabi-tamm',
      emirates: {UaeLinkEmirate.abuDhabi},
      tasks: {UaeLinkTask.tenancy, UaeLinkTask.salesTitle},
      type: UaeLinkType.portal,
      url: 'https://www.tamm.abudhabi/',
      titleEn: 'TAMM: Abu Dhabi Government Services',
      titleAr: 'تم: خدمات حكومة أبوظبي',
      descriptionEn:
          'The Abu Dhabi Government services platform, with a Property '
          'space for land and real-estate services.',
      descriptionAr:
          'منصة الخدمات الحكومية في أبوظبي، وتضم مساحة «العقارات» لخدمات '
          'الأراضي والعقارات.',
      authorityEn: 'Abu Dhabi Government (TAMM)',
      authorityAr: 'حكومة أبوظبي (تم)',
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: 'Rendered in a browser 2026-10-19: "Government Services" with '
          '"Housing & Properties"; script-rendered, so a plain download '
          'shows an empty frame.',
      keywords: ['tamm', 'تم', 'tawtheeq', 'توثيق'],
    ),
    UaeLinkEntry(
      id: 'abudhabi-dari-home',
      emirates: {UaeLinkEmirate.abuDhabi},
      tasks: {UaeLinkTask.tenancy, UaeLinkTask.salesTitle},
      type: UaeLinkType.portal,
      url: 'https://www.dari.ae/',
      titleEn: 'DARI: Abu Dhabi real-estate platform',
      titleAr: 'داري: منصة العقارات في أبوظبي',
      descriptionEn:
          'ADREC\'s digital real-estate platform for owners, tenants, '
          'brokers and developers.',
      descriptionAr: 'منصة المركز الرقمية للعقارات للملاك والمستأجرين والوسطاء '
          'والمطورين.',
      authorityEn: _adrecEn,
      authorityAr: _adrecAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence:
          'Fetched 2026-10-19: HTTP 200, title "DARI - Welcome". ADREC\'s '
          'site lists DARI support, and DARI service pages carry the ADREC tag.',
      requiresLogin: true,
      keywords: ['dari', 'داري', 'tawtheeq', 'توثيق'],
    ),
    UaeLinkEntry(
      id: 'abudhabi-dari-services',
      emirates: {UaeLinkEmirate.abuDhabi},
      tasks: {UaeLinkTask.tenancy, UaeLinkTask.salesTitle},
      type: UaeLinkType.portal,
      url: 'https://services.dari.ae/services/',
      titleEn: 'DARI service directory',
      titleAr: 'دليل خدمات داري',
      descriptionEn:
          'Every DARI service with its description, documents and steps.',
      descriptionAr: 'جميع خدمات داري مع الوصف والمستندات والخطوات.',
      authorityEn: _adrecEn,
      authorityAr: _adrecAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['dari', 'داري', 'services', 'خدمات'],
    ),
    UaeLinkEntry(
      id: 'abudhabi-tawtheeq-register',
      emirates: {UaeLinkEmirate.abuDhabi},
      tasks: {UaeLinkTask.tenancy},
      type: UaeLinkType.action,
      url:
          'https://services.dari.ae/company-services/tenancy-contract-registration/',
      titleEn: 'Register a lease contract (Tawtheeq)',
      titleAr: 'تسجيل عقد إيجار (توثيق)',
      descriptionEn:
          'Register a new lease contract for a leased unit in Abu Dhabi '
          'through DARI.',
      descriptionAr: 'تسجيل عقد إيجار جديد لوحدة مؤجرة في أبوظبي عبر داري.',
      authorityEn: _adrecEn,
      authorityAr: _adrecAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: '$_fetched The page description names Tawtheeq.',
      requiresLogin: true,
      keywords: ['tawtheeq', 'توثيق', 'lease', 'tenancy', 'dari'],
    ),
    UaeLinkEntry(
      id: 'abudhabi-tawtheeq-renew',
      emirates: {UaeLinkEmirate.abuDhabi},
      tasks: {UaeLinkTask.tenancy, UaeLinkTask.renewalCancellation},
      type: UaeLinkType.action,
      url:
          'https://services.dari.ae/company-services/tenancy-contract-renewal-2/',
      titleEn: 'Renew a lease contract (Tawtheeq)',
      titleAr: 'تجديد عقد إيجار (توثيق)',
      descriptionEn: 'Renew a registered lease contract in Abu Dhabi through '
          'DARI.',
      descriptionAr: 'تجديد عقد إيجار مسجل في أبوظبي عبر داري.',
      authorityEn: _adrecEn,
      authorityAr: _adrecAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      requiresLogin: true,
      keywords: ['tawtheeq', 'توثيق', 'renew', 'تجديد', 'dari'],
    ),
    UaeLinkEntry(
      id: 'abudhabi-tawtheeq-cancel',
      emirates: {UaeLinkEmirate.abuDhabi},
      tasks: {UaeLinkTask.renewalCancellation, UaeLinkTask.tenancy},
      type: UaeLinkType.action,
      url:
          'https://services.dari.ae/company-services/tenancy-contract-cancellation/',
      titleEn: 'Cancel a lease contract (Tawtheeq)',
      titleAr: 'إلغاء عقد إيجار (توثيق)',
      descriptionEn: 'Cancel a registered lease contract in Abu Dhabi through '
          'DARI.',
      descriptionAr: 'إلغاء عقد إيجار مسجل في أبوظبي عبر داري.',
      authorityEn: _adrecEn,
      authorityAr: _adrecAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      requiresLogin: true,
      keywords: ['tawtheeq', 'توثيق', 'cancel', 'إلغاء', 'dari'],
    ),
    UaeLinkEntry(
      id: 'abudhabi-sale-registration',
      emirates: {UaeLinkEmirate.abuDhabi},
      tasks: {UaeLinkTask.salesTitle},
      type: UaeLinkType.action,
      url:
          'https://services.dari.ae/consumer-services/registration-of-sale-and-purchase-of-land-and-real-estate/',
      titleEn: 'Register the sale of land or real estate',
      titleAr: 'تسجيل بيع وشراء الأراضي والعقارات',
      descriptionEn: 'Register a sale and purchase of land or a property in '
          'Abu Dhabi.',
      descriptionAr: 'تسجيل بيع وشراء أرض أو عقار في أبوظبي.',
      authorityEn: _adrecEn,
      authorityAr: _adrecAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      requiresLogin: true,
      keywords: ['sale', 'purchase', 'transfer', 'بيع', 'نقل ملكية'],
    ),
    UaeLinkEntry(
      id: 'abudhabi-ownership-certificate',
      emirates: {UaeLinkEmirate.abuDhabi},
      tasks: {UaeLinkTask.salesTitle, UaeLinkTask.verification},
      type: UaeLinkType.action,
      url:
          'https://services.dari.ae/company-services/certificate-of-owned-properties/',
      titleEn: 'Property ownership certificate',
      titleAr: 'شهادة ملكية عقار',
      descriptionEn: 'Request a certificate of the properties an owner holds '
          'in Abu Dhabi.',
      descriptionAr: 'طلب شهادة بالعقارات المملوكة لمالك في أبوظبي.',
      authorityEn: _adrecEn,
      authorityAr: _adrecAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      requiresLogin: true,
      keywords: ['ownership', 'certificate', 'title', 'شهادة', 'ملكية'],
    ),
    UaeLinkEntry(
      id: 'abudhabi-valuation-certificate',
      emirates: {UaeLinkEmirate.abuDhabi},
      tasks: {UaeLinkTask.valuationIndex},
      type: UaeLinkType.action,
      url:
          'https://services.dari.ae/business-services/request-a-valuation-certificate/',
      titleEn: 'Property valuation certificate',
      titleAr: 'شهادة تقييم عقاري',
      descriptionEn: 'Request an official valuation certificate for property '
          'in Abu Dhabi.',
      descriptionAr: 'طلب شهادة تقييم رسمية لعقار في أبوظبي.',
      authorityEn: _adrecEn,
      authorityAr: _adrecAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      requiresLogin: true,
      keywords: ['valuation', 'تقييم', 'تثمين'],
    ),
    UaeLinkEntry(
      id: 'abudhabi-mortgage-registration',
      emirates: {UaeLinkEmirate.abuDhabi},
      tasks: {UaeLinkTask.salesTitle},
      type: UaeLinkType.action,
      url: 'https://services.dari.ae/company-services/register-unit-mortgage/',
      titleEn: 'Register a unit mortgage',
      titleAr: 'تسجيل رهن وحدة عقارية',
      descriptionEn: 'Register a mortgage contract over a property unit in '
          'Abu Dhabi.',
      descriptionAr: 'تسجيل عقد رهن على وحدة عقارية في أبوظبي.',
      authorityEn: _adrecEn,
      authorityAr: _adrecAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      requiresLogin: true,
      keywords: ['mortgage', 'رهن', 'finance'],
    ),
    UaeLinkEntry(
      id: 'abudhabi-broker-company-licence',
      emirates: {UaeLinkEmirate.abuDhabi},
      tasks: {UaeLinkTask.brokerPermits},
      type: UaeLinkType.action,
      url:
          'https://services.dari.ae/company-services/developers/register-broker-company-2/',
      titleEn: 'Brokerage company licence (issue or renew)',
      titleAr: 'رخصة شركة وساطة عقارية (إصدار أو تجديد)',
      descriptionEn:
          'Issue or renew the licence of a real-estate brokerage company in '
          'Abu Dhabi.',
      descriptionAr: 'إصدار أو تجديد رخصة شركة وساطة عقارية في أبوظبي.',
      authorityEn: _adrecEn,
      authorityAr: _adrecAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      requiresLogin: true,
      keywords: ['broker', 'licence', 'license', 'وسيط', 'رخصة'],
    ),
    UaeLinkEntry(
      id: 'abudhabi-broker-individual-licence',
      emirates: {UaeLinkEmirate.abuDhabi},
      tasks: {UaeLinkTask.brokerPermits},
      type: UaeLinkType.action,
      url:
          'https://services.dari.ae/company-services/developers/register-broker-individual/',
      titleEn: 'Individual broker licence (issue or renew)',
      titleAr: 'رخصة وسيط عقاري فرد (إصدار أو تجديد)',
      descriptionEn: 'Issue or renew an individual real-estate broker licence '
          'in Abu Dhabi.',
      descriptionAr: 'إصدار أو تجديد رخصة وسيط عقاري فرد في أبوظبي.',
      authorityEn: _adrecEn,
      authorityAr: _adrecAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      requiresLogin: true,
      keywords: ['broker', 'licence', 'license', 'وسيط', 'رخصة'],
    ),
    UaeLinkEntry(
      id: 'abudhabi-madhmoun-permit',
      emirates: {UaeLinkEmirate.abuDhabi},
      tasks: {UaeLinkTask.brokerPermits},
      type: UaeLinkType.action,
      url:
          'https://services.dari.ae/company-services/madhmoun-en/request-permit-to-advertise-on-websites-2/',
      titleEn: 'Madhmoun: issue a listing advertisement permit',
      titleAr: 'مضمون: إصدار تصريح إعلان عقاري',
      descriptionEn:
          'Brokers obtain the permit to publish sale or rent listings on an '
          'accredited listing website.',
      descriptionAr:
          'يحصل الوسطاء على تصريح نشر إعلانات البيع أو الإيجار على موقع '
          'إعلانات معتمد.',
      authorityEn: _adrecEn,
      authorityAr: _adrecAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      requiresLogin: true,
      keywords: ['madhmoun', 'مضمون', 'permit', 'listing', 'تصريح'],
    ),
    UaeLinkEntry(
      id: 'abudhabi-madhmoun-renew',
      emirates: {UaeLinkEmirate.abuDhabi},
      tasks: {UaeLinkTask.brokerPermits, UaeLinkTask.renewalCancellation},
      type: UaeLinkType.action,
      url:
          'https://services.dari.ae/company-services/madhmoun-en/renew-permit-to-advertise-on-website/',
      titleEn: 'Madhmoun: renew a listing advertisement permit',
      titleAr: 'مضمون: تجديد تصريح إعلان عقاري',
      descriptionEn: 'Renew an existing Madhmoun advertisement permit.',
      descriptionAr: 'تجديد تصريح إعلان عقاري قائم في مضمون.',
      authorityEn: _adrecEn,
      authorityAr: _adrecAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      requiresLogin: true,
      keywords: ['madhmoun', 'مضمون', 'renew', 'تجديد'],
    ),
    UaeLinkEntry(
      id: 'abudhabi-offplan-first-sale',
      emirates: {UaeLinkEmirate.abuDhabi},
      tasks: {UaeLinkTask.developersOffPlan, UaeLinkTask.salesTitle},
      type: UaeLinkType.action,
      url:
          'https://services.dari.ae/business-services/request-to-register-a-unit-for-first-sale/',
      titleEn: 'Register a unit for first sale (off-plan)',
      titleAr: 'تسجيل وحدة للبيع الأول (على الخارطة)',
      descriptionEn: 'Developer service to register a unit for its first '
          'sale in Abu Dhabi.',
      descriptionAr: 'خدمة للمطورين لتسجيل وحدة للبيع الأول في أبوظبي.',
      authorityEn: _adrecEn,
      authorityAr: _adrecAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      requiresLogin: true,
      keywords: ['off plan', 'off-plan', 'developer', 'على الخارطة', 'مطور'],
    ),
    UaeLinkEntry(
      id: 'abudhabi-offplan-ad-permit',
      emirates: {UaeLinkEmirate.abuDhabi},
      tasks: {UaeLinkTask.developersOffPlan, UaeLinkTask.brokerPermits},
      type: UaeLinkType.action,
      url:
          'https://services.dari.ae/company-services/property-management-company-services/request-an-off-plan-sale-advertisement-permit-2/',
      titleEn: 'Off-plan sale advertisement permit',
      titleAr: 'تصريح إعلان بيع على الخارطة',
      descriptionEn: 'Request the permit to advertise off-plan sales in Abu '
          'Dhabi.',
      descriptionAr: 'طلب تصريح الإعلان عن البيع على الخارطة في أبوظبي.',
      authorityEn: _adrecEn,
      authorityAr: _adrecAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      requiresLogin: true,
      keywords: [
        'off plan',
        'off-plan',
        'advertisement',
        'على الخارطة',
        'إعلان'
      ],
    ),
    UaeLinkEntry(
      id: 'abudhabi-developer-registration',
      emirates: {UaeLinkEmirate.abuDhabi},
      tasks: {UaeLinkTask.developersOffPlan},
      type: UaeLinkType.action,
      url:
          'https://services.dari.ae/business-services/manage-real-estate-developer-registration/',
      titleEn: 'Real estate developer registration',
      titleAr: 'تسجيل المطور العقاري',
      descriptionEn: 'Register and manage a real-estate developer in Abu '
          'Dhabi.',
      descriptionAr: 'تسجيل وإدارة المطور العقاري في أبوظبي.',
      authorityEn: _adrecEn,
      authorityAr: _adrecAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      requiresLogin: true,
      keywords: ['developer', 'registration', 'مطور', 'تسجيل'],
    ),

    // ------------------------------------------------------------ Sharjah
    UaeLinkEntry(
      id: 'sharjah-srerd-home',
      emirates: {UaeLinkEmirate.sharjah},
      tasks: {UaeLinkTask.salesTitle, UaeLinkTask.verification},
      type: UaeLinkType.portal,
      url: 'https://www.shjrerd.gov.ae/',
      titleEn: 'Sharjah Real Estate Registration Department',
      titleAr: 'دائرة التسجيل العقاري في الشارقة',
      descriptionEn: 'The land registry of Sharjah (Aqari Sharjah): property '
          'transactions, mortgages, valuation, projects and statistics. The '
          'site is in Arabic.',
      descriptionAr:
          'سجل الأراضي في الشارقة (عقاري الشارقة): التصرفات العقارية '
          'والرهون والتثمين والمشاريع والإحصائيات.',
      authorityEn: _srerdEn,
      authorityAr: _srerdAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence:
          'Opened in a browser 2026-10-19 (the site is script-only; a plain '
          'download shows a "JavaScript required" notice). Page title, '
          'department name and service list observed.',
      keywords: ['srerd', 'aqari', 'عقاري', 'سريرد', 'التسجيل العقاري'],
    ),
    UaeLinkEntry(
      id: 'sharjah-srerd-services',
      emirates: {UaeLinkEmirate.sharjah},
      tasks: {UaeLinkTask.salesTitle, UaeLinkTask.valuationIndex},
      type: UaeLinkType.portal,
      url: 'https://www.shjrerd.gov.ae/services',
      titleEn: 'SRERD e-services',
      titleAr: 'الخدمات الإلكترونية لدائرة التسجيل العقاري',
      descriptionEn:
          'Property sale, assignment, inheritance, lost deed, subdivision, '
          'valuation, mortgage, licences and developer services. In Arabic.',
      descriptionAr:
          'بيع العقار والتنازل ونقل الإرث وبدل فاقد السند والإفراز والتثمين '
          'والرهن والتراخيص وخدمات المطورين.',
      authorityEn: _srerdEn,
      authorityAr: _srerdAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: 'Opened in a browser 2026-10-19; service categories listed.',
      keywords: ['srerd', 'aqari', 'عقاري', 'valuation', 'تثمين'],
    ),
    UaeLinkEntry(
      id: 'sharjah-srerd-document-verification',
      emirates: {UaeLinkEmirate.sharjah},
      tasks: {UaeLinkTask.verification},
      type: UaeLinkType.verification,
      url: 'https://www.shjrerd.gov.ae/doc-inquiry',
      titleEn: 'Verify a SRERD document',
      titleAr: 'التحقق من وثيقة صادرة عن الدائرة',
      descriptionEn:
          'Check a document by number, date and type, or by scanning its QR '
          'code. In Arabic.',
      descriptionAr:
          'التحقق من وثيقة برقمها وتاريخها ونوعها أو بمسح رمز QR الخاص بها.',
      authorityEn: _srerdEn,
      authorityAr: _srerdAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: 'Opened in a browser 2026-10-19; verification form observed.',
      keywords: ['srerd', 'verify', 'qr', 'تحقق', 'وثيقة'],
    ),
    UaeLinkEntry(
      id: 'sharjah-srerd-fee-calculator',
      emirates: {UaeLinkEmirate.sharjah},
      tasks: {UaeLinkTask.feesPayments},
      type: UaeLinkType.information,
      url: 'https://www.shjrerd.gov.ae/fee-calculator',
      titleEn: 'SRERD fee calculator',
      titleAr: 'حاسبة رسوم دائرة التسجيل العقاري',
      descriptionEn: 'Work out the registration fees of a Sharjah property '
          'transaction. In Arabic.',
      descriptionAr: 'احتساب رسوم تسجيل معاملة عقارية في الشارقة.',
      authorityEn: _srerdEn,
      authorityAr: _srerdAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: 'Opened in a browser 2026-10-19; calculator form observed.',
      keywords: ['srerd', 'fees', 'calculator', 'رسوم', 'حاسبة'],
    ),
    UaeLinkEntry(
      id: 'sharjah-srerd-projects',
      emirates: {UaeLinkEmirate.sharjah},
      tasks: {UaeLinkTask.developersOffPlan, UaeLinkTask.verification},
      type: UaeLinkType.verification,
      url: 'https://www.shjrerd.gov.ae/projects',
      titleEn: 'Registered development projects',
      titleAr: 'مشاريع التطوير العقاري المسجلة',
      descriptionEn:
          'The list of registered Sharjah real-estate projects with their '
          'area and ownership type.',
      descriptionAr:
          'قائمة المشاريع العقارية المسجلة في الشارقة مع المنطقة ونوع '
          'التملك.',
      authorityEn: _srerdEn,
      authorityAr: _srerdAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: 'Opened in a browser 2026-10-19; project list observed.',
      keywords: ['srerd', 'projects', 'developer', 'مشاريع', 'off plan'],
    ),
    UaeLinkEntry(
      id: 'sharjah-srerd-gates',
      emirates: {UaeLinkEmirate.sharjah},
      tasks: {UaeLinkTask.salesTitle, UaeLinkTask.brokerPermits},
      type: UaeLinkType.action,
      url: 'https://gates.shjrerd.gov.ae/',
      titleEn: 'SRERD portals (individuals, developers, banks)',
      titleAr: 'بوابات الدائرة (الأفراد والمطورون والبنوك)',
      descriptionEn: 'Sign-in to the SRERD portals for individuals, owners '
          'associations, developers, government entities and banks.',
      descriptionAr: 'تسجيل الدخول إلى بوابات الدائرة للأفراد واتحادات الملاك '
          'والمطورين والجهات الحكومية والبنوك.',
      authorityEn: _srerdEn,
      authorityAr: _srerdAr,
      verification: UaeLinkVerification.officialManualCheckRequired,
      lastVerified: _checked,
      evidence: 'Linked from the SRERD home page; opens a "Login - RERD" page. '
          'Authenticated functionality not tested.',
      requiresLogin: true,
      keywords: ['srerd', 'gates', 'portal', 'بوابة'],
    ),
    UaeLinkEntry(
      id: 'sharjah-digital',
      emirates: {UaeLinkEmirate.sharjah},
      tasks: {UaeLinkTask.tenancy, UaeLinkTask.digitalIdentity},
      type: UaeLinkType.portal,
      url: 'https://ds.sharjah.ae/',
      titleEn: 'Digital Sharjah (Aqari platform)',
      titleAr: 'الشارقة الرقمية (منصة عقاري)',
      descriptionEn:
          'The Sharjah Government digital portal. It lists Aqari, the '
          'unified real-estate platform. Opening Aqari needs a sign-in.',
      descriptionAr:
          'البوابة الرقمية لحكومة الشارقة، وتضم منصة «عقاري» الموحدة '
          'للخدمات العقارية. يتطلب فتح عقاري تسجيل الدخول.',
      authorityEn: 'Sharjah Digital Department',
      authorityAr: 'دائرة الشارقة الرقمية',
      verification: UaeLinkVerification.officialManualCheckRequired,
      lastVerified: _checked,
      evidence: 'Opened in a browser 2026-10-19: the home page lists the Aqari '
          'platform; the Aqari card leads to a sign-in page, so no public '
          'Aqari address could be confirmed.',
      requiresLogin: true,
      keywords: ['aqari', 'عقاري', 'digital sharjah', 'الشارقة الرقمية'],
    ),
    UaeLinkEntry(
      id: 'sharjah-municipality',
      emirates: {UaeLinkEmirate.sharjah},
      tasks: {UaeLinkTask.tenancy, UaeLinkTask.disputesLegal},
      type: UaeLinkType.portal,
      url: 'https://shjmun.gov.ae/',
      titleEn: 'Sharjah City Municipality',
      titleAr: 'بلدية مدينة الشارقة',
      descriptionEn: 'Municipality services in Sharjah city, including rental '
          'dispute resolution and certificates. In Arabic and English.',
      descriptionAr: 'خدمات بلدية مدينة الشارقة ومنها فض المنازعات الإيجارية '
          'والشهادات.',
      authorityEn: 'Sharjah City Municipality',
      authorityAr: 'بلدية مدينة الشارقة',
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence:
          'Opened in a browser 2026-10-19: "Sharjah City Municipality" with '
          'a service directory that lists rental dispute resolution. The '
          'old portal.shjmun.gov.ae home now redirects here.',
      keywords: ['municipality', 'بلدية', 'sharjah municipality', 'tenancy'],
    ),
    UaeLinkEntry(
      id: 'sharjah-tenancy-contract-details',
      emirates: {UaeLinkEmirate.sharjah},
      tasks: {UaeLinkTask.tenancy, UaeLinkTask.verification},
      type: UaeLinkType.verification,
      url:
          'https://portal.shjmun.gov.ae/en/eservices/Pages/GetTenancyContractInfo.aspx',
      titleEn: 'Request tenancy contract details',
      titleAr: 'طلب تفاصيل عقد إيجار',
      descriptionEn:
          'Look up the details of an attested Sharjah tenancy contract on '
          'the municipality portal.',
      descriptionAr: 'الاستعلام عن تفاصيل عقد إيجار موثق في الشارقة عبر بوابة '
          'البلدية.',
      authorityEn: 'Sharjah City Municipality',
      authorityAr: 'بلدية مدينة الشارقة',
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: 'Fetched 2026-10-19: HTTP 200, heading "Request for details of '
          'tenancy contract"; the municipality home page names the service.',
      keywords: ['tenancy', 'contract', 'عقد ايجار', 'تفاصيل'],
    ),
    UaeLinkEntry(
      id: 'sharjah-sewa-home',
      emirates: {UaeLinkEmirate.sharjah},
      tasks: {UaeLinkTask.utilities},
      type: UaeLinkType.portal,
      url: 'https://www.sewa.gov.ae/en/',
      titleEn: 'SEWA: Sharjah electricity, water and gas',
      titleAr: 'هيئة كهرباء ومياه وغاز الشارقة',
      descriptionEn: 'The Sharjah utility: e-services, bill payment, new '
          'connections and move in / out.',
      descriptionAr:
          'هيئة المرافق في الشارقة: الخدمات الإلكترونية وسداد الفواتير '
          'والتوصيلات الجديدة والانتقال من وإلى العقار.',
      authorityEn: 'Sharjah Electricity, Water and Gas Authority (SEWA)',
      authorityAr: 'هيئة كهرباء ومياه وغاز الشارقة',
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['sewa', 'سيوا', 'electricity', 'كهرباء'],
    ),
    UaeLinkEntry(
      id: 'sharjah-sewa-eservices',
      emirates: {UaeLinkEmirate.sharjah},
      tasks: {UaeLinkTask.utilities, UaeLinkTask.feesPayments},
      type: UaeLinkType.action,
      url: 'https://eservice.sewa.gov.ae/portal/default.aspx',
      titleEn: 'SEWA customer e-services',
      titleAr: 'الخدمات الإلكترونية للمتعاملين لدى هيئة الشارقة',
      descriptionEn:
          'Sign in to SEWA customer services: accounts, bills and the move '
          'in / out request.',
      descriptionAr:
          'تسجيل الدخول إلى خدمات المتعاملين: الحسابات والفواتير وطلب '
          'الانتقال من وإلى العقار.',
      authorityEn: 'Sharjah Electricity, Water and Gas Authority (SEWA)',
      authorityAr: 'هيئة كهرباء ومياه وغاز الشارقة',
      verification: UaeLinkVerification.officialManualCheckRequired,
      lastVerified: _checked,
      evidence: 'Linked from the SEWA home page; fetched 2026-10-19: HTTP 200, '
          'title "SEWA :Login". The move in / out form was not opened.',
      requiresLogin: true,
      keywords: ['sewa', 'move in', 'move out', 'bill', 'فاتورة'],
    ),

    // -------------------------------------------------------------- Ajman
    UaeLinkEntry(
      id: 'ajman-land-home',
      emirates: {UaeLinkEmirate.ajman},
      tasks: {UaeLinkTask.salesTitle, UaeLinkTask.verification},
      type: UaeLinkType.portal,
      url: 'https://ajmanre.gov.ae/en/',
      titleEn: 'Department of Land and Real Estate Regulation',
      titleAr: 'دائرة الأراضي والتنظيم العقاري',
      descriptionEn:
          'Ajman\'s land registry and real-estate regulator: ownership, '
          'long-term leases, brokers, valuation and projects.',
      descriptionAr:
          'سجل الأراضي والجهة المنظمة للعقارات في عجمان: التملك والإيجار '
          'طويل الأمد والوسطاء والتقييم والمشاريع.',
      authorityEn: _ajmanLandEn,
      authorityAr: _ajmanLandAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['ajmanre', 'dlrer', 'عجمان', 'tasdeeq'],
    ),
    UaeLinkEntry(
      id: 'ajman-land-services',
      emirates: {UaeLinkEmirate.ajman},
      tasks: {UaeLinkTask.salesTitle, UaeLinkTask.brokerPermits},
      type: UaeLinkType.portal,
      url: 'https://ajmanre.gov.ae/en/services/',
      titleEn: 'Land department services directory',
      titleAr: 'دليل خدمات دائرة الأراضي',
      descriptionEn: 'All land department services: ownership, transactions, '
          'permits, mortgage, valuation, projects and complaints.',
      descriptionAr: 'جميع خدمات الدائرة: الملكية والمعاملات والتصاريح والرهن '
          'والتقييم والمشاريع والشكاوى.',
      authorityEn: _ajmanLandEn,
      authorityAr: _ajmanLandAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['services', 'ajmanre', 'خدمات'],
    ),
    UaeLinkEntry(
      id: 'ajman-land-eservices',
      emirates: {UaeLinkEmirate.ajman},
      tasks: {UaeLinkTask.salesTitle},
      type: UaeLinkType.action,
      url: 'https://eservices.ajmanre.gov.ae/en/',
      titleEn: 'Land department e-services (sign-in)',
      titleAr: 'الخدمات الإلكترونية لدائرة الأراضي (تسجيل الدخول)',
      descriptionEn:
          'The online transaction portal of the land department, such as '
          'remote sale registration.',
      descriptionAr:
          'بوابة المعاملات الإلكترونية للدائرة، مثل تسجيل البيع عن بعد.',
      authorityEn: _ajmanLandEn,
      authorityAr: _ajmanLandAr,
      verification: UaeLinkVerification.officialManualCheckRequired,
      lastVerified: _checked,
      evidence: 'Linked from the land department site; fetched 2026-10-19: '
          'HTTP 200, script-only page. Sign-in not tested.',
      requiresLogin: true,
      keywords: ['eservices', 'remote sale', 'بيع عن بعد'],
    ),
    UaeLinkEntry(
      id: 'ajman-sale-registration',
      emirates: {UaeLinkEmirate.ajman},
      tasks: {UaeLinkTask.salesTitle},
      type: UaeLinkType.action,
      url:
          'https://ajmanre.gov.ae/en/services/sale-registration-of-a-real-estate-real-estate-unit/',
      titleEn: 'Sale registration of a property or unit',
      titleAr: 'تسجيل بيع عقار أو وحدة عقارية',
      descriptionEn: 'Register the sale of a property or property unit in '
          'Ajman.',
      descriptionAr: 'تسجيل بيع عقار أو وحدة عقارية في عجمان.',
      authorityEn: _ajmanLandEn,
      authorityAr: _ajmanLandAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['sale', 'transfer', 'بيع'],
    ),
    UaeLinkEntry(
      id: 'ajman-long-term-lease',
      emirates: {UaeLinkEmirate.ajman},
      tasks: {UaeLinkTask.tenancy},
      type: UaeLinkType.action,
      url:
          'https://ajmanre.gov.ae/en/services/registration-of-a-long-term-lease/',
      titleEn: 'Register a long-term lease contract',
      titleAr: 'تسجيل عقد إيجار طويل الأمد',
      descriptionEn:
          'Register a long-term lease contract with the land department. '
          'Short residential and commercial leases are attested through '
          'Tasdeeq instead.',
      descriptionAr:
          'تسجيل عقد إيجار طويل الأمد لدى دائرة الأراضي. أما عقود الإيجار '
          'السكنية والتجارية العادية فتصدَّق عبر «تصديق».',
      authorityEn: _ajmanLandEn,
      authorityAr: _ajmanLandAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence:
          '$_fetched The old address redirected here from /our-services/.',
      keywords: ['long term lease', 'lease', 'إيجار طويل', 'ايجار'],
    ),
    UaeLinkEntry(
      id: 'ajman-office-registration',
      emirates: {UaeLinkEmirate.ajman},
      tasks: {UaeLinkTask.brokerPermits},
      type: UaeLinkType.action,
      url:
          'https://ajmanre.gov.ae/en/services/issuance-of-a-real-estate-office-registration-certificate/',
      titleEn: 'Real estate office registration certificate',
      titleAr: 'شهادة تسجيل مكتب عقاري',
      descriptionEn: 'Register a real-estate brokerage office in Ajman.',
      descriptionAr: 'تسجيل مكتب وساطة عقارية في عجمان.',
      authorityEn: _ajmanLandEn,
      authorityAr: _ajmanLandAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['office', 'broker', 'مكتب عقاري', 'وسيط'],
    ),
    UaeLinkEntry(
      id: 'ajman-practice-card',
      emirates: {UaeLinkEmirate.ajman},
      tasks: {UaeLinkTask.brokerPermits},
      type: UaeLinkType.action,
      url:
          'https://ajmanre.gov.ae/en/services/issuance-of-a-real-estate-activity-practice-card/',
      titleEn: 'Real estate activity practice card',
      titleAr: 'بطاقة مزاولة النشاط العقاري',
      descriptionEn: 'Issue the card that lets a broker practise real-estate '
          'activity in Ajman.',
      descriptionAr: 'إصدار بطاقة مزاولة النشاط العقاري للوسيط في عجمان.',
      authorityEn: _ajmanLandEn,
      authorityAr: _ajmanLandAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['broker card', 'practice card', 'بطاقة', 'وسيط'],
    ),
    UaeLinkEntry(
      id: 'ajman-ad-permit',
      emirates: {UaeLinkEmirate.ajman},
      tasks: {UaeLinkTask.brokerPermits},
      type: UaeLinkType.action,
      url:
          'https://ajmanre.gov.ae/en/services/real-estate-advertisement-permission-real-estate-advertisements-plan/',
      titleEn: 'Real estate advertising permit',
      titleAr: 'تصريح الإعلان العقاري',
      descriptionEn: 'Issue a permit to advertise real estate in Ajman.',
      descriptionAr: 'إصدار تصريح للإعلان عن العقارات في عجمان.',
      authorityEn: _ajmanLandEn,
      authorityAr: _ajmanLandAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['advertisement', 'permit', 'إعلان', 'تصريح'],
    ),
    UaeLinkEntry(
      id: 'ajman-valuation',
      emirates: {UaeLinkEmirate.ajman},
      tasks: {UaeLinkTask.valuationIndex},
      type: UaeLinkType.action,
      url: 'https://ajmanre.gov.ae/en/services/real-estate-valuation/',
      titleEn: 'Real estate valuation',
      titleAr: 'التقييم العقاري',
      descriptionEn: 'Request an official valuation of a property in Ajman.',
      descriptionAr: 'طلب تقييم رسمي لعقار في عجمان.',
      authorityEn: _ajmanLandEn,
      authorityAr: _ajmanLandAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['valuation', 'تقييم', 'تثمين'],
    ),
    UaeLinkEntry(
      id: 'ajman-project-registration',
      emirates: {UaeLinkEmirate.ajman},
      tasks: {UaeLinkTask.developersOffPlan},
      type: UaeLinkType.action,
      url:
          'https://ajmanre.gov.ae/en/services/real-estate-project-registration/',
      titleEn: 'Real estate project registration',
      titleAr: 'تسجيل المشاريع العقارية',
      descriptionEn: 'Register a real-estate development project in Ajman.',
      descriptionAr: 'تسجيل مشروع تطوير عقاري في عجمان.',
      authorityEn: _ajmanLandEn,
      authorityAr: _ajmanLandAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['project', 'developer', 'off plan', 'مشروع', 'مطور'],
    ),
    UaeLinkEntry(
      id: 'ajman-dispute-resolution',
      emirates: {UaeLinkEmirate.ajman},
      tasks: {UaeLinkTask.disputesLegal},
      type: UaeLinkType.action,
      url:
          'https://ajmanre.gov.ae/en/services/application-for-resolution-of-a-real-estate-dispute/',
      titleEn: 'Apply to resolve a real estate dispute',
      titleAr: 'طلب حل نزاع عقاري',
      descriptionEn: 'Submit a real-estate dispute to the land department.',
      descriptionAr: 'تقديم نزاع عقاري إلى دائرة الأراضي.',
      authorityEn: _ajmanLandEn,
      authorityAr: _ajmanLandAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['dispute', 'complaint', 'نزاع', 'شكوى'],
    ),
    UaeLinkEntry(
      id: 'ajman-tasdeeq-home',
      emirates: {UaeLinkEmirate.ajman},
      tasks: {UaeLinkTask.tenancy, UaeLinkTask.renewalCancellation},
      type: UaeLinkType.portal,
      url: 'https://tasdeeq.am.gov.ae/en/',
      titleEn: 'Tasdeeq: lease contract attestation (Ajman)',
      titleAr: 'تصديق: توثيق عقود الإيجار (عجمان)',
      descriptionEn:
          'Ajman\'s online system for attesting, cancelling and certifying '
          'lease contracts. The landlord applies, not the tenant.',
      descriptionAr:
          'نظام عجمان الإلكتروني لتصديق عقود الإيجار وإلغائها وإصدار '
          'شهادات تسجيلها. يقدّم الطلب المؤجر وليس المستأجر.',
      authorityEn: _ajmanMunEn,
      authorityAr: _ajmanMunAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence:
          'Fetched 2026-10-19: HTTP 200, title "Tasdeeq"; footer credits the '
          'Municipality and Planning Department, Government of Ajman. This '
          'is an Ajman service (the old directory filed it under Sharjah).',
      keywords: ['tasdeeq', 'تصديق', 'tasdiq', 'attestation', 'ejari'],
    ),
    UaeLinkEntry(
      id: 'ajman-tasdeeq-services',
      emirates: {UaeLinkEmirate.ajman},
      tasks: {UaeLinkTask.tenancy, UaeLinkTask.renewalCancellation},
      type: UaeLinkType.portal,
      url: 'https://tasdeeq.am.gov.ae/en/services.html',
      titleEn: 'Tasdeeq services list',
      titleAr: 'قائمة خدمات تصديق',
      descriptionEn:
          'Property registration, residential, commercial, investment and '
          'staff-housing attestation, cancellation and registration '
          'certificates.',
      descriptionAr:
          'تسجيل العقارات وتصديق العقود السكنية والتجارية والاستثمارية '
          'وسكن العمال وإلغاء العقود وشهادات التسجيل.',
      authorityEn: _ajmanMunEn,
      authorityAr: _ajmanMunAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['tasdeeq', 'تصديق', 'attestation'],
    ),
    UaeLinkEntry(
      id: 'ajman-tasdeeq-residential',
      emirates: {UaeLinkEmirate.ajman},
      tasks: {UaeLinkTask.tenancy},
      type: UaeLinkType.action,
      url:
          'https://www.am.gov.ae/en/services/authentication-of-lease-contract-for-residential-purposes/',
      titleEn: 'Attest a residential lease contract (Tasdeeq)',
      titleAr: 'تصديق عقد إيجار سكني (تصديق)',
      descriptionEn: 'Attest the lease contract of a residential unit in '
          'Ajman.',
      descriptionAr: 'تصديق عقد إيجار وحدة سكنية في عجمان.',
      authorityEn: _ajmanMunEn,
      authorityAr: _ajmanMunAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      requiresLogin: true,
      keywords: ['tasdeeq', 'تصديق', 'residential', 'سكني'],
    ),
    UaeLinkEntry(
      id: 'ajman-tasdeeq-economic',
      emirates: {UaeLinkEmirate.ajman},
      tasks: {UaeLinkTask.tenancy},
      type: UaeLinkType.action,
      url: 'https://tasdeeq.am.gov.ae/en/service06.html',
      titleEn: 'Attest a lease contract for economic activities (Tasdeeq)',
      titleAr: 'تصديق عقد إيجار للأنشطة الاقتصادية (تصديق)',
      descriptionEn: 'Attest the lease of a property used for a commercial '
          'or economic activity in Ajman.',
      descriptionAr:
          'تصديق عقد إيجار عقار مستخدم لنشاط تجاري أو اقتصادي في عجمان.',
      authorityEn: _ajmanMunEn,
      authorityAr: _ajmanMunAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      requiresLogin: true,
      keywords: ['tasdeeq', 'تصديق', 'commercial', 'تجاري'],
    ),
    UaeLinkEntry(
      id: 'ajman-tasdeeq-cancel',
      emirates: {UaeLinkEmirate.ajman},
      tasks: {UaeLinkTask.renewalCancellation, UaeLinkTask.tenancy},
      type: UaeLinkType.action,
      url: 'https://tasdeeq.am.gov.ae/en/service07.html',
      titleEn: 'Cancel a lease contract (Tasdeeq)',
      titleAr: 'إلغاء عقد إيجار (تصديق)',
      descriptionEn: 'Cancel a residential, commercial or investment lease '
          'contract in Ajman.',
      descriptionAr: 'إلغاء عقد إيجار سكني أو تجاري أو استثماري في عجمان.',
      authorityEn: _ajmanMunEn,
      authorityAr: _ajmanMunAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      requiresLogin: true,
      keywords: ['tasdeeq', 'تصديق', 'cancel', 'إلغاء'],
    ),
    UaeLinkEntry(
      id: 'ajman-digital-catalogue',
      emirates: {UaeLinkEmirate.ajman},
      tasks: {UaeLinkTask.planningPermits, UaeLinkTask.salesTitle},
      type: UaeLinkType.portal,
      url:
          'https://www.ajman.ae/en/servicecatalog/service_categories/department-land-real-estate-regulation',
      titleEn: 'Ajman government service catalogue: land and real estate',
      titleAr: 'دليل خدمات حكومة عجمان: الأراضي والعقارات',
      descriptionEn: 'The Ajman Government catalogue of land and real-estate '
          'services.',
      descriptionAr: 'دليل حكومة عجمان لخدمات الأراضي والعقارات.',
      authorityEn: 'Department of Digital Ajman',
      authorityAr: 'دائرة عجمان الرقمية',
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['digital ajman', 'عجمان الرقمية', 'catalogue', 'دليل'],
    ),

    // ----------------------------------------------------- Ras Al Khaimah
    UaeLinkEntry(
      id: 'rak-lands-properties-sector',
      emirates: {UaeLinkEmirate.rasAlKhaimah},
      tasks: {UaeLinkTask.salesTitle, UaeLinkTask.tenancy},
      type: UaeLinkType.information,
      url:
          'https://mun.rak.ae/home/rak-municipality/organizational-structure/lands-properties-sector/',
      titleEn: 'Lands and Properties Sector',
      titleAr: 'قطاع الأراضي والأملاك',
      descriptionEn:
          'The RAK Municipality sector that registers land and property '
          'and regulates the real-estate market.',
      descriptionAr: 'قطاع بلدية رأس الخيمة المسؤول عن تسجيل الأراضي والأملاك '
          'وتنظيم السوق العقاري.',
      authorityEn: _rakMunEn,
      authorityAr: _rakMunAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['lands', 'properties', 'أراضي', 'أملاك'],
    ),
    UaeLinkEntry(
      id: 'rak-real-estate-regulatory',
      emirates: {UaeLinkEmirate.rasAlKhaimah},
      tasks: {UaeLinkTask.brokerPermits},
      type: UaeLinkType.information,
      url:
          'https://mun.rak.ae/home/rak-municipality/organizational-structure/lands-properties-sector/real-estate-regulatory-administration/',
      titleEn: 'Real Estate Regulatory Administration',
      titleAr: 'إدارة التنظيم العقاري',
      descriptionEn: 'The RAK Municipality administration that regulates '
          'real-estate offices and activity.',
      descriptionAr:
          'إدارة بلدية رأس الخيمة التي تنظّم المكاتب والنشاط العقاري.',
      authorityEn: _rakMunEn,
      authorityAr: _rakMunAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['regulatory', 'real estate office', 'تنظيم عقاري', 'مكتب'],
    ),
    UaeLinkEntry(
      id: 'rak-sanad-rental-affairs',
      emirates: {UaeLinkEmirate.rasAlKhaimah},
      tasks: {UaeLinkTask.tenancy, UaeLinkTask.renewalCancellation},
      type: UaeLinkType.information,
      url: 'https://sanad.mun.rak.ae/docs/en/rental-affairs',
      titleEn: 'Rental affairs: service cards',
      titleAr: 'شؤون الإيجار: بطاقات الخدمات',
      descriptionEn:
          'The RAK Municipality service cards for new, renewed, amended and '
          'cancelled tenancy contracts, with steps, documents and fees.',
      descriptionAr:
          'بطاقات خدمات بلدية رأس الخيمة لعقود الإيجار الجديدة والمجددة '
          'والمعدلة والملغاة مع الخطوات والمستندات والرسوم.',
      authorityEn: _rakMunEn,
      authorityAr: _rakMunAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: '$_fetched Sanad is the municipality support centre.',
      keywords: ['sanad', 'سند', 'rental', 'tenancy', 'إيجار'],
    ),
    UaeLinkEntry(
      id: 'rak-new-tenancy',
      emirates: {UaeLinkEmirate.rasAlKhaimah},
      tasks: {UaeLinkTask.tenancy},
      type: UaeLinkType.information,
      url: 'https://sanad.mun.rak.ae/docs/en/services-card-english-temp-32',
      titleEn: 'ZL41: new tenancy contract',
      titleAr: 'ZL41: عقد إيجار جديد',
      descriptionEn:
          'How to issue a residential, commercial or investment tenancy '
          'contract in Ras Al Khaimah, with fees and the EtihadWE move-in '
          'request.',
      descriptionAr:
          'كيفية إصدار عقد إيجار سكني أو تجاري أو استثماري في رأس الخيمة '
          'مع الرسوم وطلب الانتقال لدى الاتحاد للماء والكهرباء.',
      authorityEn: _rakMunEn,
      authorityAr: _rakMunAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['zl41', 'new tenancy', 'ejari', 'عقد جديد'],
    ),
    UaeLinkEntry(
      id: 'rak-renew-tenancy',
      emirates: {UaeLinkEmirate.rasAlKhaimah},
      tasks: {UaeLinkTask.tenancy, UaeLinkTask.renewalCancellation},
      type: UaeLinkType.information,
      url: 'https://sanad.mun.rak.ae/docs/en/services-card-english-temp-57',
      titleEn: 'ZL43: renew a tenancy contract',
      titleAr: 'ZL43: تجديد عقد الإيجار',
      descriptionEn: 'How to renew a tenancy contract in Ras Al Khaimah.',
      descriptionAr: 'كيفية تجديد عقد إيجار في رأس الخيمة.',
      authorityEn: _rakMunEn,
      authorityAr: _rakMunAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['zl43', 'renew', 'تجديد'],
    ),
    UaeLinkEntry(
      id: 'rak-modify-tenancy',
      emirates: {UaeLinkEmirate.rasAlKhaimah},
      tasks: {UaeLinkTask.tenancy, UaeLinkTask.renewalCancellation},
      type: UaeLinkType.information,
      url: 'https://sanad.mun.rak.ae/docs/en/services-card-english-temp-58',
      titleEn: 'ZL44: modify a tenancy contract',
      titleAr: 'ZL44: تعديل عقد الإيجار',
      descriptionEn: 'How to amend the terms or details of a tenancy '
          'contract in Ras Al Khaimah.',
      descriptionAr: 'كيفية تعديل شروط أو بيانات عقد إيجار في رأس الخيمة.',
      authorityEn: _rakMunEn,
      authorityAr: _rakMunAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['zl44', 'amend', 'modify', 'تعديل'],
    ),
    UaeLinkEntry(
      id: 'rak-sanad-lands-properties',
      emirates: {UaeLinkEmirate.rasAlKhaimah},
      tasks: {UaeLinkTask.salesTitle, UaeLinkTask.brokerPermits},
      type: UaeLinkType.information,
      url: 'https://sanad.mun.rak.ae/docs/en/lands-and-properties',
      titleEn: 'Lands and properties: service cards',
      titleAr: 'الأراضي والأملاك: بطاقات الخدمات',
      descriptionEn: 'Service cards for real-estate registration, title deeds, '
          'valuation certificates and real-estate offices.',
      descriptionAr:
          'بطاقات خدمات التسجيل العقاري وسندات الملكية وشهادات التقييم '
          'والمكاتب العقارية.',
      authorityEn: _rakMunEn,
      authorityAr: _rakMunAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['sanad', 'سند', 'title deed', 'registration', 'تسجيل'],
    ),
    UaeLinkEntry(
      id: 'rak-sale-contract',
      emirates: {UaeLinkEmirate.rasAlKhaimah},
      tasks: {UaeLinkTask.salesTitle},
      type: UaeLinkType.information,
      url: 'https://sanad.mun.rak.ae/docs/en/services-card-arabic-temp-28',
      titleEn: 'ZL13: real estate sale contract registration',
      titleAr: 'ZL13: تسجيل عقد البيع العقاري',
      descriptionEn: 'How to register a property sale contract in Ras Al '
          'Khaimah.',
      descriptionAr: 'كيفية تسجيل عقد بيع عقار في رأس الخيمة.',
      authorityEn: _rakMunEn,
      authorityAr: _rakMunAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['zl13', 'sale', 'بيع'],
    ),
    UaeLinkEntry(
      id: 'rak-digital',
      emirates: {UaeLinkEmirate.rasAlKhaimah},
      tasks: {UaeLinkTask.tenancy, UaeLinkTask.planningPermits},
      type: UaeLinkType.portal,
      url: 'https://rakdigital.rak.ae/index.html?sap-language=en',
      titleEn: 'RAK Digital: government e-services',
      titleAr: 'رأس الخيمة الرقمية: الخدمات الحكومية الإلكترونية',
      descriptionEn:
          'The RAK Government e-services portal linked from the municipality '
          'site, for online tenancy and municipal services.',
      descriptionAr:
          'بوابة الخدمات الإلكترونية لحكومة رأس الخيمة المرتبطة بموقع '
          'البلدية للخدمات الإيجارية والبلدية.',
      authorityEn: 'RAK Digital (Ras Al Khaimah Government)',
      authorityAr: 'رأس الخيمة الرقمية (حكومة رأس الخيمة)',
      verification: UaeLinkVerification.officialManualCheckRequired,
      lastVerified: _checked,
      evidence:
          'Linked as "E-Services" from the RAK Municipality site; fetched '
          '2026-10-19: HTTP 200, title "RAK Digital", script-only page. The '
          'old rak.ae/wps tenancy address is retired.',
      requiresLogin: true,
      keywords: ['rak digital', 'rakdigital', 'mrak', 'e-services'],
    ),

    // ---------------------------------------------------- Umm Al Quwain
    UaeLinkEntry(
      id: 'uaq-services-platform',
      emirates: {UaeLinkEmirate.ummAlQuwain},
      tasks: {UaeLinkTask.tenancy, UaeLinkTask.planningPermits},
      type: UaeLinkType.portal,
      url: 'https://portal.uaq.ae/',
      titleEn: 'Umm Al Quwain services platform (Digital UAQ)',
      titleAr: 'منصة خدمات أم القيوين (أم القيوين الرقمية)',
      descriptionEn: 'The single platform for Umm Al Quwain local government '
          'services, including municipality services such as property '
          'certificates. Search its directory for lease and property '
          'services.',
      descriptionAr:
          'المنصة الموحدة لخدمات حكومة أم القيوين المحلية، ومنها خدمات '
          'البلدية كشهادات العقارات. ابحث في دليلها عن خدمات الإيجار '
          'والعقار.',
      authorityEn: 'Digital UAQ (Umm Al Quwain Government)',
      authorityAr: 'أم القيوين الرقمية (حكومة أم القيوين)',
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence:
          'Opened in a browser 2026-10-19: "Services platform - DigitalUAQ" '
          'with a service directory listing a Municipality service. No '
          'lease-attestation service address could be confirmed, so only '
          'the platform is listed. The old md.uaq.ae/service.php address '
          'no longer responds and is retired.',
      keywords: ['uaq', 'digital uaq', 'smart uaq', 'أم القيوين'],
    ),
    UaeLinkEntry(
      id: 'uaq-digital-department',
      emirates: {UaeLinkEmirate.ummAlQuwain},
      tasks: {UaeLinkTask.digitalIdentity},
      type: UaeLinkType.information,
      url: 'https://www.digitaluaq.ae/',
      titleEn: 'Digital Umm Al Quwain',
      titleAr: 'أم القيوين الرقمية',
      descriptionEn:
          'About the Digital UAQ department, its apps (SmartUAQ) and the '
          'links to the other emirates\' government portals.',
      descriptionAr:
          'نبذة عن دائرة أم القيوين الرقمية وتطبيقاتها (SmartUAQ) وروابط '
          'بوابات حكومات الإمارات الأخرى.',
      authorityEn: 'Digital UAQ (Umm Al Quwain Government)',
      authorityAr: 'أم القيوين الرقمية (حكومة أم القيوين)',
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: _fetched,
      keywords: ['smartuaq', 'digital uaq', 'app', 'تطبيق'],
    ),

    // ----------------------------------------------------------- Fujairah
    UaeLinkEntry(
      id: 'fujairah-municipality',
      emirates: {UaeLinkEmirate.fujairah},
      tasks: {UaeLinkTask.tenancy, UaeLinkTask.planningPermits},
      type: UaeLinkType.portal,
      url: 'https://www.fujmun.gov.ae/',
      titleEn: 'Fujairah Municipality',
      titleAr: 'بلدية الفجيرة',
      descriptionEn:
          'The municipality website: online e-services, quick payment, the '
          'service list and the "My wallet" account.',
      descriptionAr:
          'موقع البلدية: الخدمات الإلكترونية والدفع السريع ولائحة الخدمات '
          'و«محفظتي».',
      authorityEn: _fujMunEn,
      authorityAr: _fujMunAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: 'Opened in a browser 2026-10-19; page "بلدية الفجيرة".',
      keywords: ['fujmun', 'municipality', 'بلدية الفجيرة'],
    ),
    UaeLinkEntry(
      id: 'fujairah-rental-services',
      emirates: {UaeLinkEmirate.fujairah},
      tasks: {UaeLinkTask.tenancy, UaeLinkTask.renewalCancellation},
      type: UaeLinkType.portal,
      url:
          'https://portal.fujmun.gov.ae/OnlineEServices/en/eService/ServicePages/services.aspx?RK=rental&packid=11',
      titleEn: 'Rental services',
      titleAr: 'خدمات الإيجارات',
      descriptionEn:
          'Attest, amend or cancel a lease contract, replace a lost lease '
          'document, register units, buildings and property data. The '
          'service list is in Arabic.',
      descriptionAr:
          'توثيق عقد الإيجار وتعديله وإلغاؤه وبدل فاقد وثيقة العقد وتسجيل '
          'الوحدات والمباني وتعديل بيانات العقار.',
      authorityEn: _fujMunEn,
      authorityAr: _fujMunAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence: 'Opened in a browser 2026-10-19: the "خدمات الإيجارات" list is '
          'shown (cancel lease, replace lost lease document, amend lease, '
          'attest lease, register units, register via a real-estate '
          'company, amend property data, register building).',
      requiresLogin: true,
      keywords: ['rental', 'attestation', 'توثيق عقد', 'ejaar', 'إيجار'],
    ),
    UaeLinkEntry(
      id: 'fujairah-ejaar',
      emirates: {UaeLinkEmirate.fujairah},
      tasks: {UaeLinkTask.tenancy, UaeLinkTask.renewalCancellation},
      type: UaeLinkType.action,
      url: 'https://ejaar.fujmun.gov.ae/ejaar/pages/LoginForm',
      titleEn: 'Ejaar: Fujairah tenancy system',
      titleAr: 'إيجار: نظام عقود الإيجار في الفجيرة',
      descriptionEn: 'Sign in to Ejaar as a landlord, tenant, owner, agent or '
          'property manager to manage tenancy contracts.',
      descriptionAr:
          'تسجيل الدخول إلى «إيجار» كمؤجر أو مستأجر أو مالك أو وكيل أو '
          'مدير عقارات لإدارة عقود الإيجار.',
      authorityEn: _fujMunEn,
      authorityAr: _fujMunAr,
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence:
          'Opened in a browser 2026-10-19: "Ejaar - Fujairah Municipality" '
          'sign-in with the user roles. Sign-in not tested.',
      requiresLogin: true,
      keywords: ['ejaar', 'ايجار', 'إيجار', 'ejari'],
    ),
    UaeLinkEntry(
      id: 'fujairah-ejaar-guide',
      emirates: {UaeLinkEmirate.fujairah},
      tasks: {UaeLinkTask.tenancy},
      type: UaeLinkType.information,
      url:
          'https://ejaar.fujmun.gov.ae/Ejaar/assets/files/EJAAR%20User%20Guide_English.pdf',
      titleEn: 'Ejaar user guide (PDF)',
      titleAr: 'دليل مستخدم إيجار (PDF)',
      descriptionEn: 'Step-by-step guide to the Ejaar system, in English.',
      descriptionAr: 'دليل خطوة بخطوة لنظام إيجار باللغة الإنجليزية.',
      authorityEn: _fujMunEn,
      authorityAr: _fujMunAr,
      verification: UaeLinkVerification.officialManualCheckRequired,
      lastVerified: _checked,
      evidence:
          'Linked from the Ejaar site; fetched 2026-10-19: HTTP 200, a PDF of '
          'about 1.2 MB with an "EJAAR" file name. The PDF text was not read, '
          'so its content and date were not confirmed.',
      keywords: ['ejaar', 'guide', 'manual', 'دليل'],
    ),
    UaeLinkEntry(
      id: 'fujairah-government-portal',
      emirates: {UaeLinkEmirate.fujairah},
      tasks: {UaeLinkTask.digitalIdentity},
      type: UaeLinkType.portal,
      url: 'https://www.fujairah.ae/en/Pages/default.aspx',
      titleEn: 'Fujairah Government official portal',
      titleAr: 'البوابة الرسمية لحكومة الفجيرة',
      descriptionEn:
          'The official guide to living, working and investing in Fujairah, '
          'with links to government services.',
      descriptionAr:
          'الدليل الرسمي للعيش والعمل والاستثمار في الفجيرة مع روابط '
          'للخدمات الحكومية.',
      authorityEn: 'Fujairah Government',
      authorityAr: 'حكومة الفجيرة',
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence:
          'Opened in a browser 2026-10-19: "The Official Portal of Fujairah '
          'Government".',
      keywords: ['fujairah.ae', 'government portal', 'بوابة'],
    ),

    // ------------------------------------------------ Northern Emirates
    UaeLinkEntry(
      id: 'northern-etihadwe-activation',
      emirates: {
        UaeLinkEmirate.ajman,
        UaeLinkEmirate.rasAlKhaimah,
        UaeLinkEmirate.ummAlQuwain,
        UaeLinkEmirate.fujairah,
      },
      tasks: {UaeLinkTask.utilities, UaeLinkTask.tenancy},
      type: UaeLinkType.action,
      url:
          'https://www.etihadwe.ae/en/Services/eServices/Pages/Service-Activation.aspx',
      titleEn: 'EtihadWE: activate electricity and water',
      titleAr: 'الاتحاد للماء والكهرباء: تفعيل الخدمة',
      descriptionEn:
          'Activate electricity and water for a new tenant after the '
          'previous account was closed. Sign in with UAE PASS. EtihadWE '
          'serves the northern emirates.',
      descriptionAr:
          'تفعيل الكهرباء والماء لمستأجر جديد بعد إغلاق الحساب السابق. '
          'تسجيل الدخول عبر UAE PASS. يخدم الاتحاد للماء والكهرباء الإمارات '
          'الشمالية.',
      authorityEn: 'Etihad Water and Electricity (EtihadWE)',
      authorityAr: 'الاتحاد للماء والكهرباء',
      verification: UaeLinkVerification.verifiedOfficial,
      lastVerified: _checked,
      evidence:
          'Opened in a browser 2026-10-19: "eServices Service Activation" '
          'with its steps. The home page says it provides electricity and '
          'water to the northern emirates; the exact territory of each '
          'emirate was not confirmed.',
      requiresLogin: true,
      keywords: ['etihadwe', 'ewe', 'الاتحاد للماء', 'move in', 'electricity'],
    ),
  ];
}
