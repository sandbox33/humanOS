import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../data/settings.dart';
import '../features/ajustes/presentation/ajustes_screen.dart';
import '../features/alarmas/presentation/alarmas_screen.dart';
import '../features/contexto/domain/context_model.dart';
import '../features/contexto/presentation/contexto_screen.dart';
import '../features/despensa/presentation/despensa_screen.dart';
import '../features/estado/domain/readiness_today.dart';
import '../features/estado/domain/targets.dart';
import '../features/estado/presentation/estado_screen.dart';
import '../features/habitos/domain/habits_model.dart';
import '../features/habitos/presentation/habitos_screen.dart';
import '../features/heavy_duty/domain/training_plan.dart';
import '../features/heavy_duty/presentation/heavy_duty_screen.dart';
import '../features/indice/presentation/indice_screen.dart';
import '../features/registro/presentation/registro_screen.dart';
import '../features/trabajo/domain/work_model.dart';
import '../features/trabajo/presentation/trabajo_screen.dart';
import '../services/services.dart';
import 'chores.dart';
import 'providers.dart';
import 'theme.dart';
import 'widgets/event_feedback.dart';
import 'widgets/hos_page.dart';

/// Selected bottom tab.
class ShellTab extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) => state = index;
}

final shellTabProvider = NotifierProvider<ShellTab, int>(ShellTab.new);

