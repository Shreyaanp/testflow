import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../services/auth_service.dart';

// Face Liveness Result Model
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

class WebViewFaceLiveness extends StatefulWidget {
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
  State<WebViewFaceLiveness> createState() => _WebViewFaceLivenessState();
}

class _WebViewFaceLivenessState extends State<WebViewFaceLiveness> {
  WebViewController? controller;
  bool isLoading = true;
  String? error;
  Timer? _timeoutTimer;

  static const String _faceLivenessHtmlPath = 'assets/face_liveness/index.html';

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
    _initializeWebView();
    _startTimeout();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  void _startTimeout() {
    _timeoutTimer = Timer(const Duration(seconds: 60), () {
      if (mounted && isLoading) {
        setState(() {
          error = 'Face liveness timed out. Please try again.';
          isLoading = false;
        });
        widget.onError?.call('Face liveness timed out. Please try again.');
      }
    });
  }


  Future<void> _requestCameraPermission() async {
    try {
      final cameraStatus = await Permission.camera.request();
      final micStatus = await Permission.microphone.request();

      if (cameraStatus != PermissionStatus.granted ||
          micStatus != PermissionStatus.granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Camera access is required for face liveness detection',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      // ignore
    }
  }

  Future<void> _initializeWebView() async {
    try {
      final token = await AuthService.getToken();
      final sessionId = widget.sessionId;
      String html = await rootBundle.loadString(_faceLivenessHtmlPath);
      html = html
          .replaceAll('__TOKEN__', token ?? '')
          .replaceAll('__SESSION_ID__', sessionId ?? '');

      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted);


      try {
        controller!.setBackgroundColor(const Color(0xFF1a1a1a));
      } catch (e) {
        print('⚠️ Background color not supported on this platform: $e');
      }

      controller!
        ..setNavigationDelegate(
              NavigationDelegate(
                onProgress: (int progress) {},
                onPageStarted: (String url) {
                  if (mounted) {
                    setState(() {
                      isLoading = true;
                      error = null;
                    });
                  }
                },
                onPageFinished: (String url) {
                  if (mounted) {
                    setState(() {
                      isLoading = false;
                    });
                  }
                  _setupResultListener();
                },
                onHttpError: (HttpResponseError error) {
                  if (mounted) {
                    setState(() {
                      this.error = 'HTTP Error: ${error.response?.statusCode}';
                      isLoading = false;
                    });
                  }
                },
                onWebResourceError: (WebResourceError error) {
                  if (mounted) {
                    setState(() {
                      this.error = 'Connection Error: ${error.description}';
                      isLoading = false;
                    });
                  }
                },
              ),
            )
        ..addJavaScriptChannel(
              'flutterFaceLiveness',
              onMessageReceived: (JavaScriptMessage message) {
                _handleMessageFromReact(message.message);
              },
            )

      // Android: auto-grant camera/mic prompts
      if (controller!.platform is AndroidWebViewController) {
        (controller!.platform as AndroidWebViewController)
            .setOnPlatformPermissionRequest((request) {
          request.grant();
        });
      }

      try {
        controller!.setBackgroundColor(const Color(0xFF1a1a1a));
      } catch (_) {}

      controller!
        ..setNavigationDelegate(
          NavigationDelegate(
            onPermissionRequest: (WebViewPermissionRequest request) {
              request.grant();
            },
            onProgress: (int progress) {},
            onPageStarted: (String url) {
              if (!mounted) return;
              setState(() {
                isLoading = true;
                error = null;
              });
            },
            onPageFinished: (String url) {
              if (!mounted) return;
              setState(() {
                isLoading = false;
              });
              _setupResultListener();
            },
            onHttpError: (HttpResponseError err) {
              if (!mounted) return;
              setState(() {
                error = 'HTTP Error: ${err.response?.statusCode}';
                isLoading = false;
              });
            },
            onWebResourceError: (WebResourceError err) {
              if (!mounted) return;
              setState(() {
                error = 'Connection Error: ${err.description}';
                isLoading = false;
              });
            },
          ),
        )
        ..addJavaScriptChannel(
          'flutterFaceLiveness',
          onMessageReceived: (JavaScriptMessage message) {
            _handleMessageFromReact(message.message);
          },
        )

        ..loadHtmlString(html);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = 'Failed to load face liveness';
          isLoading = false;
        });
      }

      if (widget.onError != null) {
        widget.onError!('Failed to load face liveness');
      }
      widget.onError?.call('Failed to load face liveness');
    }
  }

  void _setupResultListener() {
    if (controller == null) return;

    controller!.runJavaScript('''
      if (!window.flutterFaceLiveness) {
        console.error('flutterFaceLiveness channel not available!');
      }
      window.addEventListener('message', function(event) {
        if (event.data && typeof event.data === 'string') {
          try {
            const data = JSON.parse(event.data);
            if (data.type && (data.type === 'FACE_LIVENESS_RESULT' || data.type === 'FACE_LIVENESS_ERROR' || data.type === 'FACE_LIVENESS_CANCEL')) {
              if (window.flutterFaceLiveness) {
                window.flutterFaceLiveness.postMessage(JSON.stringify(data));
              }
            }
          } catch (e) {}
        }
      });
      window.sendResultToFlutter = function(result) {
        try {
          const messageData = { type: 'FACE_LIVENESS_RESULT', ...result };
          if (window.flutterFaceLiveness) {
            window.flutterFaceLiveness.postMessage(JSON.stringify(messageData));
          }
        } catch (e) {}
      };
    ''');
  }

  void _handleMessageFromReact(String message) {
    try {
      if (message.isEmpty) return;

      final Map<String, dynamic> data = json.decode(message);

      if (data['type'] == 'FACE_LIVENESS_RESULT') {
        _timeoutTimer?.cancel();

        final result = FaceLivenessResult.fromJson(data);
        widget.onResult?.call(result);

        if (mounted && result.success) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          });
        }
      } else if (data['type'] == 'FACE_LIVENESS_ERROR') {
        widget.onError?.call(data['message']?.toString() ?? 'Unknown error');
      } else if (data['type'] == 'FACE_LIVENESS_CANCEL') {
        widget.onCancel?.call();
      }
    } catch (e) {
      String errorMessage = 'Failed to process face liveness result';
      if (e is FormatException) {
        errorMessage = 'Invalid message format from face liveness';
      }
      widget.onError?.call(errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a1a),
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null) WebViewWidget(controller: controller!),
          if (!isLoading && error == null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: IconButton(
                  onPressed: widget.onCancel,
                  icon: const Icon(Icons.close, color: Colors.white, size: 24),
                ),
              ),
            ),
          if (isLoading)
            Container(
              color: Colors.black87,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Loading Face Liveness...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
          if (error != null)
            Container(
              color: Colors.black87,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 64),
                    const SizedBox(height: 16),
                    const Text(
                      'Connection Error',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          onPressed: () {
                            setState(() => error = null);
                            _initializeWebView();
                          },
                          child: const Text('Try Again'),
                        ),
                        const SizedBox(width: 16),
                        OutlinedButton(
                          onPressed: widget.onCancel,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
