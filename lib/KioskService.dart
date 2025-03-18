import 'package:flutter/services.dart';

class KioskService {
  static const platform = MethodChannel('kiosk_mode');

  // Iniciar o modo kiosk
  Future<void> startKioskMode() async {
    try {
      final result = await platform.invokeMethod('startKioskMode');
      print(result);
    } on PlatformException catch (e) {
      print("Erro ao iniciar Kiosk Mode: ${e.message}");
    }
  }

  // Parar o modo kiosk
  Future<void> stopKioskMode() async {
    try {
      final result = await platform.invokeMethod('stopKioskMode');
      print(result);
    } on PlatformException catch (e) {
      print("Erro ao parar Kiosk Mode: ${e.message}");
    }
  }
}
