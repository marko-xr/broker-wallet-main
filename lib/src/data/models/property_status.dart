/// Property status enumeration for tracking the lifecycle of offers and requests
/// Used to filter and organize properties based on their current availability
enum PropertyStatus {
  /// Property is available for rent/sale (default offer status)
  available,

  /// Request is actively being worked on (default request status)
  active,

  /// Property has been sold
  sold,

  /// Property has been rented
  rented,

  /// Property request/offer has been canceled by user
  canceled,

  /// Property is not available (withdrawn, under maintenance, etc.)
  notAvailable,

  /// Request has been successfully fulfilled (matching property found)
  fulfilled,

  /// Request has been closed without fulfillment (client no longer interested)
  closed,

  /// Request has expired (no longer relevant or timed out)
  expired;

  /// Display name for UI
  String get displayName {
    switch (this) {
      case PropertyStatus.available:
        return 'Available';
      case PropertyStatus.active:
        return 'Active';
      case PropertyStatus.sold:
        return 'Sold';
      case PropertyStatus.rented:
        return 'Rented';
      case PropertyStatus.canceled:
        return 'Canceled';
      case PropertyStatus.notAvailable:
        return 'Not Available';
      case PropertyStatus.fulfilled:
        return 'Fulfilled';
      case PropertyStatus.closed:
        return 'Closed';
      case PropertyStatus.expired:
        return 'Expired';
    }
  }

  /// Icon name for UI representation
  String get iconName {
    switch (this) {
      case PropertyStatus.available:
        return 'check-circle';
      case PropertyStatus.active:
        return 'play-circle';
      case PropertyStatus.sold:
        return 'currency-dollar';
      case PropertyStatus.rented:
        return 'key';
      case PropertyStatus.canceled:
        return 'x-circle';
      case PropertyStatus.notAvailable:
        return 'minus-circle';
      case PropertyStatus.fulfilled:
        return 'task-alt';
      case PropertyStatus.closed:
        return 'highlight-off';
      case PropertyStatus.expired:
        return 'hourglass-bottom';
    }
  }

  /// Color code for UI styling
  String get colorCode {
    switch (this) {
      case PropertyStatus.available:
        return '#4CAF50'; // Green
      case PropertyStatus.active:
        return '#00C853'; // Bright green
      case PropertyStatus.sold:
        return '#2196F3'; // Blue
      case PropertyStatus.rented:
        return '#FF9800'; // Orange
      case PropertyStatus.canceled:
        return '#F44336'; // Red
      case PropertyStatus.notAvailable:
        return '#9E9E9E'; // Gray
      case PropertyStatus.fulfilled:
        return '#7C4DFF'; // Deep purple accent
      case PropertyStatus.closed:
        return '#607D8B'; // Blue grey
      case PropertyStatus.expired:
        return '#FF6F00'; // Deep amber
    }
  }

  /// Convert from string (for Firestore deserialization)
  static PropertyStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'sold':
        return PropertyStatus.sold;
      case 'rented':
        return PropertyStatus.rented;
      case 'canceled':
        return PropertyStatus.canceled;
      case 'notavailable':
      case 'not_available':
        return PropertyStatus.notAvailable;
      case 'fulfilled':
        return PropertyStatus.fulfilled;
      case 'closed':
        return PropertyStatus.closed;
      case 'expired':
        return PropertyStatus.expired;
      case 'active':
        return PropertyStatus.active;
      case 'available':
      default:
        return PropertyStatus.available;
    }
  }

  /// Convert to string (for Firestore serialization)
  String toFirestoreString() {
    switch (this) {
      case PropertyStatus.available:
        return 'available';
      case PropertyStatus.active:
        return 'active';
      case PropertyStatus.sold:
        return 'sold';
      case PropertyStatus.rented:
        return 'rented';
      case PropertyStatus.canceled:
        return 'canceled';
      case PropertyStatus.notAvailable:
        return 'not_available';
      case PropertyStatus.fulfilled:
        return 'fulfilled';
      case PropertyStatus.closed:
        return 'closed';
      case PropertyStatus.expired:
        return 'expired';
    }
  }

  /// Check if status indicates property is still active/available
  bool get isActive =>
      this == PropertyStatus.available || this == PropertyStatus.active;

  /// Check if status indicates property is inactive/unavailable
  bool get isInactive => !isActive;

  /// Get list of all statuses for filtering UI
  static List<PropertyStatus> get allStatuses => PropertyStatus.values;

  /// Get list of inactive statuses for archived view
  static List<PropertyStatus> get inactiveStatuses => [
        PropertyStatus.sold,
        PropertyStatus.rented,
        PropertyStatus.canceled,
        PropertyStatus.notAvailable,
        PropertyStatus.fulfilled,
        PropertyStatus.closed,
        PropertyStatus.expired,
      ];

  /// Statuses applicable to offer workflows
  static List<PropertyStatus> get offerStatuses => [
        PropertyStatus.available,
        PropertyStatus.sold,
        PropertyStatus.rented,
        PropertyStatus.canceled,
        PropertyStatus.notAvailable,
      ];

  /// Statuses applicable to request workflows
  static List<PropertyStatus> get requestStatuses => [
        PropertyStatus.active,
        PropertyStatus.fulfilled,
        PropertyStatus.closed,
        PropertyStatus.expired,
      ];
}
