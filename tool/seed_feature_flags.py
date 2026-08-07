"""Siembra/actualiza el documento config/featureFlags en attra-database via
Firestore REST con token de owner (bypassa reglas; el doc es write:false para
clientes). Sincronizado con MonetizationFeatureFlags.fromMap.

Requiere env GTOKEN (gcloud auth print-access-token).
"""
import os
import json
import urllib.request

TOKEN = os.environ["GTOKEN"]
PROJ = "attra-database"
HDR = {
    "Authorization": f"Bearer {TOKEN}",
    "x-goog-user-project": PROJ,
    "Content-Type": "application/json",
}

# Defaults seguros para lanzamiento: monetizacion e IA ON, kill switch OFF.
FLAGS = {
    "monetizationEnabled": ("booleanValue", True),
    "attrasEnabled": ("booleanValue", True),
    "plusEnabled": ("booleanValue", True),
    "premiumEnabled": ("booleanValue", True),
    "proAiEnabled": ("booleanValue", True),
    "visualSearchEnabled": ("booleanValue", True),
    "visualTraitFiltersEnabled": ("booleanValue", True),
    "aiProcessingEnabled": ("booleanValue", True),
    "aiKillSwitch": ("booleanValue", False),
    "spark_enabled": ("booleanValue", True),
    "match_journey_enabled": ("booleanValue", True),
    "icebreakers_enabled": ("booleanValue", True),
    "mini_games_enabled": ("booleanValue", True),
    "double_answer_enabled": ("booleanValue", True),
    "this_or_that_enabled": ("booleanValue", True),
    "two_truths_enabled": ("booleanValue", True),
    "date_builder_enabled": ("booleanValue", True),
    "match_reactivation_enabled": ("booleanValue", True),
    # El parser (MonetizationFeatureFlags.fromMap) lee estas claves con default
    # FALSE, y este script era el unico que escribe config/featureFlags. Al no
    # sembrarlas, el Duelo de Quimica y el Reto Cafe quedaban INALCANZABLES en
    # produccion sin que nadie los hubiera apagado a proposito, y Attra Plans
    # caia siempre al camino de respaldo manual.
    "chat_game_enabled": ("booleanValue", True),
    "date_plans_enabled": ("booleanValue", True),
    "date_plans_ai_enabled": ("booleanValue", True),
    "date_plans_places_enabled": ("booleanValue", True),
    "date_plans_auto_nudge_enabled": ("booleanValue", True),
    "date_plans_kill_switch": ("booleanValue", False),
    "date_plans_free_limit": ("integerValue", "1"),
    # --- FEED EN VIVO (video 1:1 con desconocidos) -----------------------
    # DARK LAUNCH: se siembra explicitamente en FALSE, igual que se hizo con
    # SafeDate. No basta con no escribir la clave: sin sembrarla no hay forma
    # de encenderla ni de auditar desde la consola que esta apagada, y este es
    # justo el tipo de funcion (contenido generado por usuarios en directo, la
    # guideline 1.2 por la que Apple ya rechazo la app) que hay que poder
    # demostrar apagada. Con esto en false no existe ni el punto de entrada.
    "feature_live_enabled": ("booleanValue", False),
    # Corte de emergencia independiente del master switch: permite apagar el
    # directo en caliente sin perder la configuracion de lanzamiento.
    "feature_live_kill_switch": ("booleanValue", False),
    "weeklyFreeAttras": ("integerValue", "0"),
    # --- Pack mensual incluido en cada plan (grants.ts) ------------------
    # Free pasa de 0 a 1 Attra/mes: es el gancho de conversion, sin probar el
    # producto nadie entiende para que sirve un Attra.
    "freeMonthlyAttras": ("integerValue", "1"),
    # Plus sube de 3 a 5: con Free recibiendo 1 al mes, 3 no se notaba.
    "plusMonthlyAttras": ("integerValue", "5"),
    # `premium` ya no se vende, pero hay entitlements vivos en la base: se le
    # dan las ventajas de Pro sin IA para que nadie pierda lo que ya tenia.
    "premiumMonthlyAttras": ("integerValue", "10"),
    "proMonthlyAttras": ("integerValue", "15"),
    # Boosts incluidos al mes. Hasta ahora `monthlyBoost` se anunciaba en el
    # paywall pero NADIE los concedia: el saldo solo subia comprando.
    # Con el Superboost a 3 Boosts, Pro (4) = un Superboost + un Boost corto.
    "freeMonthlyBoosts": ("integerValue", "0"),
    "plusMonthlyBoosts": ("integerValue", "1"),
    "premiumMonthlyBoosts": ("integerValue", "2"),
    "proMonthlyBoosts": ("integerValue", "4"),
    # --- Coste del Superboost (boosts.ts) --------------------------------
    # Antes el Superboost (24 h, +150) costaba 1 Boost, lo MISMO que el Boost
    # de 30 min (+80): el producto caro valia igual que el barato.
    "superboostCostBoosts": ("integerValue", "3"),
    # --- Tope diario de likes por tier (likes.ts) ------------------------
    # El tope solo existia para Free, asi que Plus tenia likes ilimitados de
    # facto y era indistinguible de Pro. Pro/Premium siguen sin tope.
    "freeDailyLikes": ("integerValue", "25"),
    "plusDailyLikes": ("integerValue", "100"),
}

fields = {k: {t: v} for k, (t, v) in FLAGS.items()}

base = (f"https://firestore.googleapis.com/v1/projects/{PROJ}/databases/"
        f"{PROJ}/documents/config/featureFlags")
mask = "&".join(f"updateMask.fieldPaths={k}" for k in FLAGS)

req = urllib.request.Request(
    f"{base}?{mask}",
    data=json.dumps({"fields": fields}).encode(),
    method="PATCH",
    headers=HDR,
)
resp = urllib.request.urlopen(req).read().decode()
print("OK config/featureFlags sembrado:")
print(json.dumps(json.loads(resp).get("fields", {}), indent=2)[:400])
