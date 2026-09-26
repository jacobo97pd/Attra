import { X509Certificate, createHash, verify as verifySignature } from "node:crypto";

/// Verificacion de lo que firma la App Store (StoreKit 2) SIN credenciales.
///
/// Todo lo que manda la app en iOS es un JWS (`jwsRepresentation`): el plugin
/// `in_app_purchase_storekit` usa StoreKit 2 desde la primera version que se
/// publico (0.4.10) y la app nunca llama a `enableStoreKit1()`. Ese JWS lleva en
/// su cabecera la cadena de certificados (`x5c`) con la que Apple lo firmo, asi
/// que se puede comprobar aqui mismo, sin llamar a Apple y sin claves: basta con
/// fijar la raiz de Apple y seguir la cadena. Es lo mismo que hace la libreria
/// oficial `app-store-server-library` en modo offline.
///
/// Lo mismo sirve para las App Store Server Notifications V2: su
/// `signedPayload` es un JWS con la misma cadena.

/// Apple Root CA - G3, en DER (base64). Descargado de
/// https://www.apple.com/certificateauthority/AppleRootCA-G3.cer
/// SHA-256: 63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79
/// Caduca el 30-abr-2039. Es publico: no es un secreto, es el ancla de confianza.
export const APPLE_ROOT_CA_G3_BASE64 =
  "MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBD" +
  "QSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBw" +
  "bGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYD" +
  "VQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9y" +
  "aXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IA" +
  "BJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA" +
  "/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4ia" +
  "pIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gA" +
  "MGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK" +
  "1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA==";

export const APPLE_ROOT_CA_G3_SHA256 =
  "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179";

/// Bundle de la app. Un JWS autentico de OTRA app (firmado por Apple igual) no
/// puede conceder nada aqui.
export const APPLE_BUNDLE_ID =
  process.env.APPLE_BUNDLE_ID?.trim() || "com.jpedrero.attra";

/// Extensiones que Apple pone en SUS certificados de StoreKit. Sin comprobarlas,
/// cualquier certificado emitido bajo la raiz de Apple (hay muchos: developer
/// ID, push...) serviria para firmar un "recibo" falso. Son los mismos OID que
/// comprueba la libreria oficial.
///   hoja:       1.2.840.113635.100.6.11.1
///   intermedio: 1.2.840.113635.100.6.2.1
const OID_STOREKIT_LEAF = Buffer.from("060a2a864886f76364060b01", "hex");
const OID_WWDR_INTERMEDIATE = Buffer.from("060a2a864886f76364060201", "hex");

export type AppleJwsErrorCode =
  | "malformed"
  | "untrusted_chain"
  | "bad_signature"
  | "cert_not_valid_at_date";

export class AppleJwsError extends Error {
  constructor(readonly code: AppleJwsErrorCode, message: string) {
    super(message);
    this.name = "AppleJwsError";
  }
}

export interface AppleJwsOptions {
  /// Raices de confianza en DER. Solo los tests pasan otra cosa: en produccion
  /// es SIEMPRE la de Apple.
  trustedRootsDer?: Buffer[];
}

function base64UrlDecode(part: string): Buffer {
  if (!/^[A-Za-z0-9_-]*$/.test(part)) {
    throw new AppleJwsError("malformed", "JWS con caracteres no validos.");
  }
  return Buffer.from(part, "base64url");
}

function parseJsonPart(part: string, what: string): Record<string, unknown> {
  try {
    const parsed = JSON.parse(base64UrlDecode(part).toString("utf8"));
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      return parsed as Record<string, unknown>;
    }
  } catch (error) {
    if (error instanceof AppleJwsError) throw error;
  }
  throw new AppleJwsError("malformed", `El ${what} del JWS no es JSON valido.`);
}

/// True si el texto TIENE forma de JWS compacto (tres trozos base64url). No
/// dice nada de si es autentico: eso lo decide [verifyAppleSignedPayload].
export function looksLikeJws(value: string): boolean {
  return /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(value.trim());
}

function certValidAt(cert: X509Certificate, atMs: number): boolean {
  const from = Date.parse(cert.validFrom);
  const to = Date.parse(cert.validTo);
  if (Number.isNaN(from) || Number.isNaN(to)) return false;
  return atMs >= from && atMs <= to;
}

function toCert(b64: unknown): X509Certificate {
  if (typeof b64 !== "string" || b64.length === 0) {
    throw new AppleJwsError("malformed", "x5c con un certificado vacio.");
  }
  try {
    return new X509Certificate(Buffer.from(b64, "base64"));
  } catch {
    throw new AppleJwsError("malformed", "x5c con un certificado ilegible.");
  }
}

