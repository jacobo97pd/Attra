/// Punto de entrada de las Cloud Functions de Attra.
///
/// Todas son callable (onCall) con region europe-west1 y usan el Admin SDK
/// contra la base con NOMBRE attra-database. El cliente jamas escribe
/// matches/chats/saldo directamente: pasa por aqui.
import { setGlobalOptions } from "firebase-functions/v2";

// El proyecto tiene muchas Functions v2 en la misma region y el deploy chocaba
// con la cuota regional de CPU de Cloud Run. La palanca que lo arregla es
// `cpu: "gcf_gen1"` (CPU fraccionada, como en gen1), y con CPU < 1 Cloud Run
// EXIGE concurrency 1: por eso van juntos.
//
// `maxInstances` SI cuenta para la cuota: `CpuAllocPerProjectRegion` se calcula
// sobre el TECHO de instancias declarado, no sobre el uso real, y con ~95
// funciones en la region el numero se multiplica muy rapido (con 40 pedimos
// 23320 de 20000 permitidos y fallaron tres funciones).
//
// Pero 2 era pasarse de frenada en el otro sentido: con concurrency 1, cada
// funcion atendia como mucho DOS peticiones a la vez (sendLike, verifyPurchase,
// los chats...), asi que con cuatro usuarios simultaneos ya se encolaba.
//
// 15 es el punto medio: 7 veces mas capacidad que antes y entra en la cuota con
// margen para que reviewLiveFrame tenga el suyo propio (ver liveModeration.ts).
// Si algun dia hace falta mas, se pide ampliacion de cuota de la region; subir
// este numero a ciegas rompe el deploy.
setGlobalOptions({
  region: "europe-west1",
  memory: "256MiB",
  cpu: "gcf_gen1",
  concurrency: 1,
  maxInstances: 15,
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
  closeConversationGracefully,
} from "./chat";
export {
  sendPendingReplyNudges,
  answerDateFollowUp,
  recomputeReliabilityScores,
} from "./antiGhosting";
export { unmatch, blockUser, reportUser } from "./safety";
export { grantMonthlyAttras, runMonthlyAttraGrant } from "./grants";
export { onUserWrittenSyncDiscovery, backfillDiscovery } from "./discovery";
export { spotifyConnect, spotifyRefresh, spotifyDisconnect } from "./spotify";
export {
  analyzeReferencePhoto,
  getProfileInsights,
  getVisualMatches,
  getPromptMatches,
  clearAiData,
} from "./ai";
export {
  generateProfileFromVoice,
  sweepExpiredVoiceProfileAudio,
} from "./voiceProfile";
export {
  createStory,
  viewStory,
  replyToStory,
  deleteStory,
  cleanupExpiredStories,
} from "./stories";
export { completeSparkSession, sweepSparkSessions } from "./spark";
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
export {
  createDatePlanProposal,
  generateDatePlanSuggestions,
  voteDatePlan,
} from "./datePlans";
export {
  createFriendGroup,
  requestJoinGroup,
  respondJoinRequest,
  leaveFriendGroup,
  closeFriendGroup,
  setFriendGroupPhoto,
} from "./friendGroups";
export {
  saveTrustedContact,
  deleteTrustedContact,
  createSafeDatePlan,
  setSafeDatePlanStatus,
  respondCheckIn,
  safeDateCheckinSweep,
  startLiveLocation,
  updateLiveLocation,
  stopLiveLocation,
  sendSafeDateAlert,
  safeDateLiveLocationSweep,
  submitPostDateReview,
  analyzeConversationRisk,
} from "./safedate";
export { grantConsumable } from "./consumables";
export { verifyPurchase } from "./subscriptions";
export {
  startChatGame,
  respondChatGame,
  finishChatGame,
  abandonChatGame,
  // Barridos por VENCIMIENTO. Sin exportarlos aqui no se despliegan y las
  // sesiones se quedan 'active' para siempre: el veredicto de la IA no llega
  // nunca y el par no puede volver a jugar.
  sweepChatGames,
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
  productMetricsOnEvent,
  productMetricsFinalize,
} from "./productMetrics";
// FEED EN VIVO — moderacion del video 1:1. El video va peer-to-peer y el
// servidor NO lo ve: cada cliente modera el flujo que RECIBE y lo manda aqui.
// Sin estos exports no se despliega nada de moderacion y el vivo NO es
// publicable.
export { reviewLiveFrame, getLiveStrikeStatus } from "./liveModeration";
// FEED EN VIVO — cola, emparejamiento, sesion y veredictos (la moderacion va
// arriba, en liveModeration.ts).
export {
  joinLiveQueue,
  leaveLiveQueue,
  findLiveMatch,
  startLiveSession,
  submitLiveVerdict,
  endLiveSession,
  // Barrido por VENCIMIENTO del feed en vivo. Sin exportarlo aqui no se
  // despliega: las sesiones se quedarian 'active' para siempre y las entradas
  // de cola 'paired' impedirian volver a emparejar (mismo fallo que ya paso
  // con sweepChatGames).
  sweepLiveSessions,
} from "./live";
// FEED EN VIVO — credenciales TURN EFIMERAS (rele para NAT simetrico). Sin
// exportarla, el cliente recibe 'not-found' en cada intento, se queda solo con
// STUN y las llamadas tras NAT simetrico (4G/5G, CGNAT, wifis corporativas) no
// conectan NUNCA. Ver liveTurn.ts para las variables de entorno que la activan.
export { getLiveTurnCredentials } from "./liveTurn";
export {
  onLikeCreated,
  onMatchCreated,
  onMessageCreated,
  onSparkSessionCreated,
  sendComeBackNotifications,
  registerPushToken,
  unregisterPushToken,
} from "./notifications";
