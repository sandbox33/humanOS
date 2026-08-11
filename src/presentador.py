"""
HumanOS — Presentador.

ÚNICA capa que toca `database` + los motores. Traduce eso a los DatosX
que cada vista consume — las vistas nunca hablan con la base de datos ni
con los motores directamente. Si lo hicieran, la lógica de negocio
viviría repartida en seis sitios en vez de uno.

ESTADO: 5 de 6 funciones completas — datos_hoy, datos_inventario,
datos_habitos, datos_sueno y datos_perfil. `datos_comidas()` sigue
pendiente: su vista (views/comidas.py) ya existe, pero conectarla bien
implica reconstruir el mismo pipeline de armar_combinacion() +
analizar_comida() que datos_hoy() decidió NO usar, y filtrar
catalogo_extras para que no repita lo que ya está en ingredientes/extras.
Queda para el próximo paso, con más espacio dedicado.

LÍMITE COMPARTIDO CON datos_hoy: datos_sueno() e datos_habitos() también
asumen que se llaman para HOY — mismo motivo que la nota de abajo sobre
_estado_comida().

LÍMITE CONOCIDO: habits_engine.py calcula las tres rachas siempre contra
dt.date.today() (no recibe una fecha de referencia), y _estado_comida()
de aquí abajo compara contra dt.datetime.now(). Ambas cosas son
correctas mientras datos_hoy() se llame con fecha == hoy, que es el
único caso de uso actual. Si más adelante se agrega una vista para ver
un día pasado, esto hay que revisarlo primero — no es un bug hoy, pero
sería uno silencioso ese día.
"""

import datetime as dt

import config
import database as db
import nutrition_engine as ne
import sleep_engine as se         # usado en datos_sueno (paso 5)
import schedule_engine as sc
import habits_engine as he
import shopping_engine as sh
from views.hoy import DatosHoy, FilaComida, FilaCoccion, FilaHabito
import views.comidas as vc
import views.inventario as vi
import views.habitos as vh
import views.sueno as vs
import views.perfil as vp


# ---------------------------------------------------------------------------
# Helpers — horario y estado de cada comida
# ---------------------------------------------------------------------------

def _tiempo(hora, minuto) -> dt.time | None:
    """Jornada guarda hora/minuto como IntegerField nullable. None = sin dato."""
    return dt.time(hora, minuto) if hora is not None else None


def _estado_comida(registro, hora_objetivo: dt.time, ahora: dt.datetime) -> str:
    """
    'ok'        ya confirmada.
    'limite'    ya se marcó omitida, o pasó la ventana de gracia sin confirmar.
    'aviso'     dentro de la ventana de gracia (config.VENTANA_GRACIA_MIN).
    'pendiente' aún no llega la hora objetivo.

    No escribe en la base de datos — marcar `omitida=True` de forma
    persistente es trabajo de alarm_engine.py (paso 6). Aquí solo se lee
    el reloj cada vez que se pide datos_hoy().
    """
    if registro and registro.confirmada_en:
        return "ok"
    if registro and registro.omitida:
        return "limite"

    objetivo_dt = dt.datetime.combine(ahora.date(), hora_objetivo)
    limite_dt = objetivo_dt + dt.timedelta(minutes=config.VENTANA_GRACIA_MIN)

    if ahora < objetivo_dt:
        return "pendiente"
    return "aviso" if ahora <= limite_dt else "limite"


