# NotchFlow — zajawki na social media

Kilka wariantów do wyboru. Wszystkie opierają się na tej samej historii: przejście ze starego MacBooka Intela na nowszego z notchem i irytacja, że notch na Macu to głównie czarna dziura, podczas gdy na iPhonie od lat jest z tego Dynamic Island.

Unikaj wklejania list funkcji i emoji — ludzie to czytają jak reklamę. Do postów dołącz jedno zdjęcie z góry ekranu (wyspa rozłożona) albo krótki screen recording: najazd kursorem, rozwinięcie, muzyka albo półka.

Link: https://notchflow.eu/pl  
Pobranie: https://github.com/Tymcio/notchflow/releases/latest/download/NotchFlow.dmg

---

## Dlaczego NotchFlow, a nie Notchify / DynamicLake / NotchNook

To nie jest „najlepsza apka na świecie”. To apka z konkretną filozofią. Poniżej uczciwe różnice — bez ściemy, bez tabel porównawczych w stylu landing page’a.

### Co NotchFlow robi inaczej (i dlaczego to ma znaczenie)

Zanim napisałem własne, przetestowałem kilka popularnych rozwiązań. Problem nie był w tym, że są złe — problem był w tym, że każde ciągnęło w inną stronę niż ta, której szukałem.

**DynamicLake** to najbliższy odpowiednik Dynamic Island pod względem wizualnym. Ma DynaMusic, DynaClip, DynaDrop, powiadomienia z komunikatorów, Liquid Glass, miniLake — funkcji jest dużo. Po kilku dniach miałem wrażenie, że konfiguruję drugi system operacyjny w menu barze. NotchFlow celuje w coś prostszego: najedziesz kursorem, dostajesz to, czego używasz codziennie (muzyka, kalendarz, pliki, timer, notatki), i wracasz do pracy. Nie zastępuje centrum powiadomień macOS, nie śledzi WhatsAppa, nie wymaga tygodnia na ustawienie. DynamicLake kosztuje ok. $15–17 jednorazowo i nie ma darmowej wersji do przetestowania. NotchFlow ma darmowy tier bez limitu czasu i kod na GitHubie.

