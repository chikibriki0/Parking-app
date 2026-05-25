import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/cars_service.dart';
import '../theme/app_theme.dart';

/// AddCarScreen — форма добавления автомобиля.
///
/// Проверяет:
///   • российский гос-номер: «А777АА77» / «А777АА777» (1 буква + 3 цифры
///     + 2 буквы + 2–3 цифры региона), допустимые буквы — кириллические
///     омоглифы латиницы: АВЕКМНОРСТУХ.
///   • СТС: 2 цифры + 2 буквы + 6 цифр = всего 10 знаков.
class AddCarScreen extends StatefulWidget {
  const AddCarScreen({super.key});

  @override
  State<AddCarScreen> createState() => _AddCarScreenState();
}

class _AddCarScreenState extends State<AddCarScreen> {
  final _formKey = GlobalKey<FormState>();
  final _plateCtrl = TextEditingController();
  final _stsCtrl = TextEditingController();
  bool _primary = false;

  static const _plateLetters = 'АВЕКМНОРСТУХ';

  @override
  void dispose() {
    _plateCtrl.dispose();
    _stsCtrl.dispose();
    super.dispose();
  }

  String _normalizePlate(String raw) =>
      raw.toUpperCase().replaceAll(RegExp(r'\s+'), '');

  String _normalizeSts(String raw) =>
      raw.toUpperCase().replaceAll(RegExp(r'\s+'), '');

  String? _validatePlate(String? v) {
    final s = _normalizePlate(v ?? '');
    if (s.isEmpty) return 'Введите номер';
    final ok = RegExp('^[$_plateLetters]\\d{3}[$_plateLetters]{2}\\d{2,3}\$')
        .hasMatch(s);
    if (!ok) {
      return 'Формат: А777АА77 (буквы $_plateLetters)';
    }
    final cars = context.read<CarsService>();
    if (cars.hasPlate(s)) return 'Такой номер уже добавлен';
    return null;
  }

  String? _validateSts(String? v) {
    final s = _normalizeSts(v ?? '');
    if (s.isEmpty) return 'Введите СТС';
    if (!RegExp(r'^\d{2}[А-ЯA-Z]{2}\d{6}$').hasMatch(s)) {
      return 'Формат: 77АА123456';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final cars = context.read<CarsService>();
    await cars.add(UserCar(
      plate: _normalizePlate(_plateCtrl.text),
      sts: _normalizeSts(_stsCtrl.text),
      primary: _primary,
    ));
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Новый автомобиль')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Государственный номер',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _plateCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                hintText: 'А777АА77',
                prefixIcon: Icon(Icons.directions_car_rounded),
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp('[$_plateLettersа-яА-ЯA-Za-z0-9\\s]'),
                ),
                LengthLimitingTextInputFormatter(10),
              ],
              validator: _validatePlate,
              autovalidateMode: AutovalidateMode.onUserInteraction,
            ),
            const SizedBox(height: 6),
            Text(
              'Допустимые буквы: $_plateLetters (как в реальных российских номерах)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            const Text(
              'Серия и номер СТС',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _stsCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                hintText: '77АА123456',
                prefixIcon: Icon(Icons.assignment_rounded),
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'[а-яА-ЯA-Za-z0-9\s]'),
                ),
                LengthLimitingTextInputFormatter(12),
              ],
              validator: _validateSts,
              autovalidateMode: AutovalidateMode.onUserInteraction,
            ),
            const SizedBox(height: 6),
            Text(
              'Указан на лицевой стороне свидетельства о регистрации ТС',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            SwitchListTile.adaptive(
              value: _primary,
              onChanged: (v) => setState(() => _primary = v),
              title: const Text('Сделать основным'),
              subtitle: const Text(
                'Будет автоматически подставляться при бронировании',
              ),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: AppTheme.primary,
              ),
              onPressed: _submit,
              child: const Text('Добавить', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