/// Verifica un JWS firmado por la App Store y devuelve su payload.
///
/// Comprueba, por orden: forma, `alg` ES256, cadena `x5c` de tres certificados
/// cuya raiz es EXACTAMENTE la fijada (no basta con que "parezca" de Apple),
/// que cada eslabon firma al siguiente, los OID de Apple, la firma del JWS con
/// la clave de la hoja y que los certificados fueran validos en `signedDate`
/// (igual que la libreria oficial sin comprobaciones online).
///
/// Lanza [AppleJwsError]; nunca devuelve un payload sin verificar.
export function verifyAppleSignedPayload(
  jws: string,
  options: AppleJwsOptions = {}
): Record<string, unknown> {
  const parts = (jws ?? "").trim().split(".");
  if (parts.length !== 3 || parts.some((p) => p.length === 0)) {
    throw new AppleJwsError("malformed", "No es un JWS compacto.");
  }
  const [headerPart, payloadPart, signaturePart] = parts;
  const header = parseJsonPart(headerPart, "header");
  if (header.alg !== "ES256") {
    throw new AppleJwsError("malformed", `alg no admitido: ${String(header.alg)}`);
  }
  const x5c = header.x5c;
  if (!Array.isArray(x5c) || x5c.length !== 3) {
    throw new AppleJwsError("malformed", "x5c debe traer hoja, intermedio y raiz.");
  }
  const [leaf, intermediate, root] = x5c.map(toCert);

  const trustedRoots = options.trustedRootsDer ?? [
    Buffer.from(APPLE_ROOT_CA_G3_BASE64, "base64"),
  ];
  // La raiz que trae el JWS tiene que ser BYTE A BYTE la fijada. Comparar el
  // nombre o la clave publica dejaria pasar una raiz fabricada con los mismos
  // datos.
  if (!trustedRoots.some((der) => der.equals(root.raw))) {
    throw new AppleJwsError("untrusted_chain", "La raiz no es la de Apple.");
  }
  const chainOk =
    leaf.checkIssued(intermediate) &&
    intermediate.checkIssued(root) &&
    leaf.verify(intermediate.publicKey) &&
    intermediate.verify(root.publicKey);
  if (!chainOk) {
    throw new AppleJwsError("untrusted_chain", "La cadena x5c no encadena.");
  }
  if (!intermediate.ca) {
    throw new AppleJwsError("untrusted_chain", "El intermedio no es una CA.");
  }
  if (!leaf.raw.includes(OID_STOREKIT_LEAF)) {
    throw new AppleJwsError(
      "untrusted_chain",
      "La hoja no es un certificado de firma de StoreKit."
    );
  }
  if (!intermediate.raw.includes(OID_WWDR_INTERMEDIATE)) {
    throw new AppleJwsError(
      "untrusted_chain",
      "El intermedio no es el WWDR de Apple."
    );
  }

  const signature = base64UrlDecode(signaturePart);
  const signed = verifySignature(
    "sha256",
    Buffer.from(`${headerPart}.${payloadPart}`, "utf8"),
    { key: leaf.publicKey, dsaEncoding: "ieee-p1363" },
    signature
  );
  if (!signed) {
    throw new AppleJwsError("bad_signature", "La firma del JWS no es valida.");
  }

  const payload = parseJsonPart(payloadPart, "payload");
  // Fecha efectiva: la de firma (ya autenticada). Sin ella, ahora.
  const signedDate =
    typeof payload.signedDate === "number" ? payload.signedDate : Date.now();
  if (![leaf, intermediate, root].every((c) => certValidAt(c, signedDate))) {
    throw new AppleJwsError(
      "cert_not_valid_at_date",
      "Algun certificado no era valido cuando se firmo."
    );
  }
  return payload;
}

/// Transaccion de la App Store ya verificada, con lo que usa el backend.
export interface AppleTransaction {
  transactionId: string;
  originalTransactionId: string;
  bundleId: string;
  productId: string;
  /// 'Production' | 'Sandbox' (App Review compra en Sandbox).
  environment: string;
  type: string;
  purchaseDateMs: number | null;
  expiresDateMs: number | null;
  revocationDateMs: number | null;
  isUpgraded: boolean;
  quantity: number;
}

function str(value: unknown): string {
  if (typeof value === "string") return value.trim();
  if (typeof value === "number" && Number.isFinite(value)) return String(value);
  return "";
}

function msOrNull(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

/// Traduce el payload (ya verificado) de `JWSTransactionDecodedPayload`.
export function parseAppleTransaction(
  payload: Record<string, unknown>
): AppleTransaction {
  const transactionId = str(payload.transactionId);
  const productId = str(payload.productId);
  if (!transactionId || !productId) {
    throw new AppleJwsError(
      "malformed",
      "La transaccion no trae transactionId o productId."
    );
  }
  const quantity =
    typeof payload.quantity === "number" && payload.quantity >= 1
      ? Math.floor(payload.quantity)
      : 1;
  return {
    transactionId,
    originalTransactionId: str(payload.originalTransactionId) || transactionId,
    bundleId: str(payload.bundleId),
    productId,
    environment: str(payload.environment),
    type: str(payload.type),
    purchaseDateMs: msOrNull(payload.purchaseDate),
    expiresDateMs: msOrNull(payload.expiresDate),
    revocationDateMs: msOrNull(payload.revocationDate),
    isUpgraded: payload.isUpgraded === true,
    quantity,
  };
}

/// Huella SHA-256 (hex) de un DER. Solo para diagnostico y tests.
export function sha256Hex(der: Buffer): string {
  return createHash("sha256").update(der).digest("hex");
}
