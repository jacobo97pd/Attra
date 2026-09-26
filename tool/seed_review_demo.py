"""Prepara la CUENTA DEMO de App Store / Play Review (Guideline 2.1(a)).

Apple rechazo la version 1.0 (61) porque la cuenta demo no permitia ver todas
las funciones ("make sure the demo accounts you provide include pre-populated
content ... such as access to other users"). Este script deja la cuenta con:

  1. Perfil completo y onboarding/tutorial marcados como hechos (el revisor
     entra directo a la app, sin formularios).
  2. Documento `discovery/{uid}` publicado para que sea visible/consultable.
  3. Likes RECIBIDOS de varios perfiles semilla -> la bandeja "Te han dado
     like" no aparece vacia y, al devolver el like, sale un match REAL.
  4. Dos matches ya creados con su chat y mensajes -> "Chats" tiene contenido.
  5. Entitlement Pro activo -> acceso al plan sin tener que comprarlo.

Con --with-stories prepara historias de demostracion con la misma vigencia de
72 horas que las historias normales. --stories-only permite renovarlas sin
restablecer chats. --peer-uid crea un chat con otra cuenta REAL de prueba para
probar juegos y llamadas desde dos dispositivos; los mocks no responden solos.
Los mocks estan en Espana: comprueba el feed con la ubicacion del dispositivo
y, si procede, configura Modo viajes a Espana. El consentimiento de IA y la
aceptacion de terminos se completan en la app; el script no los falsifica.

Requisitos previos (una sola vez, en la consola de Firebase):
  - Authentication -> Sign-in method -> Phone -> "Phone numbers for testing":
    anadir el telefono demo y su codigo fijo (no se envia SMS real). Ese es el
    usuario/contrasena que se pone en App Store Connect.
  - Iniciar sesion UNA vez con ese telefono desde la app para que Firebase Auth
    cree el UID, y copiarlo en DEMO_UID (o pasarlo por env DEMO_UID).
  - Sembrar los perfiles mock: `python tool/seed_mock_profiles.py`.

Uso:
  $env:GTOKEN = gcloud auth print-access-token
  $env:DEMO_UID = "<uid del usuario demo>"
  python tool/seed_review_demo.py

Para revisar todos los documentos sin credenciales ni acceso a Firebase:
  python tool/seed_review_demo.py --dry-run --uid demo_offline

Si la cuenta demo YA completo el onboarding en la app (perfil real, fotos
propias), siembra solo el contenido y no pises el perfil:
  $env:DEMO_KEEP_PROFILE = "1"

Usa ids deterministas y se puede re-ejecutar; al hacerlo restablece los likes
y los chats demo. No borra bloqueos, reportes ni mensajes de usuarios.
Si una ronda anterior dejo match (activo o deshecho) con un mock de LIKED_ME,
se para antes de escribir y da el comando de tool/reset_mock_feed.py que deja
esos pares limpios: con ese match el like re-sembrado ya no daria match.
Las escrituras se agrupan en un unico commit atomico y preservan los campos
no incluidos, especialmente otros ajustes y consentimientos existentes.
IMPORTANTE: los ids de like/match/chat replican los del backend
(functions/src/ids.ts y lib/src/features/match/domain/pair_id.dart):
  like  -> `<fromUid>_<toUid>`
  match -> `<a>_<b>` con a <= b (comparacion de strings)
  chat  -> mismo id que el match
"""
import json
import os
import argparse
import copy
import re
from datetime import datetime, timedelta, timezone
import urllib.error
import urllib.parse
import urllib.request

TOKEN = os.environ.get("GTOKEN", "").strip()
PROJ = "attra-database"
DEMO_UID = os.environ.get("DEMO_UID", "").strip()
DRY_RUN = False
PENDING_WRITES = {}
SEED_FIELDS = {}

HDR = {
    "Authorization": f"Bearer {TOKEN}",
    "x-goog-user-project": PROJ,
    "Content-Type": "application/json",
}
BASE = (
    f"https://firestore.googleapis.com/v1/projects/{PROJ}/databases/{PROJ}"
    "/documents"
)