def _filas_comida(comidas_base: list, metas_por_orden: dict,
                  horas_por_orden: dict, registros: dict) -> list:
    ahora = dt.datetime.now()
    filas = []
    for c in comidas_base:
        registro = registros.get(c.id)   # ojo: indexado por comida_id, no por orden
        hora_ajustada = horas_por_orden.get(c.orden, dt.time(c.hora, c.minuto))
        estado = _estado_comida(registro, hora_ajustada, ahora)
        meta = metas_por_orden.get(c.orden)

        detalle = ""
        if estado == "ok" and registro:
            totales = registro.totales()
            detalle = f"{totales['kcal']:.0f} kcal · {totales['proteina_g']:.0f} g"
        elif estado == "limite":
            detalle = "omitida"

        filas.append(FilaComida(
            orden=c.orden, nombre=c.nombre, hora=hora_ajustada.strftime("%H:%M"),
            meta_kcal=meta.kcal if meta else 0.0,
            meta_prot=meta.proteina_g if meta else 0.0,
            estado=estado, detalle=detalle,
        ))
    return filas


# ---------------------------------------------------------------------------
# Helpers — cocciones
# ---------------------------------------------------------------------------

def _filas_coccion() -> list:
    filas = []
    for c in db.cocciones_abiertas():
        est = sc.evaluar_coccion(c.alimento.nombre, c.cocinado_en)
        filas.append(FilaCoccion(nombre=est.nombre, horas=est.horas,
                                 nivel=est.nivel, mensaje=est.mensaje))
    return filas


# ---------------------------------------------------------------------------
# Helpers — hábitos
# ---------------------------------------------------------------------------

# Ventana amplia a propósito: una racha real puede durar más de 30 días
# (el default de db.historial_habito) y truncarla la haría ver más corta
# de lo que es.
DIAS_HISTORIAL_HABITOS = 120


def _def_habito(h) -> he.DefHabito:
    # h.tipo ('mantener'/'moderar') es una etiqueta semántica del modelo
    # Habito, sin equivalente en DefHabito — no confundir con
    # tipo_objetivo ('binario'/'aumentar'/'reducir'), que sí viaja aquí.
    return he.DefHabito(nombre=h.nombre, tipo_objetivo=h.tipo_objetivo,
                        valor_objetivo=h.valor_objetivo, umbral=h.umbral,
                        peso=h.peso, esencial=h.esencial)


def _valores_por_dia_habitos(habitos_db: list) -> dict:
    """{fecha: {nombre_habito: valor}} — lo que habits_engine.resumen() espera."""
    valores = {}
    for h in habitos_db:
        for log in db.historial_habito(h, dias=DIAS_HISTORIAL_HABITOS):
            valores.setdefault(log.fecha, {})[h.nombre] = log.valor
    return valores


def _filas_habito(habitos_db: list, valores_hoy: dict,
                  resumen: "he.ResumenHabitos") -> list:
    filas = []
    for h in habitos_db:
        valor = valores_hoy.get(h.nombre)
        sin_dato = valor is None
        cumplido = not sin_dato and he.evaluar(_def_habito(h), valor).completado
        filas.append(FilaHabito(
            nombre=h.nombre, icono=h.icono, cumplido=cumplido, sin_dato=sin_dato,
            racha=resumen.rachas_individuales.get(h.nombre, 0),
        ))
    return filas


# ---------------------------------------------------------------------------
# Helpers — notas clínicas y supuestos mostrados
# ---------------------------------------------------------------------------

def _alimentos_consumidos_hoy(registros: dict) -> set:
    nombres = set()
    for r in registros.values():
        if r.confirmada_en:
            nombres.update(item.alimento.nombre for item in r.consumo)
    return nombres


def _notas_clinicas(nombres_consumidos: set) -> list:
    """
    Solo 'jamaica_uso', y solo si ya se registró jamaica hoy (seca o
    infusión) — no tiene sentido advertir sobre algo que no has tocado
    todavía. 'liquidos_con_comida' es contextual a confirmar una comida
    puntual, no al resumen del día (así lo dice el comentario en
    config.py): vive en views/comidas.py (paso 2), no aquí.
    """
    if not ({"jamaica_seca", "jamaica_infusion"} & nombres_consumidos):
        return []
    rec = next((r for r in config.RECORDATORIOS_GENERALES
               if r["id"] == "jamaica_uso"), None)
    return [rec["mensaje"]] if rec else []


