import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DigitInputDialog extends StatefulWidget {
  const DigitInputDialog({
    super.key,
    required this.title,
    required this.labelText,
    required this.hintText,
    required this.confirmText,
    this.maxLength = 6,
    this.obscureInput = false,
    this.showVisibilityToggle = false,
    this.autofocus = false,
  });

  final String title;
  final String labelText;
  final String hintText;
  final String confirmText;
  final int maxLength;
  final bool obscureInput;
  final bool showVisibilityToggle;
  final bool autofocus;

  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String labelText,
    required String hintText,
    required String confirmText,
    int maxLength = 6,
    bool obscureInput = false,
    bool showVisibilityToggle = false,
    bool autofocus = false,
  }) {
    return showDialog<String?>(
      context: context,
      useSafeArea: false,
      builder: (_) => DigitInputDialog(
        title: title,
        labelText: labelText,
        hintText: hintText,
        confirmText: confirmText,
        maxLength: maxLength,
        obscureInput: obscureInput,
        showVisibilityToggle: showVisibilityToggle,
        autofocus: autofocus,
      ),
    );
  }

  @override
  State<DigitInputDialog> createState() => _DigitInputDialogState();
}

class _DigitInputDialogState extends State<DigitInputDialog> {
  static const MethodChannel _displayMetricsChannel = MethodChannel(
    'aeterna/window_security',
  );
  static const double _targetKeyboardCm = 10;
  static const double _defaultKeyboardHeightPx = 378;
  final _inputController = TextEditingController();
  bool _passwordVisible = false;
  double? _monitorDpi;

  @override
  void initState() {
    super.initState();
    _passwordVisible = !widget.obscureInput;
    _loadMonitorDpi();
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _onConfirm() {
    Navigator.of(context).pop(_inputController.text);
  }

  Future<void> _loadMonitorDpi() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
      return;
    }
    try {
      final dpi = await _displayMetricsChannel.invokeMethod<num>('getMonitorDpi');
      if (!mounted || dpi == null || dpi <= 0) {
        return;
      }
      setState(() {
        _monitorDpi = dpi.toDouble();
      });
    } catch (_) {
      // Keep fallback size when native DPI query is unavailable.
    }
  }

  void _appendDigit(String digit) {
    if (_inputController.text.length >= widget.maxLength) {
      return;
    }
    setState(() {
      _inputController.text = '${_inputController.text}$digit';
    });
  }

  void _backspace() {
    if (_inputController.text.isEmpty) {
      return;
    }
    setState(() {
      _inputController.text = _inputController.text.substring(
        0,
        _inputController.text.length - 1,
      );
    });
  }

  void _clearAll() {
    if (_inputController.text.isEmpty) {
      return;
    }
    setState(() {
      _inputController.text = '';
    });
  }

  Widget _digitKey(String digit) {
    return FilledButton.tonal(
      onPressed: () => _appendDigit(digit),
      style: FilledButton.styleFrom(
        minimumSize: const Size(56, 56),
        shape: const CircleBorder(),
      ),
      child: Text(
        digit,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      ),
    );
  }

  double _keyboardHeight(BuildContext context) {
    final viewHeight = MediaQuery.sizeOf(context).height;
    final maxAllowed = viewHeight * 0.5;
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final logicalHeightFromDpi =
        ((_monitorDpi ?? 96) * (_targetKeyboardCm / 2.54)) / devicePixelRatio;
    final target = _monitorDpi == null
        ? _defaultKeyboardHeightPx
        : logicalHeightFromDpi;
    return target.clamp(260.0, maxAllowed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _inputController,
              autofocus: widget.autofocus,
              readOnly: true,
              showCursor: false,
              obscureText: widget.obscureInput && !_passwordVisible,
              decoration: InputDecoration(
                labelText: widget.labelText,
                hintText: widget.hintText,
                counterText: '',
                suffixIcon: widget.showVisibilityToggle
                    ? IconButton(
                        icon: Icon(
                          _passwordVisible
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() => _passwordVisible = !_passwordVisible);
                        },
                      )
                    : null,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: _keyboardHeight(context),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [_digitKey('7'), _digitKey('8'), _digitKey('9')],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [_digitKey('4'), _digitKey('5'), _digitKey('6')],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [_digitKey('1'), _digitKey('2'), _digitKey('3')],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      OutlinedButton(
                        onPressed: _clearAll,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(56, 56),
                          shape: const CircleBorder(),
                        ),
                        child: const Text('C'),
                      ),
                      _digitKey('0'),
                      FilledButton(
                        onPressed: _backspace,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(56, 56),
                          shape: const CircleBorder(),
                        ),
                        child: const Icon(Icons.backspace_outlined),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _inputController.text.isEmpty ? null : _onConfirm,
          child: Text(widget.confirmText),
        ),
      ],
    );
  }
}

class ExitPasswordDialog extends StatelessWidget {
  const ExitPasswordDialog({super.key});

  static Future<String?> show(BuildContext context) {
    return DigitInputDialog.show(
      context,
      title: '输入退出密码',
      labelText: '密码',
      hintText: '请输入 1-6 位数字',
      confirmText: '确定',
      obscureInput: true,
      showVisibilityToggle: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