# Perfiles semilla (de seed_mock_profiles.py) que interactuan con la demo.
LIKED_ME = [
    "mock_t_maria",
    "mock_t_laura",
    "mock_t_carmen",
    "mock_t_valeria",
]
MATCHED = [
    ("mock_t_ana", [
        ("mock_t_ana", "Hola! Vi que tambien te gusta el padel 🎾"),
        (None, "Si! Juego los martes. ¿Te apuntas a un partido?"),
        ("mock_t_ana", "Me encantaria. ¿Esta semana te viene bien?"),
    ]),
    ("mock_t_ines", [
        ("mock_t_ines", "Tu foto del concierto es brutal, ¿quien tocaba?"),
        (None, "Era un grupo indie de Barcelona, te paso el nombre"),
    ]),
]
# No reciben likes/matches del script: quedan disponibles para el feed.
FEED_ONLY = ["mock_t_elena", "mock_t_clara"]

# OJO con la FORMA del documento: AppUser.fromDocument NO lee estos datos de la
# raiz, sino de los mapas `profile`, `preferences`, `location` y `settings`
# (lib/src/features/auth/domain/app_user.dart:200-245). Sembrarlos en la raiz
# deja el perfil vacio en la app aunque en Firestore "se vean".
_PHOTO_MAIN = "https://randomuser.me/api/portraits/men/32.jpg"
_PHOTO_ALT = "https://randomuser.me/api/portraits/men/33.jpg"

DEMO_PROFILE = {
    "displayName": "Alex Demo",
    "email": "review.demo@attra.app",
    "photoUrl": _PHOTO_MAIN,
    "profilePhotoUrl": _PHOTO_MAIN,
    "photos": [
        {"url": _PHOTO_MAIN, "storagePath": "", "source": "demo", "order": 0},
        {"url": _PHOTO_ALT, "storagePath": "", "source": "demo", "order": 1},
    ],
    "onboardingCompleted": True,
    "profileCompleted": True,
    "isBot": False,
    # profile.* -> identidad publica que lee la app.
    "profile": {
        "visibleName": "Alex Demo",
        "gender": "male",
        "pronouns": "he",
        "orientation": ["straight"],
        "birthDate": "1995-05-20T00:00:00Z",
        "birthCity": "Madrid",
        "languages": ["es", "en"],
        "bio": (
            "Cuenta de demostracion para la revision de la App Store. "
            "Perfil completo con matches, chats y likes recibidos."
        ),
        "currentCity": "Madrid",
        "currentCountryName": "España",
        "currentCountryCode": "ES",
        "jobTitle": "Product designer",
        "company": "Attra",
        "interests": ["padel", "musica", "viajes"],
        "relationshipIntent": "long_term",
        "intentMode": "dating",
    },
    # preferences.* -> a quien quiere ver.
    "preferences": {
        "interestedIn": ["female"],
        # Los mocks estan repartidos por Espana; 100 km ocultaba casi todos.
        # 500 es el maximo que admite la app (FeedFilters.distanceCeil): con
        # 1000 se recortaba a 500 igualmente y el documento decia otra cosa.
        "maxDistanceKm": 500,
        "preferredAgeMin": 24,
        "preferredAgeMax": 40,
    },
    "location": {"latitude": 40.4168, "longitude": -3.7038},
    "geo": {"lat": 40.4168, "lng": -3.7038},
    # settings.* -> el tutorial OBLIGATORIO se marca aqui, no en la raiz:
    # AppUser lee settings['tutorial.completed'] (app_user.dart:217). Si se
    # escribe en la raiz, al revisor le salta el tutorial y el tour guiado.
    "settings": {
        "tutorial.completed": True,
        "appearance.themeMode": "system",
    },
}


