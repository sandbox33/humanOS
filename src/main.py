"""
HumanOS — Fase 1: Nutrición + Alarmas.

Escrito contra la API de Flet 0.28.x (Flet v0), fijada en requirements.txt.
Flet 0.80+ es una reescritura con cambios incompatibles (text -> label,
ImageFit -> BoxFit, entre otros). Migrar es un trabajo aparte, no un upgrade.
"""

import asyncio
import datetime as dt

import flet as ft

import config
import database as dbm
import nutrition_engine as ne
import alarm_engine as ae


# ---------------------------------------------------------------------------

VERDE = "#2E7D32"
AMBAR = "#F9A825"
ROJO = "#C62828"
GRIS = "#616161"


def color_severidad(sev: str) -> str:
    return {"alta": ROJO, "media": AMBAR}.get(sev, GRIS)


class HumanOS:
    def __init__(self, page: ft.Page):
        self.page = page
        self.usuario = dbm.init_db()
        self.backend = ae.crear_backend(page)
        self.indice = 0
        self._dialogo_abierto = False

        self._config_pagina()
        self._construir()
        self._sincronizar_alarmas()

        self.page.run_task(self._vigilante)

    # -- configuración -----------------------------------------------------

    def _config_pagina(self):
        p = self.page
        p.title = config.APP_NAME
        p.theme_mode = ft.ThemeMode.DARK
        p.padding = 0
        p.theme = ft.Theme(color_scheme_seed=VERDE)
        p.on_resized = lambda e: p.update()

    def _sincronizar_alarmas(self):
        if self.backend.disponible:
            self.backend.solicitar_permisos()
            ae.reprogramar_todo(self.backend)

    # -- objetivos ---------------------------------------------------------

    def objetivo(self) -> ne.ObjetivoDiario:
        u = self.usuario
        return ne.objetivo_diario(
            peso_kg=u.peso_kg,
            estatura_cm=u.estatura_cm,
            edad=u.edad,
            nivel_actividad=u.nivel_actividad,
            superavit_pct=u.superavit_pct,
            proteina_g_por_kg=u.proteina_g_por_kg,
        )

    def metas(self) -> list:
        return ne.repartir(self.objetivo(), dbm.comidas_ordenadas())

    # -- estructura --------------------------------------------------------

    def _construir(self):
        self.cuerpo = ft.Container(expand=True, padding=16)
        self.page.add(
            ft.Container(
                content=ft.Column([self.cuerpo], expand=True,
                                  scroll=ft.ScrollMode.AUTO),
                expand=True,
            )
        )
        self.page.navigation_bar = ft.NavigationBar(
            selected_index=0,
            on_change=self._cambiar_vista,
            destinations=[
                ft.NavigationBarDestination(icon=ft.Icons.TODAY, label="Hoy"),
                ft.NavigationBarDestination(icon=ft.Icons.RESTAURANT, label="Comidas"),
                ft.NavigationBarDestination(icon=ft.Icons.BEDTIME, label="Sueño"),
                ft.NavigationBarDestination(icon=ft.Icons.PERSON, label="Perfil"),
            ],
        )
        self._render()

    def _cambiar_vista(self, e):
        self.indice = e.control.selected_index
        self._render()

    def _render(self):
        vistas = [self._vista_hoy, self._vista_comidas,
                  self._vista_sueño, self._vista_perfil]
        self.cuerpo.content = vistas[self.indice]()
        self.page.update()

    # -- vista: hoy --------------------------------------------------------

    def _vista_hoy(self) -> ft.Control:
        obj = self.objetivo()
        totales = dbm.totales_del_dia()
        metas = self.metas()
        registros = dbm.registros_del_dia()
        ahora = dt.datetime.now()

        pct_kcal = min(totales["kcal"] / obj.objetivo_kcal, 1.0) if obj.objetivo_kcal else 0
        pct_prot = min(totales["proteina_g"] / obj.proteina_g, 1.0) if obj.proteina_g else 0

        filas = []
        for comida, meta in zip(dbm.comidas_ordenadas(), metas):
            reg = registros.get(comida.id)
            programada = comida.hora_de(dt.date.today())

            if reg and reg.confirmada_en:
                icono, color, estado = ft.Icons.CHECK_CIRCLE, VERDE, f"{reg.kcal:.0f} kcal"
            elif reg and reg.omitida:
                icono, color, estado = ft.Icons.CANCEL, ROJO, "omitida"
            elif programada <= ahora:
                tarde = int((ahora - programada).total_seconds() // 60)
                icono, color, estado = ft.Icons.ERROR, AMBAR, f"{tarde} min tarde"
            else:
                icono, color, estado = ft.Icons.SCHEDULE, GRIS, "pendiente"

            filas.append(
                ft.ListTile(
                    leading=ft.Icon(icono, color=color),
                    title=ft.Text(f"{comida.hora_str}  {comida.nombre}", size=14),
                    subtitle=ft.Text(
                        f"meta {meta.kcal:.0f} kcal · {meta.proteina_g:.0f} g prot · {estado}",
                        size=11, color=GRIS,
                    ),
                    trailing=ft.IconButton(
                        ft.Icons.ADD_CIRCLE_OUTLINE,
                        tooltip="Registrar",
                        on_click=lambda e, c=comida, m=meta: self._abrir_registro(c, m),
                    ),
                    dense=True,
                )
            )

        aviso = []
        if not self.backend.disponible:
            aviso = [ft.Container(
                content=ft.Row([
                    ft.Icon(ft.Icons.INFO_OUTLINE, size=16, color=AMBAR),
                    ft.Text(
                        "Notificaciones nativas no disponibles en este build. "
                        "Los recordatorios funcionan con la app abierta.",
                        size=11, color=AMBAR, expand=True,
                    ),
                ]),
                padding=10, bgcolor="#332B00", border_radius=8,
            )]

        return ft.Column([
            ft.Text(dt.date.today().strftime("%A %d de %B").capitalize(),
                    size=20, weight=ft.FontWeight.BOLD),
            ft.Text(str(obj), size=12, color=GRIS),
            ft.Divider(height=20),

            ft.Text(f"Calorías  {totales['kcal']:.0f} / {obj.objetivo_kcal:.0f}", size=13),
            ft.ProgressBar(value=pct_kcal, height=8, color=VERDE),
            ft.Container(height=10),
            ft.Text(f"Proteína  {totales['proteina_g']:.0f} / {obj.proteina_g:.0f} g", size=13),
            ft.ProgressBar(value=pct_prot, height=8, color="#1565C0"),

            ft.Divider(height=24),
            ft.Text("Comidas de hoy", size=15, weight=ft.FontWeight.BOLD),
            *filas,
            ft.Container(height=12),
            *aviso,
        ], spacing=4)

    # -- vista: comidas ----------------------------------------------------

    def _vista_comidas(self) -> ft.Control:
        tarjetas = []
        for comida, meta in zip(dbm.comidas_ordenadas(), self.metas()):
            sugerencia = ne.sugerir_porciones(
                meta,
                fuente_proteica=self._proteica_para(comida.orden),
                base_calorica=self._base_para(comida.orden),
                grasa="mani" if comida.orden in (2, 4) else "aceite_oliva",
            )
            detalle = "  ·  ".join(
                f"{a.replace('_', ' ')} {g} g"
                for a, g in sugerencia["porciones"].items()
            )
            alarma = comida.alarma.first()

            tarjetas.append(ft.Card(content=ft.Container(
                content=ft.Column([
                    ft.Row([
                        ft.Text(f"{comida.hora_str}", size=16,
                                weight=ft.FontWeight.BOLD, color=VERDE),
                        ft.Text(comida.nombre, size=14, expand=True),
                        ft.Switch(
                            value=alarma.activa if alarma else False,
                            on_change=lambda e, c=comida: self._toggle_alarma(c, e.control.value),
                        ),
                    ]),
                    ft.Text(comida.contexto, size=11, color=GRIS),
                    ft.Container(height=6),
                    ft.Text(f"Objetivo: {meta.kcal:.0f} kcal · {meta.proteina_g:.0f} g proteína",
                            size=12),
                    ft.Text(f"Sugerencia: {detalle}", size=11, color=GRIS),
                    ft.Text(f"→ da {sugerencia['kcal']:.0f} kcal · "
                            f"{sugerencia['proteina_g']:.0f} g prot",
                            size=11, color=VERDE),
                ], spacing=2),
                padding=14,
            )))
        return ft.Column([
            ft.Text("Plan de comidas", size=20, weight=ft.FontWeight.BOLD),
            ft.Text("Porciones calculadas sobre tu peso y objetivo actual.",
                    size=11, color=GRIS),
            ft.Container(height=10),
            *tarjetas,
        ], spacing=8)

    def _proteica_para(self, orden: int) -> str:
        return {1: "huevo", 2: "yogurt_natural", 3: "pollo_pechuga",
                4: "atun_lata", 5: "carne_res_molida"}.get(orden, "huevo")

    def _base_para(self, orden: int) -> str:
        return {1: "avena_seca", 2: "pan_integral", 3: "arroz_cocido",
                4: "platano", 5: "papa_cocida"}.get(orden, "arroz_cocido")

    def _toggle_alarma(self, comida, valor: bool):
        alarma = comida.alarma.first()
        if alarma:
            alarma.activa = valor
            alarma.save()
        ae.reprogramar_todo(self.backend)

    # -- vista: sueño ------------------------------------------------------

    def _vista_sueño(self) -> ft.Control:
        h, m = config.HORA_DESPERTAR
        v = ne.ventanas_sueño(dt.time(h, m))
        return ft.Column([
            ft.Text("Sueño", size=20, weight=ft.FontWeight.BOLD),
            ft.Container(height=10),
            ft.Card(content=ft.Container(content=ft.Column([
                ft.Text(f"Despertar fijado: {h:02d}:{m:02d}", size=14),
                ft.Container(height=8),
                ft.Text("Acostarse", size=12, color=GRIS),
                ft.Text(f"{v['rango_inicio'].strftime('%H:%M')} – "
                        f"{v['rango_fin'].strftime('%H:%M')}",
                        size=26, weight=ft.FontWeight.BOLD, color=VERDE),
                ft.Text(f"punto medio {v['ideal'].strftime('%H:%M')}",
                        size=12, color=GRIS),
            ]), padding=16)),
            ft.Container(height=12),
            ft.Container(
                content=ft.Text(v["nota"], size=11, color=GRIS),
                padding=12, bgcolor="#1E1E1E", border_radius=8,
            ),
            ft.Container(height=8),
            ft.Container(
                content=ft.Text(
                    "Se muestra un rango a propósito. Los ciclos reales varían "
                    "entre 70 y 120 min, así que una hora exacta calculada sobre "
                    "ciclos de 90 min sería precisión falsa. Prioridad: duración "
                    "total (7–9 h) > regularidad del despertar > todo lo demás.",
                    size=11, color=GRIS,
                ),
                padding=12, bgcolor="#1E1E1E", border_radius=8,
            ),
        ], spacing=2)

    # -- vista: perfil -----------------------------------------------------

    def _vista_perfil(self) -> ft.Control:
        u = self.usuario
        self.f_peso = ft.TextField(label="Peso (kg)", value=str(u.peso_kg),
                                   keyboard_type=ft.KeyboardType.NUMBER, dense=True)
        self.f_altura = ft.TextField(label="Estatura (cm)", value=str(u.estatura_cm),
                                     keyboard_type=ft.KeyboardType.NUMBER, dense=True)
        self.f_edad = ft.TextField(label="Edad", value=str(u.edad),
                                   keyboard_type=ft.KeyboardType.NUMBER, dense=True)
        self.f_actividad = ft.Dropdown(
            label="Nivel de actividad",
            value=u.nivel_actividad,
            options=[ft.dropdown.Option(k) for k in config.FACTOR_ACTIVIDAD],
            dense=True,
        )
        self.f_prot = ft.Slider(
            min=1.4, max=2.2, divisions=8, value=u.proteina_g_por_kg,
            label="{value} g/kg",
        )
        self.f_sup = ft.Slider(
            min=0.05, max=0.25, divisions=4, value=u.superavit_pct,
            label="{value}",
        )
        obj = self.objetivo()

        return ft.Column([
            ft.Text("Perfil", size=20, weight=ft.FontWeight.BOLD),
            ft.Container(height=8),
            self.f_peso, self.f_altura, self.f_edad, self.f_actividad,
            ft.Container(height=8),
            ft.Text("Proteína (g/kg) — 1.6–2.2 es el rango con evidencia", size=11, color=GRIS),
            self.f_prot,
            ft.Text("Superávit calórico — 10–20% sobre mantenimiento", size=11, color=GRIS),
            self.f_sup,
            ft.Container(height=8),
            ft.ElevatedButton("Guardar", icon=ft.Icons.SAVE,
                              on_click=self._guardar_perfil, width=400),
            ft.Divider(height=24),
            ft.Text("Cálculo actual", size=14, weight=ft.FontWeight.BOLD),
            ft.Text(f"Mantenimiento: {obj.mantenimiento_kcal:.0f} kcal", size=12),
            ft.Text(f"Objetivo: {obj.objetivo_kcal:.0f} kcal "
                    f"({obj.superavit_kcal:+.0f})", size=12),
            ft.Text(f"Proteína: {obj.proteina_g:.0f} g "
                    f"(mín {obj.proteina_min_por_comida_g:.0f} g por toma)", size=12),
            ft.Container(height=6),
            ft.Text("Mifflin-St Jeor — la ecuación con menor error promedio "
                    "frente a calorimetría indirecta.", size=10, color=GRIS),
        ], spacing=6)

    def _guardar_perfil(self, e):
        try:
            u = self.usuario
            u.peso_kg = float(self.f_peso.value)
            u.estatura_cm = float(self.f_altura.value)
            u.edad = int(self.f_edad.value)
            u.nivel_actividad = self.f_actividad.value
            u.proteina_g_por_kg = float(self.f_prot.value)
            u.superavit_pct = float(self.f_sup.value)
            u.actualizado = dt.datetime.now()
            u.save()
            self._toast("Perfil guardado. Porciones recalculadas.")
            self._render()
        except (ValueError, TypeError):
            self._toast("Revisa los valores numéricos.", error=True)

    # -- registro de comida ------------------------------------------------

    def _abrir_registro(self, comida, meta, bloqueante: bool = False):
        seleccion = {}

        campo_kcal = ft.TextField(label="kcal", value=f"{meta.kcal:.0f}",
                                  keyboard_type=ft.KeyboardType.NUMBER, dense=True)
        campo_prot = ft.TextField(label="proteína (g)", value=f"{meta.proteina_g:.0f}",
                                  keyboard_type=ft.KeyboardType.NUMBER, dense=True)
        zona_avisos = ft.Column(spacing=4)

        def recalcular():
            if seleccion:
                tot = ne.macros_de_plato(seleccion)
                campo_kcal.value = f"{tot['kcal']:.0f}"
                campo_prot.value = f"{tot['proteina_g']:.0f}"

            avisos = ne.revisar_interacciones(
                alimentos_comida=list(seleccion.keys()),
                orden_comida=comida.orden,
            )
            zona_avisos.controls = [
                ft.Container(
                    content=ft.Row([
                        ft.Icon(ft.Icons.WARNING_AMBER, size=15,
                                color=color_severidad(a.severidad)),
                        ft.Text(a.mensaje, size=10, expand=True,
                                color=color_severidad(a.severidad)),
                    ]),
                    padding=8, border_radius=6, bgcolor="#1E1E1E",
                ) for a in avisos
            ]
            dlg.update()

        def toggle(alimento, activo):
            if activo:
                seleccion[alimento] = 100.0
            else:
                seleccion.pop(alimento, None)
            recalcular()

        chips = ft.Row(wrap=True, spacing=4, run_spacing=4, controls=[
            ft.FilterChip(
                label=ft.Text(a.replace("_", " "), size=10),
                on_select=lambda e, al=a: toggle(al, e.control.selected),
            ) for a in list(config.ALIMENTOS)[:16]
        ])

        def confirmar(e):
            try:
                kcal = float(campo_kcal.value or 0)
                prot = float(campo_prot.value or 0)
            except ValueError:
                self._toast("Valores inválidos.", error=True)
                return
            detalle = ", ".join(f"{a} {g:.0f}g" for a, g in seleccion.items())
            ae.confirmar(comida, kcal, prot, detalle)
            self._cerrar(dlg)
            self._toast(f"{comida.nombre} registrada.")
            self._render()

        acciones = [ft.TextButton("Confirmar comida", on_click=confirmar)]
        if not bloqueante:
            acciones.insert(0, ft.TextButton(
                "Cancelar", on_click=lambda e: self._cerrar(dlg)))

        encabezado = []
        if bloqueante:
            encabezado = [ft.Container(
                content=ft.Text(
                    "Esta comida está pendiente. Regístrala para continuar.",
                    size=11, color=AMBAR,
                ),
                padding=8, bgcolor="#332B00", border_radius=6,
            ), ft.Container(height=6)]

        dlg = ft.AlertDialog(
            modal=True,
            title=ft.Text(f"{comida.hora_str} · {comida.nombre}", size=15),
            content=ft.Container(
                width=380,
                content=ft.Column([
                    *encabezado,
                    ft.Text(f"Meta: {meta.kcal:.0f} kcal · {meta.proteina_g:.0f} g prot",
                            size=11, color=GRIS),
                    ft.Container(height=8),
                    ft.Text("Alimentos (100 g cada uno)", size=11),
                    chips,
                    ft.Container(height=8),
                    ft.Row([campo_kcal, campo_prot], spacing=8),
                    ft.Container(height=6),
                    zona_avisos,
                ], tight=True, scroll=ft.ScrollMode.AUTO),
            ),
            actions=acciones,
            actions_alignment=ft.MainAxisAlignment.END,
        )
        self._abrir(dlg)

    # -- vigilante ---------------------------------------------------------

    async def _vigilante(self):
        """
        Capa 2: mientras la app esté abierta, revisa si hay una comida
        pendiente y fuerza el diálogo. Es la única capa que controlamos
        al 100%, independiente de permisos del sistema.
        """
        while True:
            try:
                ae.marcar_vencidas()
                if not self._dialogo_abierto:
                    p = ae.pendiente_bloqueante()
                    if p:
                        metas = {m.orden: m for m in self.metas()}
                        meta = metas.get(p.comida.orden)
                        if meta:
                            self._abrir_registro(p.comida, meta, bloqueante=True)
            except Exception:
                pass
            await asyncio.sleep(config.INTERVALO_CHECK_S)

    # -- utilidades --------------------------------------------------------

    def _abrir(self, dlg):
        self._dialogo_abierto = True
        self.page.open(dlg)

    def _cerrar(self, dlg):
        self._dialogo_abierto = False
        self.page.close(dlg)

    def _toast(self, texto: str, error: bool = False):
        self.page.snack_bar = ft.SnackBar(
            content=ft.Text(texto),
            bgcolor=ROJO if error else VERDE,
        )
        self.page.snack_bar.open = True
        self.page.update()


def main(page: ft.Page):
    HumanOS(page)


if __name__ == "__main__":
    ft.app(target=main)
