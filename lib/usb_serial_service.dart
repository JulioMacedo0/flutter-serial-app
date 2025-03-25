// usb_serial_service.dart
// ignore_for_file: constant_identifier_names

import 'dart:async';
import 'dart:typed_data';
import 'package:usb_serial/usb_serial.dart';

class UsbSerialService {
  // Singleton instance
  static final UsbSerialService _instance = UsbSerialService._internal();
  factory UsbSerialService() => _instance;
  UsbSerialService._internal();

  // ESP32 identifiers

  static const int ESP32_VID = 4292;
  static const int ESP32_PID = 60000;

  // Command constants
  static const int START_BYTE = 0x02;
  static const int END_BYTE = 0x03;

  // Service state
  UsbPort? _port;
  StreamSubscription<Uint8List>? _subscription;
  StreamSubscription<UsbEvent>? _usbEventSubscription;
  Timer? _pingTimer;
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _presence = false;
  DateTime? _lastSuccessfulConnection;
  List<UsbDevice> _devices = [];
  // Callbacks for UI updates
  Function(String)? _logCallback;
  Function(bool)? _connectionStatusCallback;
  Function(bool)? _presenceCallback;

  // Initialize the service
  Future<void> initialize({
    Function(String)? logCallback,
    Function(bool)? connectionStatusCallback,
    Function(bool)? presenceCallback,
  }) async {
    _logCallback = logCallback;
    _connectionStatusCallback = connectionStatusCallback;
    _presenceCallback = presenceCallback;

    _usbEventSubscription = UsbSerial.usbEventStream?.listen(_handleUsbEvent);
    await _refreshDeviceList();
    _connectToESP32();
  }

  // Clean up resources
  Future<void> dispose() async {
    _pingTimer?.cancel();
    _subscription?.cancel();
    _usbEventSubscription?.cancel();
    await _disconnectFromDevice();
  }

  // Handle USB events
  void _handleUsbEvent(UsbEvent event) {
    _addToLog("USB Event: ${event.event}");

    _refreshDeviceList().then((_) {
      if (event.event == UsbEvent.ACTION_USB_ATTACHED) {
        if (!_isConnected) {
          _connectToESP32();
        }
      } else if (event.event == UsbEvent.ACTION_USB_DETACHED) {
        final esp32 = _findESP32Device();
        if (esp32 == null && _isConnected) {
          _handleDeviceDisconnection();
        }
      }
    });
  }

  // Refresh device list
  Future<void> _refreshDeviceList() async {
    try {
      _devices = await UsbSerial.listDevices();
      if (_devices.isNotEmpty) {
        _addToLog("Found ${_devices.length} USB devices:");
        for (var device in _devices) {
          _addToLog(
            "  - ${device.productName}: VID=${device.vid}, PID=${device.pid}",
          );
        }
      } else {
        _addToLog("No USB devices found");
      }
    } catch (e) {
      _addToLog("Error refreshing device list: $e");
    }
  }

  // Find ESP32 device
  UsbDevice? _findESP32Device() {
    try {
      return _devices.firstWhere(
        (device) => device.vid == ESP32_VID && device.pid == ESP32_PID,
      );
    } catch (e) {
      _addToLog("Error finding ESP32: $e");
      return null;
    }
  }

  // Connect to ESP32
  void _connectToESP32() async {
    if (_isConnected || _isConnecting) return;

    _updateConnectionStatus(false, true);
    _addToLog("ESP32 found. Attempting connection...");

    try {
      UsbDevice? esp32 = _findESP32Device();
      if (esp32 != null) {
        await _connectToDevice(esp32);
      } else {
        _addToLog("ESP32 not found among connected devices");
        _updateConnectionStatus(false, false);
      }
    } catch (e) {
      _addToLog("Error in ESP32 connection attempt: $e");
      _updateConnectionStatus(false, false);
    }
  }

