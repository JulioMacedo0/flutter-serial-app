// ignore: file_names
import 'package:flutter/material.dart';

class InvisibleTextField extends StatefulWidget {
  const InvisibleTextField({super.key});

  @override
  InvisibleTextFieldState createState() => InvisibleTextFieldState();
}

class InvisibleTextFieldState extends State<InvisibleTextField> {
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _onEnterPressed(String value) {
    print('submitted value: $value');
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 0,
      height: 0,
      child: TextField(
        onSubmitted: _onEnterPressed,
        focusNode: _focusNode,
        decoration: const InputDecoration(
          border: InputBorder.none,
          hintStyle: TextStyle(color: Colors.transparent),
          filled: false,
        ),
        style: const TextStyle(color: Colors.transparent),
        cursorColor: Colors.transparent,
        onChanged: (value) {
          print('Detected a new value: ${value}');
        },
        keyboardType: TextInputType.none,
        showCursor: false,
      ),
    );
  }
}
