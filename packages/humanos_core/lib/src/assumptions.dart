/// Registry of every modelling constant used by the HumanOS engines.
///
/// These numbers are modelling decisions, not physiological laws. Each one
/// carries a default value, a Spanish title and explanation for the
/// SUPUESTOS screen, an optional source and an editable range. The app
/// seeds the `assumptions` table from [assumptionCatalog]; engines receive
/// an [Assumptions] map and never hide constants inline.
library;

/// Groups used to organise the SUPUESTOS screen.
enum AssumptionGroup {
  energia('ENERGÍA'),
  macros('MACRONUTRIENTES'),
  hidratacion('HIDRATACIÓN Y SODIO'),
  recuperacion('RECUPERACIÓN'),
  entrenamiento('HEAVY DUTY'),
  despensa('DESPENSA Y PLAN'),
  habitos('HÁBITOS Y RACHAS'),
  interacciones('INTERACCIONES'),
  seguridad('SEGURIDAD ALIMENTARIA'),
  horario('HORARIO DE COMIDAS'),
  atributos('ATRIBUTOS');

  const AssumptionGroup(this.labelEs);
  final String labelEs;
}

/// Definition of one assumption.
class AssumptionDef {
  const AssumptionDef({
    required this.key,
    required this.value,
    required this.group,
    required this.titleEs,
    required this.explainEs,
    required this.min,
    required this.max,
    this.source,
    this.unitEs = '',
  });

  final String key;
  final double value;
  final AssumptionGroup group;
  final String titleEs;
  final String explainEs;
  final String? source;
  final String unitEs;

  /// Lowest value the editor accepts.
  final double min;

  /// Highest value the editor accepts.
  final double max;

  /// Whether [candidate] is inside the editable range.
  bool accepts(double candidate) =>
      candidate.isFinite && candidate >= min && candidate <= max;
}

/// Keys of every assumption, so engines and the app never misspell one.
abstract final class A {
  // Energy
  static const tdeeEmaAlpha = 'tdee_ema_alpha';
  static const tdeeWindowDays = 'tdee_window_days';
  static const tdeeMinValidDays = 'tdee_min_valid_days';
  static const kcalPerKg = 'kcal_per_kg';
  static const gainRateMinKgWeek = 'gain_rate_min_kg_week';
  static const gainRateMaxKgWeek = 'gain_rate_max_kg_week';
  static const targetStepMaxKcal = 'target_step_max_kcal';
  static const palWorkday = 'pal_workday';
  static const palOffday = 'pal_offday';
  static const bootstrapSurplusKcal = 'bootstrap_surplus_kcal';
  static const referenceShiftHours = 'reference_shift_hours';
  // Macros
  static const proteinGPerKg = 'protein_g_per_kg';
  static const proteinGPerKgFloor = 'protein_g_per_kg_floor';
  static const proteinGPerKgCeiling = 'protein_g_per_kg_ceiling';
  static const proteinMinPerMealGPerKg = 'protein_min_per_meal_g_per_kg';
  static const proteinMealsPerDay = 'protein_meals_per_day';
  static const proteinPlanTolerance = 'protein_plan_tolerance';
  static const fatKcalFraction = 'fat_kcal_fraction';
  // Hydration
  static const sweatReplaceMinFrac = 'sweat_replace_min_frac';
  static const sweatReplaceMaxFrac = 'sweat_replace_max_frac';
  static const fluidCapLPerH = 'fluid_cap_l_per_h';
  static const heatBolusL = 'heat_bolus_l';
  static const heatBolusIntervalMinMin = 'heat_bolus_interval_min_min';
  static const heatBolusIntervalMaxMin = 'heat_bolus_interval_max_min';
  static const sweatNaMmolL = 'sweat_na_mmol_l';
  static const bodyMassLossWarnPct = 'body_mass_loss_warn_pct';
  static const hydrationGoalFraction = 'hydration_goal_fraction';
  static const heatThresholdC = 'heat_threshold_c';
  // Recovery
  static const hrvShortDays = 'hrv_short_days';
  static const hrvLongDays = 'hrv_long_days';
  static const hrvSdFactor = 'hrv_sd_factor';
  static const hrvMinShortSamples = 'hrv_min_short_samples';
  static const hrvMinLongSamples = 'hrv_min_long_samples';
  static const rhrBaselineDays = 'rhr_baseline_days';
  static const rhrSdFactor = 'rhr_sd_factor';
  static const rhrMinBaselineSamples = 'rhr_min_baseline_samples';
  static const sleepMinMinutes = 'sleep_min_minutes';
  static const sleepTargetH = 'sleep_target_h';
  static const sleepDebtMaxH = 'sleep_debt_max_h';
  static const sleepDebtNights = 'sleep_debt_nights';
  // Training
  static const restDaysMin = 'rest_days_min';
  static const restDaysMax = 'rest_days_max';
  static const stallRestThreshold = 'stall_rest_threshold';
  static const stallExtraRestDays = 'stall_extra_rest_days';
  static const stallDeloadThreshold = 'stall_deload_threshold';
  static const deloadDays = 'deload_days';
  static const deloadRirMin = 'deload_rir_min';
  static const deloadRirMax = 'deload_rir_max';
  static const warmup1Pct = 'warmup1_pct';
  static const warmup1Reps = 'warmup1_reps';
  static const warmup2Pct = 'warmup2_pct';
  static const warmup2Reps = 'warmup2_reps';
  static const tempoMinEccentricS = 'tempo_min_eccentric_s';
  static const tempoConcentricXS = 'tempo_concentric_x_s';
  static const tapDebounceMs = 'tap_debounce_ms';
  static const baselineRepTargetMin = 'baseline_rep_target_min';
  static const baselineRepTargetMax = 'baseline_rep_target_max';
  // Pantry scorer and day plan
  static const wNrfPerUsd = 'w_nrf_per_usd';
  static const wProteinQuality = 'w_protein_quality';
  static const wEnergyDensity = 'w_energy_density';
  static const wGapClosure = 'w_gap_closure';
  static const wNova4Penalty = 'w_nova4_penalty';
  static const wUserExcludedPenalty = 'w_user_excluded_penalty';
  static const wExpiryUrgency = 'w_expiry_urgency';
  static const expiryUrgencyDays = 'expiry_urgency_days';
  static const scorerPortionG = 'scorer_portion_g';
  static const sodiumLimitMg = 'sodium_limit_mg';
  static const lpMaxEnergyShare = 'lp_max_energy_share';
  static const lpFatMaxFrac = 'lp_fat_max_frac';
  // Habits
  static const globalStreakThreshold = 'global_streak_threshold';
  static const minimumRequiredEssentials = 'minimum_required_essentials';
  static const repairTokenEveryDays = 'repair_token_every_days';
  static const habitMaxToleranceFrac = 'habit_max_tolerance_frac';
  // Interactions
  static const ironRelevantMg = 'iron_relevant_mg';
  static const vitcSynergyMg = 'vitc_synergy_mg';
  static const calciumInhibitorMg = 'calcium_inhibitor_mg';
  static const polyphenolWindowMin = 'polyphenol_window_min';
  static const calciumWindowMin = 'calcium_window_min';
  static const rawFiberPreshiftG = 'raw_fiber_preshift_g';
  static const heavyFatMealG = 'heavy_fat_meal_g';
  // Food safety
  static const cookedWarnH = 'cooked_warn_h';
  static const cookedDiscardH = 'cooked_discard_h';
  static const cookedHeatWarnH = 'cooked_heat_warn_h';
  static const cookedHeatDiscardH = 'cooked_heat_discard_h';
  static const fridgeLeftoverDays = 'fridge_leftover_days';
  // Meal schedule
  static const breakfastBeforeShiftMin = 'breakfast_before_shift_min';
  static const lunchDurationMin = 'lunch_duration_min';
  static const postworkoutAfterShiftMin = 'postworkout_after_shift_min';
  static const dinnerAfterPostworkoutMin = 'dinner_after_postworkout_min';
  static const dinnerAfterShiftMin = 'dinner_after_shift_min';
  static const splitBreakfast = 'split_breakfast';
  static const splitMidMorning = 'split_mid_morning';
  static const splitLunch = 'split_lunch';
  static const splitAfternoon = 'split_afternoon';
  static const splitPostWorkout = 'split_post_workout';
  static const splitDinner = 'split_dinner';
  // Attributes
  static const attrWindowDays = 'attr_window_days';
  static const attrRhrZeroSd = 'attr_rhr_zero_sd';
}

