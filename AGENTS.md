# Echo invariants

- Schema changes ship with a migration. A newer-than-supported version is rejected. Do not only bump the version number.
- Model sentences stay unconfirmed. They never join the library or the rotation until a parent confirms them.
- Do not put child names, family recordings, API keys, or a private phrase list in the repo.
- Do not call iOS 26-only Speech APIs. Mandarin recognition stays on `SFSpeechRecognizer` with on-device recognition.
- Do not request notification permission. Do not add streaks, lives, XP, leaderboards, pronunciation scores, or locked lessons.
