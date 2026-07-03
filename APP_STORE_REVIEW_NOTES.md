# Attra — App Store Review Notes

## Summary: how this build addresses Guideline 4.3(b)

Attra has been repositioned so that the **first screen and primary experience is
an AI-powered connection product**, not a generic swipe app. On launch, users
land on the **Attra Connection Lab**, which leads with guided conversations,
anti-ghosting coaching, compatibility insights, conversation games and date
planning. Swiping/discovery still exists, but it is now **one tab among five**
(“Discover”), not the whole app.

The unique, non-templated value is immediately testable — even by a reviewer
with no matches — via the **Demo Challenge**, which runs the AI-guided
conversation flow end to end without requiring another user.

No functionality was removed. The existing dating mechanics (feed, likes, super
likes/Attras, boosts, matches, chats, subscriptions, visual AI, profile,
monetization) remain fully available under **Discover** and **Messages**.

This is a **real, user-facing experience**. It does not detect reviewers, has no
hidden “review mode”, and hides no features. It is controlled by a single build
flag: `lib/core/config/app_store_validation_config.dart`
(`const bool kAppStoreValidationExperience = true;`).

## What makes Attra different (unique features)

- **AI-guided conversation challenges** — prompts + real-time feedback (energy
  score, follow-up suggestion, suggested next message / date idea).
- **Demo / Practice Challenge** — try the full AI flow with no match required.
- **Anti-Ghosting Coach** — conversation balance, reply momentum, interest
  signal and a suggested healthy next action. Never auto-sends anything.
- **AI Compatibility Insights** — not just a percentage: 3–5 human reasons
  (communication style, date preferences, humor, lifestyle, response balance).
- **AI Date Planner** — 3 low-pressure first-date ideas + a ready-to-send
  proposal message, available from the Lab and inside a chat.
- **Conversation Games** — Break the Ice, Attra Spark (5-min live game),
  This or That, Two Truths & a Lie, Double Answer.
- **Every chat opens with an AI Challenge card** (Start Challenge / Suggest
  opener / Play quick game) above the normal conversation.

## Bottom navigation (this build)

`Connect` · `Play` · `Discover` · `Messages` · `Profile`

- **Connect** → Attra Connection Lab (default landing).
- **Play** → Conversation Games hub (+ Demo Challenge).
- **Discover** → existing discovery feed.
- **Messages** → existing matches/chats.
- **Profile** → existing profile.

## Suggested reviewer path

1. **Login** (Apple / Google / phone).
2. **Connection Lab** — see the AI-connection value proposition and the six
   feature cards.
3. **Demo Challenge** (Connection Lab → *Break the Ice* → answer the prompt) —
   experience the AI-guided conversation flow: prompt → your answer →
   follow-up → energy insight → suggested next message / date idea.
4. **Anti-Ghosting Coach** — see conversation-health analysis and suggested
   next action.
5. **AI Compatibility** — see the score with explained reasons.
6. **AI Date Planner** — see date ideas + a proposal message.
7. **Discover** — the existing discovery/swipe experience.
8. **Chat** — open any conversation to see the AI Challenge card at the top
   (Start Challenge / Suggest opener / Play quick game) with the normal chat
   below. The overflow menu also exposes Coach / Compatibility / Date Planner.

Nothing above requires a real match: the Demo Challenge, Coach, Compatibility
and Date Planner all work standalone with polished local logic, so the unique
AI experience is fully reviewable.

## Test credentials

> Fill these in before submitting.

- **Email / phone:** `__________`
- **Password / OTP:** `__________`
- Notes: `__________`

## Notes for the reviewer

- The AI feedback shown in the Demo Challenge uses on-device deterministic logic
  so it always works offline; the same surfaces connect to the live AI backend
  in production.
- Attra never sends a message on the user’s behalf — every suggestion is placed
  in the input for the user to review, edit and send.
