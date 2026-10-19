/// The emirate (or the whole country) a directory entry belongs to.
///
/// An entry only claims [uae] when the service really is federal. A service
/// that one emirate delivers names that emirate, so the directory never implies
/// a local service is nationwide.
enum UaeLinkEmirate {
  uae('ulxUaeWide'),
  dubai('dubai'),
  abuDhabi('abuDhabi'),
  sharjah('sharjah'),
  ajman('ajman'),
  rasAlKhaimah('rasAlKhaimah'),
  ummAlQuwain('ummAlQuwain'),
  fujairah('fujairah');

  const UaeLinkEmirate(this.labelKey);

  /// Localization key of the emirate's name.
  final String labelKey;
}

/// What a broker is trying to get done; one entry can serve several tasks.
enum UaeLinkTask {
  tenancy('ulxTaskTenancy'),
  renewalCancellation('ulxTaskRenewalCancellation'),
  salesTitle('ulxTaskSalesTitle'),
  verification('ulxTaskVerification'),
  brokerPermits('ulxTaskBrokerPermits'),
  developersOffPlan('ulxTaskDevelopersOffPlan'),
  valuationIndex('ulxTaskValuationIndex'),
  planningPermits('ulxTaskPlanningPermits'),
  feesPayments('ulxTaskFeesPayments'),
  utilities('ulxTaskUtilities'),
  disputesLegal('ulxTaskDisputesLegal'),
  digitalIdentity('ulxTaskDigitalIdentity');

  const UaeLinkTask(this.labelKey);

  /// Localization key of the task's name.
  final String labelKey;
}

/// What opening the link gives the user, so an online application is never
/// mistaken for general information.
enum UaeLinkType {
  /// An online application or transaction (normally behind a login).
  action('ulxTypeAction'),

  /// A public look-up or verification tool.
  verification('ulxTypeVerification'),

  /// An official page that explains a service or a rule.
  information('ulxTypeInformation'),

  /// A landing page or directory of an authority's services.
  portal('ulxTypePortal'),

  /// A payment platform (not a regulator or a government department).
  payment('ulxTypePayment');

  const UaeLinkType(this.labelKey);

  final String labelKey;
}

/// How far an entry's destination has been checked against official evidence.
enum UaeLinkVerification {
  /// The authority, the URL and the page content were all observed and match.
  verifiedOfficial,

  /// The authority and URL are established, but the destination could not be
  /// fully confirmed (script-only page, login wall, bot blocking); the user is
  /// told to check the details on the site.
  officialManualCheckRequired,

  /// Not checked. Never published.
  unverified,

  /// Known dead or replaced. Never published.
  retired;

  /// Only these two reach the user.
  bool get isPublishable =>
      this == verifiedOfficial || this == officialManualCheckRequired;
}

/// One curated official service or portal.
///
/// The Arabic and English texts live here, in the catalogue, instead of in the
/// ARB files: they are directory content that is reviewed together with the URL
/// and the evidence, not screen chrome.
class UaeLinkEntry {
  const UaeLinkEntry({
    required this.id,
    required this.emirates,
    required this.tasks,
    required this.type,
    required this.url,
    required this.titleEn,
    required this.titleAr,
    required this.descriptionEn,
    required this.descriptionAr,
    required this.authorityEn,
    required this.authorityAr,
    required this.verification,
    required this.lastVerified,
    required this.evidence,
    this.requiresLogin = false,
    this.keywords = const <String>[],
    this.alternativeUrl,
  });

  /// Stable, unique, never reused.
  final String id;

  /// The emirate(s) the service applies to; [UaeLinkEmirate.uae] only for
  /// federal services.
  final Set<UaeLinkEmirate> emirates;

  /// Every task the service helps with (one catalogue row, several tags).
  final Set<UaeLinkTask> tasks;
  final UaeLinkType type;

  /// The canonical destination. HTTPS, on [domain].
  final String url;
  final String titleEn;
  final String titleAr;
  final String descriptionEn;
  final String descriptionAr;

  /// The government body (or the payment platform) that runs the service.
  final String authorityEn;
  final String authorityAr;
  final UaeLinkVerification verification;

  /// ISO date (`yyyy-MM-dd`) the destination was last checked.
  final String lastVerified;

  /// Short, non-localized note of what was observed and how.
  final String evidence;

  /// Opening the service asks the user to sign in (for example with UAE PASS).
  final bool requiresLogin;

  /// Aliases people search by, in Arabic and Latin spelling.
  final List<String> keywords;

  /// A second official entry point, used only when it was itself verified.
  final String? alternativeUrl;

  /// The host of [url]: the official destination domain.
  String get domain => Uri.parse(url).host;

  bool get isFederal => emirates.contains(UaeLinkEmirate.uae);

  String title(String languageCode) => languageCode == 'ar' ? titleAr : titleEn;

  String description(String languageCode) =>
      languageCode == 'ar' ? descriptionAr : descriptionEn;

  String authority(String languageCode) =>
      languageCode == 'ar' ? authorityAr : authorityEn;

  DateTime get lastVerifiedDate => DateTime.parse(lastVerified);
}
