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
  Timer? _pingTimer;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _initUsb();
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _subscription?.cancel();
    _disconnectFromDevice();
    super.dispose();
  }

  Future<void> _initUsb() async {
    UsbSerial.usbEventStream?.listen((UsbEvent event) {
      _refreshDeviceList();
    });

    await _refreshDeviceList();
    _tryAutoConnect();
  }

  Future<void> _refreshDeviceList() async {
    List<UsbDevice> devices = await UsbSerial.listDevices();
    setState(() {
      _devices = devices;
    });
  }

  void _tryAutoConnect() async {
    if (_devices.isEmpty) return;

    final esp32 = _devices.cast<UsbDevice?>().firstWhere(
      (device) => device?.vid == 4292 && device?.pid == 60000,
      orElse: () => null,
    );

    _connectToDevice(esp32!);
  }

  void _connectToDevice(UsbDevice device) async {
    _port = await device.create();

    if (_port == null) {
      _addToSerialOutput('Failed to create port for ${device.productName}');
      return;
    }

    bool openResult = await _port!.open();
    if (!openResult) {
      _addToSerialOutput('Failed to open port for ${device.productName}');
      return;
    }

    await _port!.setDTR(true);
    await _port!.setRTS(true);

    await _port!.setPortParameters(
      115200, // Baud rate
      UsbPort.DATABITS_8,
      UsbPort.STOPBITS_1,
      UsbPort.PARITY_NONE,
    );

    _subscription = _port!.inputStream!.listen((Uint8List data) {
      _processIncomingData(data);
    });

    setState(() {
      _isConnected = true;
    });

    _addToSerialOutput('Connected to ${device.productName}');

    // Start sending ping every second
    _startPingTimer();
  }

  void _disconnectFromDevice() {
    _pingTimer?.cancel();
    _subscription?.cancel();

    if (_port != null) {
      _port!.close();
      _port = null;
    }

    setState(() {
      _isConnected = false;
    });

    _addToSerialOutput('Disconnected');
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

    final int cmdByte = COMMANDS[command]!;
    final Uint8List frame = Uint8List.fromList([START_BYTE, cmdByte, END_BYTE]);

    _port!.write(frame);
    _addToSerialOutput(
      'Sent: $command (0x${cmdByte.toRadixString(16).padLeft(2, '0')})',
    );
  }

  void _processIncomingData(Uint8List data) {
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
      // Keep only the last 100 messages
      if (_serialData.length > 100) {
        _serialData.removeAt(0);
      }
    });
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
                _disconnectFromDevice();
              } else {
                await _refreshDeviceList();
                _showDeviceSelectionDialog();
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
                Text(
                  'Status: ${_isConnected ? 'Connected' : 'Disconnected'}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _isConnected ? Colors.green : Colors.red,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Commands:',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Wrap(
                  direction: Axis.horizontal,
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
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _serialData.clear();
                          });
                        },
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

  void _showDeviceSelectionDialog() {
    if (_devices.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No USB devices available')));
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select USB Device'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _devices.length,
              itemBuilder: (context, index) {
                UsbDevice device = _devices[index];
                return ListTile(
                  title: Text(device.productName ?? 'Unknown device'),
                  subtitle: Text('VID: ${device.vid}, PID: ${device.pid}'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _connectToDevice(device);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }
}
