// ignore_for_file: constant_identifier_names

import 'package:barcode_app/drawer_widget.dart';
import 'package:barcode_app/invisible_text_field.dart';
import 'package:barcode_app/usb_serial_service.dart';

import 'package:flutter/material.dart';

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
  final UsbSerialService _serialService = UsbSerialService();

  final List<String> _serialData = [];

  @override
  void initState() {
    super.initState();
    _initializeSerialService();
  }

  @override
  void dispose() {
    _serialService.dispose();

    super.dispose();
  }

  void _initializeSerialService() async {
    await _serialService.initialize(
      logCallback: _addToSerialOutput,
      connectionStatusCallback: (connected) {
        setState(() {});
      },
      presenceCallback: (presence) {
        setState(() {});
      },
    );
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
    if (_serialService.isConnected) {
      return 'Connected to ESP32';
    } else if (_serialService.isConnecting) {
      return 'Connecting...';
    } else {
      return 'Disconnected';
    }
  }

  Color _getConnectionStatusColor() {
    if (_serialService.isConnected) {
      return Colors.green;
    } else if (_serialService.isConnecting) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      endDrawer: CustomDrawer(),
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
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
                    InvisibleTextField(),
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
                    Expanded(
                      child: Text(
                        'presence: ${_serialService.presence}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _getConnectionStatusColor(),
                        ),
                      ),
                    ),
                    if (_serialService.lastSuccessfulConnection != null)
                      Text(
                        'Last connected: ${{_serialService.lastSuccessfulConnection!.hour.toString().padLeft(2, '0')}}:${_serialService.lastSuccessfulConnection!.minute.toString().padLeft(2, '0')}:${_serialService.lastSuccessfulConnection!.second.toString().padLeft(2, '0')}',
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
                              _serialService.isConnected
                                  ? () => _serialService.sendCommand(command)
                                  : null,
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
                              // await _refreshDeviceList();
                              // _connectToESP32();
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
