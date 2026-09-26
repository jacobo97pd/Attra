import { DocumentData } from "firebase-admin/firestore";

/// FICHA DE PERFIL POR UID: `profileCards/{uid}`, separada del listado del feed.
///
/// QUE FALLABA: `discovery/{uid}` hacia dos trabajos a la vez. Era el listado
/// del feed y tambien la UNICA ficha publica de un usuario real, porque
/// `users/{uid}` solo lo lee su dueno. Ocultar el perfil, pausar la cuenta, no
/// salir en recomendaciones o el incognito de pago BORRABAN esa ficha. Sus
/// matches y las personas a las que habia dado like pasaban a ver "Alguien" sin
/// foto y "No se pudo cargar el perfil". El incognito ("Solo te ven las
/// personas a las que tu has dado like") le escondia justo de esas personas, y
/// no podian saber quien era para devolverle el like.
///
/// Ahora hay dos documentos, los dos escritos SOLO por el backend:
///   - `discovery/{uid}`: el listado, SOLO para quien sale en el feed (igual
///     que antes). Las versiones antiguas de la app leen discovery sin filtro,
///     asi que un perfil oculto no puede volver ahi.
///   - `profileCards/{uid}`: la ficha para verle por uid, para TODO usuario
///     publicable (ver [cardBlocker]), este o no en el feed. Las reglas solo
///     dejan leerla al dueno, a sus matches activos y a las personas a las que
///     el dueno dio like (firestore.rules). Nunca lleva coordenadas.
export const PROFILE_CARDS_COLLECTION = "profileCards";

/// Edad minima para publicar a alguien, en el feed o en su ficha.
export const MIN_PUBLIC_AGE = 18;

/// Por que un usuario NO tiene ficha publica (ni ficha ni listado).
export type CardBlocker =
  | "incomplete"
  | "bot"
  | "banned"
  | "deleted"
  | "no_birth_date"
  | "underage";

function asMap(value: unknown): DocumentData {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as DocumentData)
    : {};
}

/// Milisegundos de una fecha de nacimiento: Timestamp del onboarding, Date,
/// cualquier objeto con toMillis/toDate o texto ISO. null si no se entiende.
function birthDateMillis(value: unknown): number | null {
  if (value instanceof Date) {
    const ms = value.getTime();
    return Number.isFinite(ms) ? ms : null;
  }
  if (value && typeof value === "object") {
    const maybe = value as { toMillis?: unknown; toDate?: unknown };
    if (typeof maybe.toMillis === "function") {
      const ms = (maybe.toMillis as () => unknown)();
      return typeof ms === "number" && Number.isFinite(ms) ? ms : null;
    }
    if (typeof maybe.toDate === "function") {
      const date = (maybe.toDate as () => unknown)();
      return date instanceof Date && Number.isFinite(date.getTime())
        ? date.getTime()
        : null;
    }
    return null;
  }
  if (typeof value === "string" && value.trim().length > 0) {
    const ms = Date.parse(value.trim());
    return Number.isFinite(ms) ? ms : null;
  }
  return null;
}

/// Edad cumplida en [nowMs] (calendario UTC, como live.ts y voiceProfile.ts).
/// null si no hay fecha valida, si es futura o si da mas de 120 anos.
export function ageFromBirthDateAt(
  value: unknown,
  nowMs: number = Date.now()
): number | null {
  const ms = birthDateMillis(value);
  if (ms === null) return null;
  const birth = new Date(ms);
  const now = new Date(nowMs);
  let age = now.getUTCFullYear() - birth.getUTCFullYear();
  const birthdayPassed =
    now.getUTCMonth() > birth.getUTCMonth() ||
    (now.getUTCMonth() === birth.getUTCMonth() &&
      now.getUTCDate() >= birth.getUTCDate());
  if (!birthdayPassed) age -= 1;
  if (age < 0 || age > 120) return null;
  return age;
}

/// Motivo por el que [data] (users/{uid}) NO puede tener ficha publica, o null
/// si puede. Es la puerta comun de la ficha y del listado del feed:
///   - onboarding y perfil completos; nunca bots;
///   - `isBanned`/`isDeleted`: la moderacion y el borrado lo retiran todo;
///   - 18+ (D06): la edad solo se comprobaba en el onboarding del cliente, asi
///     que un cliente modificado o una escritura REST publicaba a un menor. Se
///     mira la FECHA DE NACIMIENTO, no `profile.age` (se podia declarar 25 con
///     una fecha de 16). Sin fecha valida no se publica: los dos onboardings
///     (formulario y voz) la exigen, y si bastara con borrarla la puerta no
///     serviria de nada.
export function cardBlocker(
  data: DocumentData | undefined,
  nowMs: number = Date.now()
): CardBlocker | null {
  if (!data) return "incomplete";
  if (data.onboardingCompleted !== true || data.profileCompleted !== true) {
    return "incomplete";
  }
  if (data.isBot === true) return "bot";
  if (data.isBanned === true) return "banned";
  if (data.isDeleted === true) return "deleted";
  const age = ageFromBirthDateAt(
    asMap(data.profile).birthDate ?? data.birthDate,
    nowMs
  );
  if (age === null) return "no_birth_date";
  if (age < MIN_PUBLIC_AGE) return "underage";
  return null;
}

/// La ficha por uid a partir del documento de listado ya construido
/// (`buildDiscoveryDoc`): misma forma, para que el cliente la lea con el mismo
/// parser, pero sin lo que solo sirve para el feed:
///   - `geo` (ni aproximado): quien te ve por uid no necesita tu posicion;
///   - `filterTraits`: rasgos sensibles que el usuario solo cedio para FILTRAR,
///     no para ensenarlos en su perfil;
///   - `preferredAgeMin/Max`: el rango de edad que BUSCA solo sirve para
///     emparejar en el feed (la reciprocidad de edad). En la ficha lo leian sus
///     matches y cualquiera a quien diera like, tambien si estaba oculto o en
///     incognito, y la app no lo pinta en ninguna parte.
/// Con incognito de pago activo tampoco lleva ubicacion ni actividad: el ajuste
/// promete "Oculta tu ubicacion y tu estado de actividad", y antes, sin ficha
/// alguna, no se veia nada de eso. Eso incluye `updatedAt`: es un
/// serverTimestamp que cambia con CADA escritura de users/{uid} (el
/// lastLoginAt y el token push de cada arranque), asi que leido en crudo decia
/// cuando habia abierto la app por ultima vez. La app no lo lee de la ficha.
export function profileCardFrom(
  listing: DocumentData,
  opts: { incognito: boolean }
): DocumentData {
  const card: DocumentData = { ...listing };
  delete card.geo;
  delete card.filterTraits;
  delete card.preferredAgeMin;
  delete card.preferredAgeMax;
  if (opts.incognito) {
    card.currentCity = "";
    card.currentCountryName = "";
    card.traveling = false;
    delete card.countryIso2;
    delete card.travelUntil;
    card.showDistance = false;
    card.showActiveStatus = false;
    delete card.updatedAt;
  }
  return card;
}
