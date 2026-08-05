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
  5. Entitlement Pro activo -> el revisor ve todas las funciones de pago sin
     tener que comprar nada.

Requisitos previos (una sola vez, en la consola de Firebase):
  - Authentication -> Sign-in method -> Phone -> "Phone numbers for testing":
    anadir el telefono demo y su codigo fijo (no se envia SMS real). Ese es el
    usuario/contrasena que se pone en App Store Connect.
  - Iniciar sesion UNA vez con ese telefono desde la app para que Firebase Auth
    cree el UID, y copiarlo en DEMO_UID (o pasarlo por env DEMO_UID).
  - Sembrar los perfiles mock: `python tool/seed_mock_profiles.py`.

Uso:
  set GTOKEN=<gcloud auth print-access-token>
  set DEMO_UID=<uid del usuario demo>
  python tool/seed_review_demo.py

Si la cuenta demo YA completo el onboarding en la app (perfil real, fotos
propias), siembra solo el contenido y no pises el perfil:
  set DEMO_KEEP_PROFILE=1

Idempotente: usa PATCH con ids deterministas, se puede re-ejecutar.
IMPORTANTE: los ids de like/match/chat replican los del backend
(functions/src/ids.ts y lib/src/features/match/domain/pair_id.dart):
  like  -> `<fromUid>_<toUid>`
  match -> `<a>_<b>` con a <= b (comparacion de strings)
  chat  -> mismo id que el match
"""
import json
import os
import urllib.request

TOKEN = os.environ["GTOKEN"]
PROJ = "attra-database"
DEMO_UID = os.environ.get("DEMO_UID", "").strip()
if not DEMO_UID:
    raise SystemExit(
        "Falta DEMO_UID. Inicia sesion una vez con el telefono de prueba y "
        "exporta el UID: set DEMO_UID=<uid>"
    )

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
        (DEMO_UID, "Si! Juego los martes. ¿Te apuntas a un partido?"),
        ("mock_t_ana", "Me encantaria. ¿Esta semana te viene bien?"),
    ]),
    ("mock_t_ines", [
        ("mock_t_ines", "Tu foto del concierto es brutal, ¿quien tocaba?"),
        (DEMO_UID, "Era un grupo indie de Barcelona, te paso el nombre"),
    ]),
]

# OJO con la FORMA del documento: AppUser.fromDocument NO lee estos datos de la
# raiz, sino de los mapas `profile`, `preferences`, `location` y `settings`
# (lib/src/features/auth/domain/app_user.dart:200-245). Sembrarlos en la raiz
# deja el perfil vacio en la app aunque en Firestore "se vean".
_PHOTO_MAIN = "https://randomuser.me/api/portraits/men/32.jpg"
_PHOTO_ALT = "https://randomuser.me/api/portraits/men/33.jpg"

DEMO_PROFILE = {
    "uid": DEMO_UID,
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
        "maxDistanceKm": 100,
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
    """PATCH idempotente sobre `documents/<path>` con updateMask."""
    fields = {k: to_value(v) for k, v in data.items()}
    mask = "&".join(f"updateMask.fieldPaths={k}" for k in data)
    req = urllib.request.Request(
        f"{BASE}/{path}?{mask}",
        data=json.dumps({"fields": fields}).encode(),
        method="PATCH",
        headers=HDR,
    )
    urllib.request.urlopen(req).read()


def pair_id(a, b):
    """Mismo id determinista que ids.ts / pair_id.dart."""
    return f"{a}_{b}" if a <= b else f"{b}_{a}"


def directed_id(from_uid, to_uid):
    return f"{from_uid}_{to_uid}"


# Marca temporal fija: el backend usa serverTimestamp, pero al sembrar por REST
# basta una fecha valida para ordenar. Se puede sobrescribir por env.
STAMP = os.environ.get("DEMO_STAMP", "2026-08-01T10:00:00Z")


def seed_profile():
    patch(f"users/{DEMO_UID}", DEMO_PROFILE)
    discovery = {
        "uid": DEMO_UID,
        "displayName": DEMO_PROFILE["displayName"],
        "age": DEMO_PROFILE["age"],
        "gender": DEMO_PROFILE["gender"],
        "interestedIn": DEMO_PROFILE["interestedIn"],
        "orientation": DEMO_PROFILE["orientation"],
        "photoUrl": DEMO_PROFILE["photoUrl"],
        "currentCity": DEMO_PROFILE["currentCity"],
        "geo": DEMO_PROFILE["geo"],
        "isBot": False,
        "visible": True,
    }
    patch(f"discovery/{DEMO_UID}", discovery)
    print(f"OK perfil demo: users/{DEMO_UID} + discovery/{DEMO_UID}")


def seed_entitlement():
    """Pro activo para que el revisor vea TODAS las funciones sin comprar.

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
            "productId": "app_review_demo",
            "note": "Cuenta de revision de App Store. Concesion manual.",
        },
    )
    print(f"OK entitlement Pro: userEntitlements/{DEMO_UID}")


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
        print(f"OK like recibido de {uid}")


def seed_match(other_uid, messages):
    """Match + chat + mensajes, con el MISMO esquema que writeMatchAndChat."""
    mid = pair_id(DEMO_UID, other_uid)
    user_a, user_b = sorted([DEMO_UID, other_uid])
    users = [user_a, user_b]

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
            "lastMessageAt": STAMP,
            "realMessageCount": len(messages),
            "createdAt": STAMP,
            "updatedAt": STAMP,
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
                "createdAt": STAMP,
            },
        )
    print(f"OK match+chat con {other_uid}: {len(messages)} mensajes")


def main():
    # Si la cuenta ya completo el onboarding en la app, su perfil es real y
    # NO hay que pisarlo: bastaria con sembrar el contenido. Ademas, el
    # repositorio restaura displayName/photoUrl desde profile.* en cada login,
    # asi que sobrescribirlos aqui dejaria el perfil a medias.
    if os.environ.get("DEMO_KEEP_PROFILE", "").strip() in ("1", "true", "yes"):
        print("DEMO_KEEP_PROFILE activo: no se toca el perfil existente.")
    else:
        seed_profile()
    seed_entitlement()
    seed_received_likes()
    for other_uid, messages in MATCHED:
        seed_match(other_uid, messages)
    print(
        "\nCuenta demo lista. Recuerda:\n"
        "  - Telefono de prueba y codigo fijo dados de alta en Firebase Auth.\n"
        "  - Esos mismos datos en App Store Connect -> App Review "
        "Information.\n"
        "  - Verifica en la app: feed con perfiles, likes recibidos, chats "
        "con historial y funciones Pro visibles."
    )


if __name__ == "__main__":
    main()
