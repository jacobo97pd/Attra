/// App Store validation experience switch (branch `apple-validation`).
///
/// When `true`, the app boots into a **plan-first** experience: the primary
/// tabs are **Inicio · Planes · Personas · Chats · Perfil**. The first screen
/// (Inicio) surfaces plans, groups and people around shared interests instead
/// of a full-screen swipe. The existing dating mechanics (feed, likes, matches,
/// chats, subscriptions, visual AI, profile, monetization) remain fully
/// available: the feed lives under **Personas**, and SafeDate is reachable from
/// the shield in the Inicio top bar.
///
/// This is a REAL user-facing experience — it is NOT reviewer-only, does not
/// detect Apple reviewers, and hides no functionality. It only reorders and
/// reframes what the user sees first, so Attra no longer reads as "swipe-first".
/// The main navigation no longer reads this flag. It stays enabled to preserve
/// the guided AI challenge/coach/date-planner affordances already in chats.
const bool kAppStoreValidationExperience = true;