def _supuestos_relevantes(claves: list) -> list:
    """Solo los supuestos que de verdad se usaron en el cálculo de hoy."""
    salida = []
    for clave in claves:
        entrada = config.SUPUESTOS.get(clave)
        if entrada:
            salida.append((entrada["titulo"], entrada["explica"]))
    return salida


# ---------------------------------------------------------------------------
# datos_hoy — completa
# ---------------------------------------------------------------------------

def datos_hoy(usuario: db.Usuario, fecha: dt.date = None) -> DatosHoy:
    fecha = fecha or dt.date.today()
    supuestos_usados = []

    # 1. Jornada del día
    jornada = db.jornada_de(fecha)
    hora_entrada = _tiempo(jornada.hora_entrada, jornada.minuto_entrada)
    hora_salida = _tiempo(jornada.hora_salida, jornada.minuto_salida)
    hora_almuerzo = _tiempo(jornada.hora_almuerzo, jornada.minuto_almuerzo)

    # 2-3. Objetivo diario, y ajuste proporcional según la jornada real.
    # El ajuste se aplica también a las metas por comida más abajo — una
    # sola cifra de objetivo_kcal, no dos que puedan desacoplarse.
    objetivo = ne.objetivo_diario(
        peso_kg=usuario.peso_kg, estatura_cm=usuario.estatura_cm, edad=usuario.edad,
        nivel_actividad=usuario.nivel_actividad, superavit_pct=usuario.superavit_pct,
        proteina_g_por_kg=usuario.proteina_g_por_kg,
    )
    prop = sc.objetivo_proporcional(objetivo.objetivo_kcal, hora_entrada, hora_salida,
                                    dia_libre=jornada.dia_libre)
    # round(): en el estado 'sin_datos', objetivo_proporcional() devuelve
    # objetivo_kcal_completo sin redondear (a diferencia de 'jornada' y
    # 'dia_libre', que sí hacen round(ajustado)) — inconsistencia real en
    # schedule_engine.py que no toco porque está protegido por contratos;
    # se blinda aquí para que DatosHoy.objetivo_kcal sea siempre int.
    objetivo.objetivo_kcal = round(prop["objetivo_kcal"])
    if prop["supuesto"]:
        supuestos_usados.append(prop["supuesto"])

    # 4. Horario de comidas ajustado a la jornada real
    comidas_base = db.comidas_ordenadas()
    horario = sc.horario_del_dia(comidas_base, hora_entrada, hora_salida,
                                 hora_almuerzo, jornada.dia_libre)
    horas_por_orden = {orden: hora for orden, _nombre, hora in horario.comidas}

    # 5. Metas por comida, ya sobre el objetivo ajustado
    metas = ne.repartir(objetivo, comidas_base)
    metas_por_orden = {m.orden: m for m in metas}
    explicacion_prot = objetivo.explicacion_proteina(usuario.peso_kg)
    if explicacion_prot:
        supuestos_usados.append("tolerancia_proteina")

    # 6. Comidas del día: registros reales + estado + detalle
    registros = db.registros_del_dia(fecha)
    filas_comida = _filas_comida(comidas_base, metas_por_orden, horas_por_orden, registros)
    proxima = next((f"{f.nombre} · {f.hora}" for f in filas_comida
                    if f.estado in ("pendiente", "aviso")), "")

    # 7. Cocciones abiertas — seguridad alimentaria sin nevera
    filas_coccion = _filas_coccion()

    # 8. Hábitos y las tres rachas
    habitos_db = db.habitos_activos()
    defs_habito = [_def_habito(h) for h in habitos_db]
    valores_por_dia = _valores_por_dia_habitos(habitos_db)
    resumen_h = he.resumen(defs_habito, valores_por_dia)
    filas_habito = _filas_habito(habitos_db, valores_por_dia.get(fecha, {}), resumen_h)

    # 9. Notas clínicas — solo si ya aplica hoy
    notas_clinicas = _notas_clinicas(_alimentos_consumidos_hoy(registros))

    # 10. Progreso real del día
    totales = db.totales_del_dia(fecha)

    return DatosHoy(
        fecha=fecha,
        estado_dia=prop["estado"], confianza_dia=prop["confianza"], nota_dia=prop["nota"],
        horas_jornada=prop["horas"],
        objetivo_kcal=objetivo.objetivo_kcal, kcal_hoy=totales["kcal"],
        objetivo_prot=round(objetivo.proteina_g), prot_hoy=totales["proteina_g"],
        explicacion_proteina=explicacion_prot,
        comidas=filas_comida, cocciones=filas_coccion, habitos=filas_habito,
        racha_minima=resumen_h.racha_minima_dias, racha_global=resumen_h.racha_global_dias,
        puntaje_pct=resumen_h.puntaje_hoy.pct,
        sugerir_mision_minima=resumen_h.sugerir_mision_minima,
        sinergias=[], advertencias=[],   # sin combinación automática aquí — ver docstring del módulo
        notas_clinicas=notas_clinicas,
        supuestos=_supuestos_relevantes(supuestos_usados),
        proxima_comida=proxima,
    )


