"""
HumanOS — Pruebas de contrato.

No prueban que el código corra: prueban que las GARANTÍAS que sostienen
la honestidad de la app sigan en pie. Cada una nació de un bug real o de
una decisión que costó discutir.

Correr con:  python tests_contrato.py
"""

import datetime as dt
import shutil, os, sys

for _d in ("data",):
    shutil.rmtree(_d, ignore_errors=True)

import config
import database as db
import nutrition_engine as ne
import sleep_engine as se
import schedule_engine as sc
import habits_engine as he
import shopping_engine as sh

db.init_db()
fallos = []


def check(nombre, condicion, detalle=""):
    if condicion:
        print(f"  OK    {nombre}")
    else:
        print(f"  FALLA {nombre} {detalle}")
        fallos.append(nombre)


def _nut(nombre, gramos):
    a = db.alimento(nombre)
    return ne.ItemNutrido(nombre, gramos, a.nutrientes(gramos),
                          a.hierro_es_hemo, a.inhibe_hierro_no_hemo,
                          frozenset(a.etiquetas))


print("\nPRECISIÓN — no prometer más exactitud de la que hay")
fe = ne.estimar_hierro_absorbido([_nut('lenteja_cocida', 250), _nut('cafe', 200)])
check("hierro absorbido con 1 decimal",
      all(len(p.split('.')[1]) == 1 for p in fe.rango_texto.replace(' mg','').split('–')),
      f"-> {fe.rango_texto}")
check("ingerido y absorbido son campos distintos",
      fe.ingerido_mg != fe.absorbido_max_mg)
check("la nota aclara que no es medición clínica",
      "no equivale a una medición clínica" in fe.nota_incertidumbre)

print("\nHONESTIDAD — mitigar no es neutralizar")
an = ne.analizar_comida([_nut('lenteja_cocida',250), _nut('brocoli',150), _nut('cafe',200)])
textos = " ".join([s.mensaje for s in an.sinergias] + [i.mensaje for i in an.inhibiciones])
check("ningún texto dice 'neutraliza'", "neutraliz" not in textos.lower())
check("dice que compensa en parte", "en parte" in textos.lower())
con_inhib = ne.estimar_hierro_absorbido([_nut('lenteja_cocida',250), _nut('brocoli',150), _nut('cafe',200)])
sin_nada  = ne.estimar_hierro_absorbido([_nut('lenteja_cocida',250)])
solo_c    = ne.estimar_hierro_absorbido([_nut('lenteja_cocida',250), _nut('brocoli',150)])
solo_inh  = ne.estimar_hierro_absorbido([_nut('lenteja_cocida',250), _nut('cafe',200)])
check("vitC+inhibidor queda por DEBAJO del basal",
      con_inhib.absorbido_max_mg < sin_nada.absorbido_max_mg)
check("vitC+inhibidor queda por ENCIMA del inhibidor solo",
      con_inhib.absorbido_max_mg > solo_inh.absorbido_max_mg)
check("vitC sola es el mejor caso",
      solo_c.absorbido_max_mg > sin_nada.absorbido_max_mg)

print("\nJAMAICA — dos alimentos, no uno")
seca, inf = db.alimento('jamaica_seca'), db.alimento('jamaica_infusion')
check("la infusión no hereda el calcio de la flor",
      inf.calcio_mg_100g < seca.calcio_mg_100g / 10,
      f"-> {inf.calcio_mg_100g} vs {seca.calcio_mg_100g}")
check("la infusión no hereda el hierro de la flor",
      inf.hierro_mg_100g <= seca.hierro_mg_100g / 10)
check("ambas inhiben hierro no-hemo",
      seca.inhibe_hierro_no_hemo and inf.inhibe_hierro_no_hemo)
check("la infusión se declara de confianza baja", inf.confianza == "baja")

print("\nESTADO DEL DÍA — ausencia de datos ≠ día libre")
jor = sc.objetivo_proporcional(3055, dt.time(7,0), dt.time(13,0))
libre = sc.objetivo_proporcional(3055, dia_libre=True)
sin = sc.objetivo_proporcional(3055)
check("los tres estados son distintos",
      len({jor["estado"], libre["estado"], sin["estado"]}) == 3)
check("día libre y sin datos no comparten texto", libre["nota"] != sin["nota"])
check("día libre y sin datos no comparten confianza",
      libre["confianza"] != sin["confianza"])
check("monótono: menos trabajo, menos o igual gasto",
      jor["objetivo_kcal"] >= libre["objetivo_kcal"])
check("sin datos no inventa recorte", sin["ajuste_kcal"] == 0)
check("ajuste_kcal siempre int",
      all(isinstance(r["ajuste_kcal"], int) for r in (jor, libre, sin)))

print("\nPROTEÍNA — el exceso se explica")
obj = ne.objetivo_diario(60, 172, 28)
ne.repartir(obj, db.comidas_ordenadas())
check("el plan se expone aparte del objetivo", obj.proteina_plan_g is not None)
check("hay explicación del exceso", bool(obj.explicacion_proteina(60)))
check("no afirma que 0.4 g/kg 'activa' la síntesis",
      "activa la síntesis" not in obj.explicacion_proteina(60))
