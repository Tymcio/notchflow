# Polar — pełna instrukcja rejestracji dla NotchFlow

Przewodnik od zera: konto, organizacja, produkty, licencje, wypłaty i podpięcie pod aplikację.

Powiązane: [polar-setup.md](polar-setup.md) (integracja techniczna w repo).

---

## 1. Jak Polar jest zorganizowany (ważne na start)

Polar ma **trzy poziomy** — nie myl ich z „rejestracją per projekt”:

| Poziom | Co to jest | NotchFlow |
|--------|------------|-----------|
| **Konto użytkownika** | Twój login (GitHub / Google / e-mail). Jedno na całe życie. | Ty jako founder |
| **Organizacja (Organization)** | Osobna „firma / marka” w Polar: produkty, klienci, finanse, API, Organization ID | **Jedna organizacja: NotchFlow** |
| **Produkt (Product)** | Konkretna oferta do kupienia (roczna, lifetime, itd.) | 2 produkty w tej samej organizacji |

### Czy rejestrujesz firmę, czy projekt?

- **Rejestrujesz się raz** jako użytkownik Polar.
- **Tworzysz organizację** — to jest jednostka „biznesowa” (NotchFlow / notchflow.eu).
- **Produkty** dodajesz **wewnątrz** organizacji — **nie** zakładasz osobnego konta Polar na każdy projekt.

### Wiele projektów w przyszłości

Masz dwie sensowne strategie:

| Strategia | Kiedy | Jak |
|-----------|-------|-----|
| **A. Jedna organizacja, wiele produktów** | Projekty pod tą samą marką / tym samym deweloperem | Np. NotchFlow Premium Annual + Lifetime + później dodatek |
| **B. Wiele organizacji** | Osobne marki, osobne finanse, osobne Organization ID | Menu → **New Organization** (lewy dolny róg dashboardu) |

Dla **NotchFlow**: wystarczy **jedna organizacja** i **dwa produkty**.

---

## 2. Kogo Polar obsługuje w Polsce

