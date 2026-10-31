import 'package:drift/drift.dart' show Value;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../app/providers.dart';
import '../../app/widgets/big_button.dart';
import '../../app/widgets/hos_page.dart';
import '../../app/widgets/terminal_panel.dart';
import '../../data/backup_service.dart';
import '../../data/export_crypto.dart';
import '../../data/user_db.dart';

/// First screen of a new install: the profile is entered by the user (the
/// app ships no personal data). An existing backup can be restored instead.
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _birthYear = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _target = TextEditingController();
  Sex _sex = Sex.male;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _birthYear, _height, _weight, _target]) {
      c.dispose();
    }
    super.dispose();
  }

  static double? _number(String text) => double.tryParse(text.trim().replaceAll(',', '.'));

  String? _range(String? text, double min, double max, String unit) {
    final v = _number(text ?? '');
    if (v == null) return 'Escribe un número';
    if (v < min || v > max) return 'Entre ${min.round()} y ${max.round()} $unit'.trim();
    return null;
  }

  Future<void> _save() async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final db = ref.read(userDbProvider);
    final today = isoDate(ref.read(todayProvider));
    await db.transaction(() async {
      await db.into(db.profile).insertOnConflictUpdate(ProfileCompanion.insert(
            id: const Value(1),
            name: _name.text.trim(),
            birthYear: _number(_birthYear.text)!.round(),
            heightCm: _number(_height.text)!,
            sex: _sex.code,
            targetWeightKg: _number(_target.text)!,
          ));
      await db.into(db.bodyMetrics).insertOnConflictUpdate(BodyMetricsCompanion.insert(
            date: today,
            weightKg: Value(_number(_weight.text)),
          ));
    });
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _restore() async {
    final file = await openFile();
    if (file == null || !mounted) return;
    final password = await askText(context, title: 'Contraseña de la copia', obscure: true);
    if (password == null || !mounted) return;
    try {
      final rows = await BackupService(ref.read(userDbProvider)).import(await file.readAsBytes(), password);
      if (mounted) toast(context, 'Copia restaurada: $rows registros.');
    } on ExportException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final year = ref.watch(todayProvider).year;
    InputDecoration field(String label, [String? suffix]) =>
        InputDecoration(labelText: label, suffixText: suffix);
    final numbers = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    return HosPage(
      title: 'TU PERFIL',
      subtitle: 'Se guarda solo en este teléfono, cifrado',
      body: Form(
        key: _form,
        child: PanelList(children: [
          TerminalPanel(
            label: 'Datos para tus cálculos',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: field('Nombre o apodo'),
                  maxLength: 40,
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Escribe cómo quieres que te llame' : null,
                ),
                const SizedBox(height: 8),
                SegmentedButton<Sex>(
                  segments: const [
                    ButtonSegment(value: Sex.male, label: Text('HOMBRE')),
                    ButtonSegment(value: Sex.female, label: Text('MUJER')),
                  ],
                  selected: {_sex},
                  onSelectionChanged: (s) => setState(() => _sex = s.first),
                ),
                const Note('Solo para la fórmula del gasto basal (Mifflin–St Jeor).'),
                TextFormField(
                  controller: _birthYear,
                  decoration: field('Año de nacimiento'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) => _range(v, year - 100.0, year - 12.0, ''),
                ),
                TextFormField(
                  controller: _height,
                  decoration: field('Estatura', 'cm'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: numbers,
                  validator: (v) => _range(v, 120, 230, 'cm'),
                ),
                TextFormField(
                  controller: _weight,
                  decoration: field('Peso de hoy', 'kg'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: numbers,
                  validator: (v) => _range(v, 30, 250, 'kg'),
                ),
                TextFormField(
                  controller: _target,
                  decoration: field('Peso meta', 'kg'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: numbers,
                  validator: (v) => _range(v, 30, 250, 'kg'),
                ),
                const SizedBox(height: 16),
                BigButton(
                  label: _saving ? 'Guardando…' : 'Guardar y entrar',
                  icon: Icons.check,
                  onPressed: _saving ? null : _save,
                ),
              ],
            ),
          ),
          TerminalPanel(
            label: '¿Ya tenías HumanOS?',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Note('Restaura tu copia cifrada (.hos3) con su contraseña.'),
                OutlinedButton(onPressed: _restore, child: const Text('RESTAURAR COPIA')),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
