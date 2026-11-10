# Propozycja cennika (listopad 2026)

## Problem z obecnym cennikiem

- Są trzy SKU (Premium 12 €/rok, Premium 24 € lifetime, Agents 14,90 €), a Agents nie wchodzi w Premium. Klient, który przyszedł po agentów, widzi dwa produkty i nie wie, który kupić.
- **Wszystkie trzy przyciski „Kup” prowadzą dziś do tego samego linku Polar, który sprzedaje tylko Premium Annual 12 €/rok** (sprawdzone w API checkoutu 10.11.2026). Lifetime i Agents są obecnie nie do kupienia.
- Konkurencja w niszy agentów jest jednorazowa i w jednej cenie: NotchNook Pro 19 $ (z zatwierdzaniem Claude Code i Codex), Vibe Island 19,99 $ (tylko agenci). Darmowe są coucou, CodexBar, Open Vibe Island i Boring Notch.

## Propozycja

| Plan | Cena | Co zawiera |
|------|------|------------|
| **Free** | 0 € | Cała wyspa jak dziś (muzyka, kalendarz, półka 1+3, 5 notatek, 5 wpisów schowka, minutnik, HUD) **oraz status agentów**: które sesje Claude Code, Codex i Cursora pracują, czekają albo skończyły, z przejściem do terminala |
| **NotchFlow Pro** | **19 € jednorazowo** (cena startowa 14 € przez 2 tygodnie launchu) | Wszystko z Premium **i** Agents: zatwierdzanie Claude Code z notcha, limity 5h/tygodniowe Claude i Codexa, wykorzystanie Cursora i Groka, motywy, Pomodoro, powiadomienia, nielimitowane notatki i schowek, lokalne API. 3 Maki, aktualizacje 1.x bez dopłat |
| **Trial** | 7 dni | Pełne Pro bez klucza, startuje przy pierwszym uruchomieniu funkcji Pro |

### Dlaczego tak

1. **Jeden produkt płatny**: nikt nie musi rozumieć różnicy między Premium a Agents. 19 € jest na poziomie NotchNook Pro i poniżej Vibe Island, a dostaje się więcej (cała wyspa plus agenci).
2. **Darmowy status agentów** to lejek. Darmowe alternatywy (coucou, CodexBar) już dają status i limity za zero, więc ukrywanie samego statusu za paywallem odcina ruch z Reddita i HN. Płaci się za to, co oszczędza czas: zatwierdzanie z notcha i limity w jednym miejscu.
3. **Trial zamiast twardych blokad**: zgodnie z roadmapą (v1.2). Kod jest na GPL, więc trial lokalny wystarczy; zabezpieczanie go mocniej nie ma sensu.
4. **Bez subskrypcji**: na rynku narzędzi do Maca subskrypcja za utility jest źle odbierana, a roczne 12 € i tak było tańsze niż lifetime za dwa lata.

### Istniejący klienci

- Premium Lifetime: dostają Pro (z Agents) automatycznie.
- Agents: dostają Pro automatycznie.
- Premium Annual: zachowują dostęp do końca okresu; po nim mogą przejść na Pro z rabatem równym zapłaconej kwocie (kod rabatowy w Polar) albo dalej odnawiać.

### Kody rabatowe (Polar → Discounts)

- `LAUNCH30`: −30% na 72 godziny po Product Hunt / Show HN.
- `STUDENT`: −50% na zgłoszenie mailem.
- Kod dla kontrybutorów i osób zgłaszających błędy.

## Co trzeba zrobić, jeśli przyjmujesz propozycję

W Polar (tylko Ty, wymaga logowania):
1. Utwórz produkt **NotchFlow Pro** (19 €, jednorazowy) z benefitem License Keys, prefiks np. `NOTCHFLOW_PRO_`, limit aktywacji 3.
2. Utwórz **Checkout Link** do tego produktu i podaj mi URL.
3. Ustaw w GitHub Actions sekrety z ID benefitów (`POLAR_PREMIUM_BENEFIT_IDS` itd.), żeby aplikacja rozpoznawała plan po benefit ID, a nie po nazwie.

W kodzie (mogę zrobić):
1. Jeden poziom Pro w `LicenseManager` (stare klucze Premium i Agents mapowane na Pro).
2. 7-dniowy trial.
3. Status agentów w wersji darmowej; zatwierdzanie i limity w Pro.
4. Nowy cennik na stronie (EN i PL) i w `docs/free-vs-premium.md`.

## Jeśli zostajemy przy obecnym modelu

Minimum, które trzeba naprawić od razu: osobne Checkout Linki dla Lifetime i Agents w Polar i wpisanie ich do `website/checkout-urls.js`. Bez tego strona sprzedaje tylko subskrypcję roczną.
