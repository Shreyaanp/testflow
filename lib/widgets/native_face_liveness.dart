import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:face_liveness_detector/face_liveness_detector.dart';
import 'package:mercle/models/face_liveness_result.dart';
import 'package:mercle/services/auth_service.dart';

class NativeFaceLiveness extends StatelessWidget {
  final String sessionId;
  final void Function(FaceLivenessResult result)? onResult;
  final void Function(String error)? onError;
  final VoidCallback? onCancel;

  const NativeFaceLiveness({
    super.key,
    required this.sessionId,
    this.onResult,
    this.onError,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    // Guard: only Android supported for native plugin in this project setup
    if (!Platform.isAndroid) {
      return _UnsupportedPlatform(onCancel: onCancel);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Face Scan', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: onCancel ?? () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: FaceLivenessDetector(
          sessionId: sessionId,
          region: 'us-east-1',
          onComplete: () {
            // Native SDK completed capture; backend will have results
            onResult?.call(FaceLivenessResult(
              success: true,
              isLive: true,
              confidence: 0.0, // real score comes from backend processing
              message: 'Liveness capture complete',
              sessionId: sessionId,
              fullResult: null,
            ));
          },
          onError: (errorCode) {
            onError?.call(errorCode?.toString() ?? 'Face liveness error');
          },
        ),
      ),
    );
  }
}

class _UnsupportedPlatform extends StatelessWidget {
  final VoidCallback? onCancel;

  const _UnsupportedPlatform({this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 64),
            const SizedBox(height: 12),
            const Text(
              'Face scan not supported on this platform yet',
              style: TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: onCancel ?? () => Navigator.of(context).maybePop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

// Backwards-compatible wrapper so existing routes using WebViewFaceLiveness
// transparently use the native detector on Android.
class WebViewFaceLiveness extends StatelessWidget {
  final Function(FaceLivenessResult result)? onResult;
  final Function(String error)? onError;
  final VoidCallback? onCancel;
  final String? sessionId;

  const WebViewFaceLiveness({
    super.key,
    this.onResult,
    this.onError,
    this.onCancel,
    this.sessionId,
  });

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return _UnsupportedPlatform(onCancel: onCancel);
    }

    // If a sessionId is provided, use it directly
    if (sessionId != null && sessionId!.isNotEmpty) {
      return NativeFaceLiveness(
        sessionId: sessionId!,
        onResult: onResult,
        onError: onError,
        onCancel: onCancel,
      );
    }

    // Otherwise create a new session
    return FutureBuilder<Map<String, dynamic>>(
      future: AuthService.createLivenessSession(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          );
        }

        final data = snapshot.data ?? {};
        if (data['success'] == true && data['sessionId'] != null) {
          final sid = data['sessionId'] as String;
          return NativeFaceLiveness(
            sessionId: sid,
            onResult: onResult,
            onError: onError,
            onCancel: onCancel,
          );
        }

        // Failed to create session
        onError?.call(data['message']?.toString() ?? 'Failed to create face scan session');
        return Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 64),
                const SizedBox(height: 12),
                Text(
                  data['message']?.toString() ?? 'Failed to create face scan session',
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: onCancel ?? () => Navigator.of(context).maybePop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
