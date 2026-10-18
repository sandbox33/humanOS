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
  perfil('PERFIL INICIAL'),
  hidratacion('HIDRATACIÓN'),
  recuperacion('RECUPERACIÓN'),
  entrenamiento('HEAVY DUTY'),
  despensa('DESPENSA Y PLAN'),
  habitos('HÁBITOS Y RACHAS'),
  interacciones('INTERACCIONES'),
  seguridad('SEGURIDAD ALIMENTARIA'),
  horario('HORARIO DE COMIDAS'),
  atributos('ATRIBUTOS'),
  avisos('AVISOS Y CONTEXTO'),
  gamificacion('NIVELES Y XP'),
  mente('MENTE'),
  cuant('LABORATORIO CUANT'),
  toxcheck('TOX-CHECK');

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
  static const referenceShiftHours = 'reference_shift_hours';
  // Starting profile (onboarding priors)
  static const surplusEctoKcal = 'surplus_ecto_kcal';
  static const surplusMesoKcal = 'surplus_meso_kcal';
  static const surplusEndoKcal = 'surplus_endo_kcal';
  static const surplusUnknownKcal = 'surplus_unknown_kcal';
  static const palJobModerate = 'pal_job_moderate';
  static const palJobDesk = 'pal_job_desk';
  static const maintainRateMinKgWeek = 'maintain_rate_min_kg_week';
  static const maintainRateMaxKgWeek = 'maintain_rate_max_kg_week';
  static const loseRateMinKgWeek = 'lose_rate_min_kg_week';
  static const loseRateMaxKgWeek = 'lose_rate_max_kg_week';
  // Macros
  static const proteinGPerKg = 'protein_g_per_kg';
  static const proteinGPerKgFloor = 'protein_g_per_kg_floor';
  static const proteinGPerKgCeiling = 'protein_g_per_kg_ceiling';
  static const proteinMinPerMealGPerKg = 'protein_min_per_meal_g_per_kg';
  static const proteinMealsPerDay = 'protein_meals_per_day';
  static const proteinPlanTolerance = 'protein_plan_tolerance';
  static const fatKcalFraction = 'fat_kcal_fraction';
  // Hydration
  static const heatBolusL = 'heat_bolus_l';
  static const fluidCapLPerH = 'fluid_cap_l_per_h';
  static const sweatFeelPocoFactor = 'sweat_feel_poco_factor';
  static const sweatFeelNormalFactor = 'sweat_feel_normal_factor';
  static const sweatFeelMuchoFactor = 'sweat_feel_mucho_factor';
  static const sweatFeelDays = 'sweat_feel_days';
  static const hydrationPreShiftLeadMin = 'hydration_pre_shift_lead_min';
  static const heatBolusIntervalMinMin = 'heat_bolus_interval_min_min';
  static const heatBolusIntervalMaxMin = 'heat_bolus_interval_max_min';
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
  static const feelLowThreshold = 'feel_low_threshold';
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
  static const restBetweenExercisesS = 'rest_between_exercises_s';
  static const restPauseS = 'rest_pause_s';
  static const baselineRepTargetMin = 'baseline_rep_target_min';
  static const baselineRepTargetMax = 'baseline_rep_target_max';
  static const jumpRepsOverMax = 'jump_reps_over_max';
  static const jumpRepsAbsolute = 'jump_reps_absolute';
  static const jumpTargetReps = 'jump_target_reps';
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
  static const lpKcalOvershootFrac = 'lp_kcal_overshoot_frac';
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
  static const attrNutritionTolerance = 'attr_nutrition_tolerance';
  // Notifications and context
  static const tipsMaxPerDay = 'tips_max_per_day';
  static const quietFromH = 'quiet_from_h';
  static const quietToH = 'quiet_to_h';
  static const stressSdThreshold = 'stress_sd_threshold';
  static const stressBaselineDays = 'stress_baseline_days';
  static const stressMinBaselineSamples = 'stress_min_baseline_samples';
  static const stressWorkoutMarginMin = 'stress_workout_margin_min';
  // XP and levels
  static const xpMealLogged = 'xp_meal_logged';
  static const xpMealCap = 'xp_meal_cap';
  static const xpWeighIn = 'xp_weigh_in';
  static const xpSession = 'xp_session';
  static const xpPr = 'xp_pr';
  static const xpPrCap = 'xp_pr_cap';
  static const xpMinimumDay = 'xp_minimum_day';
  static const xpShiftLogged = 'xp_shift_logged';
  static const xpHydrationAck = 'xp_hydration_ack';
  static const xpCheckIn = 'xp_check_in';
  static const xpMindCorrect = 'xp_mind_correct';
  static const xpMindCap = 'xp_mind_cap';
  static const xpMindReflection = 'xp_mind_reflection';
  static const xpReflectionCap = 'xp_reflection_cap';
  static const xpQuantExperiment = 'xp_quant_experiment';
  static const xpQuantCap = 'xp_quant_cap';
  static const levelBaseXp = 'level_base_xp';
  static const levelExponent = 'level_exponent';
  static const pipchamoStreakDays = 'pipchamo_streak_days';
  // Mind
  static const mindEloK = 'mind_elo_k';
  static const mindStartRating = 'mind_start_rating';
  static const mindTargetSuccess = 'mind_target_success';
  static const mindRetryDays = 'mind_retry_days';
  // Quant lab
  static const quantCostBps = 'quant_cost_bps';
  static const quantDsrThreshold = 'quant_dsr_threshold';
  static const quantTrainBars = 'quant_train_bars';
  static const quantTestBars = 'quant_test_bars';
  static const quantBootstrapBlock = 'quant_bootstrap_block';
  static const quantBootstrapSamples = 'quant_bootstrap_samples';
  static const quantBarsPerYear = 'quant_bars_per_year';
  // Tox-Check
  static const fluorideToothpasteMaxPpm = 'fluoride_toothpaste_max_ppm';
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
    titleEs: 'Actividad: trabajo manual pesado',
    explainEs:
        'Arranque: gasto basal de Mifflin × 1,9 en día de trabajo manual '
        'pesado (por ejemplo soldadura de pie, 10 h, y entrenamiento '
        'después del turno).',
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
        'Arranque: gasto basal de Mifflin × 1,6 en día libre (nunca más '
        'que en un día de trabajo). Un día libre no es reposo absoluto: '
        'caminas, cocinas, entrenas.',
    source:
        'Mifflin MD y col., Am J Clin Nutr 1990;51:241–247 (fórmula). '
        'Factor: supuesto',
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
  AssumptionDef(
    key: A.surplusEctoKcal,
    value: 400,
    min: 0,
    max: 800,
    unitEs: 'kcal',
    group: AssumptionGroup.perfil,
    titleEs: 'Superávit inicial: ecto',
    explainEs:
        'Si tu meta es ganar y marcaste ectomorfo, el objetivo de arranque suma 400 kcal. El somatotipo es descriptivo y su evidencia es débil: tras 14 días válidos el gasto real lo reemplaza.',
    source: 'Prior de arranque (evidencia débil)',
  ),
  AssumptionDef(
    key: A.surplusMesoKcal,
    value: 300,
    min: 0,
    max: 800,
    unitEs: 'kcal',
    group: AssumptionGroup.perfil,
    titleEs: 'Superávit inicial: meso',
    explainEs: 'Mesomorfo con meta de ganar: +300 kcal al arranque.',
    source: 'Prior de arranque (evidencia débil)',
  ),
  AssumptionDef(
    key: A.surplusEndoKcal,
    value: 200,
    min: 0,
    max: 800,
    unitEs: 'kcal',
    group: AssumptionGroup.perfil,
    titleEs: 'Superávit inicial: endo',
    explainEs: 'Endomorfo con meta de ganar: +200 kcal al arranque.',
    source: 'Prior de arranque (evidencia débil)',
  ),
  AssumptionDef(
    key: A.surplusUnknownKcal,
    value: 300,
    min: 0,
    max: 800,
    unitEs: 'kcal',
    group: AssumptionGroup.perfil,
    titleEs: 'Superávit inicial: no sé',
    explainEs: 'Sin somatotipo elegido: +300 kcal al arranque.',
    source: 'Prior de arranque (evidencia débil)',
  ),
  AssumptionDef(
    key: A.palJobModerate,
    value: 1.6,
    min: 1.2,
    max: 2.4,
    group: AssumptionGroup.perfil,
    titleEs: 'Actividad: trabajo moderado',
    explainEs:
        'Multiplicador del metabolismo basal en días de trabajo moderado (de pie, cargas ligeras).',
    source: 'FAO/WHO/UNU 2004, niveles de actividad física',
  ),
  AssumptionDef(
    key: A.palJobDesk,
    value: 1.4,
    min: 1.2,
    max: 2.4,
    group: AssumptionGroup.perfil,
    titleEs: 'Actividad: trabajo de escritorio',
    explainEs: 'Multiplicador para trabajo sentado.',
    source: 'FAO/WHO/UNU 2004, niveles de actividad física',
  ),
  AssumptionDef(
    key: A.maintainRateMinKgWeek,
    value: -0.05,
    min: -0.3,
    max: 0,
    unitEs: 'kg/sem',
    group: AssumptionGroup.perfil,
    titleEs: 'Mantener: ritmo mínimo',
    explainEs:
        'Con meta «mantener», el ajuste semanal apunta a un cambio entre −0,05 y +0,05 kg por semana.',
    source: _model,
  ),
  AssumptionDef(
    key: A.maintainRateMaxKgWeek,
    value: 0.05,
    min: 0,
    max: 0.3,
    unitEs: 'kg/sem',
    group: AssumptionGroup.perfil,
    titleEs: 'Mantener: ritmo máximo',
    explainEs: 'Límite superior del ritmo para «mantener».',
    source: _model,
  ),
  AssumptionDef(
    key: A.loseRateMinKgWeek,
    value: -0.5,
    min: -1.5,
    max: 0,
    unitEs: 'kg/sem',
    group: AssumptionGroup.perfil,
    titleEs: 'Perder: ritmo más rápido',
    explainEs:
        'Con meta «perder», el ajuste apunta a bajar entre 0,25 y 0,5 kg por semana (alrededor de 0,5–1 % del peso), para proteger el músculo.',
    source: 'Helms et al. 2014, J Int Soc Sports Nutr 11:20',
  ),
  AssumptionDef(
    key: A.loseRateMaxKgWeek,
    value: -0.25,
    min: -1.5,
    max: 0,
    unitEs: 'kg/sem',
    group: AssumptionGroup.perfil,
    titleEs: 'Perder: ritmo más lento',
    explainEs: 'Límite más lento del ritmo para «perder».',
    source: 'Helms et al. 2014, J Int Soc Sports Nutr 11:20',
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
    key: A.heatBolusL,
    value: 0.24,
    min: 0.1,
    max: 0.5,
    unitEs: 'L',
    group: AssumptionGroup.hidratacion,
    titleEs: 'Taza de referencia',
    explainEs:
        'Base del plan del termo: 0,24 L (una taza) cada 15–20 minutos '
        'de calor. Es un rango orientativo, no una receta.',
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
    explainEs:
        'Con tomas cada 15 min sale el extremo alto del rango del termo.',
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
        'Con tomas cada 20 min sale el extremo bajo del rango del termo. '
        'Durante el turno no hay avisos: el rango se muestra antes de '
        'entrar y en el almuerzo.',
    source: 'NIOSH 2016, Occupational Exposure to Heat and Hot Environments',
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
        'El rango nunca pasa de 1,42 L por hora (1,5 cuartos de galón). '
        'Más que eso no se absorbe y aumenta el riesgo de hiponatremia.',
    source: 'Ejército de EE. UU., TB MED 507 (trabajo en calor)',
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
  AssumptionDef(
    key: A.sweatFeelPocoFactor,
    value: 0.8,
    min: 0.3,
    max: 1.0,
    group: AssumptionGroup.hidratacion,
    titleEs: 'Sudé poco: factor del plan',
    explainEs:
        'Si en tus últimos turnos marcaste «poco», el rango del termo se multiplica por 0,8.',
    source: _model,
  ),
  AssumptionDef(
    key: A.sweatFeelNormalFactor,
    value: 1.0,
    min: 0.5,
    max: 1.5,
    group: AssumptionGroup.hidratacion,
    titleEs: 'Sudé normal: factor del plan',
    explainEs: '«Normal» deja el rango base tal cual.',
    source: _model,
  ),
  AssumptionDef(
    key: A.sweatFeelMuchoFactor,
    value: 1.2,
    min: 1.0,
    max: 2.0,
    group: AssumptionGroup.hidratacion,
    titleEs: 'Sudé mucho: factor del plan',
    explainEs:
        'Si marcaste «mucho», el rango se multiplica por 1,2. El sudor cambia con el clima y la tarea: por eso es un rango, no una receta.',
    source: _model,
  ),
  AssumptionDef(
    key: A.sweatFeelDays,
    value: 7,
    min: 3,
    max: 28,
    unitEs: 'días',
    group: AssumptionGroup.hidratacion,
    titleEs: 'Días de sensación de sudor',
    explainEs:
        'El factor usa la media de lo que marcaste en los últimos 7 días.',
    source: _model,
  ),
  AssumptionDef(
    key: A.hydrationPreShiftLeadMin,
    value: 30,
    min: 5,
    max: 120,
    unitEs: 'min',
    group: AssumptionGroup.hidratacion,
    titleEs: 'Aviso antes del turno',
    explainEs:
        'El aviso «llena el termo» llega 30 min antes de entrar. Durante el turno no hay avisos, salvo en el almuerzo.',
    source: _model,
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
  AssumptionDef(
    key: A.feelLowThreshold,
    value: 2,
    min: 1,
    max: 4,
    unitEs: 'de 5',
    group: AssumptionGroup.recuperacion,
    titleEs: 'Sensación matinal baja',
    explainEs:
        'Si al despertar marcas 2 o menos (de 1 a 5), esa señal cuenta como AMARILLO.',
    source: _model,
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
    key: A.restBetweenExercisesS,
    value: 120,
    min: 30,
    max: 600,
    unitEs: 's',
    group: AssumptionGroup.entrenamiento,
    titleEs: 'Descanso entre ejercicios',
    explainEs:
        'Duración del temporizador entre ejercicios. Una sola serie por '
        'ejercicio permite descansos cortos; súbelo si llegas sin aliento '
        'a la siguiente.',
    source: _model,
  ),
  AssumptionDef(
    key: A.restPauseS,
    value: 15,
    min: 5,
    max: 60,
    unitEs: 's',
    group: AssumptionGroup.entrenamiento,
    titleEs: 'Pausa del rest-pause',
    explainEs:
        'Segundos de pausa tras el fallo antes de las repeticiones extra. '
        'Solo en ejercicios seguros al fallo.',
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
  AssumptionDef(
    key: A.jumpRepsOverMax,
    value: 5,
    min: 1,
    max: 20,
    unitEs: 'reps',
    group: AssumptionGroup.entrenamiento,
    titleEs: 'Salto de carga: reps sobre el máximo',
    explainEs:
        'Si haces 5 o más repeticiones por encima del máximo del rango, la carga era demasiado ligera: la próxima se calcula con tu 1RM estimado.',
    source: _model,
  ),
  AssumptionDef(
    key: A.jumpRepsAbsolute,
    value: 20,
    min: 10,
    max: 50,
    unitEs: 'reps',
    group: AssumptionGroup.entrenamiento,
    titleEs: 'Salto de carga: reps totales',
    explainEs: 'Más de 20 repeticiones también dispara el salto de carga.',
    source: _model,
  ),
  AssumptionDef(
    key: A.jumpTargetReps,
    value: 10,
    min: 6,
    max: 15,
    unitEs: 'reps',
    group: AssumptionGroup.entrenamiento,
    titleEs: 'Salto de carga: reps objetivo',
    explainEs:
        'La nueva carga es la que tu 1RM estimado (Epley) da para 10 repeticiones, redondeada a tus discos. Diez es el extremo prudente del rango 8–10.',
    source: 'Epley 1985',
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
  AssumptionDef(
    key: A.lpKcalOvershootFrac,
    value: 0.10,
    min: 0,
    max: 0.5,
    group: AssumptionGroup.despensa,
    titleEs: 'Margen de kcal del plan sin precios',
    explainEs:
        'Sin precios, el plan busca la mejor puntuación sin pasar de las '
        'kcal que faltan más un 10 %, para no llenarte de comida.',
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
        'RESISTENCIA, NUTRICIÓN, RECUPERACIÓN y DISCIPLINA se calculan '
        'sobre los últimos 30 días con datos.',
    source: _model,
  ),
  AssumptionDef(
    key: A.attrNutritionTolerance,
    value: 0.10,
    min: 0.02,
    max: 0.3,
    group: AssumptionGroup.atributos,
    titleEs: 'NUTRICIÓN: margen del día cumplido',
    explainEs:
        'Un día cuenta para NUTRICIÓN si las kcal quedan a ±10 % de tu '
        'objetivo y la proteína llega al menos al 90 %.',
    source: _model,
  ),
  AssumptionDef(
    key: A.tipsMaxPerDay,
    value: 3,
    min: 0,
    max: 3,
    group: AssumptionGroup.avisos,
    titleEs: 'Consejos por día',
    explainEs:
        'Como máximo 3 avisos de consejo al día, y nunca durante el turno salvo en el almuerzo.',
    source: _model,
  ),
  AssumptionDef(
    key: A.quietFromH,
    value: 21,
    min: 18,
    max: 24,
    unitEs: 'h',
    group: AssumptionGroup.avisos,
    titleEs: 'Silencio desde',
    explainEs:
        'Desde las 21:00 no llegan consejos ni preguntas de contexto. Los '
        'avisos del termo siguen tu turno.',
    source: _model,
  ),
  AssumptionDef(
    key: A.quietToH,
    value: 6,
    min: 3,
    max: 10,
    unitEs: 'h',
    group: AssumptionGroup.avisos,
    titleEs: 'Silencio hasta',
    explainEs: 'Hasta las 06:00 no llegan consejos ni preguntas de contexto.',
    source: _model,
  ),
  AssumptionDef(
    key: A.stressSdThreshold,
    value: 2,
    min: 1.5,
    max: 4,
    unitEs: 'DE',
    group: AssumptionGroup.avisos,
    titleEs: 'Pulso alto fuera de ejercicio',
    explainEs:
        'Solo si tu dispositivo comparte pulso fuera del ejercicio: si está 2 desviaciones por encima de tu base para esa hora, sin entreno y fuera del taller, la app te pregunta qué pasaba (una vez al día como máximo).',
    source: _model,
  ),
  AssumptionDef(
    key: A.stressBaselineDays,
    value: 28,
    min: 14,
    max: 60,
    unitEs: 'días',
    group: AssumptionGroup.avisos,
    titleEs: 'Base de pulso por hora',
    explainEs:
        'La base de cada hora del día se calcula con los últimos 28 días.',
    source: _model,
  ),
  AssumptionDef(
    key: A.stressMinBaselineSamples,
    value: 10,
    min: 5,
    max: 60,
    group: AssumptionGroup.avisos,
    titleEs: 'Muestras mínimas por hora',
    explainEs: 'Hacen falta 10 lecturas de esa hora para comparar.',
    source: _model,
  ),
  AssumptionDef(
    key: A.stressWorkoutMarginMin,
    value: 30,
    min: 0,
    max: 120,
    unitEs: 'min',
    group: AssumptionGroup.avisos,
    titleEs: 'Margen tras el ejercicio',
    explainEs:
        'El pulso de los 30 min después de un entreno no cuenta como '
        'pulso alto: es la recuperación normal.',
    source: _model,
  ),
  AssumptionDef(
    key: A.xpMealLogged,
    value: 5,
    min: 0,
    max: 50,
    unitEs: 'XP',
    group: AssumptionGroup.gamificacion,
    titleEs: 'XP por comida registrada',
    explainEs:
        'Cada comida registrada da 5 XP, hasta 4 por día. Solo cuentan acciones reales: nada al azar.',
    source: _model,
  ),
  AssumptionDef(
    key: A.xpMealCap,
    value: 4,
    min: 0,
    max: 10,
    group: AssumptionGroup.gamificacion,
    titleEs: 'Tope diario de comidas con XP',
    explainEs: 'Máximo de comidas que dan XP en un día.',
    source: _model,
  ),
  AssumptionDef(
    key: A.xpWeighIn,
    value: 10,
    min: 0,
    max: 50,
    unitEs: 'XP',
    group: AssumptionGroup.gamificacion,
    titleEs: 'XP por pesarte',
    explainEs: 'Un pesaje al día da 10 XP.',
    source: _model,
  ),
  AssumptionDef(
    key: A.xpSession,
    value: 60,
    min: 0,
    max: 200,
    unitEs: 'XP',
    group: AssumptionGroup.gamificacion,
    titleEs: 'XP por sesión completa',
    explainEs: 'Guardar una sesión de Heavy Duty da 60 XP (una por día).',
    source: _model,
  ),
  AssumptionDef(
    key: A.xpPr,
    value: 25,
    min: 0,
    max: 100,
    unitEs: 'XP',
    group: AssumptionGroup.gamificacion,
    titleEs: 'XP por récord',
    explainEs:
        'Cada récord real (1RM estimado o repeticiones con la misma carga) da 25 XP.',
    source: _model,
  ),
  AssumptionDef(
    key: A.xpPrCap,
    value: 3,
    min: 0,
    max: 10,
    group: AssumptionGroup.gamificacion,
    titleEs: 'Tope de récords con XP',
    explainEs: 'Máximo de récords con XP en un día.',
    source: _model,
  ),
  AssumptionDef(
    key: A.xpMinimumDay,
    value: 20,
    min: 0,
    max: 100,
    unitEs: 'XP',
    group: AssumptionGroup.gamificacion,
    titleEs: 'XP por cumplir el mínimo',
    explainEs: 'Cumplir el mínimo del día da 20 XP.',
    source: _model,
  ),
  AssumptionDef(
    key: A.xpShiftLogged,
    value: 10,
    min: 0,
    max: 50,
    unitEs: 'XP',
    group: AssumptionGroup.gamificacion,
    titleEs: 'XP por registrar el turno',
    explainEs: 'Registrar esfuerzo y sudor del turno da 10 XP.',
    source: _model,
  ),
  AssumptionDef(
    key: A.xpHydrationAck,
    value: 5,
    min: 0,
    max: 30,
    unitEs: 'XP',
    group: AssumptionGroup.gamificacion,
    titleEs: 'XP por confirmar el agua',
    explainEs:
        'Confirmar el aviso del termo (antes del turno y en el almuerzo) da 5 XP cada uno.',
    source: _model,
  ),
  AssumptionDef(
    key: A.xpCheckIn,
    value: 5,
    min: 0,
    max: 30,
    unitEs: 'XP',
    group: AssumptionGroup.gamificacion,
    titleEs: 'XP por la sensación matinal',
    explainEs: 'Responder cómo amaneciste da 5 XP al día.',
    source: _model,
  ),
  AssumptionDef(
    key: A.xpMindCorrect,
    value: 8,
    min: 0,
    max: 50,
    unitEs: 'XP',
    group: AssumptionGroup.gamificacion,
    titleEs: 'XP por respuesta correcta en MENTE',
    explainEs: 'Cada reto acertado da 8 XP, hasta 10 al día.',
    source: _model,
  ),
  AssumptionDef(
    key: A.xpMindCap,
    value: 10,
    min: 0,
    max: 30,
    group: AssumptionGroup.gamificacion,
    titleEs: 'Tope diario de retos con XP',
    explainEs: 'Máximo de retos acertados con XP en un día.',
    source: _model,
  ),
  AssumptionDef(
    key: A.xpMindReflection,
    value: 6,
    min: 0,
    max: 50,
    unitEs: 'XP',
    group: AssumptionGroup.gamificacion,
    titleEs: 'XP por explicar tu razonamiento',
    explainEs:
        'Explicar con tus palabras por qué respondiste así da 6 XP, hasta 3 al día.',
    source: _model,
  ),
  AssumptionDef(
    key: A.xpReflectionCap,
    value: 3,
    min: 0,
    max: 10,
    group: AssumptionGroup.gamificacion,
    titleEs: 'Tope de explicaciones con XP',
    explainEs: 'Máximo de explicaciones con XP por día.',
    source: _model,
  ),
  AssumptionDef(
    key: A.xpQuantExperiment,
    value: 12,
    min: 0,
    max: 50,
    unitEs: 'XP',
    group: AssumptionGroup.gamificacion,
    titleEs: 'XP por experimento cuantitativo',
    explainEs:
        'Correr un experimento en el laboratorio da 12 XP, hasta 3 al día.',
    source: _model,
  ),
  AssumptionDef(
    key: A.xpQuantCap,
    value: 3,
    min: 0,
    max: 10,
    group: AssumptionGroup.gamificacion,
    titleEs: 'Tope de experimentos con XP',
    explainEs: 'Máximo de experimentos con XP por día.',
    source: _model,
  ),
  AssumptionDef(
    key: A.levelBaseXp,
    value: 120,
    min: 50,
    max: 1000,
    unitEs: 'XP',
    group: AssumptionGroup.gamificacion,
    titleEs: 'XP del nivel 2',
    explainEs:
        'Pasar al nivel 2 cuesta 120 XP; cada nivel cuesta más que el anterior.',
    source: _model,
  ),
  AssumptionDef(
    key: A.levelExponent,
    value: 2.1,
    min: 1.2,
    max: 3,
    group: AssumptionGroup.gamificacion,
    titleEs: 'Dureza de la curva de niveles',
    explainEs:
        'El XP acumulado para el nivel n es 120 × (n − 1)^2,1: el nivel 10 pide unos 12 000 XP, meses de constancia real.',
    source: _model,
  ),
  AssumptionDef(
    key: A.pipchamoStreakDays,
    value: 7,
    min: 3,
    max: 30,
    unitEs: 'días',
    group: AssumptionGroup.gamificacion,
    titleEs: 'Pipchamo «en racha»',
    explainEs:
        'Con 7 días seguidos de mínimo cumplido, Pipchamo aparece en racha. '
        'Refleja tus datos, no es un premio.',
    source: _model,
  ),
  AssumptionDef(
    key: A.mindEloK,
    value: 24,
    min: 8,
    max: 64,
    group: AssumptionGroup.mente,
    titleEs: 'Velocidad de ajuste de tu nivel',
    explainEs:
        'Tras cada reto tu puntuación de esa habilidad sube o baja hasta 24 puntos, según lo difícil que era.',
    source: 'Elo 1978, sistema de puntuación',
  ),
  AssumptionDef(
    key: A.mindStartRating,
    value: 1000,
    min: 600,
    max: 1600,
    group: AssumptionGroup.mente,
    titleEs: 'Puntuación inicial',
    explainEs: 'Cada habilidad empieza en 1000 y se ajusta con tus respuestas.',
    source: _model,
  ),
  AssumptionDef(
    key: A.mindTargetSuccess,
    value: 0.65,
    min: 0.4,
    max: 0.9,
    group: AssumptionGroup.mente,
    titleEs: 'Dificultad buscada',
    explainEs:
        'Los retos se eligen para que aciertes cerca del 65 %: ni fáciles ni imposibles.',
    source: _model,
  ),
  AssumptionDef(
    key: A.mindRetryDays,
    value: 3,
    min: 1,
    max: 30,
    unitEs: 'días',
    group: AssumptionGroup.mente,
    titleEs: 'Repetir lo fallado',
    explainEs: 'Un reto fallado vuelve a aparecer a los 3 días.',
    source: 'Repetición espaciada (Cepeda et al. 2006)',
  ),
  AssumptionDef(
    key: A.quantCostBps,
    value: 10,
    min: 0,
    max: 200,
    unitEs: 'pb',
    group: AssumptionGroup.cuant,
    titleEs: 'Costo por operación',
    explainEs:
        'Cada cambio de posición paga 10 puntos básicos (0,10 %) entre comisión y deslizamiento. Sin costos casi todo parece rentable.',
    source: _model,
  ),
  AssumptionDef(
    key: A.quantDsrThreshold,
    value: 0.95,
    min: 0.5,
    max: 0.999,
    group: AssumptionGroup.cuant,
    titleEs: 'Umbral del Sharpe deflactado',
    explainEs:
        'Una estrategia solo se considera prometedora si la probabilidad de que su Sharpe real sea positivo, corrigiendo por todo lo que probaste, supera 0,95.',
    source: 'Bailey y López de Prado 2014, J Portfolio Management 40(5)',
  ),
  AssumptionDef(
    key: A.quantTrainBars,
    value: 504,
    min: 100,
    max: 2520,
    unitEs: 'barras',
    group: AssumptionGroup.cuant,
    titleEs: 'Ventana de entrenamiento',
    explainEs:
        'En la validación caminante se elige el parámetro con 504 barras (unos 2 años diarios) y se prueba en las siguientes.',
    source: _model,
  ),
  AssumptionDef(
    key: A.quantTestBars,
    value: 126,
    min: 20,
    max: 1260,
    unitEs: 'barras',
    group: AssumptionGroup.cuant,
    titleEs: 'Ventana de prueba',
    explainEs:
        'Cada tramo fuera de muestra dura 126 barras (unos 6 meses diarios).',
    source: _model,
  ),
  AssumptionDef(
    key: A.quantBootstrapBlock,
    value: 20,
    min: 5,
    max: 120,
    unitEs: 'barras',
    group: AssumptionGroup.cuant,
    titleEs: 'Bloque del bootstrap',
    explainEs:
        'El intervalo del Sharpe remuestrea bloques de 20 barras para respetar la autocorrelación.',
    source: 'Politis y Romano 1994',
  ),
  AssumptionDef(
    key: A.quantBootstrapSamples,
    value: 500,
    min: 100,
    max: 5000,
    group: AssumptionGroup.cuant,
    titleEs: 'Remuestreos del bootstrap',
    explainEs: 'Número de remuestreos para el intervalo de confianza.',
    source: _model,
  ),
  AssumptionDef(
    key: A.quantBarsPerYear,
    value: 252,
    min: 12,
    max: 8760,
    unitEs: 'barras',
    group: AssumptionGroup.cuant,
    titleEs: 'Barras por año',
    explainEs:
        'Para anualizar: 252 sesiones bursátiles al año en datos diarios (365 para cripto).',
    source: _model,
  ),
  // ---------------------------------------------------------- TOX-CHECK
  AssumptionDef(
    key: A.fluorideToothpasteMaxPpm,
    value: 1500,
    min: 1000,
    max: 1500,
    unitEs: 'ppm',
    group: AssumptionGroup.toxcheck,
    titleEs: 'Flúor máximo en pasta dental',
    explainEs:
        'Hasta 1500 ppm de flúor la pasta dental es VERDE para adultos, con '
        'una nota para menores de 6 años. Por encima pasa a ÁMBAR: supera el '
        'límite de los cosméticos en la UE y se usa solo por indicación '
        'del odontólogo.',
    source:
        'Reglamento (CE) 1223/2009, anexo III (0,15 % F); SCCP, opinión '
        'sobre compuestos de flúor en higiene oral infantil',
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