- **Polska (PL)** jest na liście krajów wypłat ([Supported countries](https://polar.sh/docs/merchant-of-record/supported-countries)).
- Możesz być **osobą fizyczną (individual)** albo **firmą (business)** — zależy od tego, co wybierzesz w Stripe Connect przy wypłatach.
- Polar jest **Merchant of Record** — to **Polar** sprzedaje klientowi licencję i rozlicza VAT globalnie; Ty dostajesz wypłatę netto.
- **Konto bankowe** do wypłat: kraj Polska, waluta zgodna z wymaganiami Stripe Connect (zwykle **EUR** lub lokalna — Stripe podpowie przy onboardingu).

> Uwaga podatkowa (nie jest poradą księgową): wypłata z Polar to Twój przychód w PL — rozliczasz go u siebie (JDG / sp. z o.o.). VAT od sprzedaży B2C globalnie ogarnia Polar jako MoR. W razie wątpliwości — księgowy.

---

## 3. Krok po kroku: założenie konta

### 3.1 Rejestracja użytkownika

1. Wejdź na [https://polar.sh](https://polar.sh)
2. **Sign up** — wybierz:
   - **GitHub** (wygodne dla devów), albo
   - **Google**, albo
   - **E-mail + hasło**
3. Potwierdź e-mail, jeśli wymagane.

**Nie potrzebujesz karty** na start.

### 3.2 Pierwsza organizacja

Po pierwszym logowaniu Polar poprosi o utworzenie organizacji.

| Pole | Co wpisać (NotchFlow) |
|------|------------------------|
| **Organization name** | `NotchFlow` |
| **Slug** | `notchflow` (URL: polar.sh/notchflow…) |
| **Website** | `https://notchflow.eu` |
| **Description** | Krótki opis: native macOS notch utility, freemium + premium license |

Zapisz — to jest Twoja **jedyna** organizacja na start.

### 3.3 Ustawienia organizacji (Settings)

W dashboardzie: **Settings** (ikona koła zębatego / menu organizacji).

| Sekcja | Co uzupełnić |
|--------|----------------|
| **General** | Nazwa, slug, strona www |
| **Organization ID** | **Skopiuj UUID** — wkleisz do `POLAR_ORGANIZATION_ID` w buildzie NotchFlow |
| **Social media** | Link do strony, GitHub (`Tymcio/notchflow`), ewentualnie X — **używane tylko do weryfikacji**, niepubliczne |
| **Branding** | Logo, kolory checkoutu (opcjonalnie, pod markę NotchFlow) |
| **Members** | Na start tylko Ty (Owner); później możesz dodać współpracownika |

---

## 4. Benefit: License Keys (zanim produkty)

Najpierw zdefiniuj **korzyść** (benefit), potem podepniesz ją do produktów.

1. **Benefits** → **+ New Benefit**
2. Typ: **License Keys**
3. Ustawienia:

| Ustawienie | Wartość dla NotchFlow |
|------------|------------------------|
| **Name** | `NotchFlow Premium License` |
| **Prefix** | `NOTCHFLOW_` (opcjonalnie, ładniejsze klucze) |
| **Activation limit** | **2** (zgodnie z „2 Maci” w cenniku) |
| **Allow customer deactivation** | **Włączone** — klient może odpiąć stary Mac w portalu Polar |
| **Expiration** | Zostaw puste na poziomie benefitu — wygaśnięcie ustawisz na produkcie subskrypcyjnym |

Zapisz benefit.

---

## 5. Produkty Premium

### Produkt 1: Premium Annual (subskrypcja)

1. **Products** → **Catalogue** → **New Product**
2. Ustawienia:

| Pole | Wartość |
|------|---------|
| **Name** | `NotchFlow Premium Annual` |
| **Description** | Roczna licencja premium — 2 Maci, wszystkie funkcje premium |
| **Pricing type** | **Subscription** |
| **Billing period** | **Yearly** |
| **Price** | `12` **EUR** (lub PLN jeśli wolisz — EUR pasuje do cennika na stronie) |
| **Benefits** | Dodaj `NotchFlow Premium License` |
| **License expiration** | **1 year** / powiązane z subskrypcją (klucz wygasa z odnowieniem) |

### Produkt 2: Premium Lifetime (jednorazowo)

1. **New Product** ponownie
2. Ustawienia:

| Pole | Wartość |
|------|---------|
| **Name** | `NotchFlow Premium Lifetime` |
| **Pricing type** | **One-time purchase** |
| **Price** | `24` **EUR** |
| **Benefits** | Ten sam benefit License Keys |
| **Expiration** | **Brak** / perpetual |

### Wariant z jednym checkoutem (opcjonalnie)

Zamiast dwóch osobnych linków możesz zrobić **jeden Checkout Link** z **oboma produktami** — klient wybiera Annual vs Lifetime na stronie płatności. Dla NotchFlow na stronie masz dwa osobne przyciski — wtedy **dwa Checkout Links** (prościej).

---

## 6. Checkout Links (integracja ze stroną)

Strona **nie potrzebuje backendu** — wystarczą dwa Checkout Links i plik `website/checkout-urls.js`.

### 6.1 Utwórz linki w Polar

**Products → Checkout Links → New Link** (dwa osobne linki).

| Pole | Lifetime | Annual |
|------|----------|--------|
| Produkt | tylko Lifetime | tylko Annual |
| Label | `NotchFlow Lifetime` | `NotchFlow Annual` |
| **Success URL** | `https://notchflow.eu/pricing/?purchased=lifetime` | `https://notchflow.eu/pricing/?purchased=annual` |
| **Return URL** | `https://notchflow.eu/pricing/` | `https://notchflow.eu/pricing/` |
| Discount / trial | wyłączone na start | wyłączone na start |

Success URL pokazuje baner „sprawdź e-mail i aktywuj w aplikacji”. Wersja PL (opcjonalnie): `/pl/pricing/?purchased=…`.

Skopiuj URL każdego linku: `https://buy.polar.sh/polar_cl_…`

### 6.2 Wklej w repo

```javascript
// website/checkout-urls.js
var NOTCHFLOW_CHECKOUT = {
  lifetime: "https://buy.polar.sh/polar_cl_XXXXX",
  annual: "https://buy.polar.sh/polar_cl_YYYYY",
};
```

Przyciski z `data-polar-checkout` na stronie głównej i `/pricing` dostaną te URL-e automatycznie.

Szczegóły techniczne: [polar-setup.md §3](polar-setup.md).

---

## 7. Weryfikacja konta i pierwsza wypłata

Żeby **przyjmować prawdziwe płatności i wypłacać**, Polar wymaga review (MoR + AML).

**Finance** → **Account** — trzy kroki:

### Krok 1: Submit for approval

Opisz krótko:

- **Co sprzedajesz:** licencję na aplikację macOS NotchFlow (oprogramowanie cyfrowe)
- **Strona:** https://notchflow.eu
- **Repo (open source):** https://github.com/Tymcio/notchflow
- **Model:** freemium + klucz licencyjny po zakupie
- **Dostawa:** automatyczna (license key e-mail + aktywacja w aplikacji)

Polar zaleca: **najpierw zbuduj integrację, potem złóż wniosek** — masz już kod Polar w aplikacji i stronę.

### Krok 2: KYC (weryfikacja tożsamości)

- Owner organizacji: dowód / paszport + selfie (Stripe Identity)
- Trwa kilka minut

### Krok 3: Payout account (Stripe Connect Express)

| Jeśli… | Wybierz |
|--------|---------|
| Działasz jako **JDG / osoba fizyczna** | **Individual** + kraj **Poland** |
| Masz **sp. z o.o.** | **Business** + dane firmy (NIP, KRS itd. — Stripe poprosi) |

**Konto bankowe:**

- Kraj: **Polska**
- Waluta: zgodnie z wymaganiami Stripe (często EUR dla cross-border)
- Konto musi być **prawdziwe**, na Twoje dane — wirtualne „borderless” często **nie** przechodzą

Pierwszy review: **do ~14 dni** (czasem szybciej). **Sprzedaż może działać wcześniej** — wypłata może być „Held” do zatwierdzenia.

---

## 8. Testy bez prawdziwych płatności

**Nie rób testowych zakupów prawdziwą kartą** — Polar/Stripe traktują to jako fraud.

Zamiast tego:

1. Użyj **sandbox** Polar (jeśli dostępny w dashboardzie), albo
2. Utwórz produkt **za 0 €** / kupon **100% zniżki** i przejdź pełną ścieżkę
3. Albo poproś support Polar o kod testowy (wspominają o tym w [Account reviews](https://polar.sh/docs/merchant-of-record/account-reviews))

Test w aplikacji:

1. Skopiuj klucz z e-maila / portalu klienta Polar
2. NotchFlow → Ustawienia → Licencja → **Aktywuj**
3. Sprawdź premium + drugi Mac + limit 2 urządzeń

---

## 9. Podpięcie pod NotchFlow (technicznie)

Po skopiowaniu **Organization ID**:

```bash
export POLAR_ORGANIZATION_ID="uuid-z-polar-settings"
ENFORCE_LICENSE=1 Scripts/package_app.sh
```

W `Info.plist` pojawi się `PolarOrganizationID` — aplikacja waliduje klucze przez API Polar.

Szczegóły: [polar-setup.md](polar-setup.md).

---

## 10. Co klient widzi po zakupie

1. Checkout Polar (karta, Apple Pay, itd.)
2. E-mail z potwierdzeniem + **klucz licencyjny**
3. Portal klienta Polar: [https://polar.sh](https://polar.sh) → logowanie e-mailem → **Purchases** → klucz, data wygaśnięcia, **dezaktywacja urządzeń**
4. W NotchFlow: wkleja klucz → aplikacja robi `activate` (rezerwacja slotu na tym Macu) → premium

---

## 11. Opłaty Polar (orientacyjnie, 2026)

Plan **Starter** (bez abonamentu): ok. **5% + 0,50 USD** za transakcję (MoR + podatki w cenie).

Plany płatne (Pro/Growth) obniżają procent za stałą opłatą miesięczną — sensowne dopiero przy większej sprzedaży.

Dodatkowo przy wypłacie: opłaty Stripe Connect (np. 2 USD/mies. jeśli była wypłata, 0,25% + 0,25 USD za transfer).

Szczegóły: [Polar fees](https://polar.sh/docs/merchant-of-record/fees).

---

## 12. Checklist przed launch 1.0

- [ ] Konto Polar + organizacja **NotchFlow**
- [ ] Organization ID → `POLAR_ORGANIZATION_ID` w CI / release build
- [ ] Benefit License Keys (limit 2 aktywacji)
- [ ] Produkty Annual €12 + Lifetime €24
- [ ] Checkout links → `website/checkout-urls.js`
- [ ] Privacy/terms na stronie (już mówią o Polar)
- [ ] Finance → Account: approval + KYC + payout PL
- [ ] Test: zakup (sandbox / 0€ / kupon) → klucz → aktywacja w app
- [ ] Opcjonalnie: nagraj krótki film „zakup → klucz → premium” na review Polar

---

## 13. FAQ

### Czy muszę mieć firmę (sp. z o.o.)?

Nie. Możesz jako **individual** w PL, jeśli Stripe Connect to obsługuje dla Twojego przypadku. Wielu indie devów zaczyna na JDG lub jako osoba fizyczna — potwierdź z księgowym.

### Czy drugi projekt = drugie konto Polar?

Nie. **To samo konto użytkownika**, nowa **organizacja** (menu → New Organization) lub nowy **produkt** w tej samej organizacji.

### Czy Organization ID jest tajny?

**Nie** — jest w aplikacji i służy do walidacji kluczy. To jak publiczny identyfikator sklepu.

### Co jeśli review trwa długo?

Sprzedaż może iść; wypłaty czekają. Uzupełnij social media, opis produktu, działającą stronę i integrację.

### Support Polar

- E-mail: support@polar.sh
- Docs: [https://polar.sh/docs](https://polar.sh/docs)

---

## 14. Mapowanie: Polar ↔ NotchFlow repo

| Polar | Plik / miejsce w repo |
|-------|------------------------|
| Organization ID | `POLAR_ORGANIZATION_ID` → `Info.plist` |
| Checkout URLs | `website/checkout-urls.js` |
| Walidacja klucza | `Sources/NotchFlow/Licensing/PolarLicenseClient.swift` |
| UI aktywacji | `Sources/NotchFlow/Views/Settings/LicenseSettingsTab.swift` |
| Instrukcja techniczna | `docs/polar-setup.md` |
