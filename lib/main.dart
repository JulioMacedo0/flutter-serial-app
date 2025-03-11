import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:usb_serial/transaction.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'USB Serial Control',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const SerialControlPage(title: 'USB Serial Control'),
    );
  }
}

class SerialControlPage extends StatefulWidget {
  const SerialControlPage({super.key, required this.title});
  final String title;

  @override
  State<SerialControlPage> createState() => _SerialControlPageState();
}

class _SerialControlPageState extends State<SerialControlPage> {
  UsbPort? _port;
  List<UsbDevice> _devices = [];
  List<String> _serialData = [];

  // ESP32 identifiers
  static const int ESP32_VID = 4292;
  static const int ESP32_PID = 60000;

  // Command constants
  static const int START_BYTE = 0x02;
  static const int END_BYTE = 0x03;
  static const int LOG_START_BYTE = 0x04;

  static const Map<String, int> COMMANDS = {
    'FORWARD': 0x10,
    'REVERSE': 0x11,
    'STOP': 0x12,
    'PING': 0x13,
    'PONG': 0x14,
  };

  static const Map<int, String> RESPONSES = {
    0x14: 'PONG',
    0x15: 'CMD_DETECTION_ON',
    0x16: 'CMD_DETECTION_OFF',
  };

  StreamSubscription<Uint8List>? _subscription;
  StreamSubscription<UsbEvent>? _usbEventSubscription;
  Timer? _pingTimer;
  bool _isConnected = false;
  bool _isConnecting = false;
  DateTime? _lastSuccessfulConnection;

  @override
  void initState() {
    super.initState();
    _initUsb();
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _subscription?.cancel();
    _usbEventSubscription?.cancel();
    _disconnectFromDevice();
    super.dispose();
  }

  Future<void> _initUsb() async {
    // Set up USB event listener
    _usbEventSubscription = UsbSerial.usbEventStream?.listen((UsbEvent event) {
      _addToSerialOutput("USB Event: ${event.event}");

      // Update device list and check for ESP32 on any USB event
      _refreshDeviceList().then((_) {
        // If device was added or we're starting up, try to connect to ESP32
        if (event.event == UsbEvent.ACTION_USB_ATTACHED) {
          _connectToESP32();
        }
        // If device was removed and we were connected, handle disconnection
        else if (event.event == UsbEvent.ACTION_USB_DETACHED && _isConnected) {
          _handleDeviceDisconnection();
        }
      });
    });

    // Initial device discovery and connection attempt
    await _refreshDeviceList();
    _connectToESP32();
  }

  Future<void> _refreshDeviceList() async {
    try {
      List<UsbDevice> devices = await UsbSerial.listDevices();
      setState(() {
        _devices = devices;
      });

      // Log found devices for debugging
      if (devices.isNotEmpty) {
        _addToSerialOutput("Found ${devices.length} USB devices:");
        for (var device in devices) {
          _addToSerialOutput(
            "  - ${device.productName}: VID=${device.vid}, PID=${device.pid}",
          );
        }
      } else {
        _addToSerialOutput("No USB devices found");
      }
    } catch (e) {
      _addToSerialOutput("Error refreshing device list: $e");
    }
  }

  UsbDevice? _findESP32Device() {
    try {
      return _devices.cast<UsbDevice?>().firstWhere(
        (device) => device?.vid == ESP32_VID && device?.pid == ESP32_PID,
        orElse: () => null,
      );
    } catch (e) {
      _addToSerialOutput("Error finding ESP32: $e");
      return null;
    }
  }

  void _connectToESP32() async {
    // Don't try to connect if already connected or in process of connecting
    if (_isConnected || _isConnecting) {
      return;
    }

    setState(() {
      _isConnecting = true;
    });

    try {
      // Find ESP32 device
      UsbDevice? esp32 = _findESP32Device();

      if (esp32 != null) {
        _addToSerialOutput("ESP32 found. Attempting connection...");
        await _connectToDevice(esp32);
      } else {
        _addToSerialOutput("ESP32 not found among connected devices");
        setState(() {
          _isConnecting = false;
        });
      }
    } catch (e) {
      _addToSerialOutput("Error in ESP32 connection attempt: $e");
      setState(() {
        _isConnecting = false;
      });
    }
  }