# ---------------------------------------------------------------------------
# Pendientes — firma estable, se completan junto a su vista (pasos 2-5)
# ---------------------------------------------------------------------------

def datos_comidas(usuario: db.Usuario, fecha: dt.date, orden_comida: int,
                  ediciones: dict = None, extras_agregados: dict = None) -> vc.DatosComidas:
    """
    ediciones: {nombre: gramos} — pisa los gramos que sugiere armar_combinacion()
    para lo que el usuario ya movió con el stepper.
    extras_agregados: {nombre: gramos} — extras que el usuario ya declaró
    (café, jamaica, cualquier cosa con inventario) antes de confirmar.

    Ninguno de los dos se guarda en la base: son borrador. Quien orquesta la
    pantalla (main.py) los mantiene en memoria entre toques y los reenvía
    aquí en cada llamada — así funciona el 'en vivo' que se decidió para
    views/comidas.py. Al confirmar, ingredientes + extras van directo a
    database.confirmar_consumo().
    """
    ediciones = ediciones or {}
    extras_agregados = extras_agregados or {}
    fecha = fecha or dt.date.today()

    jornada = db.jornada_de(fecha)
    hora_entrada = _tiempo(jornada.hora_entrada, jornada.minuto_entrada)
    hora_salida = _tiempo(jornada.hora_salida, jornada.minuto_salida)
    hora_almuerzo = _tiempo(jornada.hora_almuerzo, jornada.minuto_almuerzo)

    comidas_base = db.comidas_ordenadas()
    comida = next((c for c in comidas_base if c.orden == orden_comida), None)
    if comida is None:
        raise ValueError(f"No existe una comida activa con orden={orden_comida}")

    horario = sc.horario_del_dia(comidas_base, hora_entrada, hora_salida, hora_almuerzo,
                                 jornada.dia_libre)
    horas_por_orden = {o: h for o, _n, h in horario.comidas}
    hora_ajustada = horas_por_orden.get(orden_comida, dt.time(comida.hora, comida.minuto))

    objetivo = ne.objetivo_diario(
        peso_kg=usuario.peso_kg, estatura_cm=usuario.estatura_cm, edad=usuario.edad,
        nivel_actividad=usuario.nivel_actividad, superavit_pct=usuario.superavit_pct,
        proteina_g_por_kg=usuario.proteina_g_por_kg,
    )
    prop = sc.objetivo_proporcional(objetivo.objetivo_kcal, hora_entrada, hora_salida,
                                    dia_libre=jornada.dia_libre)
    objetivo.objetivo_kcal = round(prop["objetivo_kcal"])
    metas_por_orden = {m.orden: m for m in ne.repartir(objetivo, comidas_base)}
    meta = metas_por_orden.get(orden_comida)

    registros = db.registros_del_dia(fecha)
    registro = registros.get(comida.id)
    ahora = dt.datetime.now()
    estado = _estado_comida(registro, hora_ajustada, ahora)
    ya_confirmada = estado == "ok"

    otras = [
        vc.ResumenComida(
            orden=c.orden, nombre=c.nombre,
            hora=horas_por_orden.get(c.orden, dt.time(c.hora, c.minuto)).strftime("%H:%M"),
            estado=_estado_comida(registros.get(c.id),
                                  horas_por_orden.get(c.orden, dt.time(c.hora, c.minuto)), ahora),
        )
        for c in comidas_base if c.orden != orden_comida
    ]

    # --- Comida ya confirmada: solo lectura, con lo que de verdad se comió ---
    if ya_confirmada:
        ingredientes = []
        for item in registro.consumo:
            nut = item.alimento.nutrientes(item.gramos)
            ingredientes.append(vc.FilaIngrediente(nombre=item.alimento.nombre, gramos=item.gramos,
                                                    kcal=nut["kcal"], proteina_g=nut["proteina_g"]))
        totales = registro.totales()
        return vc.DatosComidas(
            fecha=fecha, orden=orden_comida, nombre=comida.nombre,
            hora=hora_ajustada.strftime("%H:%M"), estado=estado, ya_confirmada=True,
            meta_kcal=meta.kcal if meta else 0.0, meta_prot=meta.proteina_g if meta else 0.0,
            kcal_total=totales["kcal"], prot_total=totales["proteina_g"],
            ingredientes=ingredientes, otras_comidas=otras,
        )

    # --- Sin confirmar: sugerencia del motor + lo que ya se ajustó en el borrador ---
    catalogo = db.catalogo_alimentos()
    alimento_por_nombre = {a.nombre: a for a in catalogo}
    inv = db.inventario_dict()

    disponibles = [
        ne.ItemInventario(a.nombre, a.kcal_100g, a.proteina_100g, frozenset(a.etiquetas),
                          inv.get(a.nombre, 0.0), a.categoria)
        for a in catalogo if inv.get(a.nombre, 0.0) > 0
    ]
    resultado = ne.armar_combinacion(meta, disponibles, extras=extras_agregados or None)

    def _fila(nombre, gramos, es_extra):
        a = alimento_por_nombre.get(nombre)
        if not a:
            return None
        nut = a.nutrientes(gramos)
        return vc.FilaIngrediente(nombre=nombre, gramos=gramos, kcal=nut["kcal"],
                                  proteina_g=nut["proteina_g"],
                                  gramos_disponibles=inv.get(nombre, 0.0), es_extra=es_extra)

    # armar_combinacion() ya mezcla los extras dentro de resultado.porciones
    # (así entran en la revisión de interacciones) — se saltan acá para no
    # duplicarlos, y se arman aparte con su propio flag es_extra=True.
    ingredientes = []
    for nombre, gramos_sugeridos in resultado.porciones.items():
        if nombre in extras_agregados:
            continue
        fila = _fila(nombre, ediciones.get(nombre, gramos_sugeridos), False)
        if fila:
            ingredientes.append(fila)

    extras_filas = []
    for nombre, gramos_sugeridos in extras_agregados.items():
        fila = _fila(nombre, ediciones.get(nombre, gramos_sugeridos), True)
        if fila:
            extras_filas.append(fila)

    todo = ingredientes + extras_filas
    usados = {f.nombre for f in todo}
    catalogo_extras = [
        vc.ExtraDisponible(nombre=a.nombre, categoria=a.categoria, gramos_sugeridos=100.0)
        for a in catalogo if inv.get(a.nombre, 0.0) > 0 and a.nombre not in usados
    ]

    items_nutridos = [
        ne.ItemNutrido(f.nombre, f.gramos, alimento_por_nombre[f.nombre].nutrientes(f.gramos),
                       alimento_por_nombre[f.nombre].hierro_es_hemo,
                       alimento_por_nombre[f.nombre].inhibe_hierro_no_hemo,
                       frozenset(alimento_por_nombre[f.nombre].etiquetas))
        for f in todo
    ]
    analisis = ne.analizar_comida(items_nutridos) if items_nutridos else None

    sinergias = [(s.mensaje, s.magnitud) for s in analisis.sinergias] if analisis else []
    advertencias = [(a.mensaje, a.severidad) for a in resultado.advertencias_interaccion]
    if analisis:
        advertencias += [(a.mensaje, a.severidad) for a in analisis.inhibiciones]

    notas_clinicas = _notas_clinicas(_alimentos_consumidos_hoy(registros) | usados)

    return vc.DatosComidas(
        fecha=fecha, orden=orden_comida, nombre=comida.nombre,
        hora=hora_ajustada.strftime("%H:%M"), estado=estado, ya_confirmada=False,
        meta_kcal=meta.kcal if meta else 0.0, meta_prot=meta.proteina_g if meta else 0.0,
        kcal_total=sum(f.kcal for f in todo), prot_total=sum(f.proteina_g for f in todo),
        ingredientes=ingredientes, extras=extras_filas, catalogo_extras=catalogo_extras,
        faltantes=list(resultado.faltantes), sinergias=sinergias, advertencias=advertencias,
        notas_clinicas=notas_clinicas, otras_comidas=otras,
    )