check("el plan respeta la tolerancia configurada",
      obj.proteina_plan_g <= obj.proteina_g * (1 + config.supuesto("tolerancia_proteina")))

print("\nSUPUESTOS — configurables, no escondidos")
check("los 5 supuestos están declarados", len(config.SUPUESTOS) == 5)
check("cada supuesto tiene explicación",
      all(s.get("explica") and s.get("titulo") for s in config.SUPUESTOS.values()))
check("los motores los leen de config",
      "config.supuesto" in open("schedule_engine.py").read()
      and "config.supuesto" in open("nutrition_engine.py").read())

print("\nSEGURIDAD ALIMENTARIA — sin nevera")
ahora = dt.datetime.now()
niveles = [sc.evaluar_coccion('arroz', ahora - dt.timedelta(hours=h), ahora).nivel
           for h in (0.5, 2.5, 4.5)]
check("tres niveles según horas", niveles == ["ok", "aviso", "limite"], f"-> {niveles}")
check("el nivel límite avisa que recalentar no sirve",
      "recalentar no elimina" in sc.evaluar_coccion('arroz', ahora - dt.timedelta(hours=5), ahora).mensaje)

print("\nMOTORES PUROS — la lógica no depende de la UI ni de la DB")
for m in ("nutrition_engine", "sleep_engine", "habits_engine",
          "schedule_engine", "shopping_engine"):
    src = open(f"{m}.py").read()
    check(f"{m} es puro",
          "import database" not in src and "import flet" not in src)

print("\nDATOS FALTANTES — null significa 'no sé', no 'cero'")
an2 = ne.analizar_comida([_nut('jamaica_seca', 30), _nut('lenteja_cocida', 200)])
check("los nutrientes sin dato se reportan", bool(an2.datos_incompletos))
noches = [se.RegistroNoche(dt.date.today(), 7.0),
          se.RegistroNoche(dt.date.today() - dt.timedelta(days=1), None)]
d = se.deuda_de_sueño(noches, dias=7, objetivo_h=8.0)
check("las noches sin registro no cuentan como deuda", d.noches_con_dato == 1)

print("\nHÁBITOS — un fallo secundario no borra el día")
habs = [he.DefHabito('esencial1','binario',peso=3.0,esencial=True),
        he.DefHabito('esencial2','binario',peso=3.0,esencial=True),
        he.DefHabito('secundario','aumentar',valor_objetivo=20,peso=1.0)]
dia = {'esencial1':1, 'esencial2':1, 'secundario':0}
check("la racha mínima sobrevive a fallar lo secundario",
      he.dia_minimo(habs, dia).cumplido)
check("un día sin registros no cuenta como fallo",
      he.dia_minimo(habs, {}).sin_registros)


if fallos:
    print(f"{len(fallos)} CONTRATO(S) ROTO(S): {fallos}")
    sys.exit(1)
print("TODOS LOS CONTRATOS EN PIE")


# --- Regresión: bebidas fuera de la fase de verduras -----------------------
# Nació de un bug real: el motor puso 370 g de infusión de jamaica en un
# plato porque cumplía "pocas kcal, sin proteína".

print("\nBEBIDAS — no son comida aunque tengan pocas calorías")
_beb = [db.alimento(n) for n in ('jamaica_infusion', 'cafe', 'te', 'jengibre')]
_ver = [db.alimento(n) for n in ('brocoli', 'espinaca')]


def _inv(a, g=300):
    return ne.ItemInventario(a.nombre, a.kcal_100g, a.proteina_100g,
                             frozenset(a.etiquetas), g, a.categoria)


check("ninguna bebida cuenta como verdura",
      not any(ne.es_verdura(_inv(a)) for a in _beb))
check("las verduras sí cuentan",
      all(ne.es_verdura(_inv(a)) for a in _ver))

for _n, _g in [('pollo_pechuga', 300), ('arroz_cocido', 600),
               ('brocoli', 200), ('jamaica_infusion', 300)]:
    db.set_inventario(db.alimento(_n), _g)
_u = db.get_usuario()
_obj = ne.objetivo_diario(_u.peso_kg, _u.estatura_cm, _u.edad)
_metas = ne.repartir(_obj, db.comidas_ordenadas())
_inv_d = db.inventario_dict()
_disp = [ne.ItemInventario(a.nombre, a.kcal_100g, a.proteina_100g,
                           frozenset(a.etiquetas), _inv_d[a.nombre], a.categoria)
         for a in db.catalogo_alimentos() if _inv_d.get(a.nombre, 0) > 0]
_c = ne.armar_combinacion(_metas[2], _disp)
check("el motor no mete bebidas en el plato solo",
      'jamaica_infusion' not in _c.porciones)
_c2 = ne.armar_combinacion(_metas[2], _disp, extras={'jamaica_infusion': 250})
check("la bebida entra solo si se declara, con su cantidad",
      _c2.porciones.get('jamaica_infusion') == 250)

print("\n" + "=" * 54)
if fallos:
    print(f"{len(fallos)} CONTRATO(S) ROTO(S): {fallos}")
    sys.exit(1)
print("TODOS LOS CONTRATOS EN PIE")