const _v1 = 'Supuesto heredado de HumanOS v1';
const _model = 'Supuesto de modelado';

/// Every assumption with its default.
const List<AssumptionDef> assumptionCatalog = [
  // ------------------------------------------------------------ ENERGÍA
  AssumptionDef(
    key: A.tdeeEmaAlpha,
    value: 0.1,
    min: 0.01,
    max: 0.5,
    group: AssumptionGroup.energia,
    titleEs: 'Suavizado de la tendencia de peso',
    explainEs:
        'Cada día la tendencia se mueve un 10 % hacia el peso medido. '
        'Así el agua, la sal y el contenido intestinal del día no mueven el '
        'cálculo del gasto.',
    source: _model,
  ),
  AssumptionDef(
    key: A.tdeeWindowDays,
    value: 21,
    min: 14,
    max: 42,
    unitEs: 'días',
    group: AssumptionGroup.energia,
    titleEs: 'Ventana del gasto adaptativo',
    explainEs:
        'Se miran los últimos 21 días de peso e ingesta para estimar '
        'tu gasto real.',
    source: _model,
  ),
  AssumptionDef(
    key: A.tdeeMinValidDays,
    value: 14,
    min: 7,
    max: 42,
    unitEs: 'días',
    group: AssumptionGroup.energia,
    titleEs: 'Días completos mínimos',
    explainEs:
        'Con menos de 14 días de ingesta registrada completa dentro de '
        'la ventana no se estima el gasto: se muestra «datos insuficientes» y '
        'se usa el arranque con Mifflin.',
    source: _model,
  ),
  AssumptionDef(
    key: A.kcalPerKg,
    value: 7700,
    min: 5000,
    max: 9000,
    unitEs: 'kcal/kg',
    group: AssumptionGroup.energia,
    titleEs: 'Energía por kilo de cambio de peso',
    explainEs:
        'Aproximación clásica de ~7700 kcal por kg. El tejido que se '
        'gana en superávit no es grasa pura, por eso es un supuesto y no una '
        'ley.',
    source: 'Wishnofsky 1958 (regla de 3500 kcal por libra)',
  ),
  AssumptionDef(
    key: A.gainRateMinKgWeek,
    value: 0.15,
    min: 0,
    max: 1,
    unitEs: 'kg/semana',
    group: AssumptionGroup.energia,
    titleEs: 'Ganancia semanal mínima',
    explainEs:
        'Si la tendencia sube menos de 0,15 kg por semana, el objetivo '
        'calórico sube en el ajuste semanal.',
    source: _model,
  ),
  AssumptionDef(
    key: A.gainRateMaxKgWeek,
    value: 0.30,
    min: 0.05,
    max: 1.5,
    unitEs: 'kg/semana',
    group: AssumptionGroup.energia,
    titleEs: 'Ganancia semanal máxima',
    explainEs:
        'Si la tendencia sube más de 0,30 kg por semana, el objetivo '
        'baja: ganar más rápido suele ser más grasa, no más músculo.',
    source: _model,
  ),
  AssumptionDef(
    key: A.targetStepMaxKcal,
    value: 150,
    min: 25,
    max: 500,
    unitEs: 'kcal',
    group: AssumptionGroup.energia,
    titleEs: 'Cambio máximo por ajuste semanal',
    explainEs:
        'El objetivo se mueve como mucho ±150 kcal por semana para no '
        'reaccionar a ruido de la báscula.',
    source: _model,
  ),
  AssumptionDef(
    key: A.palWorkday,
    value: 1.9,
    min: 1.2,
    max: 2.5,
    group: AssumptionGroup.energia,
    titleEs: 'Factor de actividad en día de taller',
    explainEs:
        'Arranque: gasto basal de Mifflin × 1,9 en día de trabajo '
        '(soldadura de pie, 10 h, y entrenamiento después del turno).',
    source:
        'Mifflin MD y col., Am J Clin Nutr 1990;51:241–247 (fórmula). '
        'Factor: supuesto',
  ),
  AssumptionDef(
    key: A.palOffday,
    value: 1.6,
    min: 1.2,
    max: 2.5,
    group: AssumptionGroup.energia,
    titleEs: 'Factor de actividad en día libre',
    explainEs:
        'Arranque: gasto basal de Mifflin × 1,6 en día libre. Un día '
        'libre no es reposo absoluto: caminas, cocinas, entrenas.',
    source:
        'Mifflin MD y col., Am J Clin Nutr 1990;51:241–247 (fórmula). '
        'Factor: supuesto',
  ),
  AssumptionDef(
    key: A.bootstrapSurplusKcal,
    value: 300,
    min: 0,
    max: 1000,
    unitEs: 'kcal',
    group: AssumptionGroup.energia,
    titleEs: 'Superávit de arranque',
    explainEs:
        'Mientras no hay 14 días completos, el objetivo es el gasto '
        'estimado con Mifflin más 300 kcal.',
    source: _model,
  ),
  AssumptionDef(
    key: A.referenceShiftHours,
    value: 10,
    min: 4,
    max: 14,
    unitEs: 'h',
    group: AssumptionGroup.energia,
    titleEs: 'Horas de referencia del turno',
    explainEs:
        'Un turno de 07:00 a 17:00 son 10 h. Si el turno es más corto '
        'o más largo, solo se escala la parte de actividad del gasto; el '
        'gasto basal no cambia con las horas trabajadas.',
    source: _v1,
  ),
  // ------------------------------------------------------------ MACROS
  AssumptionDef(
    key: A.proteinGPerKg,
    value: 1.8,
    min: 1.6,
    max: 2.2,
    unitEs: 'g/kg',
    group: AssumptionGroup.macros,
    titleEs: 'Proteína diaria por kg',
    explainEs:
        '1,8 g por kg de peso al día. El cálculo la limita entre 1,6 y '
        '2,2 g/kg: por encima de ~2,2 no se ha demostrado beneficio adicional '
        'para ganar músculo.',
    source: 'Morton RW y col., Br J Sports Med 2018;52:376–384',
  ),
  AssumptionDef(
    key: A.proteinGPerKgFloor,
    value: 1.6,
    min: 1.0,
    max: 2.2,
    unitEs: 'g/kg',
    group: AssumptionGroup.macros,
    titleEs: 'Proteína: límite inferior',
    explainEs:
        'Por debajo de 1,6 g/kg el metaanálisis de referencia ya no '
        'muestra el máximo efecto sobre la masa magra.',
    source: 'Morton RW y col., Br J Sports Med 2018;52:376–384',
  ),
  AssumptionDef(
    key: A.proteinGPerKgCeiling,
    value: 2.2,
    min: 1.6,
    max: 3.0,
    unitEs: 'g/kg',
    group: AssumptionGroup.macros,
    titleEs: 'Proteína: límite superior',
    explainEs:
        '2,2 g/kg es el extremo superior del intervalo de confianza; '
        'más proteína no suma músculo, solo desplaza carbohidratos.',
    source: 'Morton RW y col., Br J Sports Med 2018;52:376–384',
  ),
  AssumptionDef(
    key: A.proteinMinPerMealGPerKg,
    value: 0.4,
    min: 0.2,
    max: 0.6,
    unitEs: 'g/kg',
    group: AssumptionGroup.macros,
    titleEs: 'Proteína mínima por comida',
    explainEs:
        '0,4 g/kg por toma, repartida en 4 tomas. Es un objetivo '
        'práctico de reparto, no un interruptor que «activa» la síntesis: la '
        'respuesta es gradual.',
    source: 'Schoenfeld BJ, Aragon AA. J Int Soc Sports Nutr 2018;15:10',
  ),
  AssumptionDef(
    key: A.proteinMealsPerDay,
    value: 4,
    min: 2,
    max: 6,
    unitEs: 'tomas',
    group: AssumptionGroup.macros,
    titleEs: 'Tomas de proteína al día',
    explainEs: 'Número de comidas entre las que se reparte la proteína.',
    source: 'Schoenfeld BJ, Aragon AA. J Int Soc Sports Nutr 2018;15:10',
  ),
  AssumptionDef(
    key: A.proteinPlanTolerance,
    value: 0.15,
    min: 0,
    max: 0.5,
    group: AssumptionGroup.macros,
    titleEs: 'Margen del plan de proteína',
    explainEs:
        'El mínimo por toma puede empujar el plan por encima del '
        'objetivo diario. Se permite hasta 15 % de exceso; si se pasa, la '
        'proteína se reparte pareja entre las tomas.',
    source: _v1,
  ),
  AssumptionDef(
    key: A.fatKcalFraction,
    value: 0.30,
    min: 0.15,
    max: 0.45,
    group: AssumptionGroup.macros,
    titleEs: 'Grasa (% de las calorías)',
    explainEs:
        'El 30 % de las calorías se asigna a grasa; los carbohidratos '
        'completan el resto después de la proteína.',
    source: _model,
  ),
  // ------------------------------------------------------- HIDRATACIÓN
  AssumptionDef(
    key: A.sweatReplaceMinFrac,
    value: 0.8,
    min: 0.5,
    max: 1.0,
    group: AssumptionGroup.hidratacion,
    titleEs: 'Reposición mínima del sudor',
    explainEs:
        'Con prueba de sudor se planifica reponer entre el 80 % y el '
        '100 % de lo que pierdes por hora.',
    source: _model,
  ),
  AssumptionDef(
    key: A.sweatReplaceMaxFrac,
    value: 1.0,
    min: 0.5,
    max: 1.2,
    group: AssumptionGroup.hidratacion,
    titleEs: 'Reposición máxima del sudor',
    explainEs:
        'Extremo alto del plan: reponer el 100 % de la tasa de sudor, '
        'siempre por debajo del tope por hora.',
    source: _model,
  ),
  AssumptionDef(
    key: A.fluidCapLPerH,
    value: 1.42,
    min: 0.5,
    max: 1.5,
    unitEs: 'L/h',
    group: AssumptionGroup.hidratacion,
    titleEs: 'Tope de líquido por hora',
    explainEs:
        'No más de 1,42 L por hora (1,5 cuartos de galón). Más que eso '
        'no se absorbe y aumenta el riesgo de hiponatremia.',
    source: 'Ejército de EE. UU., TB MED 507 (trabajo en calor)',
  ),
  AssumptionDef(
    key: A.heatBolusL,
    value: 0.24,
    min: 0.1,
    max: 0.5,
    unitEs: 'L',
    group: AssumptionGroup.hidratacion,
    titleEs: 'Toma sin prueba de sudor',
    explainEs:
        'Sin prueba de sudor: 0,24 L (una taza) cada 15–20 minutos '
        'mientras estés al calor.',
    source: 'NIOSH 2016, Occupational Exposure to Heat and Hot Environments',
  ),
  AssumptionDef(
    key: A.heatBolusIntervalMinMin,
    value: 15,
    min: 5,
    max: 60,
    unitEs: 'min',
    group: AssumptionGroup.hidratacion,
    titleEs: 'Intervalo corto entre tomas',
    explainEs: 'Intervalo más frecuente del plan sin prueba de sudor.',
    source: 'NIOSH 2016, Occupational Exposure to Heat and Hot Environments',
  ),
  AssumptionDef(
    key: A.heatBolusIntervalMaxMin,
    value: 20,
    min: 5,
    max: 60,
    unitEs: 'min',
    group: AssumptionGroup.hidratacion,
    titleEs: 'Intervalo largo entre tomas',
    explainEs:
        'Intervalo menos frecuente del plan sin prueba de sudor. '
        'También marca los avisos de hidratación (cada 20 min).',
    source: 'NIOSH 2016, Occupational Exposure to Heat and Hot Environments',
  ),
  AssumptionDef(
    key: A.sweatNaMmolL,
    value: 40,
    min: 10,
    max: 100,
    unitEs: 'mmol/L',
    group: AssumptionGroup.hidratacion,
    titleEs: 'Sodio en el sudor',
    explainEs:
        'Concentración típica asumida: 40 mmol/L. Varía mucho entre '
        'personas (de ~10 a ~90 mmol/L). Sodio a reponer = litros × mmol/L × '
        '23 mg. El potasio no se calcula a partir del sodio.',
    source: 'Baker LB. Sports Med 2017;47(Supl 1):111–128',
  ),
  AssumptionDef(
    key: A.bodyMassLossWarnPct,
    value: 2.0,
    min: 0.5,
    max: 5,
    unitEs: '%',
    group: AssumptionGroup.hidratacion,
    titleEs: 'Pérdida de peso que dispara aviso',
    explainEs:
        'Perder más del 2 % del peso corporal durante el turno empeora '
        'el rendimiento y el juicio con calor.',
    source: 'ACSM, Med Sci Sports Exerc 2007;39:377–390 (Sawka y col.)',
  ),
  AssumptionDef(
    key: A.hydrationGoalFraction,
    value: 0.80,
    min: 0.5,
    max: 1.0,
    group: AssumptionGroup.hidratacion,
    titleEs: 'Cumplimiento de hidratación',
    explainEs:
        'Un turno cuenta como bien hidratado si bebiste al menos el '
        '80 % del plan del termo.',
    source: _model,
  ),
  AssumptionDef(
    key: A.heatThresholdC,
    value: 32,
    min: 25,
    max: 40,
    unitEs: '°C',
    group: AssumptionGroup.seguridad,
    titleEs: 'Temperatura que cuenta como calor',
    explainEs:
        'Por encima de 32 °C (90 °F) la comida cocinada fuera de la '
        'nevera tiene solo 1 h de margen. Es la pregunta «¿estuvo al calor?».',
    source: 'USDA FSIS, «Danger Zone» (40 °F–140 °F)',
  ),
  // ------------------------------------------------------- RECUPERACIÓN
  AssumptionDef(
    key: A.hrvShortDays,
    value: 7,
    min: 3,
    max: 14,
    unitEs: 'días',
    group: AssumptionGroup.recuperacion,
    titleEs: 'Ventana corta de VFC',
    explainEs:
        'Se promedia el ln rMSSD de los últimos 7 días: un solo día '
        'de variabilidad cardiaca es demasiado ruidoso.',
    source: 'Plews DJ y col., Sports Med 2013;43:773–781',
  ),
  AssumptionDef(
    key: A.hrvLongDays,
    value: 60,
    min: 21,
    max: 120,
    unitEs: 'días',
    group: AssumptionGroup.recuperacion,
    titleEs: 'Línea base de VFC',
    explainEs:
        'Tu rango normal se calcula con los últimos 60 días, no con un '
        'valor fijo de referencia.',
    source: 'Plews DJ y col., Sports Med 2013;43:773–781',
  ),
  AssumptionDef(
    key: A.hrvSdFactor,
    value: 0.5,
    min: 0.25,
    max: 2,
    unitEs: 'DE',
    group: AssumptionGroup.recuperacion,
    titleEs: 'Rango normal de VFC',
    explainEs:
        'Si la media de 7 días cae por debajo de la línea base menos '
        '0,5 desviaciones estándar, cuenta como aviso.',
    source: 'Plews DJ y col., Sports Med 2013;43:773–781',
  ),
  AssumptionDef(
    key: A.hrvMinShortSamples,
    value: 3,
    min: 1,
    max: 14,
    unitEs: 'mediciones',
    group: AssumptionGroup.recuperacion,
    titleEs: 'Mediciones mínimas de VFC (7 días)',
    explainEs:
        'Con menos de 3 mediciones en la semana no se usa la VFC y se '
        'pasa a la frecuencia cardiaca en reposo.',
    source: _model,
  ),
  AssumptionDef(
    key: A.hrvMinLongSamples,
    value: 14,
    min: 5,
    max: 120,
    unitEs: 'mediciones',
    group: AssumptionGroup.recuperacion,
    titleEs: 'Mediciones mínimas de VFC (línea base)',
    explainEs:
        'Hace falta al menos 14 mediciones para tener una línea base '
        'de VFC creíble.',
    source: _model,
  ),
  AssumptionDef(
    key: A.rhrBaselineDays,
    value: 28,
    min: 7,
    max: 90,
    unitEs: 'días',
    group: AssumptionGroup.recuperacion,
    titleEs: 'Línea base de FC en reposo',
    explainEs:
        'Sin VFC, se compara la frecuencia cardiaca en reposo de hoy '
        'con la media de los 28 días anteriores.',
    source: _model,
  ),
  AssumptionDef(
    key: A.rhrSdFactor,
    value: 1.0,
    min: 0.5,
    max: 3,
    unitEs: 'DE',
    group: AssumptionGroup.recuperacion,
    titleEs: 'Umbral de FC en reposo',
    explainEs:
        'Una FC en reposo más de 1 desviación estándar por encima de '
        'tu media cuenta como aviso.',
    source: _model,
  ),
  AssumptionDef(
    key: A.rhrMinBaselineSamples,
    value: 7,
    min: 3,
    max: 60,
    unitEs: 'mediciones',
    group: AssumptionGroup.recuperacion,
    titleEs: 'Mediciones mínimas de FC en reposo',
    explainEs:
        'Con menos de 7 días de FC en reposo no hay línea base y no se '
        'evalúa.',
    source: _model,
  ),
  AssumptionDef(
    key: A.sleepMinMinutes,
    value: 360,
    min: 240,
    max: 480,
    unitEs: 'min',
    group: AssumptionGroup.recuperacion,
    titleEs: 'Sueño mínimo de la noche',
    explainEs: 'Dormir menos de 6 h (360 min) anoche cuenta como aviso.',
    source: _model,
  ),
  AssumptionDef(
    key: A.sleepTargetH,
    value: 8,
    min: 6,
    max: 10,
    unitEs: 'h',
    group: AssumptionGroup.recuperacion,
    titleEs: 'Sueño objetivo',
    explainEs:
        'La deuda de sueño se mide contra 8 h por noche. Las noches '
        'sin registro no cuentan como deuda.',
    source:
        'Hirshkowitz M y col., Sleep Health 2015;1:40–43 (7–9 h en '
        'adultos)',
  ),
  AssumptionDef(
    key: A.sleepDebtMaxH,
    value: 5,
    min: 1,
    max: 20,
    unitEs: 'h',
    group: AssumptionGroup.recuperacion,
    titleEs: 'Deuda de sueño máxima',
    explainEs:
        'Más de 5 h de deuda en las últimas 7 noches cuenta como '
        'aviso.',
    source: _model,
  ),
  AssumptionDef(
    key: A.sleepDebtNights,
    value: 7,
    min: 3,
    max: 14,
    unitEs: 'noches',
    group: AssumptionGroup.recuperacion,
    titleEs: 'Noches para la deuda de sueño',
    explainEs: 'Número de noches que se suman para la deuda.',
    source: _v1,
  ),
  // -------------------------------------------------------- HEAVY DUTY
  AssumptionDef(
    key: A.restDaysMin,
    value: 4,
    min: 2,
    max: 10,
    unitEs: 'días',
    group: AssumptionGroup.entrenamiento,
    titleEs: 'Descanso mínimo entre sesiones',
    explainEs:
        'Una serie al fallo por ejercicio exige 4–5 días de '
        'recuperación antes de la siguiente sesión.',
    source: 'Método Heavy Duty (Mike Mentzer). Rango: supuesto',
  ),
  AssumptionDef(
    key: A.restDaysMax,
    value: 5,
    min: 2,
    max: 12,
    unitEs: 'días',
    group: AssumptionGroup.entrenamiento,
    titleEs: 'Descanso máximo entre sesiones',
    explainEs:
        'Límite superior de la ventana de la próxima sesión cuando no '
        'hay estancamiento.',
    source: 'Método Heavy Duty (Mike Mentzer). Rango: supuesto',
  ),
  AssumptionDef(
    key: A.stallRestThreshold,
    value: 2,
    min: 1,
    max: 5,
    unitEs: 'sesiones',
    group: AssumptionGroup.entrenamiento,
    titleEs: 'Estancamientos para descanso extra',
    explainEs:
        'Dos sesiones seguidas con menos repeticiones que la anterior '
        'en un ejercicio añaden días de descanso.',
    source: _model,
  ),
  AssumptionDef(
    key: A.stallExtraRestDays,
    value: 2,
    min: 1,
    max: 7,
    unitEs: 'días',
    group: AssumptionGroup.entrenamiento,
    titleEs: 'Días extra por estancamiento',
    explainEs: 'Descanso adicional cuando hay dos retrocesos seguidos.',
    source: _model,
  ),
  AssumptionDef(
    key: A.stallDeloadThreshold,
    value: 3,
    min: 2,
    max: 6,
    unitEs: 'sesiones',
    group: AssumptionGroup.entrenamiento,
    titleEs: 'Estancamientos para descarga',
    explainEs:
        'Tres retrocesos seguidos inician una semana de descarga y '
        'luego una sesión de re-test.',
    source: _model,
  ),
  AssumptionDef(
    key: A.deloadDays,
    value: 7,
    min: 3,
    max: 14,
    unitEs: 'días',
    group: AssumptionGroup.entrenamiento,
    titleEs: 'Duración de la descarga',
    explainEs: 'Una semana de descarga: mismas máquinas, sin llegar al fallo.',
    source: _model,
  ),
  AssumptionDef(
    key: A.deloadRirMin,
    value: 2,
    min: 1,
    max: 5,
    unitEs: 'RIR',
    group: AssumptionGroup.entrenamiento,
    titleEs: 'Reserva mínima en descarga',
    explainEs:
        'En descarga cada serie termina con al menos 2 repeticiones en '
        'reserva.',
    source: _model,
  ),
  AssumptionDef(
    key: A.deloadRirMax,
    value: 3,
    min: 1,
    max: 6,
    unitEs: 'RIR',
    group: AssumptionGroup.entrenamiento,
    titleEs: 'Reserva máxima en descarga',
    explainEs: 'Y como mucho con 3 repeticiones en reserva.',
    source: _model,
  ),
  AssumptionDef(
    key: A.warmup1Pct,
    value: 0.50,
    min: 0.2,
    max: 0.8,
    group: AssumptionGroup.entrenamiento,
    titleEs: 'Calentamiento 1: carga',
    explainEs: 'Primera serie de aproximación al 50 % de la carga objetivo.',
    source: _model,
  ),
  AssumptionDef(
    key: A.warmup1Reps,
    value: 8,
    min: 3,
    max: 15,
    unitEs: 'reps',
    group: AssumptionGroup.entrenamiento,
    titleEs: 'Calentamiento 1: repeticiones',
    explainEs: 'Ocho repeticiones controladas al 50 %.',
    source: _model,
  ),
  AssumptionDef(
    key: A.warmup2Pct,
    value: 0.75,
    min: 0.4,
    max: 0.9,
    group: AssumptionGroup.entrenamiento,
    titleEs: 'Calentamiento 2: carga',
    explainEs: 'Segunda serie de aproximación al 75 % de la carga objetivo.',
    source: _model,
  ),
  AssumptionDef(
    key: A.warmup2Reps,
    value: 3,
    min: 1,
    max: 8,
    unitEs: 'reps',
    group: AssumptionGroup.entrenamiento,
    titleEs: 'Calentamiento 2: repeticiones',
    explainEs: 'Tres repeticiones al 75 %: preparan sin fatigar.',
    source: _model,
  ),
  AssumptionDef(
    key: A.tempoMinEccentricS,
    value: 3.0,
    min: 1,
    max: 8,
    unitEs: 's',
    group: AssumptionGroup.entrenamiento,
    titleEs: 'Bajada mínima válida',
    explainEs:
        'Una repetición solo cuenta como válida si la bajada '
        '(excéntrica) dura al menos 3 s.',
    source: _model,
  ),
  AssumptionDef(
    key: A.tempoConcentricXS,
    value: 1.0,
    min: 0.3,
    max: 3,
    unitEs: 's',
    group: AssumptionGroup.entrenamiento,
    titleEs: 'Duración asumida de la subida «X»',
    explainEs:
        'Para estimar la bajada a partir de tus toques se asume que la '
        'subida explosiva dura ~1 s.',
    source: _model,
  ),
  AssumptionDef(
    key: A.tapDebounceMs,
    value: 350,
    min: 100,
    max: 1500,
    unitEs: 'ms',
    group: AssumptionGroup.entrenamiento,
    titleEs: 'Antirrebote del contador',
    explainEs: 'Dos toques separados por menos de 0,35 s cuentan como uno.',
    source: _model,
  ),
  AssumptionDef(
    key: A.baselineRepTargetMin,
    value: 8,
    min: 3,
    max: 15,
    unitEs: 'reps',
    group: AssumptionGroup.entrenamiento,
    titleEs: 'Sesión base: repeticiones mínimas',
    explainEs:
        'En la sesión base se busca la carga con la que el fallo '
        'técnico llegue entre la repetición 8 y la 10.',
    source: _model,
  ),
  AssumptionDef(
    key: A.baselineRepTargetMax,
    value: 10,
    min: 4,
    max: 20,
    unitEs: 'reps',
    group: AssumptionGroup.entrenamiento,
    titleEs: 'Sesión base: repeticiones máximas',
    explainEs: 'Extremo alto del objetivo de la sesión base.',
    source: _model,
  ),
  // ---------------------------------------------------------- DESPENSA
  AssumptionDef(
    key: A.wNrfPerUsd,
    value: 0.30,
    min: 0,
    max: 1,
    group: AssumptionGroup.despensa,
    titleEs: 'Peso: densidad nutricional por dólar',
    explainEs:
        'Cuánto pesa en «MEJOR OPCIÓN AHORA» el índice NRF9.3 por cada '
        'dólar gastado.',
    source: 'Fulgoni VL y col., J Nutr 2009;139:1549–1554 (NRF9.3)',
  ),
  AssumptionDef(
    key: A.wProteinQuality,
    value: 0.25,
    min: 0,
    max: 1,
    group: AssumptionGroup.despensa,
    titleEs: 'Peso: proteína por 100 kcal',
    explainEs:
        'Proteína por cada 100 kcal, ajustada por DIAAS cuando hay un '
        'valor publicado. Sin DIAAS se usa la proteína sin ajustar y baja la '
        'confianza.',
    source: 'FAO 2013, Dietary protein quality evaluation (DIAAS)',
  ),
  AssumptionDef(
    key: A.wEnergyDensity,
    value: 0.15,
    min: 0,
    max: 1,
    group: AssumptionGroup.despensa,
    titleEs: 'Peso: densidad energética',
    explainEs:
        'En fase de superávit, más kcal por gramo ayuda a llegar al '
        'objetivo sin comer volúmenes enormes.',
    source: _model,
  ),
  AssumptionDef(
    key: A.wGapClosure,
    value: 0.15,
    min: 0,
    max: 1,
    group: AssumptionGroup.despensa,
    titleEs: 'Peso: cierre de la brecha de hoy',
    explainEs:
        'Premia lo que cierra lo que falta hoy de kcal y proteína con '
        'una porción de referencia.',
    source: _model,
  ),
  AssumptionDef(
    key: A.wNova4Penalty,
    value: 0.25,
    min: 0,
    max: 2,
    group: AssumptionGroup.despensa,
    titleEs: 'Penalización: ultraprocesado (NOVA 4)',
    explainEs:
        'Se resta este valor a los productos NOVA 4. No se prohíben: '
        'solo bajan en la lista.',
    source: 'Monteiro CA y col., Public Health Nutr 2019;22:936–941 (NOVA)',
  ),
  AssumptionDef(
    key: A.wUserExcludedPenalty,
    value: 1.0,
    min: 0,
    max: 5,
    group: AssumptionGroup.despensa,
    titleEs: 'Penalización: excluido por ti',
    explainEs: 'Lo que marcaste como excluido baja al final de la lista.',
    source: _model,
  ),
  AssumptionDef(
    key: A.wExpiryUrgency,
    value: 0.10,
    min: 0,
    max: 1,
    group: AssumptionGroup.despensa,
    titleEs: 'Peso: vence pronto',
    explainEs: 'Sube lo que vence en los próximos días para no botar comida.',
    source: _model,
  ),
  AssumptionDef(
    key: A.expiryUrgencyDays,
    value: 7,
    min: 1,
    max: 30,
    unitEs: 'días',
    group: AssumptionGroup.despensa,
    titleEs: 'Horizonte de vencimiento',
    explainEs:
        'La urgencia crece en los últimos 7 días antes de la fecha de '
        'vencimiento.',
    source: _model,
  ),
  AssumptionDef(
    key: A.scorerPortionG,
    value: 100,
    min: 20,
    max: 500,
    unitEs: 'g',
    group: AssumptionGroup.despensa,
    titleEs: 'Porción de referencia',
    explainEs:
        'Porción con la que se mide cuánto cierra un alimento la '
        'brecha de hoy.',
    source: _model,
  ),
  AssumptionDef(
    key: A.sodiumLimitMg,
    value: 2300,
    min: 1000,
    max: 5000,
    unitEs: 'mg',
    group: AssumptionGroup.despensa,
    titleEs: 'Límite de sodio diario',
    explainEs:
        'El plan del día no pasa de 2300 mg de sodio más el sodio que '
        'pierdes en el sudor del turno.',
    source: 'NASEM 2019, Dietary Reference Intakes for Sodium and Potassium',
  ),
  AssumptionDef(
    key: A.lpMaxEnergyShare,
    value: 0.35,
    min: 0.1,
    max: 1,
    group: AssumptionGroup.despensa,
    titleEs: 'Máximo de un alimento en el plan',
    explainEs:
        'Ningún alimento aporta más del 35 % de las kcal del plan: '
        'evita planes absurdos como medio kilo de aceite.',
    source: _model,
  ),
  AssumptionDef(
    key: A.lpFatMaxFrac,
    value: 0.35,
    min: 0.15,
    max: 1,
    group: AssumptionGroup.despensa,
    titleEs: 'Máximo de grasa en el plan',
    explainEs: 'La grasa del plan no pasa del 35 % de las kcal objetivo.',
    source: _model,
  ),
  // ------------------------------------------------------------ HÁBITOS
  AssumptionDef(
    key: A.globalStreakThreshold,
    value: 0.70,
    min: 0.3,
    max: 1,
    group: AssumptionGroup.habitos,
    titleEs: 'Umbral de la racha global',
    explainEs:
        'Un día cuenta para la racha global si el puntaje ponderado '
        'llega al 70 %. Exigir 100 % vuelve la racha frágil.',
    source: _v1,
  ),
  AssumptionDef(
    key: A.minimumRequiredEssentials,
    value: 2,
    min: 1,
    max: 10,
    unitEs: 'hábitos',
    group: AssumptionGroup.habitos,
    titleEs: 'Esenciales para el día mínimo',
    explainEs:
        'Con 3 hábitos esenciales basta cumplir 2: la racha mínima '
        'existe para los días malos.',
    source: _v1,
  ),
  AssumptionDef(
    key: A.repairTokenEveryDays,
    value: 14,
    min: 3,
    max: 60,
    unitEs: 'días',
    group: AssumptionGroup.habitos,
    titleEs: 'Días cumplidos por ficha de reparación',
    explainEs:
        'Cada 14 días cumplidos ganas una ficha que cubre un día '
        'perdido sin romper la racha.',
    source: _model,
  ),
  AssumptionDef(
    key: A.habitMaxToleranceFrac,
    value: 0.5,
    min: 0,
    max: 2,
    group: AssumptionGroup.habitos,
    titleEs: 'Tolerancia en hábitos «como máximo»',
    explainEs:
        'En hábitos de límite (pantalla ≤ 60 min) la nota baja de '
        'forma gradual: con 50 % de tolerancia, 75 min dan 0,5 en vez de 0.',
    source: _v1,
  ),
  // ------------------------------------------------------ INTERACCIONES
  AssumptionDef(
    key: A.ironRelevantMg,
    value: 1.5,
    min: 0.5,
    max: 10,
    unitEs: 'mg',
    group: AssumptionGroup.interacciones,
    titleEs: 'Hierro vegetal relevante',
    explainEs:
        'Por debajo de 1,5 mg de hierro no-hemo en la comida el efecto '
        'de las interacciones es demasiado pequeño para avisar.',
    source: _v1,
  ),
  AssumptionDef(
    key: A.vitcSynergyMg,
    value: 25,
    min: 5,
    max: 200,
    unitEs: 'mg',
    group: AssumptionGroup.interacciones,
    titleEs: 'Vitamina C que mejora el hierro',
    explainEs:
        'Desde 25 mg de vitamina C en la comida se menciona que mejora '
        'la absorción del hierro vegetal.',
    source: 'Hallberg L y col., Am J Clin Nutr 1989;49:140–144',
  ),
  AssumptionDef(
    key: A.calciumInhibitorMg,
    value: 250,
    min: 50,
    max: 1000,
    unitEs: 'mg',
    group: AssumptionGroup.interacciones,
    titleEs: 'Calcio que compite con el hierro',
    explainEs:
        'Desde 250 mg de calcio en la misma toma se avisa que compite '
        'con el hierro. Efecto moderado.',
    source: 'Hallberg L y col., Am J Clin Nutr 1991;53:112–119',
  ),
  AssumptionDef(
    key: A.polyphenolWindowMin,
    value: 90,
    min: 0,
    max: 240,
    unitEs: 'min',
    group: AssumptionGroup.interacciones,
    titleEs: 'Ventana café/té y hierro',
    explainEs:
        'Los polifenoles del café o el té reducen la absorción del '
        'hierro vegetal si se toman a menos de ~90 min.',
    source: 'Hurrell RF y col., Br J Nutr 1999;81:289–295',
  ),
  AssumptionDef(
    key: A.calciumWindowMin,
    value: 60,
    min: 0,
    max: 240,
    unitEs: 'min',
    group: AssumptionGroup.interacciones,
    titleEs: 'Ventana calcio y hierro',
    explainEs:
        'El calcio compite con el hierro si se toman a menos de 60 '
        'min.',
    source: _v1,
  ),
  AssumptionDef(
    key: A.rawFiberPreshiftG,
    value: 10,
    min: 2,
    max: 40,
    unitEs: 'g',
    group: AssumptionGroup.interacciones,
    titleEs: 'Fibra cruda antes del turno',
    explainEs:
        'Desde 10 g de fibra de alimentos crudos en el desayuno o la '
        'media mañana se avisa: en volumen suele dar molestias en el trabajo '
        'físico.',
    source: _v1,
  ),
  AssumptionDef(
    key: A.heavyFatMealG,
    value: 25,
    min: 5,
    max: 100,
    unitEs: 'g',
    group: AssumptionGroup.interacciones,
    titleEs: 'Grasa que pesa (reflujo)',
    explainEs:
        'Desde 25 g de grasa en una comida se avisa: retrasa el '
        'vaciado gástrico y puede empeorar el reflujo. No hay que evitarla.',
    source: _v1,
  ),
  // -------------------------------------------------------- SEGURIDAD
  AssumptionDef(
    key: A.cookedWarnH,
    value: 2,
    min: 0.5,
    max: 4,
    unitEs: 'h',
    group: AssumptionGroup.seguridad,
    titleEs: 'Comida cocinada: aviso',
    explainEs:
        'Fuera de la nevera y sin calor extremo, a las 2 h se avisa '
        'que hay que comerla pronto.',
    source: _v1,
  ),
  AssumptionDef(
    key: A.cookedDiscardH,
    value: 4,
    min: 1,
    max: 6,
    unitEs: 'h',
    group: AssumptionGroup.seguridad,
    titleEs: 'Comida cocinada: desechar',
    explainEs:
        'A las 4 h fuera de la nevera se desecha. Bacillus cereus deja '
        'una toxina que resiste el calor: recalentar no la elimina.',
    source: _v1,
  ),
  AssumptionDef(
    key: A.cookedHeatWarnH,
    value: 0.5,
    min: 0.25,
    max: 1,
    unitEs: 'h',
    group: AssumptionGroup.seguridad,
    titleEs: 'Al calor: aviso',
    explainEs:
        'Si la comida estuvo al calor (taller, lonchera al sol), a los '
        '30 min se avisa.',
    source: _model,
  ),
  AssumptionDef(
    key: A.cookedHeatDiscardH,
    value: 1,
    min: 0.5,
    max: 2,
    unitEs: 'h',
    group: AssumptionGroup.seguridad,
    titleEs: 'Al calor: desechar',
    explainEs: 'Por encima de 32 °C el margen es de 1 h.',
    source: 'USDA FSIS, «Danger Zone»',
  ),
  AssumptionDef(
    key: A.fridgeLeftoverDays,
    value: 4,
    min: 1,
    max: 7,
    unitEs: 'días',
    group: AssumptionGroup.seguridad,
    titleEs: 'Sobras refrigeradas',
    explainEs:
        'Refrigerada se conserva de forma normal: consúmela en 3–4 '
        'días.',
    source: 'USDA FSIS, «Leftovers and Food Safety»',
  ),
  // ---------------------------------------------------------- HORARIO
  AssumptionDef(
    key: A.breakfastBeforeShiftMin,
    value: 45,
    min: 15,
    max: 180,
    unitEs: 'min',
    group: AssumptionGroup.horario,
    titleEs: 'Desayuno antes del turno',
    explainEs: 'El desayuno se agenda 45 min antes de entrar al turno.',
    source: _model,
  ),
  AssumptionDef(
    key: A.lunchDurationMin,
    value: 60,
    min: 20,
    max: 120,
    unitEs: 'min',
    group: AssumptionGroup.horario,
    titleEs: 'Duración del almuerzo',
    explainEs: 'Una hora de receso para almorzar.',
    source: _model,
  ),
  AssumptionDef(
    key: A.postworkoutAfterShiftMin,
    value: 90,
    min: 30,
    max: 240,
    unitEs: 'min',
    group: AssumptionGroup.horario,
    titleEs: 'Post-entreno después del turno',
    explainEs:
        'Se entrena después del turno: la comida post-entreno va 90 '
        'min después de la salida.',
    source: _model,
  ),
  AssumptionDef(
    key: A.dinnerAfterPostworkoutMin,
    value: 75,
    min: 30,
    max: 240,
    unitEs: 'min',
    group: AssumptionGroup.horario,
    titleEs: 'Cena después del post-entreno',
    explainEs:
        'En días de entreno la cena va 75 min después del '
        'post-entreno.',
    source: _model,
  ),
  AssumptionDef(
    key: A.dinnerAfterShiftMin,
    value: 150,
    min: 30,
    max: 300,
    unitEs: 'min',
    group: AssumptionGroup.horario,
    titleEs: 'Cena después del turno',
    explainEs:
        'En días sin entreno la cena va 2 h 30 min después de la '
        'salida.',
    source: _model,
  ),
  AssumptionDef(
    key: A.splitBreakfast,
    value: 0.22,
    min: 0,
    max: 1,
    group: AssumptionGroup.horario,
    titleEs: 'Reparto: desayuno',
    explainEs:
        'Parte de las kcal del día para el desayuno. Los repartos se '
        'normalizan para sumar 100 % entre las comidas del día.',
    source: _v1,
  ),
  AssumptionDef(
    key: A.splitMidMorning,
    value: 0.13,
    min: 0,
    max: 1,
    group: AssumptionGroup.horario,
    titleEs: 'Reparto: media mañana',
    explainEs: 'Parte de las kcal del día para la media mañana.',
    source: _v1,
  ),
  AssumptionDef(
    key: A.splitLunch,
    value: 0.22,
    min: 0,
    max: 1,
    group: AssumptionGroup.horario,
    titleEs: 'Reparto: almuerzo',
    explainEs: 'Parte de las kcal del día para el almuerzo.',
    source: _v1,
  ),
  AssumptionDef(
    key: A.splitAfternoon,
    value: 0.10,
    min: 0,
    max: 1,
    group: AssumptionGroup.horario,
    titleEs: 'Reparto: tarde',
    explainEs: 'Parte de las kcal del día para el refrigerio de la tarde.',
    source: _v1,
  ),
  AssumptionDef(
    key: A.splitPostWorkout,
    value: 0.13,
    min: 0,
    max: 1,
    group: AssumptionGroup.horario,
    titleEs: 'Reparto: post-entreno',
    explainEs:
        'Parte de las kcal para después de entrenar. En días sin '
        'entreno se reparte entre las demás comidas.',
    source: _model,
  ),
  AssumptionDef(
    key: A.splitDinner,
    value: 0.20,
    min: 0,
    max: 1,
    group: AssumptionGroup.horario,
    titleEs: 'Reparto: cena',
    explainEs: 'Parte de las kcal del día para la cena.',
    source: _v1,
  ),
  // ---------------------------------------------------------- ATRIBUTOS
  AssumptionDef(
    key: A.attrWindowDays,
    value: 30,
    min: 7,
    max: 90,
    unitEs: 'días',
    group: AssumptionGroup.atributos,
    titleEs: 'Ventana de atributos',
    explainEs:
        'RESISTENCIA y DISCIPLINA se calculan sobre los últimos 30 '
        'días con datos.',
    source: _model,
  ),
  AssumptionDef(
    key: A.attrRhrZeroSd,
    value: 2,
    min: 0.5,
    max: 5,
    unitEs: 'DE',
    group: AssumptionGroup.atributos,
    titleEs: 'RECUPERACIÓN: FC en reposo que da cero',
    explainEs:
        'Si tu FC en reposo de la semana está 2 desviaciones estándar '
        'por encima de tu media, esa parte de RECUPERACIÓN vale 0.',
    source: _model,
  ),
];

/// Catalog indexed by key.
final Map<String, AssumptionDef> assumptionsByKey = {
  for (final def in assumptionCatalog) def.key: def,
};

/// Immutable key → value view used by every engine.
class Assumptions {
  Assumptions(Map<String, double> values) : _values = Map.unmodifiable(values);

  /// Catalog defaults.
  factory Assumptions.defaults() =>
      Assumptions({for (final def in assumptionCatalog) def.key: def.value});

  final Map<String, double> _values;

  /// Value for [key]: the stored value if present, else the catalog default.
  /// Unknown keys throw, so a typo can never silently become zero.
  double operator [](String key) {
    final stored = _values[key];
    if (stored != null) return stored;
    final def = assumptionsByKey[key];
    if (def == null) {
      throw ArgumentError.value(key, 'key', 'Supuesto desconocido');
    }
    return def.value;
  }

  /// Integer view for counts (days, samples, reps).
  int integer(String key) => this[key].round();

  /// Copy with some values replaced.
  Assumptions copyWith(Map<String, double> overrides) =>
      Assumptions({..._values, ...overrides});

  Map<String, double> toMap() => Map.of(_values);
}
