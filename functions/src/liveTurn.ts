/// FEED EN VIVO — CREDENCIALES TURN EFIMERAS.
///
/// POR QUE ESTE FICHERO EXISTE
/// ---------------------------------------------------------------------------
/// El video del vivo va peer-to-peer. Para que dos moviles se encuentren hace
/// falta ICE, y ICE tiene dos patas:
///
///   - STUN: "cual es mi IP publica y que puerto me ha abierto el router".
///     Gratis, resuelve la mayoria de los casos domesticos.
///   - TURN: un RELE que reenvia el medio. Es la UNICA salida cuando el NAT es
///     SIMETRICO (4G/5G de varias operadoras, CGNAT, wifis corporativas):
///     ahi el puerto que vio el servidor STUN NO es el que servira para el otro
///     peer, la ruta directa no existe y la llamada se queda "conectando" para
///     siempre. Es el modo de fallo mas comun de WebRTC en produccion y NO se
///     reproduce probando dos equipos en la misma wifi.
///
/// POR QUE EFIMERAS Y NO UNA CREDENCIAL FIJA
/// ---------------------------------------------------------------------------
/// Antes esto se resolvia con `--dart-define` (usuario/clave TURN compilados en
/// el binario). Una credencial estatica dentro del IPA/APK se extrae con
/// herramientas triviales, y el rele TURN se paga POR GIGABYTE de video: quien
/// la saque tiene un proxy gratis a nuestra costa. Por eso el secreto vive SOLO
/// aqui y el cliente recibe un usuario/clave que caduca en horas.
///
/// EL ESQUEMA (coturn "TURN REST API", draft-uberti-behave-turn-rest-00)
/// ---------------------------------------------------------------------------
///   username   = "<caducidad_unix_segundos>:<uid>"
///   credential = base64( HMAC-SHA1( username, <secreto compartido> ) )
///
/// El servidor TURN NO consulta ninguna base de datos: recalcula el mismo HMAC
/// con su copia del secreto y compara, y rechaza el username si la caducidad ya
/// paso. Por eso no hay que darle de alta usuarios ni revocarlos.
///
/// COMO SE ACTIVA (sin desplegar codigo: son variables de entorno)
/// ---------------------------------------------------------------------------
/// En `functions/.env` (mismo mecanismo que GOOGLE_PLACES_API_KEY / Spotify):
///
///   LIVE_TURN_SECRET=<el mismo valor que `static-auth-secret` en coturn>
///   LIVE_TURN_URLS=turn:turn.attra.app:3478?transport=udp,turns:turn.attra.app:5349?transport=tcp
///   LIVE_TURN_TTL_SECONDS=7200        # opcional; se recorta a [1 h, 4 h]
///
/// Formato de las URL: `turn:` o `turns:` + host + puerto (+ `?transport=`).
/// Conviene publicar al menos UDP 3478 y TLS 5349/tcp: las redes corporativas
/// que mas necesitan el rele son justo las que solo dejan salir por 443/TLS.
///
/// QUE PROVEEDOR ENCAJA
/// ---------------------------------------------------------------------------
///   - coturn propio (una VM pequena) con `use-auth-secret` +
///     `static-auth-secret=<X>`: es LA implementacion de referencia de este
///     esquema y con la que esta escrito este fichero.
///   - Cualquier TURN gestionado que anuncie soporte del "TURN REST API"
///     (Xirsys, Metered y similares) sirve tal cual: solo cambian URLs+secreto.
///   - Twilio NTS y Cloudflare emiten las credenciales por su PROPIA API HTTP,
///     no con este HMAC. Si se contrata uno de esos, se sustituye el cuerpo de
///     `getLiveTurnCredentials` por la llamada a su API: el contrato con el
///     cliente (`iceServers` + `ttlSeconds`) NO cambia.
///
/// CONTROL DE COSTE: el TTL corto y la puerta de `assertLiveNotBlocked` limitan
/// el reparto, pero el tope REAL de gasto se pone en el propio coturn
/// (`user-quota`, `total-quota`, `max-bps`). No lo puede poner esta funcion.
///
/// DEGRADACION: si no hay secreto/URLs configurados esta funcion NO falla:
/// devuelve `configured:false` y el cliente sigue con STUN a secas. Asi el vivo
/// funciona HOY sin TURN contratado, con el porcentaje de llamadas fallidas que
/// eso implica, y activarlo es rellenar dos variables.
import { onCall } from "firebase-functions/v2/https";
import { createHmac } from "node:crypto";
import { REGION } from "./firebase";
import { requireAuthUid } from "./common";
import { assertLiveNotBlocked } from "./liveModeration";