  // Connect to specific device
  Future<void> _connectToDevice(UsbDevice device) async {
    if (_port != null) {
      await _disconnectFromDevice(notify: false);
    }

    try {
      _port = await device.create();
      if (_port == null) {
        _addToLog('Failed to create port for ${device.productName}');
        _updateConnectionStatus(false, false);
        return;
      }

      bool openResult = await _port!.open();
      if (!openResult) {
        _addToLog('Failed to open port for ${device.productName}');
        _updateConnectionStatus(false, false);
        return;
      }

      await _port!.setDTR(true);
      await _port!.setRTS(true);
      await _port!.setPortParameters(
        115200,
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );

      _subscription = _port!.inputStream!.listen(
        _processIncomingData,
        onError: (error) {
          _addToLog('Error from USB stream: $error');
          _handleDeviceDisconnection();
        },
        onDone: () {
          _addToLog('USB stream closed');
          _handleDeviceDisconnection();
        },
      );

      _updateConnectionStatus(true, false);
      _lastSuccessfulConnection = DateTime.now();
      _addToLog(
        'Connected to ${device.productName} (VID: ${device.vid}, PID: ${device.pid})',
      );

      _startPingTimer();
    } catch (e) {
      _addToLog('Connection error: $e');
      _updateConnectionStatus(false, false);
      _port = null;
    }
  }

  // Disconnect from device
  Future<void> _disconnectFromDevice({bool notify = true}) async {
    _pingTimer?.cancel();

    if (_subscription != null) {
      await _subscription!.cancel();
      _subscription = null;
    }

    if (_port != null) {
      await _port!.close();
      _port = null;
    }

    if (notify) {
      _updateConnectionStatus(false, false);
      _addToLog('Disconnected');
    }
  }

  // Handle disconnection
  void _handleDeviceDisconnection() async {
    await _disconnectFromDevice();
    _addToLog('ESP32 disconnected');
  }

  // Start ping timer
  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      sendCommand(COMMANDS.ping);
    });
  }

  // Send command to device
  void sendCommand(COMMANDS command) {
    if (!_isConnected || _port == null) return;

    try {
      final int cmdByte = command.value;
      final Uint8List frame = Uint8List.fromList([
        START_BYTE,
        cmdByte,
        END_BYTE,
      ]);

      _port!.write(frame);
      _addToLog(
        '[SENDER]: ${command.name} (0x${cmdByte.toRadixString(16).padLeft(2, '0')})',
      );
    } catch (e) {
      _addToLog('Error sending command $command: $e');
    }
  }

  // Process incoming data
  void _processIncomingData(Uint8List data) {
    if (data.isEmpty) return;

    if (data.length >= 3 &&
        data[0] == START_BYTE &&
        data[data.length - 1] == END_BYTE) {
      int cmdByte = data[1];
      _handleCommand(cmdByte);
    }
  }

  // Handle commands from device
  void _handleCommand(int command) {
    final value = RESPONSES.fromValue(command);
    const initMsg = "[COMMAND_RECIVER]";
    if (value == null) {
      _addToLog('Unknown command: $command');
      return;
    }

    switch (value) {
      case RESPONSES.pong:
        _addToLog('$initMsg: ${RESPONSES.pong.name}');
        break;
      case RESPONSES.cmdDetectionOn:
        _addToLog('$initMsg: ${RESPONSES.cmdDetectionOn.name}');
        _updatePresence(true);
        break;
      case RESPONSES.cmdDetectionOff:
        _addToLog('$initMsg: ${RESPONSES.cmdDetectionOff.name}');
        _updatePresence(false);
        break;
    }
  }

  // Update connection status
  void _updateConnectionStatus(bool connected, bool connecting) {
    _isConnected = connected;
    _isConnecting = connecting;
    _connectionStatusCallback?.call(connected);
  }

  // Update presence status
  void _updatePresence(bool presence) {
    _presence = presence;
    _presenceCallback?.call(presence);
  }

  // Add log message
  void _addToLog(String message) {
    final formattedMessage =
        '${DateTime.now().toString().split('.').first}: $message';
    _logCallback?.call(formattedMessage);
  }

  // Getters for UI
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  bool get presence => _presence;
  DateTime? get lastSuccessfulConnection => _lastSuccessfulConnection;
  List<UsbDevice> get devices => _devices;
}

// Command enums
enum COMMANDS {
  forward(0x10),
  reverse(0x11),
  stop(0x12),
  ping(0x13),
  pong(0x14);

  final int value;
  const COMMANDS(this.value);

  static COMMANDS? fromValue(int value) {
    try {
      return COMMANDS.values.firstWhere((e) => e.value == value);
    } catch (e) {
      return null;
    }
  }
}

enum RESPONSES {
  pong(0x14),
  cmdDetectionOn(0x15),
  cmdDetectionOff(0x16);

  final int value;
  const RESPONSES(this.value);

  static RESPONSES? fromValue(int value) {
    try {
      return RESPONSES.values.firstWhere((e) => e.value == value);
    } catch (e) {
      return null;
    }
  }
}
