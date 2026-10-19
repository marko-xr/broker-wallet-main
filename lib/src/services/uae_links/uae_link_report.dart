import 'package:broker_wallet/src/data/models/uae_links_model.dart';

/// What is wrong with a directory entry, as the user sees it.
enum UaeLinkIssue {
  doesNotOpen('ulxIssueDoesNotOpen', 'The link does not open'),
  wrongOrOutdatedPage('ulxIssueWrongPage', 'The page is wrong or out of date'),
  wrongAuthorityOrEmirate(
      'ulxIssueWrongAuthority', 'Wrong authority or emirate'),
  serviceMoved('ulxIssueServiceMoved', 'The service moved or changed'),
  other('ulxIssueOther', 'Another problem');

  const UaeLinkIssue(this.labelKey, this.reportText);

  /// Localization key of the label shown to the user.
  final String labelKey;

  /// The fixed English wording written into the report, so a report reads the
  /// same whatever language the app was in.
  final String reportText;
}

/// Builds the text of a "report a broken link" message.
///
/// The report is only text the user copies or shares themselves; nothing is
/// sent from here. It holds the service, its authority and address, the kind
/// of problem and the time, and nothing about the user: no identity, token,
/// document or free text.
abstract final class UaeLinkReport {
  static String build({
    required UaeLinkEntry entry,
    required UaeLinkIssue issue,
    required DateTime reportedAt,
  }) {
    return [
      'Broker Wallet - UAE Links report',
      'Service: ${entry.titleEn}',
      'Service ID: ${entry.id}',
      'Authority: ${entry.authorityEn}',
      'URL: ${entry.url}',
      'Issue: ${issue.reportText}',
      'Reported (UTC): ${reportedAt.toUtc().toIso8601String()}',
    ].join('\n');
  }
}