**Notchify** ([fr0sty1122/notchify](https://github.com/fr0sty1122/notchify)) to też darmowy, open-source’owy projekt na GitHubie — bez subskrypcji. Funkcje się pokrywają (muzyka, kalendarz, półka, notatki, schowek, lustro kamery). NotchFlow nie wygrywa ceną, bo oba są darmowe do zbudowania. Różnica jest gdzie indziej: NotchFlow ma oficjalne podpisane buildy z aktualizacjami Sparkle, jawne zero telemetrii w v1.0, schowek wyłączony domyślnie, minutnik/Pomodoro, integrację Raycast i opcjonalne premium jednorazowe (€24 dożywotnio) zamiast modelu „wszystko albo nic z GitHuba”. Jeśli wolisz czysty open source bez warstwy komercyjnej — Notchify jest fair choice.

**NotchNook** to najpopularniejszy gracz w tej kategorii — $25 jednorazowo albo $3/miesiąc, ładny, rozbudowany, z półką plików i AirDrop. Ma sens, jeśli chcesz wszystko naraz i nie przeszkadza ci zamknięty kod. NotchFlow idzie inną drogą: darmowa wersja na stałe (nie 48h trial), open source, zero telemetrii, schowek wyłączony domyślnie. NotchNook ma więcej gadżetów (widgety, AirDrop); NotchFlow stawia na to, żeby wyspa nie kradła fokusu i nie żarła baterii od ciągłych animacji i powiadomień.

**Boring Notch / Notchy** — darmowe, open source, sensowne. Szczerze: jeśli szukasz czegoś za zero złotych i nie potrzebujesz premium, te apki są świetnym wyborem. NotchFlow ma sens, gdy chcesz podpisany i notaryzowany build od razu (bez kompilacji), lustro kamery, Pomodoro w jednym miejscu, integrację Raycast przez lokalne API, albo po prostu wolisz model „darmowe na zawsze + opcjonalne premium jednorazowe” zamiast donate.

### Jednym zdaniem — dla kogo jest NotchFlow

Dla kogoś, kto chce wyspę pod kursorem do codziennej pracy, bez subskrypcji, bez telemetrii, z kodem do przejrzenia — a nie kolejny „super-hub” z powiadomieniami z pięciu komunikatorów i tygodniem konfiguracji.

### Czego NotchFlow nie obiecuje (żeby nie kłamać w postach)

Nie ma integracji AirDrop jak NotchNook. Nie ma pogody w wyspie jak niektóre apki. Wymaga MacBooka z notchem — nie działa na Mac mini, iMacu ani Mac Studio bez notcha (przy zewnętrznym monitorze podłączonym do MacBooka z notchem wyspa tam działa). Nie zastępuje centrum powiadomień. Jeśli ktoś w komentarzu pyta „a co z X?” — powiedz wprost, czego nie ma, zamiast udawać, że ma wszystko.

---

## Facebook

### Wariant A — historia (najbardziej „ludzki”)

Kupiłem nowego MacBooka po latach na Intelu. Pierwsze wrażenie: szybki, cichy, ekran piękny. Drugie: ten notch na górze… i nic.

Na iPhonie od dawna mam wrażenie, że wycięcie w ekranie to nie wada, tylko miejsce na żywe rzeczy — muzyka, timer, powiadomienia, wszystko pod kciukiem. Na Macu notch wygląda jak element konstrukcyjny, którego system kompletnie nie wykorzystuje. Siedziałem z tym kilka tygodni i w końcu napisałem małą aplikację, żeby ten kawałek ekranu w końcu coś robił.

Nazywa się NotchFlow. Najedziesz kursorem na środek górnej krawędzi i notch rozwija się w wyspę — sterowanie muzyką, kalendarz, półka na pliki, minutnik, notatki. Bez przełączania okien, bez kolejnej ikonki w docku. Działa w tle i nie zabiera fokusu z tego, nad czym akurat pracujesz.

Zanim to napisałem, sprawdziłem DynamicLake i NotchNook. DynamicLake robi wrażenie, ale po kilku dniach miałem dość konfigurowania — powiadomienia, konwertery, pół modułów, których nie używam. NotchNook ładny, ale bez darmowej wersji i bez otwartego kodu. Chciałem coś prostszego: hover, wyspa, wracam do roboty. Bez subskrypcji, bez telemetrii, schowek wyłączony dopóki sam go nie włączysz.

Zrobiłem to najpierw dla siebie. Teraz wrzucam na zewnątrz — darmowa wersja bez limitu czasu, premium jednorazowo €24. Jeśli też przeszedłeś na nowego Maca i masz wrażenie, że notch marnuje miejsce, sprawdź: notchflow.eu

---

### Wariant B — krótszy, bardziej bezpośredni

Stary MacBook Intel → nowy z notchem. Szybkość super, ale notch denerwował od pierwszego dnia. Na telefonie to Dynamic Island, na laptopie czarna plamka.

Sprawdziłem DynamicLake i NotchNook — oba fajne, ale albo za dużo rzeczy naraz, albo subskrypcja / brak darmowej wersji. Napisałem NotchFlow: najazd na górę ekranu i notch zamienia się w centrum sterowania. Muzyka, kalendarz, pliki, timer. Open source, bez telemetrii.

Darmowe na zawsze: notchflow.eu

---

### Wariant C — z pytaniem na końcu (lepsze zaangażowanie)

Ktoś jeszcze ma wrażenie, że notch na MacBooku to zmarnowana szansa?

Ja przesiadłem się ze starego Intela na nowszego Maca i przez pierwszy miesiąc nie mogłem przejść obok tego wycięcia obojętnie. Na iPhonie ten sam pomysł działa od lat — wiesz, co gra, ile zostało do spotkania, masz pod ręką szybkie akcje. Na macOS notch jest… tylko notchem.

Postanowiłem to naprawić po swojemu. NotchFlow to natywna aplikacja, która rozwija wyspę z góry ekranu: muzyka, kalendarz, półka na pliki, notatki, minutnik. Najedziesz kursorem i masz to pod ręką, bez wychodzenia z tego, co robisz.

Różnica względem DynamicLake czy NotchNook? Nie próbuję zrobić drugiego centrum powiadomień ani zawodów w liczbie modułów. Chcę, żeby wyspa była cicha, szybka i nie wymagała tygodnia konfiguracji. Kod na GitHubie, darmowa wersja bez limitu czasu, premium jednorazowo zamiast subskrypcji.

Testuję to na co dzień od kilku miesięcy. Jeśli chcesz zobaczyć, o co chodzi — notchflow.eu. A Ty — używasz notcha na Macu w ogóle, czy też go ignorujesz?

---

## X (Twitter)

### Wariant A

Przesiadłem się z MacBooka Intela na nowego z notchem. Szybki, cichy — ale ten notch to przez miesiąc irytował mnie bardziej niż cokolwiek innego.

Na iPhonie wycięcie = Dynamic Island. Na Macu = czarna dziura.

Napisałem NotchFlow: najazd na górę ekranu → wyspa z muzyką, kalendarzem, plikami, timerem. Prostsze niż DynamicLake, darmowe na stałe w przeciwieństwie do NotchNook, open source w przeciwieństwie do obu.

notchflow.eu

---

### Wariant B (krótszy)

Notch na MacBooku marnuje miejsce. Na iPhonie to Dynamic Island.

Zrobiłem NotchFlow — wyspa pod kursorem: muzyka, kalendarz, półka, notatki. Bez subskrypcji, bez telemetrii, kod na GitHubie. Nie kolejny „super-hub” z powiadomieniami z pięciu appek.

Darmowe: notchflow.eu

---

### Wariant C (wątek — 3 tweety)

**Tweet 1**  
Nowy MacBook po latach na Intelu. Notch od dnia jeden wygląda jak coś, co Apple zostawiło w połowie drogi. Na iPhonie ten sam pomysł ma sens. Na Macu — nie.

**Tweet 2**  
Napisałem NotchFlow. Najedziesz na środek górnej krawędzi i notch rozwija się w wyspę: muzyka, kalendarz, pliki, minutnik, notatki. Bez przełączania aplikacji. Prostsze niż DynamicLake, darmowe na stałe w przeciwieństwie do NotchNook.

**Tweet 3**  
Open source (GPL-3.0), zero telemetrii, premium jednorazowo €24 zamiast $3/mies.  
notchflow.eu  
github.com/Tymcio/notchflow

---

## Reddit

Na Reddicie lepiej działa post „zrobiłem, bo mnie to denerwowało” niż zajawka produktowa. Poniżej wersje pod konkretne subreddity — dostosuj tytuł do reguł danego suba.

---

### r/macapps — wersja szczera, bez marketingu

**Tytuł:** Przesiadłem się na Maca z notchem i napisałem narzędzie, bo notch nic nie robił

**Treść:**

Kilka miesięcy temu wymieniłem starego MacBooka Intela na nowszego z notchem. Ogólnie super, ale jedna rzecz mnie wkurzała od pierwszego dnia: na iPhonie wycięcie w ekranie to Dynamic Island — muzyka, timery, szybkie info. Na Macu ten sam notch to po prostu czarna plamka w menu barze.

Próbowałem żyć z tym, ale w końcu napisałem własną apkę. NotchFlow — najedziesz kursorem na górę ekranu (środek, tam gdzie notch) i rozwija się wyspa. Mam tam muzykę, kalendarz, półkę na pliki, minutnik, szybkie notatki, historię schowka. Działa na wszystkich Spaces; przy zewnętrznym monitorze podłączonym do MacBooka z notchem wyspa tam też jest. Wymaga MacBooka z notchem — nie działa na Mac mini ani iMacu.

Zanim to zrobiłem, testowałem DynamicLake (fajny, ale za dużo modułów i konfiguracji) i NotchNook (ładny, ale trial a nie darmowa wersja, zamknięty kod, subskrypcja $3/mies.). NotchFlow poszedł w stronę prostoty: hover, wyspa, wracam do pracy. Open source, zero telemetrii, schowek wyłączony domyślnie. Podstawa darmowa bez limitu czasu, premium jednorazowo.

Wrzucam, bo może komuś z Was też przeszkadza ten niewykorzystany notch. Chętnie wezmę feedback — szczególnie jeśli coś się dziwnie zachowuje na Waszym setupie (wiele monitorów, pełny ekran itd.).

https://notchflow.eu  
DMG: https://github.com/Tymcio/notchflow/releases/latest/download/NotchFlow.dmg

---

### r/MacOS — wersja pod dyskusję o systemie

**Tytuł:** Czy notch na MacBooku Was też irytuje? Zrobiłem coś w stylu Dynamic Island

**Treść:**

Nie chodzi o to, że notch jest brzydki — chodzi o to, że macOS prawie w ogóle z niego nie korzysta. Przesiadłem się z Intela na nowszego Maca i przez jakiś czas myślałem, że to tylko mój problem, aż zrozumiałem, że po prostu nikt tego nie ogarnął po stronie systemu.

Na iPhonie od lat widać, że wycięcie może być interfejsem. Na Macu — kamera i tyle.

Napisałem NotchFlow: hover na górną krawędź, notch rozwija się w panel. Muzyka, kalendarz, pliki, timer, notatki — bez Alt-Tab i bez nowego okna.

Testowałem wcześniej DynamicLake — robi wrażenie wizualnie, ale to pół systemu operacyjnego w menu barze. NotchNook ma więcej gadżetów (AirDrop, widgety), ale kosztuje $25 albo $3/mies. i nie ma darmowej wersji. NotchFlow: prostszy, open source, darmowy tier na stałe, premium jednorazowo.

Jeśli macie podobne odczucia — dajcie znać, czy w ogóle byście z czegoś takiego korzystali, czy wolicie notch zostawić w spokoju. Link do testów: https://notchflow.eu

---

### r/apple — wersja osobista, mniej techniczna

**Tytuł:** Po przejściu z Intela na nowego Maca zostawiłem notch w spokoju… przez dwa tygodnie

**Treść:**

Kupiłem nowego MacBooka głównie dlatego, że stary Intel już ledwo zipał. Notch był dla mnie wtedy detalem — „ok, jest, przeżyję”.

Potem wziąłem iPhone do ręki i zaczęło mnie to dziwić. Ten sam Apple, ten sam pomysł wycięcia w ekranie — na telefonie to żyje (Dynamic Island), na laptopie nie. Przez kilka tygodni próbowałem udawać, że mnie to nie boli.

W końcu napisałem małą aplikację, która rozwija wyspę z notcha po najechaniu kursorem: muzyka, kalendarz, pliki, minutnik. Nazywa się NotchFlow. Nie udaje, że to funkcja systemowa — po prostu wypełnia lukę, która mi osobiście przeszkadzała.

Patrzyłem na DynamicLake i Notchify — DynamicLake za dużo naraz, Notchify podobny pomysł i też darmowy na GitHubie. NotchFlow poszedł w stronę oficjalnych podpisanych buildów, zero telemetrii i opcjonalnego premium jednorazowego zamiast subskrypcji.

Jeśli ktoś z Was też czuje, że notch na Macu to niedokończony pomysł — możecie sprawdzić za darmo: https://notchflow.eu

---

### r/SideProject — wersja „jak powstało”

**Tytuł:** Z irytacji na notch powstała moja pierwsza sensowna apka na macOS

**Treść:**

Trigger był banalny: nowy MacBook po latach na Intelu, notch na górze ekranu, zero pomysłu z czym to połączyć. Na iPhonie Dynamic Island od dawna pokazuje, że wycięcie może być UI, nie wadą.

NotchFlow zaczął jako projekt „naprawię to sobie”. Hover na górę ekranu → wyspa z modułami: muzyka, kalendarz, półka plików, minutnik, notatki, schowek. Swift/SwiftUI, działa w tle, nie kradnie fokusu.

Konkurencja (DynamicLake, NotchNook) albo robi wszystko naraz i bierze opłatę bez darmowej wersji, albo wymaga subskrypcji. Notchify jest podobny i też darmowy na GitHubie — tu różnica to oficjalna dystrybucja, prywatność domyślnie i opcjonalne premium jednorazowe. Kilka miesięcy codziennego używania, dopiero potem strona i release.

https://notchflow.eu  
Repo: https://github.com/Tymcio/notchflow

---

## Notatki praktyczne

**Zdjęcia / wideo:** jedno ujęcie wystarczy — notch w stanie zwiniętym i rozłożonym, najlepiej z muzyką albo kalendarzem. Na Reddicie screeny bez watermarków i bez nachalnego logo.

**Facebook:** wariant A lub C; najlepiej wieczorem, wt–czw. Wariant C z pytaniem zwykle zbiera więcej komentarzy.

**X:** wariant A jako pojedynczy post; wariant C jeśli chcesz wątek z kontekstem. Bez hashtagów typu #productivity #macos #notch — wyglądają sztucznie.

**Reddit:** nie wrzucaj tego samego posta w kilka subów tego samego dnia — Reddit to wykrywa. r/macapps jest najbardziej na miejscu. W r/apple i r/MacOS ton „szukam opinii / dzielę się doświadczeniem” działa lepiej niż „pobierz moją apkę”.

**Czego nie pisać:** „rewolucja w produktywności”, „must-have”, „Apple powinno to kupić”, „najlepsza apka na rynku”. Porównania z nazwami są OK, ale tylko uczciwe — nie udawaj, że NotchFlow ma AirDrop, pogodę albo powiadomienia z WhatsAppa.

**Odpowiadanie w komentarzach — gotowe odpowiedzi:**

*„Czym to się różni od DynamicLake?"*  
DynamicLake robi dużo — powiadomienia, konwertery, Liquid Glass, pół modułów. NotchFlow celuje w prostotę: hover, codzienne rzeczy (muzyka, kalendarz, pliki, timer), bez zastępowania centrum powiadomień. Plus open source i darmowa wersja bez limitu czasu.

*„A NotchNook?"*  
NotchNook jest świetny, jeśli chcesz wszystko naraz i nie przeszkadza ci $25 albo $3/mies. NotchFlow ma darmową wersję na stałe, kod na GitHubie i premium jednorazowo. Nie ma AirDrop ani widgetów — za to mniej „gadżetów", których nie używasz.

*„A Notchify?"*  
Notchify też jest darmowy na GitHubie (fr0sty1122/notchify), bez subskrypcji — podobny zestaw funkcji. NotchFlow różni się oficjalnymi podpisanymi buildami, zerem telemetrii, schowkiem wyłączonym domyślnie i opcjonalnym premium jednorazowym (€24) za rozszerzone funkcje. Jeśli wystarczy ci sam GitHub — Notchify jest OK.

*„Po co płacić, skoro Boring Notch / Notchy / Notchify są darmowe?"*  
Słusznie — jeśli darmowe ci pasują, zostań przy nich. NotchFlow ma sens, gdy chcesz podpisany build bez kompilacji, aktualizacje Sparkle, lustro kamery w premium, Pomodoro, integrację Raycast, albo wolisz model „darmowe na zawsze + opcjonalne premium jednorazowe”.

*„Zbiera dane?"*  
Nie. v1.0 bez telemetrii. Sieć tylko przy aktualizacjach i walidacji licencji premium. Schowek wyłączony domyślnie.

*„Działa na Intelu / Macu bez notcha?"*  
Wymaga MacBooka z notchem i macOS 14+ (Apple Silicon). Przy zewnętrznym monitorze podłączonym do takiego MacBooka wyspa tam działa. Mac mini, iMac, Mac Studio bez notcha — nie.
