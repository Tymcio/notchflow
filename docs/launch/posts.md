# Launch posts (drafts)

Replace `{PRICE}` once the pricing decision is made, and add UTM tags to every link. Attach the 25-second video or GIF to each post. Reply to every comment for the first 6 hours.

---

## r/ClaudeAI

**Title:** I kept missing Claude Code permission prompts while in another window, so I put them in the MacBook notch

**Body:**

Long Claude Code runs kept stalling on a permission prompt while I was in the browser or another editor. I'd come back 20 minutes later to "Allow Bash: npm test?" sitting there.

So I built this into NotchFlow, a small native Mac app I've been working on: when Claude Code asks for permission, the notch pulses, you hover, read the exact command, and click Allow or Deny. It uses Claude Code's own `PermissionRequest` hook, so nothing is patched, and you can still answer in the terminal.

It also shows how much of your 5-hour and weekly limits is left (the same numbers as `/usage`) and when they reset, using the login already on your Mac. Tokens only go to Anthropic's API, nothing to me. It also shows Codex limits and Cursor's included usage if you use those.

- Native Swift, ~30 MB RAM, idle CPU near zero
- Open source (GPL-3.0): github.com/Tymcio/notchflow
- No telemetry
- The rest of the island (music, file shelf, timers, notes) is free

Download: notchflow.eu. Happy to answer questions about how the hooks work.

---

## r/cursor

**Title:** Cursor usage and agent status in the Mac notch (native, open source)

**Body:**

I wanted to see Cursor's included usage without opening settings, and to know when an agent run finishes while I'm in another app. NotchFlow now shows both in the notch: which Cursor sessions are running or done, and how much of your monthly or weekly included usage is left.

It installs monitor-only hooks in `~/.cursor/hooks.json`. They never make permission decisions, so Cursor's own Skip/Run prompts and allowlist work exactly as before. If it looks like a risky command is waiting, the notch pulses and one click takes you back to the right window.

It also does Claude Code (including approving prompts from the notch) and Codex limits. Native Swift, open source, no telemetry: github.com/Tymcio/notchflow · notchflow.eu

---

## Show HN

**Title:** Show HN: NotchFlow – approve Claude Code prompts and see agent limits from the Mac notch

**Body:**

NotchFlow is a native macOS app (Swift, AppKit + SwiftUI) that turns the area around the MacBook notch into a hover island. On Macs without a notch it shows a small capsule at the top of the screen.

The part I use most: coding agents. Claude Code's `PermissionRequest` hook posts to a local HTTP API bound to 127.0.0.1 with a bearer token. The island shows the command, and your Allow or Deny goes back to the hook. Cursor and Grok get monitor-only hooks that never answer permission prompts. Usage limits (Claude and Codex 5-hour and weekly, Cursor included usage) are read with the login already on the Mac and sent only to those vendors' APIs.

The rest is the usual notch-app set: Spotify/Music controls, file shelf, calendar, timers, notes, opt-in clipboard history, volume/brightness HUD. Raycast extension and URL scheme included.

Some details:
- GPL-3.0, no telemetry, signed and notarized, Sparkle updates with EdDSA
- No MediaRemote or other private frameworks; notifications are read through Accessibility
- Idle: ~30 MB RAM, near-zero CPU; numbers and method in docs/performance.md

Source: https://github.com/Tymcio/notchflow · Site: https://notchflow.eu

I'd especially like feedback on the hook design and on the local API's security model.

---

## Product Hunt

**Name:** NotchFlow
**Tagline (≤60):** Your coding agents and daily controls, in the Mac notch
**Topics:** Mac, Developer Tools, Productivity, Artificial Intelligence

**Description (≤260):**
Approve Claude Code prompts from the notch, see when Codex or Cursor finishes, and watch your 5-hour and weekly limits. Music, file shelf, calendar, timers and notes live in the same island. Native Swift, open source, no telemetry.

**Gallery (in order):** 1. Video. 2. Claude Code approval in the notch. 3. Usage limits. 4. Music. 5. Shelf. 6. Timers. 7. "Works on any Mac" (capsule on a notch-less display).

**Maker's first comment:**
Hi PH! I'm the solo developer behind NotchFlow. It started as a Dynamic Island for my MacBook's notch and became the place I watch my coding agents. When Claude Code stops on a permission prompt while I'm in another window, the notch tells me and I approve it there. The core island is free forever. Pro is {PRICE} one-time, no subscription, and today `LAUNCH30` takes 30% off. It's open source (GPL-3.0) if you'd like to see how the hooks and the local API work. I'd love to hear which agents or features you'd want next.

---

## r/macapps

**Title:** [Free / open source] NotchFlow – native notch island with music, shelf, timers, and coding-agent status

**Body:**

Native Swift notch app I've been building since summer. Hover the top of the screen and the island opens: Spotify/Apple Music controls, a file shelf, calendar, timer/stopwatch/Pomodoro, quick notes, opt-in clipboard history, and volume/brightness HUD. On Macs without a notch it uses a small capsule at the top.

What's different from Boring Notch, NotchNook, and others:
- It shows coding agents (Claude Code, Codex, Cursor) and can approve Claude Code prompts from the notch
- No telemetry, clipboard history off by default, local API bound to 127.0.0.1
- GPL-3.0, signed and notarized, Sparkle updates
- One-time Pro ({PRICE}), no subscription; the free tier has no time limit

Download: notchflow.eu · Source: github.com/Tymcio/notchflow · Homebrew: `brew install --cask tymcio/tap/notchflow`

Feedback on what's missing is very welcome.
