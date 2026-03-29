import 'package:flutter/material.dart';

class ExitPasswordDialog extends StatefulWidget {
  const ExitPasswordDialog({super.key});

  static Future<String?> show(BuildContext context) {
    return showDialog<String?>(
      context: context,
      useSafeArea: false,
      builder: (_) => const ExitPasswordDialog(),
    );
  }

  @override
  State<ExitPasswordDialog> createState() => _ExitPasswordDialogState();
}

class _ExitPasswordDialogState extends State<ExitPasswordDialog> {
  final _passwordController = TextEditingController();
  bool _passwordVisible = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _onConfirm() {
    Navigator.of(context).pop(_passwordController.text);
  }

  void _appendDigit(String digit) {
    if (_passwordController.text.length >= 6) {
      return;
    }
    setState(() {
      _passwordController.text = '${_passwordController.text}$digit';
    });
  }

  void _backspace() {
    if (_passwordController.text.isEmpty) {
      return;
    }
    setState(() {
      _passwordController.text = _passwordController.text.substring(
        0,
        _passwordController.text.length - 1,
      );
    });
  }

  void _clearAll() {
    if (_passwordController.text.isEmpty) {
      return;
    }
    setState(() {
      _passwordController.text = '';
    });
  }

  Widget _digitKey(String digit) {
    return FilledButton.tonal(
      onPressed: () => _appendDigit(digit),
      style: FilledButton.styleFrom(
        minimumSize: const Size(72, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
        digit,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('输入退出密码'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _passwordController,
              readOnly: true,
              showCursor: false,
              obscureText: !_passwordVisible,
              decoration: InputDecoration(
                labelText: '密码',
                hintText: '请输入 1-6 位数字',
                counterText: '',
                suffixIcon: IconButton(
                  icon: Icon(
                    _passwordVisible ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () {
                    setState(() => _passwordVisible = !_passwordVisible);
                  },
                ),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [_digitKey('7'), _digitKey('8'), _digitKey('9')],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [_digitKey('4'), _digitKey('5'), _digitKey('6')],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [_digitKey('1'), _digitKey('2'), _digitKey('3')],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton(
                  onPressed: _clearAll,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(72, 56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('C'),
                ),
                _digitKey('0'),
                FilledButton(
                  onPressed: _backspace,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(72, 56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Icon(Icons.backspace_outlined),
                ),
              ],
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
          onPressed: _passwordController.text.isEmpty ? null : _onConfirm,
          child: const Text('确定'),
        ),
      ],
    );
  }
}