def datos_inventario() -> vi.DatosInventario:
    alimentos_db = db.catalogo_alimentos()
    inv = db.inventario_dict()   # ojo: solo trae gramos > 0 — .get(nombre, 0.0) cubre el resto

    filas_alimento = [
        vi.FilaAlimento(nombre=a.nombre, categoria=a.categoria,
                        gramos_disponibles=inv.get(a.nombre, 0.0),
                        kcal_100g=a.kcal_100g, proteina_100g=a.proteina_100g,
                        unidad_compra=a.unidad_compra, confianza=a.confianza)
        for a in alimentos_db
    ]

    # Historial de compras -> hábitos de compra (sh.resumen_compras espera dicts planos)
    compras_dicts = [{"nombre": c.alimento.nombre, "fecha": c.fecha,
                      "gramos": c.gramos, "precio": c.precio}
                     for c in db.historial_compras(dias=90)]
    resumen_compras = sh.resumen_compras(compras_dicts, dias=90)

    items_compra = []
    for a in alimentos_db:
        r = resumen_compras.get(a.nombre, {})
        items_compra.append(sh.ItemCompra(
            nombre=a.nombre, categoria=a.categoria, unidad_compra=a.unidad_compra,
            kcal_100g=a.kcal_100g, proteina_100g=a.proteina_100g,
            gramos_disponibles=inv.get(a.nombre, 0.0),
            precio_por_100g=r.get("precio_por_100g"), compras_en_ventana=r.get("veces", 0),
            ultima_compra=r.get("ultima"), gramos_por_unidad=a.gramos_por_unidad,
        ))

    # Brecha del día: cuánto falta hoy vs el objetivo — sh.construir_lista() la usa
    # para la sección 'faltante'. consumo_diario_g queda vacío por ahora: no hay
    # todavía una función en database.py que calcule gramos/día por alimento desde
    # el historial de ConsumoItem — sin eso, 'agotado por días de reserva' no
    # dispara, pero 'se acabó' (stock en 0) sí, porque no depende de esa cifra.
    usuario = db.get_usuario()
    objetivo = ne.objetivo_diario(
        peso_kg=usuario.peso_kg, estatura_cm=usuario.estatura_cm, edad=usuario.edad,
        nivel_actividad=usuario.nivel_actividad, superavit_pct=usuario.superavit_pct,
        proteina_g_por_kg=usuario.proteina_g_por_kg,
    )
    totales_hoy = db.totales_del_dia()
    brecha_prot = max(0.0, objetivo.proteina_g - totales_hoy["proteina_g"])
    brecha_kcal = max(0.0, objetivo.objetivo_kcal - totales_hoy["kcal"])

    lista = sh.construir_lista(items_compra, consumo_diario_g={},
                               brecha_proteina_g=brecha_prot, brecha_kcal=brecha_kcal)

    lista_por_categoria = {}
    for linea in lista.lineas:
        lista_por_categoria.setdefault(linea.categoria, []).append(vi.FilaListaCompra(
            nombre=linea.nombre, categoria=linea.categoria, prioridad=linea.prioridad,
            motivo=linea.motivo, cantidad_texto=linea.cantidad_texto,
            precio_estimado=linea.precio_estimado,
        ))

    return vi.DatosInventario(alimentos=filas_alimento, lista_por_categoria=lista_por_categoria,
                              total_estimado=lista.total_estimado, nota_lista=lista.nota)