/// Nombres de las variables de entorno. Se exportan para que el mensaje de
/// aviso y los tests no los repitan como literales sueltos.
export const LIVE_TURN_SECRET_ENV = "LIVE_TURN_SECRET";
export const LIVE_TURN_URLS_ENV = "LIVE_TURN_URLS";
export const LIVE_TURN_TTL_ENV = "LIVE_TURN_TTL_SECONDS";

/// TTL por defecto y limites duros.
///
/// Por debajo de 1 h el movil pediria credenciales varias veces por sesion de
/// espera en cola; por encima de 4 h una credencial filtrada (log, captura de
/// trafico de un cliente comprometido) valdria demasiado tiempo. La caducidad
/// se comprueba al AUTENTICAR: una llamada ya establecida no se corta cuando
/// vence, asi que no hace falta margen para la duracion de la sesion.
export const LIVE_TURN_DEFAULT_TTL_SECONDS = 2 * 60 * 60;
export const LIVE_TURN_MIN_TTL_SECONDS = 60 * 60;
export const LIVE_TURN_MAX_TTL_SECONDS = 4 * 60 * 60;

/// Tope de URLs aceptadas. WebRTC prueba TODAS las que le des durante la
/// recoleccion ICE: una lista larga alarga el establecimiento de una llamada
/// que solo dura 3 minutos.
const LIVE_TURN_MAX_URLS = 6;

/// Credencial emitida, ya lista para el cliente.
export interface LiveTurnGrant {
  urls: string[];
  username: string;
  credential: string;
  ttlSeconds: number;
  /// Caducidad en ms de epoch segun el reloj del SERVIDOR. Informativa: el
  /// cliente cachea contra su propio reloj usando `ttlSeconds` (ver el fichero
  /// hermano live_rtc_config.dart y el porque del desfase de relojes).
  expiresAtMs: number;
}

/// `uid` saneado para meterlo en el username.
///
/// coturn parte el username por el PRIMER ':' para leer la caducidad; un uid
/// con ':' o con espacios desplazaria el resto y el HMAC no validaria. Los uid
/// de Firebase son [A-Za-z0-9] de 28 caracteres, asi que esto es defensa en
/// profundidad (proveedores futuros, emulador, tests).
export function sanitizeTurnUid(uid: string): string {
  const cleaned = (uid ?? "").replace(/[^A-Za-z0-9_-]/g, "").slice(0, 64);
  return cleaned.length > 0 ? cleaned : "anon";
}

/// `"<caducidad_unix>:<uid>"`. Byte a byte lo que coturn espera.
export function turnUsername(uid: string, expiryUnixSeconds: number): string {
  return `${Math.floor(expiryUnixSeconds)}:${sanitizeTurnUid(uid)}`;
}

/// base64(HMAC-SHA1(username, secreto)).
///
/// SHA-1 no es una eleccion nuestra: es la que fija el esquema y la que
/// implementa coturn. Aqui no se usa como resumen resistente a colisiones sino
/// como MAC con clave, que sigue siendo solido para este uso.
export function turnCredential(username: string, secret: string): string {
  return createHmac("sha1", secret).update(username).digest("base64");
}

/// Lee `LIVE_TURN_URLS` (lista separada por comas) y la valida.
export function parseTurnUrls(raw: unknown): string[] {
  const text = typeof raw === "string" ? raw : "";
  const seen = new Set<string>();
  const urls: string[] = [];
  for (const chunk of text.split(",")) {
    const url = chunk.trim();
    if (!url) continue;
    // Solo turn:/turns:. Un `stun:` colado aqui llevaria usuario y clave a un
    // servidor que no los pide, y un esquema invalido hace que el constructor
    // de RTCPeerConnection lance: tiraria TODA la configuracion ICE, tambien
    // el STUN que si funcionaba.
    if (!/^turns?:[^\s]+$/i.test(url)) {
      console.warn(`[liveTurn] URL descartada por formato: ${url}`);
      continue;
    }
    if (seen.has(url)) continue;
    seen.add(url);
    urls.push(url);
    if (urls.length >= LIVE_TURN_MAX_URLS) break;
  }
  return urls;
}

