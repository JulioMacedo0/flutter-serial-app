// ignore: file_names
import 'dart:async';
import 'package:barcode_app/kiosk_service.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppVersionWidget extends StatefulWidget {
  final int maxClicks;
  final Duration resetDuration;

  const AppVersionWidget({
    super.key,
    this.maxClicks = 5,
    this.resetDuration = const Duration(seconds: 2),
  });

  @override
  AppVersionWidgetState createState() => AppVersionWidgetState();
}

class AppVersionWidgetState extends State<AppVersionWidget> {
  int _clickCount = 0;
  Timer? _resetTimer;

  void _handleClick() {
    _resetTimer?.cancel();
    _clickCount++;

    if (_clickCount >= widget.maxClicks) {
      _showPopup();
      _clickCount = 0;
    } else {
      _resetTimer = Timer(widget.resetDuration, () {
        setState(() {
          _clickCount = 0;
        });
      });
    }
  }

  void _showPopup() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Center(
              child: Text("🔒", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Ativar ou desativar o modo Kiosk:",
                  style: TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Column(
                      children: [
                        IconButton(
                          onPressed: () async {
                            KioskService().startKioskMode();
                            Navigator.pop(context);
                          },
                          icon: Icon(Icons.lock, size: 40, color: Colors.green),
                        ),
                        Text("Ativar", style: TextStyle(fontSize: 14)),
                      ],
                    ),
                    SizedBox(width: 40), // Espaço entre os botões
                    Column(
                      children: [
                        IconButton(
                          onPressed: () async {
                            KioskService().stopKioskMode();
                            Navigator.pop(context);
                          },
                          icon: Icon(
                            Icons.lock_open,
                            size: 40,
                            color: Colors.red,
                          ),
                        ),
                        Text("Desativar", style: TextStyle(fontSize: 14)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text("Fechar", style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(child: CircularProgressIndicator());
        }
        PackageInfo packageInfo = snapshot.data!;

        return GestureDetector(
          onTap: () {
            setState(_handleClick);
          },
          child: Center(
            child: Text(
              "Versão: ${packageInfo.version} (Build ${packageInfo.buildNumber})",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        );
      },
    );
  }
}