def datos_habitos(usuario: db.Usuario, fecha: dt.date = None) -> vh.DatosHabitos:
    fecha = fecha or dt.date.today()

    habitos_db = db.habitos_activos()
    defs_habito = [_def_habito(h) for h in habitos_db]
    valores_por_dia = _valores_por_dia_habitos(habitos_db)
    resumen_h = he.resumen(defs_habito, valores_por_dia)
    valores_hoy = valores_por_dia.get(fecha, {})

    filas = []
    for h in habitos_db:
        d_h = _def_habito(h)
        valor_hoy = valores_hoy.get(h.nombre)
        completado_hoy = valor_hoy is not None and he.evaluar(d_h, valor_hoy).completado

        historial = []
        for i in range(6, -1, -1):
            f = fecha - dt.timedelta(days=i)
            v = valores_por_dia.get(f, {}).get(h.nombre)
            completado = v is not None and he.evaluar(d_h, v).completado
            historial.append(vh.FilaHistorial(fecha=f, valor=v, completado=completado))

        filas.append(vh.FilaHabitoDetalle(
            nombre=h.nombre, tipo=h.tipo, metrica=h.metrica, tipo_objetivo=h.tipo_objetivo,
            valor_objetivo=h.valor_objetivo, esencial=h.esencial, icono=h.icono,
            valor_hoy=valor_hoy, completado_hoy=completado_hoy,
            racha=resumen_h.rachas_individuales.get(h.nombre, 0), historial_7d=historial,
        ))

    return vh.DatosHabitos(
        fecha=fecha, habitos=filas,
        racha_global=resumen_h.racha_global_dias, racha_minima=resumen_h.racha_minima_dias,
        puntaje_pct=resumen_h.puntaje_hoy.pct, sugerir_mision_minima=resumen_h.sugerir_mision_minima,
    )


