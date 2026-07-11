# Materiały na stronę — screeny i wideo

Krótka checklista przed wrzuceniem nowych assetów do `website/assets/`.

## Screeny (9 modułów)

### Przygotowanie Maca

1. **Tapeta** — ustaw stonowaną, rozmytą tapetę macOS (np. domyślna Sonoma/Sequoia w jasnym lub ciemnym wariancie). Unikaj jednolitego jaskrawego koloru.
2. **Menu bar** — ukryj zbędne ikony w menu barze albo użyj czystego konta testowego.
3. **Język UI** — na razie PL na obu wersjach strony; trzymaj spójny język we wszystkich 9 ujęciach.
4. **Motyw NotchFlow** — motyw **NotchFlow** lub **Graphite** w ustawieniach wyglądu.
5. **Dane przykładowe** — sensowne treści (muzyka z okładką, 2–3 pliki na półce, notatka, 2 wpisy schowka).

### Jak robić zrzuty

| Moduł | Plik docelowy | Co pokazać |
|-------|---------------|------------|
| Muzyka | `01-music.png` | Odtwarzanie z okładką, tytuł, pasek postępu |
| Kalendarz | `02-calendar.png` | Siatka miesiąca z kilkoma wydarzeniami |
| Półka | `03-shelf.png` | Przypięte + tymczasowe pliki |
| Minutnik | `04-timer.png` | Odliczanie (nie idle) |
| Stoper | `05-stopwatch.png` | Licznik w trakcie |
| Pomodoro | `06-pomodoro.png` | Sesja pracy |
| Notatki | `07-notes.png` | Lista z treścią |
| Schowek | `08-clipboard.png` | Historia z wyszukiwaniem |
| Kamera | `09-camera.png` | Podgląd lustra |

**Sposób 1 (najprostszy):** rozwiń wyspę na wybranym module → `Cmd+Shift+4`, spacja, kliknij okno z tłem pulpitu (macOS doda cień — OK).

**Sposób 2 (najczystszy):** `Cmd+Shift+5` → „Nagraj wybrany obszar” lub screenshot z QuickTime → wybierz prostokąt: **górna krawędź ekranu + wyspa + ~80 px tła pod spodem**. Szerokość ~900–1100 px.

### Wymiary i jakość

- Szerokość **960–1100 px** (wystarczy na stronę)
- Format **PNG**
- Bez Retina ×2 — strona skaluje sama
- Kadruj **ciasno**: wyspa + odrobina tapety, bez całego ekranu

### Po wrzuceniu plików

Pliki w `screeny notchflow pl/` mogą być ponumerowane inną kolejnością niż na stronie. Mapowanie:

| Plik źródłowy | Plik na stronie |
|---------------|-----------------|
| `notchflow screeny pl 2.png` | `01-music.png` |
| `notchflow screeny pl 3.png` | `02-calendar.png` |
| `notchflow screeny pl 4.png` | `03-shelf.png` |
| `notchflow screeny pl 5.png` | `04-timer.png` |
| `notchflow screeny pl 6.png` | `05-stopwatch.png` |
| `notchflow screeny pl 7.png` | `06-pomodoro.png` |
| `notchflow screeny pl 8.png` | `07-notes.png` |
| `notchflow screeny pl 9.png` | `08-clipboard.png` |
| `notchflow screeny pl 1.png` | `09-camera.png` |

```bash
SRC="screeny notchflow pl"
DST="website/assets/screenshots"
cp "$SRC/notchflow screeny pl 2.png" "$DST/01-music.png"
# … pozostałe według tabeli

python3 website/scripts/prepare-screenshots.py   # tylko dla starych zrzutów z jaskrawym tłem
```

Skrypt `prepare-screenshots.py` jest **opcjonalny** — nie uruchamiaj go dla nowych screenów z dobrą tapetą (dodaje dolną ramkę i gradient, które psują wygląd na stronie). Wystarczy `./website/scripts/sync-screenshots.sh`.

---

## Wideo (hero / social)

### Cel

15–30 s pokazujące **flow**: najechanie na notch → rozwinięcie → 2–3 moduły → zwinięcie.

### Ustawienia nagrania

| Parametr | Wartość |
|----------|---------|
| Rozdzielczość | **1920×1080** lub **2560×1440** |
| FPS | **60** (płynne animacje wyspy) |
| Kodek | H.264 (kompatybilność) lub HEVC (mniejszy plik) |

### Narzędzia

- **QuickTime** — `Plik → Nowe nagranie ekranu` (darmowe, wystarczy na start)
- **Screen Studio** / **CleanShot X** — zoom na notch, gładkie przejścia (polecane pod landing)
- **OBS** — jeśli chcesz pełną kontrolę i eksport MP4

### Scenariusz (storyboard)

1. **0–3 s** — pulpit z muzyką w idle notch; kursor podjeżdża pod notch
2. **3–8 s** — rozwinięcie; muzyka (play/pause lub przewinięcie)
3. **8–14 s** — przełączenie na półkę lub kalendarz
4. **14–20 s** — focus timer / pomodoro
5. **20–25 s** — zwinięcie; notch wraca do stanu spoczynku

Bez myszki skaczącej po całym ekranie — **ruchy powolne**, celowe.

### Postprodukcja

- Przytnij martwy czas na początku/końcu
- Opcjonalnie: **krótki podpis** na dole (np. „Hover. Expand. Flow.”) — font Inter
- Eksport: `website/assets/hero.mp4` + `hero-poster.jpg` (klatka z rozwiniętej wyspy)
- Rozmiar docelowy pod web: **&lt; 5 MB** (dla hero użyj `ffmpeg -crf 28`)

```bash
ffmpeg -i surowe.mov -c:v libx264 -crf 28 -preset slow -an website/assets/hero.mp4
ffmpeg -ss 00:00:05 -i website/assets/hero.mp4 -vframes 1 website/assets/hero-poster.jpg
```

### Czego unikać

- Jaskrawych tapet i bałaganu na pulpicie
- Nagrywania całego monitora w 4K bez kadru — plik będzie ogromny
- Długiego wyczekiwania między akcjami
- Powiadomień systemowych w trakcie nagrania (W tryb skupienia)

---

## Pliki źródłowe w repo

| Plik | Opis |
|------|------|
| `assets/logo-source.png` | Kolorowe logo (źródło) |
| `website/scripts/prepare-logo.py` | Logo z przezroczystym tłem |
| `website/scripts/prepare-screenshots.py` | Miękkie tło pod screeny |

Po dodaniu nowych screenów lub logo uruchom odpowiedni skrypt przed commitem.