def to_value(v):
    """Convierte un valor Python al formato tipado de Firestore REST."""
    if v is None:
        return {"nullValue": None}
    if isinstance(v, datetime):
        return {"timestampValue": v.astimezone(timezone.utc).isoformat()}
    if isinstance(v, bool):
        return {"booleanValue": v}
    if isinstance(v, int):
        return {"integerValue": str(v)}
    if isinstance(v, float):
        return {"doubleValue": v}
    if isinstance(v, str):
        return {"stringValue": v}
    if isinstance(v, list):
        return {"arrayValue": {"values": [to_value(x) for x in v]}}
    if isinstance(v, dict):
        return {"mapValue": {"fields": {k: to_value(x) for k, x in v.items()}}}
    raise TypeError(f"tipo no soportado: {type(v)}")


def patch(path, data):
    """Prepara un update; main confirma todo junto tras validar requisitos."""
    fields = {k: to_value(v) for k, v in data.items()}
    if DRY_RUN:
        # Escapes JSON para que funcione tambien redirigido en PowerShell/cp1252.
        print(json.dumps({"path": path, "fields": fields}))
        return
    def merge(target, source):
        for key, value in source.items():
            if isinstance(value, dict) and isinstance(target.get(key), dict):
                merge(target[key], value)
            else:
                target[key] = copy.deepcopy(value)
    merge(PENDING_WRITES.setdefault(path, {}), data)


def field_paths(data, prefix=()):
    """Mascaras de hojas; settings['tutorial.completed'] es una clave literal."""
    for key, value in data.items():
        escaped = key if re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*", key) else (
            "`" + key.replace("\\", "\\\\").replace("`", "\\`") + "`"
        )
        parts = (*prefix, escaped)
        if isinstance(value, dict) and value:
            yield from field_paths(value, parts)
        else:
            yield ".".join(parts)


def commit_writes():
    """Firestore commit es atomico: no deja un perfil con contenido a medias."""
    if DRY_RUN or not PENDING_WRITES:
        return
    writes = [{
        "update": {
            "name": f"projects/{PROJ}/databases/{PROJ}/documents/{path}",
            "fields": {key: to_value(value) for key, value in data.items()},
        },
        "updateMask": {"fieldPaths": list(field_paths(data))},
    } for path, data in PENDING_WRITES.items()]
    req = urllib.request.Request(
        f"{BASE}:commit",
        data=json.dumps({"writes": writes}).encode(),
        method="POST",
        headers=HDR,
    )
    with urllib.request.urlopen(req, timeout=30) as response:
        response.read()