def datos_sueno(usuario: db.Usuario, fecha: dt.date = None) -> vs.DatosSueno:
    fecha = fecha or dt.date.today()

    log_abierto = (db.SueñoLog.select()
                  .where(db.SueñoLog.hora_dormir_real.is_null(False),
                         db.SueñoLog.hora_despertar_real.is_null(True))
                  .order_by(db.SueñoLog.hora_dormir_real.desc())
                  .first())
    durmiendo_ahora = log_abierto is not None
    hora_dormir_registrada = (log_abierto.hora_dormir_real.strftime("%H:%M")
                              if log_abierto else "")

    ultima_cerrada = (db.SueñoLog.select()
                      .where(db.SueñoLog.hora_despertar_real.is_null(False))
                      .order_by(db.SueñoLog.fecha.desc())
                      .first())
    horas_ultima_noche = ultima_cerrada.horas_dormidas if ultima_cerrada else None

    # Ventana ideal: no hay una 'hora de despertar planeada' registrada en
    # ningún lado todavía, así que se usa la hora de despertar por defecto de
    # config — es una referencia, no una medición, por eso no lleva ≈ aquí
    # (ventanas_sueño() ya lo deja claro en su propia nota).
    hora_desp = dt.time(*config.HORA_DESPERTAR)
    ventana = se.ventanas_sueño(hora_desp)
    ventana_ideal = (f"{ventana['rango_inicio'].strftime('%H:%M')}"
                     f" – {ventana['rango_fin'].strftime('%H:%M')}"
                     f" (ideal {ventana['ideal'].strftime('%H:%M')})")

    noches_db = db.historial_sueño(dias=7)
    registros = [se.RegistroNoche(fecha=n.fecha, horas_dormidas=n.horas_dormidas)
                for n in noches_db]
    deuda = se.deuda_de_sueño(registros, dias=7)
    racha = se.racha_actual(registros)

    por_fecha = {n.fecha: n.horas_dormidas for n in noches_db}
    historial_7d = []
    for i in range(6, -1, -1):
        f = fecha - dt.timedelta(days=i)
        horas = por_fecha.get(f)
        dentro = horas is not None and se.RANGO_BUENO_H[0] <= horas <= se.RANGO_BUENO_H[1]
        historial_7d.append(vs.FilaNoche(fecha=f, horas=horas, dentro_rango=dentro))

    return vs.DatosSueno(
        fecha=fecha, durmiendo_ahora=durmiendo_ahora,
        hora_dormir_registrada=hora_dormir_registrada, horas_ultima_noche=horas_ultima_noche,
        ventana_ideal=ventana_ideal, nota_ventana=ventana["nota"],
        deuda_h=deuda.deuda_h, noches_con_dato=deuda.noches_con_dato,
        noches_sin_dato=deuda.noches_sin_dato, promedio_h=deuda.promedio_real_h,
        racha=racha, historial_7d=historial_7d,
    )


