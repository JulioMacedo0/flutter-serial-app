// ignore_for_file: constant_identifier_names

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:usb_serial/usb_serial.dart';

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

Uint8List serialBuffer = Uint8List(0);

enum COMMANDS {
  forward(0x10),
  reverse(0x11),
  stop(0x12),
  ping(0x13),
  pong(0x14);

  final int value;
  const COMMANDS(this.value);

  static COMMANDS? fromValue(int value) {
    return COMMANDS.values.cast().firstWhere(
      (e) => e.value == value,
      orElse: () => null,
    );
  }
}

enum RESPONSES {
  pong(0x14),
  cmdDetectionOn(0x15),
  cmdDetectionOff(0x16);

  final int value;
  const RESPONSES(this.value);

  static RESPONSES? fromValue(int value) {
    return RESPONSES.values.cast().firstWhere(
      (e) => e.value == value,
      orElse: () => null,
    );
  }
}

class _SerialControlPageState extends State<SerialControlPage> {
  UsbPort? _port;
  List<UsbDevice> _devices = [];
  final List<String> _serialData = [];

  // ESP32 identifiers
  static const int ESP32_VID = 4292;
  static const int ESP32_PID = 60000;

  // Command constants
  static const int START_BYTE = 0x02;
  static const int END_BYTE = 0x03;
  //static const int LOG_START_BYTE = 0x04;

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
    });

    await _refreshDeviceList();
    _connectToESP32();
  }

  Future<void> _refreshDeviceList() async {
    try {
      List<UsbDevice> devices = await UsbSerial.listDevices();
      setState(() {
        _devices = devices;
      });

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
    if (_isConnected || _isConnecting) {
      return;
    }

    setState(() {
      _isConnecting = true;
    });

    try {
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

      await _port!.setDTR(true);
      await _port!.setRTS(true);

      await _port!.setPortParameters(
        115200,
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );

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

      setState(() {
        _isConnected = true;
        _isConnecting = false;
        _lastSuccessfulConnection = DateTime.now();
      });

      _addToSerialOutput(
        'Connected to ${device.productName} (VID: ${device.vid}, PID: ${device.pid})',
      );

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
    await _disconnectFromDevice();
    _addToSerialOutput('ESP32 disconnected');
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      sendCommand(COMMANDS.ping);
    });
  }

  void sendCommand(COMMANDS command) {
    if (!_isConnected || _port == null) {
      return;
    }

    try {
      final int cmdByte = command.value;
      final Uint8List frame = Uint8List.fromList([
        START_BYTE,
        cmdByte,
        END_BYTE,
      ]);

      _port!.write(frame);
      _addToSerialOutput(
        '[SENDER]: ${command.name} (0x${cmdByte.toRadixString(16).padLeft(2, '0')})',
      );
    } catch (e) {
      _addToSerialOutput('Error sending command $command: $e');
    }
  }

  void _processIncomingData(Uint8List data) {
    if (data.isEmpty) return;

    String string = String.fromCharCodes(data);
    _addToSerialOutput('[RECIVER]: $string');

    if (data.length >= 3 &&
        data[0] == START_BYTE &&
        data[data.length - 1] == END_BYTE) {
      int cmdByte = data[1];
      handleCommand(cmdByte);
      String response =
          RESPONSES.fromValue(cmdByte)?.name ??
          'Unknown (0x${cmdByte.toRadixString(16).padLeft(2, '0')})';
      _addToSerialOutput('Received command: $response');
    }
  }

  void _addToSerialOutput(String message) {
    setState(() {
      _serialData.add(
        '${DateTime.now().toString().split('.').first}: $message',
      );
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

  void handleCommand(int command) {
    final value = RESPONSES.fromValue(command);

    if (value == null) {
      _addToSerialOutput('Unknown command: $command');
      return;
    }

    switch (value) {
      case RESPONSES.pong:
        _addToSerialOutput('Command received: ${RESPONSES.pong.name}');
        break;
      case RESPONSES.cmdDetectionOn:
        _addToSerialOutput(
          'Command received: ${RESPONSES.cmdDetectionOn.name}',
        );
        break;
      case RESPONSES.cmdDetectionOff:
        _addToSerialOutput(
          'Command received: ${RESPONSES.cmdDetectionOff.name}',
        );
        break;
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
                      COMMANDS.values.map((command) {
                        return ElevatedButton(
                          onPressed:
                              _isConnected ? () => sendCommand(command) : null,
                          child: Text(command.name),
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
