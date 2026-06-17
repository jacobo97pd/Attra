import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

/// Inicializacion del Admin SDK apuntando a la base con NOMBRE attra-database
/// (NO la default). El Admin SDK bypassa las reglas de seguridad: estas
/// funciones son la unica via autorizada para escribir matches/chats/saldo.
const app = initializeApp();

export const db = getFirestore(app, "attra-database");

/// Region europea por defecto (latencia + residencia de datos UE / RGPD).
export const REGION = "europe-west1";

/// Bucket de Storage (naming nuevo .firebasestorage.app). Se referencia
/// explicitamente porque el Admin SDK se inicializa sin storageBucket.
export const STORAGE_BUCKET = "attra-database.firebasestorage.app";