def datos_perfil(usuario: db.Usuario) -> vp.DatosPerfil:
    objetivo = ne.objetivo_diario(
        peso_kg=usuario.peso_kg, estatura_cm=usuario.estatura_cm, edad=usuario.edad,
        nivel_actividad=usuario.nivel_actividad, superavit_pct=usuario.superavit_pct,
        proteina_g_por_kg=usuario.proteina_g_por_kg,
    )

    jornada = db.jornada_de(dt.date.today())
    entrada_str = (f"{jornada.hora_entrada:02d}:{jornada.minuto_entrada:02d}"
                  if jornada.hora_entrada is not None else "")
    salida_str = (f"{jornada.hora_salida:02d}:{jornada.minuto_salida:02d}"
                 if jornada.hora_salida is not None else "")
    almuerzo_str = (f"{jornada.hora_almuerzo:02d}:{jornada.minuto_almuerzo:02d}"
                    if jornada.hora_almuerzo is not None else "")

    supuestos = [vp.FilaSupuesto(clave=clave, titulo=info["titulo"], explica=info["explica"],
                                 valor=info["valor"])
                for clave, info in config.SUPUESTOS.items()]

    suplementos = [vp.FilaSuplemento(nombre=s.nombre, hora=s.hora_str, notas=s.notas)
                  for s in db.suplementos_pendientes_hoy()]

    return vp.DatosPerfil(
        peso_kg=usuario.peso_kg, estatura_cm=usuario.estatura_cm, edad=usuario.edad,
        nivel_actividad=usuario.nivel_actividad, superavit_pct=usuario.superavit_pct,
        proteina_g_por_kg=usuario.proteina_g_por_kg,
        objetivo_kcal_actual=round(objetivo.objetivo_kcal),
        objetivo_prot_actual=round(objetivo.proteina_g),
        jornada_hoy_entrada=entrada_str, jornada_hoy_salida=salida_str,
        jornada_hoy_almuerzo=almuerzo_str, jornada_hoy_dia_libre=jornada.dia_libre,
        supuestos=supuestos, suplementos_pendientes=suplementos,
    )
