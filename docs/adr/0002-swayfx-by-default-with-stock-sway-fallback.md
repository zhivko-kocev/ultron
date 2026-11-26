# 2. SwayFX by default, with stock sway as the fallback

Date: 2026-11-26. Status: accepted (ultron 0.3.0).

**Context.** The owner wants the polished feel of Omarchy (rounded corners, shadows, window animations). Stock sway has none of these. SwayFX has them but is AUR-only, replaces the `sway` package, depends on a specific wlroots, and stock sway rejects its options as config errors.

**Decision.** `EFFECTS=yes` is the default for everyone. The `desktop` step builds SwayFX from the AUR; `EFFECTS=no` swaps stock sway back in. The effect options live in `generated/effects.conf`, which `ultron apply` fills only when SwayFX is installed, so stock sway never sees them. When `ultron update`'s repo upgrade fails on SwayFX (a new wlroots), SwayFX is removed for stock sway, the upgrade finishes, and SwayFX is rebuilt after the AUR phase; a failed build leaves stock sway running with a warning. The session wrapper prints a way back when the desktop dies within 10 seconds of starting.

**Rejected: effects opt-in.** Most people never find the switch, so the default look is what ultron is judged by.

**Rejected: SwayFX without a fallback.** An AUR package that lags a wlroots bump would block every system update, or leave the user with no desktop.
