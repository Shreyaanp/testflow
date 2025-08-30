class FaceLivenessResult {
  final bool success;
  final bool isLive;
  final double confidence;
  final Object? message;
  final String? sessionId;
  final Map<String, dynamic>? fullResult;

  FaceLivenessResult({
    required this.success,
    required this.isLive,
    required this.confidence,
    required this.message,
    this.sessionId,
    this.fullResult,
  });

  factory FaceLivenessResult.fromJson(Map<String, dynamic> json) {
    var message = json['message'];
    if (message != null && message is! String) {
      message = message.toString();
    }

    return FaceLivenessResult(
      success: json['success'] ?? false,
      isLive: json['isLive'] ?? false,
      confidence: (json['confidence'] ?? 0.0).toDouble(),
      message: message ?? 'Unknown result',
      sessionId: json['sessionId'],
      fullResult: json['fullResult'],
    );
  }
}

