import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrConfigScannerPage extends StatefulWidget {
  const QrConfigScannerPage({super.key});

  @override
  State<QrConfigScannerPage> createState() => _QrConfigScannerPageState();
}

class _QrConfigScannerPageState extends State<QrConfigScannerPage> {
  static const double _scanFrameSize = 320;
  static const double _scanOverlayOpacity = 0.2;

  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  bool _isCompleting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleDetection(BarcodeCapture capture) async {
    if (_isCompleting) {
      return;
    }

    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue?.trim();
      if (rawValue == null || rawValue.isEmpty) {
        continue;
      }

      _isCompleting = true;
      await _controller.stop();
      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(rawValue);
      return;
    }
  }

  Widget _buildScanOverlay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final leftInset = (constraints.maxWidth - _scanFrameSize) / 2;
        final topInset = (constraints.maxHeight - _scanFrameSize) / 2;
        final overlayColor = Colors.black.withValues(alpha: _scanOverlayOpacity);

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: 0,
              top: 0,
              right: 0,
              height: topInset.clamp(0, double.infinity),
              child: ColoredBox(color: overlayColor),
            ),
            Positioned(
              left: 0,
              top: topInset,
              width: leftInset.clamp(0, double.infinity),
              height: _scanFrameSize,
              child: ColoredBox(color: overlayColor),
            ),
            Positioned(
              right: 0,
              top: topInset,
              width: leftInset.clamp(0, double.infinity),
              height: _scanFrameSize,
              child: ColoredBox(color: overlayColor),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: topInset.clamp(0, double.infinity),
              child: ColoredBox(color: overlayColor),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _handleDetection,
          ),
          IgnorePointer(child: _buildScanOverlay()),
        ],
      ),
    );
  }
}