/// TTL efectivo: valor configurado recortado a [1 h, 4 h]; basura -> defecto.
export function clampTurnTtlSeconds(raw: unknown): number {
  const parsed =
    typeof raw === "number" ? raw : Number.parseInt(String(raw ?? ""), 10);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return LIVE_TURN_DEFAULT_TTL_SECONDS;
  }
  return Math.min(
    LIVE_TURN_MAX_TTL_SECONDS,
    Math.max(LIVE_TURN_MIN_TTL_SECONDS, Math.floor(parsed))
  );
}

/// Genera la credencial. `nowMs` es inyectable para poder probar la caducidad
/// sin depender del reloj de la maquina que corre el test.
export function buildTurnGrant(params: {
  uid: string;
  secret: string;
  urls: string[];
  ttlSeconds?: unknown;
  nowMs?: number;
}): LiveTurnGrant {
  const ttlSeconds = clampTurnTtlSeconds(params.ttlSeconds);
  const nowMs = params.nowMs ?? Date.now();
  const expiryUnix = Math.floor(nowMs / 1000) + ttlSeconds;
  const username = turnUsername(params.uid, expiryUnix);
  return {
    urls: params.urls,
    username,
    credential: turnCredential(username, params.secret),
    ttlSeconds,
    expiresAtMs: expiryUnix * 1000,
  };
}

/// Respuesta de la callable. `configured:false` es un resultado NORMAL (aun no
/// hay rele contratado), no un error: el cliente cae a STUN a secas.
export interface LiveTurnResponse {
  configured: boolean;
  iceServers: Array<{
    urls: string[];
    username?: string;
    credential?: string;
  }>;
  ttlSeconds: number;
  expiresAtMs: number;
}

/// NOTA sobre el secreto: va por `process.env` (fichero `functions/.env`, ya
/// gitignored) igual que GOOGLE_PLACES_API_KEY y las claves de Spotify. Se
/// podria atar a Secret Manager anadiendo `secrets: [LIVE_TURN_SECRET_ENV]` a
/// las opciones de abajo, PERO entonces el deploy FALLA mientras el secreto no
/// exista, y el requisito es justo el contrario: que hoy, sin TURN contratado,
/// todo despliegue y funcione.
export const getLiveTurnCredentials = onCall(
  { region: REGION },
  async (request): Promise<LiveTurnResponse> => {
    const uid = requireAuthUid(request.auth);
    // Un sancionado por desnudos NO recibe credenciales de rele: seria
    // regalarle ancho de banda de pago a quien acabamos de expulsar. Misma
    // puerta que usa el emparejador (joinLiveQueue/findLiveMatch).
    await assertLiveNotBlocked(uid);

    const secret = (process.env[LIVE_TURN_SECRET_ENV] ?? "").trim();
    const urls = parseTurnUrls(process.env[LIVE_TURN_URLS_ENV]);

    if (!secret || urls.length === 0) {
      // Se registra a proposito en cada peticion: cuando empiecen a llegar
      // quejas de "se queda conectando", este aviso en los logs es la primera
      // pista de que el rele nunca se llego a configurar.
      console.warn(
        `[liveTurn] sin rele: define ${LIVE_TURN_SECRET_ENV} y ` +
          `${LIVE_TURN_URLS_ENV} en functions/.env. El cliente seguira solo ` +
          "con STUN y las conexiones tras NAT simetrico fallaran."
      );
      return {
        configured: false,
        iceServers: [],
        ttlSeconds: 0,
        expiresAtMs: 0,
      };
    }

    const grant = buildTurnGrant({
      uid,
      secret,
      urls,
      ttlSeconds: process.env[LIVE_TURN_TTL_ENV],
    });

    // Se devuelve UNA entrada con todas las URLs (mismo usuario/clave para
    // todas): es como lo espera `RTCIceServer` y evita repetir la credencial.
    // El STUN NO viaja aqui: el cliente lo lleva de constante para que un fallo
    // de esta llamada no lo deje sin ICE ninguno.
    return {
      configured: true,
      iceServers: [
        {
          urls: grant.urls,
          username: grant.username,
          credential: grant.credential,
        },
      ],
      ttlSeconds: grant.ttlSeconds,
      expiresAtMs: grant.expiresAtMs,
    };
  }
);