def require_document(path):
    """Detecta prerequisitos ausentes ANTES de crear contenido parcial."""
    req = urllib.request.Request(
        f"{BASE}/{urllib.parse.quote(path, safe='/')}", headers=HDR
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            return json.load(response).get("fields", {})
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
        raise SystemExit(
            f"Falta {path}. Inicia sesion con la cuenta demo y ejecuta "
            "python tool/seed_mock_profiles.py antes de preparar la revision."
        ) from error


def find_document(path):
    """Como require_document, pero un doc ausente es un resultado (None)."""
    req = urllib.request.Request(
        f"{BASE}/{urllib.parse.quote(path, safe='/')}", headers=HDR
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            return json.load(response).get("fields", {})
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        raise


def check_liked_me_pairs():
    """Un like recibido solo sirve si el par NO tiene ya un match de antes.

    QUE FALLABA: el backend trata cualquier match que no este 'active'
    (unmatch, cierre con elegancia) como terminal y contesta 'blocked' a un
    like nuevo. Si en una ronda anterior el revisor respondio a uno de estos
    likes y luego deshizo el match, al re-sembrar la tarjeta volvia a salir en
    "Te han dado like" (el like vuelve a 'active'), pero "Responder" mostraba
    "No puedes interactuar con este perfil" en el flujo estrella de la demo.
    Con el match aun 'active' la tarjeta ni siquiera sale. Este script no
    borra matches ni mensajes, asi que se para ANTES de escribir nada y dice
    como dejar esos pares limpios.
    """
    stale = {}
    for uid in LIKED_ME:
        fields = find_document(f"matches/{pair_id(DEMO_UID, uid)}")
        if fields is not None:
            stale[uid] = fields.get("status", {}).get("stringValue", "active")
    if stale:
        found = ", ".join(f"{uid} ({status})" for uid, status in stale.items())
        raise SystemExit(
            "La cuenta demo ya tiene match con mocks que deben llegar como "
            f"like recibido: {found}. Limpia esos pares con\n"
            f"  python tool/reset_mock_feed.py --uid {DEMO_UID} "
            f"--only {' '.join(stale)}\n"
            "(borra likes, descartes, bloqueos, matches y chats de esos pares) "
            "y vuelve a ejecutar este script."
        )


def check_prerequisites(keep_profile, peer_uid=None):
    fields = require_document(f"users/{DEMO_UID}")
    if keep_profile and not all(
        fields.get(key, {}).get("booleanValue") is True
        for key in ("onboardingCompleted", "profileCompleted")
    ):
        raise SystemExit(
            "DEMO_KEEP_PROFILE requiere completar el onboarding de la cuenta."
        )
    for uid in LIKED_ME + [uid for uid, _ in MATCHED] + FEED_ONLY:
        fields = require_document(f"seed_profiles/{uid}")
        SEED_FIELDS[uid] = fields
        if (fields.get("isBot", {}).get("booleanValue") is not True
                or not fields.get("photoUrl", {}).get("stringValue")
                or not fields.get("displayName", {}).get("stringValue")):
            raise SystemExit(
                f"Perfil semilla incompleto: {uid}. Ejecuta "
                "python tool/seed_mock_profiles.py."
            )
    check_liked_me_pairs()
    if peer_uid:
        require_document(f"users/{peer_uid}")


def check_only(keep_profile, peer_uid, travel_spain=False):
    """Comprueba acceso y contenido existente sin escribir ni exponer secretos."""
    check_prerequisites(keep_profile, peer_uid)
    flags = require_document("config/featureFlags")
    print("Requisitos de perfil y perfiles semilla: OK.")
    print("storiesEnabled=" + str(
        flags.get("storiesEnabled", {}).get("booleanValue", False)))
    if travel_spain:
        # Antes no se miraba: la cuenta COMPANION llego a revision con un
        # viaje caducado que el backend iba a apagar.
        now = datetime.now(timezone.utc)
        problems = []
        for uid in filter(None, [DEMO_UID, peer_uid]):
            problems += travel_problems(
                uid,
                find_document(f"users/{uid}"),
                find_document(f"userEntitlements/{uid}"),
                now,
            )
        if problems:
            raise SystemExit(
                "Modo viajes a Espana NO listo para la revision:\n  - "
                + "\n  - ".join(problems)
                + "\nVuelve a ejecutar el script con --keep-profile "
                "--travel-spain (y --peer-uid) y repite --check-only."
            )
        print("Modo viajes a Espana: OK en todas las cuentas revisadas.")
    print("Comprobacion terminada. No se ha escrito en Firebase. "
          "El acceso desde la app y el contenido vigente requieren validacion.")


def seed_stories():
    """Contenido demo identificado; no cambia la caducidad normal de 72 h."""
    mock_names = ["Maria", "Laura", "Carmen", "Valeria", "Ana", "Ines",
                  "Elena", "Clara"]
    owners = LIKED_ME + [uid for uid, _ in MATCHED] + FEED_ONLY
    for index, (uid, name) in enumerate(zip(owners, mock_names), 1):
        fields = SEED_FIELDS.get(uid, {})
        photo = fields.get("photoUrl", {}).get("stringValue") or (
            f"https://randomuser.me/api/portraits/women/{index}.jpg"
        )
        display_name = fields.get("displayName", {}).get("stringValue", name)
        story_id = f"review_demo_{uid}"
        patch(f"stories/{story_id}", {
            "storyId": story_id,
            "ownerUid": uid,
            "displayName": display_name,
            "mediaType": "image",
            "imageUrl": photo,
            "imagePath": "",
            "thumbnailUrl": photo,
            "thumbnailPath": "",
            "videoUrl": "",
            "videoPath": "",
            "caption": "Historia de demostracion - contenido de prueba",
            "overlays": [],
            "visibility": "discovery",
            "status": "active",
            "durationSeconds": 0,
            "createdAt": STAMP,
            "expiresAt": STAMP + timedelta(hours=72),
        })
    print("Preparadas 8 historias demo; caducan a las 72 h. "
          "Renueva con --stories-only antes de que caduquen.")


def pair_id(a, b):
    """Mismo id determinista que ids.ts / pair_id.dart."""
    return f"{a}_{b}" if a <= b else f"{b}_{a}"


def directed_id(from_uid, to_uid):
    return f"{from_uid}_{to_uid}"


# Firestore debe recibir Timestamp, igual que los mensajes enviados por la app.
# Las cadenas ISO se ordenan por tipo, separadas de los mensajes reales.
STAMP = None


def seed_profile():
    profile = DEMO_PROFILE["profile"]
    preferences = DEMO_PROFILE["preferences"]
    birth_date = datetime.fromisoformat(profile["birthDate"].replace("Z", "+00:00"))
    today = STAMP.date()
    age = today.year - birth_date.year - (
        (today.month, today.day) < (birth_date.month, birth_date.day)
    )
    patch(f"users/{DEMO_UID}", {
        **DEMO_PROFILE,
        "uid": DEMO_UID,
        "profile": {**profile, "birthDate": birth_date},
        "updatedAt": STAMP,
    })
    discovery = {
        "uid": DEMO_UID,
        "displayName": profile["visibleName"],
        "age": age,
        "gender": profile["gender"],
        "interestedIn": preferences["interestedIn"],
        "photoUrl": DEMO_PROFILE["photoUrl"],
        "photos": DEMO_PROFILE["photos"],
        "bio": profile["bio"],
        "currentCity": profile["currentCity"],
        "currentCountryName": profile["currentCountryName"],
        "jobTitle": profile["jobTitle"],
        "company": profile["company"],
        "relationshipIntent": profile["relationshipIntent"],
        "intentMode": profile["intentMode"],
        "interests": profile["interests"],
        # Igual que DiscoveryPublisher: coordenadas publicas aproximadas.
        "geo": {key: round(value, 2) for key, value in DEMO_PROFILE["geo"].items()},
        "isBot": False,
        "updatedAt": STAMP,
    }
    patch(f"discovery/{DEMO_UID}", discovery)
    print(f"Preparado perfil demo: users/{DEMO_UID} + discovery/{DEMO_UID}")


def travel_spain_patch():
    """Modo viajes "Espana sin ciudad" de una cuenta de revision.

    La mascara de commit_writes es de HOJAS: lo que no se nombra se conserva.
    Antes solo se escribian active/iso2/country/city, asi que sobrevivian:
      - un `until`/`untilAt` de un viaje anterior. La cuenta COMPANION tenia
        uno de agosto YA PASADO: la app avisaba "Tu viaje a Espana ha
        terminado", el barrido horario del backend lo apagaba y el revisor
        veia Descubrir vacio fuera de Espana. Resembrar no lo arreglaba.
      - `lat`/`lng` de un viaje a una ciudad: el viaje a un pais entero se
        media desde esa ciudad con 500 km y dejaba fuera Barcelona o Bilbao.
    Los None se escriben como null y borran esos valores. Sin fecha, el
    viaje no caduca durante la revision.
    """
    return {
        "preferences": {"maxDistanceKm": 500},
        "settings": {"travel": {
            "active": True, "iso2": "ES", "country": "España",
            "city": "",
            "until": None, "untilAt": None,
            "lat": None, "lng": None, "geoCity": None, "geoIso2": None,
            "geoSource": "none",
            "updatedAt": STAMP,
        }},
    }


def _plain(value):
    """Valor tipado de Firestore REST -> Python (solo lo que se revisa)."""
    if not isinstance(value, dict):
        return None
    if "mapValue" in value:
        return {k: _plain(v)
                for k, v in value["mapValue"].get("fields", {}).items()}
    if "timestampValue" in value:
        return datetime.fromisoformat(
            value["timestampValue"].replace("Z", "+00:00"))
    for key in ("booleanValue", "stringValue", "doubleValue"):
        if key in value:
            return value[key]
    if "integerValue" in value:
        return int(value["integerValue"])
    return None


def _as_date(value):
    if isinstance(value, datetime):
        return value
    if isinstance(value, str) and value.strip():
        try:
            parsed = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
        except ValueError:
            return "ilegible"
        return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
    return None


def travel_problems(uid, user_fields, entitlement_fields, now):
    """Por que el viaje a Espana de `uid` NO serviria al revisor ([] = OK).

    Mismas reglas que la app y el backend: tiene que estar activo, en Espana,
    sin fecha pasada (manda la mas tardia de until/untilAt), sin centro de
    otra ciudad, y con un plan de pago vigente (el viaje es Plus/Pro).
    """
    problems = []
    settings = _plain((user_fields or {}).get("settings")) or {}
    travel = settings.get("travel") if isinstance(settings.get("travel"), dict) else {}
    if travel.get("active") is not True:
        problems.append("settings.travel.active no es true")
    iso2 = (travel.get("iso2") or "").strip().upper()
    country = (travel.get("country") or "").strip().lower()
    if iso2 != "ES" and country not in ("españa", "espana", "spain"):
        problems.append("el destino no es Espana")
    dates = [_as_date(travel.get(k)) for k in ("untilAt", "until")]
    if "ilegible" in dates:
        problems.append("fecha de fin ilegible")
    dates = [d for d in dates if isinstance(d, datetime)]
    if dates and max(dates) <= now:
        problems.append(f"viaje caducado ({max(dates).isoformat()}): "
                        "el barrido del backend lo apagara")
    if not (travel.get("city") or "").strip() and (
            travel.get("lat") is not None or travel.get("lng") is not None):
        problems.append("viaje sin ciudad con lat/lng de un viaje anterior")
    ent = {k: _plain(v) for k, v in (entitlement_fields or {}).items()}
    tier = (ent.get("tier") or "free")
    expires = ent.get("expiresAt")
    paid = tier != "free" and (
        ent.get("isLifetime") is True
        or not isinstance(expires, datetime) or expires >= now)
    if not paid:
        problems.append("sin plan de pago vigente: el viaje no cuenta "
                        f"(ejecuta el script con --uid {uid})")
    return [f"{uid}: {p}" for p in problems]


def seed_entitlement():
    """Pro activo; consentimientos y flags de producto siguen aplicando.

    OJO con la coleccion: el cliente lee `userEntitlements/{uid}`
    (lib/src/features/monetization/data/entitlement_service.dart) y las reglas
    la declaran en firestore.rules. Sembrar en `entitlements/` no tiene ningun
    efecto: la app sigue viendo Free.

    Los campos son los que escribe verifyPurchase (functions/src/subscriptions.ts)
    y los que parsea UserEntitlements.fromMap: tier, source, expiresAt,
    isLifetime. `source` debe ser uno de EntitlementSource (app_store,
    play_store, admin, promo); usamos "admin" porque es una concesion manual.
    """
    patch(
        f"userEntitlements/{DEMO_UID}",
        {
            "tier": "pro",
            "source": "admin",
            "isLifetime": True,
            "expiresAt": None,
            "renewsAt": None,
            # [] activa defaultFeaturesForTier(pro), incluso si antes habia
            # una lista explicita de features de un tier inferior.
            "features": [],
            "productId": "app_review_demo",
            "note": "Cuenta de revision de App Store. Concesion manual.",
            "updatedAt": STAMP,
        },
    )
    patch(f"users/{DEMO_UID}", {
        "subscriptionTier": "pro",
        "hasActiveSubscription": True,
    })
    print(f"Preparado entitlement Pro: userEntitlements/{DEMO_UID}")


def seed_received_likes():
    """Likes ENTRANTES: la bandeja no queda vacia y devolverlos crea match."""
    for uid in LIKED_ME:
        patch(
            f"likes/{directed_id(uid, DEMO_UID)}",
            {
                "fromUid": uid,
                "toUid": DEMO_UID,
                "type": "like",
                "status": "active",
                "targetType": "profile",
                "commentText": None,
                "commentStatus": "none",
                "commentModerationStatus": "approved",
                "createdAt": STAMP,
            },
        )
        print(f"Preparado like recibido de {uid}")


def seed_match(other_uid, messages):
    """Match + chat + mensajes, con el MISMO esquema que writeMatchAndChat."""
    mid = pair_id(DEMO_UID, other_uid)
    user_a, user_b = sorted([DEMO_UID, other_uid])
    users = [user_a, user_b]
    messages = [(sender or DEMO_UID, text) for sender, text in messages]
    # Cada mensaje tiene su propia fecha; el resumen apunta al ultimo.
    last_message_at = STAMP + timedelta(seconds=len(messages) - 1)

    patch(
        f"matches/{mid}",
        {
            "users": users,
            "userA": user_a,
            "userB": user_b,
            "status": "active",
            "createdBy": other_uid,
            "createdByAction": "like",
            "hasAttra": False,
            "attraSenderUid": None,
            "chatId": mid,
            "originLikeId": directed_id(other_uid, DEMO_UID),
            "originTargetType": "profile",
            "originPhotoId": None,
            "originPhotoUrlSnapshot": None,
            "originCommentText": None,
            "createdAt": STAMP,
            "updatedAt": STAMP,
        },
    )

    last_sender, last_text = messages[-1]
    patch(
        f"chats/{mid}",
        {
            "matchId": mid,
            "users": users,
            "status": "active",
            "unreadCountByUser": {user_a: 0, user_b: 0},
            "typingByUser": {user_a: False, user_b: False},
            "hasAttra": False,
            "lastMessage": last_text,
            "lastMessageType": "text",
            "lastMessageSenderId": last_sender,
            "lastMessageAt": last_message_at,
            "realMessageCount": len(messages),
            "createdAt": STAMP,
            "updatedAt": last_message_at,
        },
    )

    # Ambos likes quedan como "matched", igual que hace el backend.
    for a, b in ((DEMO_UID, other_uid), (other_uid, DEMO_UID)):
        patch(
            f"likes/{directed_id(a, b)}",
            {
                "fromUid": a,
                "toUid": b,
                "type": "like",
                "status": "matched",
                "targetType": "profile",
                "createdAt": STAMP,
                "matchedAt": STAMP,
            },
        )

    for i, (sender, text) in enumerate(messages):
        receiver = other_uid if sender == DEMO_UID else DEMO_UID
        patch(
            f"chats/{mid}/messages/demo_{i:02d}",
            {
                "senderId": sender,
                "receiverId": receiver,
                "type": "text",
                "text": text,
                "status": "sent",
                "createdAt": STAMP + timedelta(seconds=i),
            },
        )
    print(f"Preparado match+chat con {other_uid}: {len(messages)} mensajes")


def main(argv=None):
    global DEMO_UID, DRY_RUN, STAMP, HDR
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--uid", default=DEMO_UID)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true",
                      help="Muestra el payload REST sin acceso a Firebase.")
    mode.add_argument("--check-only", action="store_true",
                      help="Comprueba requisitos en Firebase sin escribir.")
    parser.add_argument("--keep-profile", action="store_true",
                        help="Conserva el perfil existente; concede Pro y contenido.")
    parser.add_argument("--peer-uid", help="UID de otra cuenta real de prueba.")
    parser.add_argument("--with-stories", action="store_true",
                        help="Incluye 8 historias demo de 72 h para A ciegas.")
    parser.add_argument("--stories-only", action="store_true",
                        help="Renueva solo historias demo; conserva perfil y chats.")
    parser.add_argument("--travel-spain", action="store_true",
                        help="Configura Modo viajes a Espana (sin fecha de fin) "
                             "para ver los mocks desde cualquier pais; tambien "
                             "en --peer-uid. Con --check-only, lo comprueba.")
    args = parser.parse_args(argv)
    DEMO_UID = args.uid.strip()
    DRY_RUN = args.dry_run
    def valid_uid(uid):
        return (bool(uid) and len(uid) <= 128 and "/" not in uid
                and uid not in (".", "..") and not any(ord(c) < 32 for c in uid))
    if not valid_uid(DEMO_UID):
        parser.error("Indica un UID valido mediante --uid o DEMO_UID.")
    peer_uid = (args.peer_uid or "").strip()
    if args.peer_uid and (not valid_uid(peer_uid) or peer_uid == DEMO_UID
                         or peer_uid.startswith("mock_")):
        parser.error("--peer-uid requiere otra cuenta real de prueba, no un mock.")
    if not DRY_RUN and not TOKEN:
        parser.error("Falta GTOKEN (gcloud auth print-access-token).")
    HDR = {**HDR, "Authorization": f"Bearer {TOKEN}"}
    PENDING_WRITES.clear()
    SEED_FIELDS.clear()
    try:
        STAMP = datetime.fromisoformat(
            os.environ.get("DEMO_STAMP", "").replace("Z", "+00:00")
        ) if os.environ.get("DEMO_STAMP") else (
            datetime.now(timezone.utc) - timedelta(minutes=5)
        )
        if STAMP.tzinfo is None:
            raise ValueError("DEMO_STAMP debe incluir zona horaria")
        STAMP = STAMP.astimezone(timezone.utc)
    except ValueError as error:
        parser.error(str(error))
    # Si la cuenta ya completo el onboarding en la app, su perfil es real y
    # NO hay que pisarlo: bastaria con sembrar el contenido. Ademas, el
    # repositorio restaura displayName/photoUrl desde profile.* en cada login,
    # asi que sobrescribirlos aqui dejaria el perfil a medias.
    keep_profile = args.keep_profile or os.environ.get("DEMO_KEEP_PROFILE", "").strip().lower() in (
        "1", "true", "yes"
    )
    if args.check_only:
        check_only(keep_profile, peer_uid, args.travel_spain)
        return
    if not DRY_RUN:
        check_prerequisites(keep_profile, peer_uid)
    if not args.stories_only:
        if keep_profile:
            print("Se conserva el perfil y se prepara la concesion Pro.")
        else:
            seed_profile()
        if args.travel_spain:
            # Tambien la cuenta compa\u00f1era: las notas de revision dicen que
            # AMBAS viajan a Espana y antes solo se tocaba --uid. OJO: el viaje
            # solo cuenta con plan de pago y la concesion Pro de este script es
            # solo para --uid (compruebalo con --check-only --travel-spain).
            for uid in filter(None, [DEMO_UID, peer_uid]):
                patch(f"users/{uid}", travel_spain_patch())
        seed_entitlement()
        seed_received_likes()
        for other_uid, messages in MATCHED:
            seed_match(other_uid, messages)
        if peer_uid:
            seed_match(peer_uid, [
                (peer_uid, "Hola, esta cuenta de prueba permite revisar juegos y llamadas desde otro dispositivo."),
                (None, "Perfecto, podemos probar las funciones de chat juntos."),
            ])
    if args.with_stories or args.stories_only:
        seed_stories()
    if DRY_RUN:
        print("Simulacion terminada. No se ha leido ni escrito en Firebase.")
        return
    commit_writes()
    print(
        "\nDatos demo preparados. Verificacion en dispositivo pendiente:\n"
        "  - Telefono de prueba y codigo fijo dados de alta en Firebase Auth.\n"
        "  - Esos mismos datos en App Store Connect -> App Review "
        "Information.\n"
        "  - Verifica en la app: feed con perfiles, likes recibidos, chats "
        "con historial y funciones Pro visibles.\n"
        "  - Los mocks estan en Espana: revisa ubicacion/Modo viajes con\n"
        "    --check-only --travel-spain (y --peer-uid) tras el despliegue.\n"
        "  - Si storiesEnabled activa A ciegas, usa --with-stories y renueva "
        "con --stories-only al menos cada 72 h durante la revision.\n"
        "  - Los mocks no responden a juegos ni llamadas; prepara otra "
        "cuenta real de prueba para esos flujos.\n"
        "  - Acepta terminos y consentimiento IA desde la app cuando se pidan.\n"
        "  - Si reutilizas la cuenta, revisa bloqueos, matches previos y "
        "filtros: este script no borra esas acciones."
    )


if __name__ == "__main__":
    main()
