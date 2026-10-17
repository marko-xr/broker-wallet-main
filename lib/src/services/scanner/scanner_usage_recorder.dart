/// Records that a scan was completed. One call is one scan, however many pages
/// or image files it produced, and it is made only after the whole scan was
/// stored, so a failed save never uses up an allowance.
abstract interface class ScannerUsageRecorder {
  Future<void> recordScan(String userId);
}