/// Bottom navigation (ESTADO · REGISTRO · HEAVY · TRABAJO · MÁS) and the
/// background chores: Health Connect and screen-time reads, automatic
/// habit values, streak/attribute history and reminders.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with WidgetsBindingObserver {
  Timer? _habitDebounce;
  StreamSubscription<void>? _contextChanges;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startup());
    _contextChanges = ref.read(deviceContextProvider).changes.listen((_) => unawaited(_readTransitions()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _habitDebounce?.cancel();
    unawaited(_contextChanges?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(todayProvider.notifier).refresh();
      unawaited(_refreshExternal());
      unawaited(_readTransitions());
    }
  }

  Future<void> _startup() async {
    if (_started) return;
    _started = true;
    final settings = ref.read(settingsRepositoryProvider);
    final notifications = ref.read(notificationServiceProvider);
    try {
      await notifications.init();
      // Android 13+ asks once; the answer can be changed in AJUSTES.
      if (await settings.get(SettingKey.notificationsAsked) != '1') {
        await notifications.requestPermissions();
        await settings.setBool(SettingKey.notificationsAsked, true);
      }
    } on Object {
      // Notifications unavailable: the app works without them.
    }
    if (!mounted) return;
    await _refreshExternal();
    if (mounted) await rescheduleReminders(ref);
    // The phone's copies of zones, event reminders and alarms are rebuilt
    // from the encrypted database on every start.
    await _readTransitions();
    if (mounted) await _syncNative(zones: true, eventReminders: true, alarms: true);
  }

  /// Transitions the phone saw while the app was closed or in background.
  Future<void> _readTransitions() async {
    if (!mounted) return;
    try {
      await drainTransitions(ref);
    } on Object {
      // The phone's queue stays; it is read again on the next start.
    }
  }

  Future<void> _syncNative({bool zones = false, bool eventReminders = false, bool alarms = false}) async {
    try {
      if (zones && mounted) {
        final settings = ref.read(settingsProvider);
        if (settings.zonesEnabled && settings.batteryOverLimit) await disableZones(ref);
        if (mounted) await syncZones(ref);
      }
      if (eventReminders && mounted) await syncEventReminders(ref);
      if (alarms && mounted) await syncAlarms(ref);
    } on Object {
      // Platform unavailable: the database keeps everything.
    }
  }

  /// Health Connect (only after the user granted it once) and screen time.
  Future<void> _refreshExternal() async {
    final settings = ref.read(settingsRepositoryProvider);
    final granted = await settings.get(SettingKey.healthGranted) == '1';
    if (!mounted) return;
    if (granted) await syncHealth(ref);
    if (!mounted) return;
    await syncScreenTime(ref);
    if (mounted) await recordReadiness(ref);
  }

  void _scheduleHabitSync() {
    _habitDebounce?.cancel();
    _habitDebounce = Timer(const Duration(milliseconds: 800), () async {
      if (!mounted) return;
      await syncAutoHabits(ref);
      if (!mounted) return;
      final streaks = await saveStreaks(ref);
      if (!mounted) return;
      final attributes = await saveAttributes(ref);
      if (!mounted || !ref.read(settingsProvider).eventFeedback) return;
      final overview = ref.read(habitsOverviewProvider);
      final messages = [
        for (final kind in streaks)
          kind == StreakKind.minimum
              ? 'RACHA MÍNIMA ${overview?.minimum.current ?? ''}'
              : 'RACHA GLOBAL ${overview?.global.current ?? ''}',
        for (final kind in attributes) '${kind.labelEs} SUBE',
      ];
      if (messages.isNotEmpty && mounted) {
        await EventFeedback.show(context, messages.join(' · '));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(autoHabitValuesProvider, (previous, next) {
      if (previous == null || !mapEquals(previous, next)) _scheduleHabitSync();
    });
    ref.listen(habitsOverviewProvider.select((o) => o == null), (_, missing) {
      if (!missing) _scheduleHabitSync();
    });
    ref.listen(energyStatusProvider.select((s) => s?.estimate.sufficient ?? false),
        (previous, sufficient) async {
      if (!sufficient) return;
      final reason = await reviewWeeklyTarget(ref);
      if (reason != null && context.mounted) toast(context, reason);
    });
    ref.listen(sessionPlanProvider.select((p) => (p.earliestDate, p.template, p.mode)),
        (previous, next) {
      if (previous != next) unawaited(rescheduleReminders(ref));
    });
    ref.listen(settingsProvider.select((s) => (s.mealReminders, s.sessionReminder)),
        (previous, next) {
      if (previous != next) unawaited(rescheduleReminders(ref));
    });
    ref.listen(workTemplatesProvider, (previous, next) {
      if (previous?.value != next.value) unawaited(rescheduleReminders(ref));
    });
    ref.listen(inProgressEntryProvider.select((r) => r?.row.id), (previous, next) {
      if (previous != next) unawaited(rescheduleReminders(ref));
    });
    ref.listen(settingsProvider.select((s) => (s.hydrationReminders, s.dayCloseTime)),
        (previous, next) {
      if (previous != next) unawaited(rescheduleReminders(ref));
    });
    ref.listen(zoneRowsProvider, (previous, next) {
      if (previous?.value != next.value) unawaited(_syncNative(zones: true, eventReminders: true));
    });
    ref.listen(settingsProvider.select((s) => (s.zonesEnabled, s.batteryOverLimit)), (previous, next) {
      if (previous != next) unawaited(_syncNative(zones: true, eventReminders: true));
    });
    ref.listen(contextParamsProvider.select((p) => (p.maxActiveZones, p.responsivenessMin, p.staleHours)),
        (previous, next) {
      if (previous != next) unawaited(_syncNative(zones: true));
    });
    ref.listen(eventReminderRowsProvider, (previous, next) {
      if (previous?.value != next.value) unawaited(_syncNative(eventReminders: true));
    });
    ref.listen(alarmRowsProvider, (previous, next) {
      if (previous?.value != next.value) unawaited(_syncNative(alarms: true));
    });
    final index = ref.watch(shellTabProvider);
    return Scaffold(
      body: IndexedStack(
        index: index,
        children: const [
          EstadoScreen(),
          RegistroScreen(),
          HeavyDutyScreen(),
          TrabajoScreen(),
          MasScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => ref.read(shellTabProvider.notifier).select(i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.monitor_heart_outlined), label: 'ESTADO'),
          NavigationDestination(icon: Icon(Icons.restaurant_outlined), label: 'REGISTRO'),
          NavigationDestination(icon: Icon(Icons.fitness_center), label: 'HEAVY'),
          NavigationDestination(icon: Icon(Icons.work_outline), label: 'TRABAJO'),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: 'MÁS'),
        ],
      ),
    );
  }
}

/// MÁS: the screens that are not used every shift.
class MasScreen extends StatelessWidget {
  const MasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Widget tile(String title, String subtitle, IconData icon, Widget Function() page) => Card(
          child: ListTile(
            minVerticalPadding: 14,
            leading: Icon(icon, size: 32),
            title: Text(title, style: Theme.of(context).textTheme.titleLarge),
            subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page())),
          ),
        );
    return HosPage(
      title: 'MÁS',
      body: PanelList(children: [
        tile('DESPENSA', 'Stock, compras, cocidos y plan del día', Icons.kitchen_outlined,
            () => const DespensaScreen()),
        tile('ÍNDICE', 'Alimentos, productos y sus datos', Icons.menu_book_outlined,
            () => const IndiceScreen()),
        tile('HÁBITOS', 'Rachas, misión mínima y atributos', Icons.check_box_outlined,
            () => const HabitosScreen()),
        tile('CONTEXTO', 'Modo, zonas y «Llegué / Voy a salir»', Icons.place_outlined,
            () => const ContextoScreen()),
        tile('ALARMAS', 'Alarmas de la mañana', Icons.alarm_outlined, () => const AlarmasScreen()),
        tile('AJUSTES', 'Perfil, supuestos, datos de salud y copias', Icons.settings_outlined,
            () => const AjustesScreen()),
        const SizedBox(height: 12),
        Text(
          'HumanOS v3 · sin conexión salvo búsquedas de códigos en Open Food Facts.',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: kTouchTarget),
      ]),
    );
  }
}
