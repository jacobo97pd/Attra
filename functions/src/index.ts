/// Punto de entrada de las Cloud Functions de Attra.
///
/// Todas son callable (onCall) con region europe-west1 y usan el Admin SDK
/// contra la base con NOMBRE attra-database. El cliente jamas escribe
/// matches/chats/saldo directamente: pasa por aqui.
import { setGlobalOptions } from "firebase-functions/v2";

// El proyecto tiene muchas Functions v2 en la misma region. Con los defaults
// actuales cada servicio Cloud Run reserva mas CPU y el deploy puede chocar con
// la cuota regional. Estos defaults son conservadores para MVP y reducen la
// presion de cuota sin cambiar la API publica de las funciones.
setGlobalOptions({
  region: "europe-west1",
  memory: "256MiB",
  cpu: "gcf_gen1",
  concurrency: 1,
  maxInstances: 2,
});

export { sendLike, passProfile } from "./likes";
export { sendAttra } from "./attras";
export { rewindFeedAction } from "./rewind";
export {
  sendMessage,
  sendMediaMessage,
  markMessagesAsRead,
  markChatAsUnread,
  setTyping,
  openBombImage,
  sendDateProposal,
  respondDateProposal,
} from "./chat";
export { unmatch, blockUser, reportUser } from "./safety";
export { grantMonthlyAttras, runMonthlyAttraGrant } from "./grants";
export { onUserWrittenSyncDiscovery, backfillDiscovery } from "./discovery";
export { spotifyConnect, spotifyRefresh, spotifyDisconnect } from "./spotify";
export {
  analyzeReferencePhoto,
  getProfileInsights,
  getVisualMatches,
  clearAiData,
} from "./ai";
export {
  createStory,
  viewStory,
  replyToStory,
  deleteStory,
  cleanupExpiredStories,
} from "./stories";
export { completeSparkSession } from "./spark";
export {
  startDoubleAnswer,
  submitDoubleAnswer,
  startTwoTruths,
  guessTwoTruths,
} from "./journey_games";
export {
  activateBoost,
  expireBoosts,
  getActiveBoostForUser,
  getBoostSummary,
  recordBoostImpression,
} from "./boosts";
export { grantConsumable } from "./consumables";
export { verifyPurchase } from "./subscriptions";
export {
  startChatGame,
  respondChatGame,
  finishChatGame,
  abandonChatGame,
} from "./chatGame";
export {
  rankingOnLike,
  rankingOnMatch,
  rankingOnMessage,
  rankingOnReport,
  rankingOnBlock,
  rankingOnGameSession,
  rankingNightly,
} from "./ranking";
export {
  onLikeCreated,
  onMatchCreated,
  onMessageCreated,
  sendComeBackNotifications,
  registerPushToken,
  unregisterPushToken,
} from "./notifications";