  Future<void> _connectToDevice(UsbDevice device) async {
    // Close any existing connections first
    if (_port != null) {
      await _disconnectFromDevice(notify: false);
    }

    try {
      _port = await device.create();

      if (_port == null) {
        _addToSerialOutput('Failed to create port for ${device.productName}');
        setState(() {
          _isConnecting = false;
        });
        return;
      }

      bool openResult = await _port!.open();
      if (!openResult) {
        _addToSerialOutput('Failed to open port for ${device.productName}');
        setState(() {
          _isConnecting = false;
        });
        return;
      }

      // Configure port
      await _port!.setDTR(true);
      await _port!.setRTS(true);

      await _port!.setPortParameters(
        115200, // Baud rate
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );

      // Set up data listener
      _subscription = _port!.inputStream!.listen(
        (Uint8List data) {
          _processIncomingData(data);
        },
        onError: (error) {
          _addToSerialOutput('Error from USB stream: $error');
          _handleDeviceDisconnection();
        },
        onDone: () {
          _addToSerialOutput('USB stream closed');
          _handleDeviceDisconnection();
        },
      );

      // Update connection state
      setState(() {
        _isConnected = true;
        _isConnecting = false;
        _lastSuccessfulConnection = DateTime.now();
      });

      _addToSerialOutput(
        'Connected to ${device.productName} (VID: ${device.vid}, PID: ${device.pid})',
      );

      // Start sending ping every second
      _startPingTimer();
    } catch (e) {
      _addToSerialOutput('Connection error: $e');
      setState(() {
        _isConnecting = false;
      });
      _port = null;
    }
  }

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

    setState(() {
      _isConnected = false;
    });

    if (notify) {
      _addToSerialOutput('Disconnected');
    }
  }

  void _handleDeviceDisconnection() async {
    if (!_isConnected) return;

    await _disconnectFromDevice();
    _addToSerialOutput('Device disconnected');
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      sendCommand('PING');
    });
  }

  void sendCommand(String command) {
    if (!_isConnected || _port == null || !COMMANDS.containsKey(command)) {
      return;
    }

    try {
      final int cmdByte = COMMANDS[command]!;
      final Uint8List frame = Uint8List.fromList([
        START_BYTE,
        cmdByte,
        END_BYTE,
      ]);

      _port!.write(frame);
      _addToSerialOutput(
        'Sent: $command (0x${cmdByte.toRadixString(16).padLeft(2, '0')})',
      );
    } catch (e) {
      _addToSerialOutput('Error sending command $command: $e');
      _handleDeviceDisconnection();
    }
  }

  void _processIncomingData(Uint8List data) {
    if (data.isEmpty) return;

    String hexData = data
        .map((byte) => '0x${byte.toRadixString(16).padLeft(2, '0')}')
        .join(' ');
    _addToSerialOutput('Received: $hexData');

    // Process specific responses
    if (data.length >= 3 &&
        data[0] == START_BYTE &&
        data[data.length - 1] == END_BYTE) {
      int cmdByte = data[1];
      String response =
          RESPONSES[cmdByte] ??
          'Unknown (0x${cmdByte.toRadixString(16).padLeft(2, '0')})';
      _addToSerialOutput('Received command: $response');
    }
  }

  void _addToSerialOutput(String message) {
    setState(() {
      _serialData.add(
        '${DateTime.now().toString().split('.').first}: $message',
      );
      // Keep only the last 200 messages
      if (_serialData.length > 200) {
        _serialData.removeAt(0);
      }
    });
  }

  void _clearSerialOutput() {
    setState(() {
      _serialData.clear();
    });
  }

  String _getConnectionStatusText() {
    if (_isConnected) {
      return 'Connected to ESP32';
    } else if (_isConnecting) {
      return 'Connecting...';
    } else {
      return 'Disconnected';
    }
  }

  Color _getConnectionStatusColor() {
    if (_isConnected) {
      return Colors.green;
    } else if (_isConnecting) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: Icon(_isConnected ? Icons.usb : Icons.usb_off),
            onPressed: () async {
              if (_isConnected) {
                await _disconnectFromDevice();
              } else {
                await _refreshDeviceList();
                _connectToESP32();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Status: ${_getConnectionStatusText()}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _getConnectionStatusColor(),
                        ),
                      ),
                    ),
                    if (_lastSuccessfulConnection != null)
                      Text(
                        'Last connected: ${_lastSuccessfulConnection!.hour.toString().padLeft(2, '0')}:${_lastSuccessfulConnection!.minute.toString().padLeft(2, '0')}:${_lastSuccessfulConnection!.second.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Commands:',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      COMMANDS.keys.map((command) {
                        return ElevatedButton(
                          onPressed:
                              _isConnected ? () => sendCommand(command) : null,
                          child: Text(command),
                        );
                      }).toList(),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Serial Monitor:',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            onPressed: () async {
                              await _refreshDeviceList();
                              _connectToESP32();
                            },
                            tooltip: 'Refresh and reconnect',
                          ),
                          IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: _clearSerialOutput,
                            tooltip: 'Clear monitor',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(16.0),
                    padding: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListView.builder(
                      reverse: true,
                      itemCount: _serialData.length,
                      itemBuilder: (context, index) {
                        return Text(
                          _serialData[_serialData.length - 1 - index],
                          style: const TextStyle(
                            color: Colors.green,
                            fontFamily: 'monospace',
                          ),
                        );
                      },
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
