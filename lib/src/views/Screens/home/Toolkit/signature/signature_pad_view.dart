import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/constants/constants.dart';

/// A widget that provides a signature capture pad with color selection,
/// clear, and confirm functionality.
///
/// This widget allows users to:
/// - Draw freehand signatures with finger or stylus
/// - Change signature color (black, blue, red, green)
/// - Clear the current signature
/// - Confirm and export signature as Uint8List image
class SignaturePadView extends StatefulWidget {
  /// Optional initial signature data to display
  final Uint8List? initialSignature;

  /// Callback when signature is confirmed with the signature image data
  final Function(Uint8List signatureData) onConfirm;

  const SignaturePadView({
    super.key,
    this.initialSignature,
    required this.onConfirm,
  });

  @override
  State<SignaturePadView> createState() => _SignaturePadViewState();
}

class _SignaturePadViewState extends State<SignaturePadView> {
  // Signature controller from the signature package
  late SignatureController _signatureController;

  // Available pen colors for signature
  final List<Color> _penColors = [
    Colors.black,
    Colors.blue,
    Colors.red,
    Colors.green,
  ];

  // Currently selected pen color
  Color _selectedColor = Colors.black;

  // Flag to track if signature has been drawn
  bool _hasSignature = false;

  @override
  void initState() {
    super.initState();

    // Initialize signature controller with default settings
    // Using transparent background for export so signature blends with document
    _signatureController = SignatureController(
      penStrokeWidth: 3,
      penColor: _selectedColor,
      exportBackgroundColor: Colors.transparent,
    );

    // Listen to signature changes to update the confirm button state
    _signatureController.addListener(_onSignatureChanged);

    // Load initial signature if provided
    if (widget.initialSignature != null) {
      _loadInitialSignature();
    }
  }

  /// Load initial signature data if provided
  Future<void> _loadInitialSignature() async {
    try {
      // Note: The signature package doesn't support loading PNG directly
      // For now, we'll just mark that we have a signature
      setState(() {
        _hasSignature = true;
      });
    } catch (e) {
      debugPrint('Error loading initial signature: $e');
    }
  }

  /// Called whenever the signature changes
  void _onSignatureChanged() {
    final hasPoints = _signatureController.isNotEmpty;
    if (hasPoints != _hasSignature) {
      setState(() {
        _hasSignature = hasPoints;
      });
    }
  }

  /// Clear the signature pad
  void _clearSignature() {
    _signatureController.clear();
    setState(() {
      _hasSignature = false;
    });
  }

  /// Change the pen color
  void _changePenColor(Color color) {
    setState(() {
      _selectedColor = color;
      // Create a new controller with the new color since penColor is final
      final points = _signatureController.points;
      _signatureController.removeListener(_onSignatureChanged);
      _signatureController.dispose();

      _signatureController = SignatureController(
        penStrokeWidth: 3,
        penColor: color,
        exportBackgroundColor:
            Colors.transparent, // Transparent background for export
        points: points, // Preserve existing points
      );
      _signatureController.addListener(_onSignatureChanged);
    });
  }

  /// Confirm and export the signature
  Future<void> _confirmSignature() async {
    if (_signatureController.isEmpty) {
      _showToast('Please draw a signature first');
      return;
    }

    try {
      // Export signature as PNG image
      final Uint8List? signatureData = await _signatureController.toPngBytes();

      if (signatureData != null) {
        // Return the signature data to the parent widget
        widget.onConfirm(signatureData);

        // Close this screen
        if (mounted) {
          Navigator.of(context).pop();
        }
      } else {
        _showToast('Failed to export signature');
      }
    } catch (e) {
      _showToast('Error exporting signature: $e');
    }
  }

  /// Show a snackbar message
  void _showToast(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: Theme.of(context).colorScheme.error.withValues(alpha: 0.9),
      textColor: Colors.white,
    );
  }

  @override
  void dispose() {
    _signatureController.removeListener(_onSignatureChanged);
    _signatureController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          localization.translate('drawSignature'),
          style: AppTextStyles.appBarTitle.copyWith(
            fontSize: 20,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFFF44336),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          // Instructions
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Text(
              localization.translate('signatureInstructions'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey[700],
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // Color palette
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${localization.translate('color')}: ',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 12),
                ..._penColors.map((color) {
                  final isSelected = color == _selectedColor;
                  return GestureDetector(
                    onTap: () => _changePenColor(color),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? Colors.grey[800]!
                              : Colors.grey[300]!,
                          width: isSelected ? 3 : 1,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.4),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 24,
                            )
                          : null,
                    ),
                  );
                }).toList(),
              ],
            ),
          ),

          const Divider(height: 1),

          // Signature pad
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Signature(
                  controller: _signatureController,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
          ),

          // Action buttons
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Row(
              children: [
                // Clear button
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _hasSignature ? _clearSignature : null,
                    icon: const Icon(Icons.clear),
                    label: Text(localization.translate('clear')),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(
                        color: _hasSignature
                            ? Colors.red[400]!
                            : Colors.grey[300]!,
                      ),
                      foregroundColor: Colors.red[400],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // Confirm button
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _hasSignature ? _confirmSignature : null,
                    icon: const Icon(Icons.check),
                    label: Text(localization.translate('confirm')),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: const Color(0xFFF44336),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[300],
                      disabledForegroundColor: Colors.grey[500],
                      elevation: _hasSignature ? 4 : 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
