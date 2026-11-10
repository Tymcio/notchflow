# Plan launchu NotchFlow

Cel: pierwsze 1 000 instalacji i 30–50 płacących klientów w 6 tygodni, z mierzalnym źródłem każdego z nich.

## Zanim cokolwiek opublikujesz

- [ ] **Napraw checkout.** Wszystkie przyciski prowadzą dziś do Premium Annual (patrz `docs/pricing-proposal.md`).
- [ ] Wydanie z obsługą Maców bez notcha (rozszerza rynek o Mac mini, Studio, iMaca, MacBooka Neo i MacBooka Pro z Dynamic Island).
- [ ] **Wideo 20–30 s** (scenariusz niżej) jako `website/assets/hero.mp4`, GIF do README i wszystkich postów.
- [ ] Screenshot karty Agents (zatwierdzanie i limity) do galerii na stronie i do Product Hunt.
- [ ] Homebrew tap (`packaging/homebrew/README.md`) i linia `brew tap tymcio/tap && brew trust --cask tymcio/tap/notchflow && brew install --cask notchflow` obok przycisku pobierania.
- [ ] UTM-y w linkach z każdego kanału (`?utm_source=reddit&utm_campaign=launch`), żeby w GA i Polar było widać, skąd przyszli klienci.
- [ ] Kod `LAUNCH30` w Polar.

## Kolejność (jeden kanał na 2–3 dni, żeby odpowiadać na komentarze)

| Dzień | Kanał | Plik | Uwagi |
|-------|-------|------|-------|
| 1 | r/ClaudeAI | `posts.md` | Największa grupa docelowa. Post o problemie (prompt czeka, gdy jesteś w innym oknie), nie o aplikacji |
| 3 | r/cursor | `posts.md` | Akcent na wykorzystanie Cursora w notchu |
| 5 | Show HN | `posts.md` | Wtorek–czwartek, 15:00–17:00 czasu PL. Akcent: open source, lokalne API, brak telemetrii |
| 8 | Product Hunt | `posts.md` | Start 09:01 czasu PL (00:01 PT). Poproś wcześniej 10–20 osób o feedback, nie o upvote |
| 10 | r/macapps | `posts.md` | Wymaga karmy w suba; inaczej post trafia do miesięcznego wątku. Raz na 30 dni |
| 12 | Prasa DE/PL | `press.md` | ifun.de, appgefahren.de, Mac Life, iMagazine.pl, MyApple.pl |
| 14+ | YouTube / X | `press.md` | Twórcy o produktywności na Macu i o Claude Code; darmowa licencja Pro w zamian za szczerą recenzję |

Stałe kanały w tle: Homebrew tap, rozszerzenie Raycast w Raycast Store (darmowe, dla zasięgu), strony porównawcze na stronie (SEO: „NotchNook alternative”, „Claude Code notch”, „Claude Code usage limit Mac”).

## Czego nie robić

- Nie wrzucać tego samego tekstu do wielu subów w jeden dzień (filtr spamu i bany).
- Nie prosić o upvote na Product Hunt ani HN (kara w rankingu).
- Nie obiecywać zatwierdzania dla Cursora i Codexa: działa tylko dla Claude Code. Cursor i Grok mają status, Codex i inne przez skrypt powiadomień.

## Scenariusz wideo (25 s, bez dźwięku, z napisami)

1. (0–4 s) Edytor na pełnym ekranie, terminal z Claude Code schowany. Napis: „Claude Code is waiting for you. You're in another window.”
2. (4–9 s) Notch pulsuje. Kursor najeżdża, wyspa rozwija się z prośbą „Bash: npm test”. Klik **Allow**.
3. (9–14 s) Wyspa pokazuje „Running”, potem limity: Claude 5h 62% left, weekly 80% left; Cursor included usage.
4. (14–20 s) Szybkie przełączenie kart: muzyka, półka (przeciągnięcie pliku), minutnik.
5. (20–25 s) Logo + „Free on notchflow.eu · Homebrew: tymcio/tap”.

Nagrywaj w 2× (Retina), eksport 1920×1080 MP4 H.264 < 4 MB na stronę i GIF < 8 MB do README.

## Mierniki po 6 tygodniach

- Instalacje: pobrania DMG (GitHub) + instalacje brew (tap nie ma statystyk; pobrania z GitHuba je obejmują).
- Konwersja: zamówienia w Polar / pobrania. Cel 3%.
- Kanał: UTM w GA (po zgodzie) i pole „Skąd o nas wiesz?” w Polar checkout (custom field).
