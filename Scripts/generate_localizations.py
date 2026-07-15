#!/usr/bin/env python3
"""Generate Localizable.xcstrings from embedded translation tables."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "Sources/NotchFlow/Resources/Localizable.xcstrings"

# English key -> {pl, de, it, es}
TRANSLATIONS: dict[str, dict[str, str]] = {
    # Island modules
    "Music": {"pl": "Muzyka", "de": "Musik", "it": "Musica", "es": "Música"},
    "Calendar": {"pl": "Kalendarz", "de": "Kalender", "it": "Calendario", "es": "Calendario"},
    "Shelf": {"pl": "Półka", "de": "Ablage", "it": "Mensola", "es": "Bandeja"},
    "Timer": {"pl": "Minutnik", "de": "Timer", "it": "Timer", "es": "Temporizador"},
    "Notes": {"pl": "Notatki", "de": "Notizen", "it": "Note", "es": "Notas"},
    "Clipboard": {"pl": "Schowek", "de": "Zwischenablage", "it": "Appunti", "es": "Portapapeles"},
    "Mirror": {"pl": "Lustro", "de": "Spiegel", "it": "Specchio", "es": "Espejo"},
    # Settings tabs
    "General": {"pl": "Ogólne", "de": "Allgemein", "it": "Generale", "es": "General"},
    "Appearance": {"pl": "Wygląd", "de": "Erscheinungsbild", "it": "Aspetto", "es": "Apariencia"},
    "Notifications": {"pl": "Powiadomienia", "de": "Mitteilungen", "it": "Notifiche", "es": "Notificaciones"},
    "License": {"pl": "Licencja", "de": "Lizenz", "it": "Licenza", "es": "Licencia"},
    "Privacy": {"pl": "Prywatność", "de": "Datenschutz", "it": "Privacy", "es": "Privacidad"},
    "Integrations": {"pl": "Integracje", "de": "Integrationen", "it": "Integrazioni", "es": "Integraciones"},
    # Themes
    "Violet": {"pl": "Fiolet", "de": "Violett", "it": "Viola", "es": "Violeta"},
    "Theme": {"pl": "Motyw", "de": "Design", "it": "Tema", "es": "Tema"},
    # Menu bar
    "NotchFlow — hover the notch to open": {
        "pl": "NotchFlow — najedź na notch, aby otworzyć",
        "de": "NotchFlow — zum Öffnen mit dem Cursor über die Notch fahren",
        "it": "NotchFlow — passa il mouse sul notch per aprire",
        "es": "NotchFlow — pasa el cursor sobre el notch para abrir",
    },
    "Show Notch Island": {
        "pl": "Pokaż wyspę Notch",
        "de": "Notch-Insel anzeigen",
        "it": "Mostra isola Notch",
        "es": "Mostrar isla Notch",
    },
    "Hide Notch Island": {
        "pl": "Ukryj wyspę Notch",
        "de": "Notch-Insel ausblenden",
        "it": "Nascondi isola Notch",
        "es": "Ocultar isla Notch",
    },
    "Settings…": {"pl": "Ustawienia…", "de": "Einstellungen…", "it": "Impostazioni…", "es": "Ajustes…"},
    "Quit NotchFlow": {"pl": "Zakończ NotchFlow", "de": "NotchFlow beenden", "it": "Esci da NotchFlow", "es": "Salir de NotchFlow"},
    "NotchFlow Settings": {"pl": "Ustawienia NotchFlow", "de": "NotchFlow-Einstellungen", "it": "Impostazioni NotchFlow", "es": "Ajustes de NotchFlow"},
    # First launch
    "NotchFlow is running": {"pl": "NotchFlow działa", "de": "NotchFlow läuft", "it": "NotchFlow è attivo", "es": "NotchFlow está en ejecución"},
    "Hover the top center of the screen (notch area) to open NotchFlow.": {
        "pl": "Najedź na środek górnej krawędzi ekranu (obszar notcha), aby otworzyć NotchFlow.",
        "de": "Bewege den Cursor zur oberen Bildschirmmitte (Notch-Bereich), um NotchFlow zu öffnen.",
        "it": "Passa il mouse al centro del bordo superiore (area notch) per aprire NotchFlow.",
        "es": "Pasa el cursor al centro del borde superior (zona del notch) para abrir NotchFlow.",
    },
    # Unsupported Mac
    "NotchFlow requires a MacBook with a notch": {
        "pl": "NotchFlow wymaga MacBooka z notchem",
        "de": "NotchFlow erfordert ein MacBook mit Notch",
        "it": "NotchFlow richiede un MacBook con notch",
        "es": "NotchFlow requiere un MacBook con notch",
    },
    "NotchFlow only works on MacBooks with a display notch. This Mac has no notch, so the app cannot start.\n\nSupported: MacBook Pro / Air with notch (macOS 14+, Apple Silicon).": {
        "pl": "NotchFlow działa tylko na MacBookach z wycięciem (notch) w ekranie. Ten Mac nie ma notcha, więc aplikacja nie może się uruchomić.\n\nObsługiwane: MacBook Pro / Air z notchem (macOS 14+, Apple Silicon).",
        "de": "NotchFlow funktioniert nur auf MacBooks mit Display-Notch. Dieser Mac hat keine Notch, daher kann die App nicht starten.\n\nUnterstützt: MacBook Pro / Air mit Notch (macOS 14+, Apple Silicon).",
        "it": "NotchFlow funziona solo su MacBook con notch nel display. Questo Mac non ha notch, quindi l'app non può avviarsi.\n\nSupportati: MacBook Pro / Air con notch (macOS 14+, Apple Silicon).",
        "es": "NotchFlow solo funciona en MacBook con notch en la pantalla. Este Mac no tiene notch, por lo que la app no puede iniciarse.\n\nCompatible: MacBook Pro / Air con notch (macOS 14+, Apple Silicon).",
    },
    "OK": {"pl": "OK", "de": "OK", "it": "OK", "es": "OK"},
    "Cancel": {"pl": "Anuluj", "de": "Abbrechen", "it": "Annulla", "es": "Cancelar"},
    # General settings
    "Launch at login": {"pl": "Uruchamiaj przy logowaniu", "de": "Bei der Anmeldung öffnen", "it": "Apri al login", "es": "Abrir al iniciar sesión"},
    "Language": {"pl": "Język", "de": "Sprache", "it": "Lingua", "es": "Idioma"},
    "Apps": {"pl": "Aplikacje", "de": "Apps", "it": "App", "es": "Apps"},
    "Island size": {"pl": "Rozmiar wyspy", "de": "Inselgröße", "it": "Dimensione isola", "es": "Tamaño de la isla"},
    "System default": {"pl": "Domyślny systemu", "de": "Systemstandard", "it": "Predefinita di sistema", "es": "Predeterminado del sistema"},
    "Changing the language restarts NotchFlow.": {
        "pl": "Zmiana języka uruchamia NotchFlow ponownie.",
        "de": "Beim Ändern der Sprache wird NotchFlow neu gestartet.",
        "it": "Il cambio di lingua riavvia NotchFlow.",
        "es": "Cambiar el idioma reinicia NotchFlow.",
    },
    "Notch hover": {"pl": "Najechanie na notch", "de": "Notch-Hover", "it": "Passaggio sul notch", "es": "Cursor sobre el notch"},
    "NotchFlow tracks the cursor globally (requires Accessibility).": {
        "pl": "NotchFlow wykrywa kursor globalnie (wymaga Dostępności).",
        "de": "NotchFlow erfasst den Cursor global (Bedienungshilfen erforderlich).",
        "it": "NotchFlow rileva il cursore globalmente (richiede Accessibilità).",
        "es": "NotchFlow detecta el cursor globalmente (requiere Accesibilidad).",
    },
    "Without Accessibility, a fallback zone along the top edge is used. For the fastest response, enable NotchFlow in System Settings → Privacy → Accessibility.": {
        "pl": "Bez Dostępności działa tryb zapasowy nad górną krawędzią ekranu. Dla najszybszej reakcji włącz NotchFlow w Ustawienia → Prywatność → Dostępność.",
        "de": "Ohne Bedienungshilfen wird ein Ersatzbereich am oberen Bildschirmrand verwendet. Für die schnellste Reaktion aktiviere NotchFlow unter Systemeinstellungen → Datenschutz → Bedienungshilfen.",
        "it": "Senza Accessibilità viene usata una zona di riserva sul bordo superiore. Per la risposta più rapida, abilita NotchFlow in Impostazioni di Sistema → Privacy → Accessibilità.",
        "es": "Sin Accesibilidad se usa una zona de respaldo en el borde superior. Para la respuesta más rápida, activa NotchFlow en Ajustes del Sistema → Privacidad → Accesibilidad.",
    },
    "Grant permission": {"pl": "Nadaj uprawnienie", "de": "Berechtigung erteilen", "it": "Concedi il permesso", "es": "Conceder permiso"},
    "Open System Settings": {"pl": "Otwórz ustawienia systemowe", "de": "Systemeinstellungen öffnen", "it": "Apri Impostazioni di Sistema", "es": "Abrir Ajustes del Sistema"},
    "App menu": {"pl": "Menu aplikacji", "de": "App-Menü", "it": "Menu app", "es": "Menú de la app"},
    "Avoid covering the app menu": {"pl": "Unikaj zasłaniania menu aplikacji", "de": "App-Menü nicht überdecken", "it": "Evita di coprire il menu app", "es": "Evitar cubrir el menú de la app"},
    "NotchFlow narrows the left idle wing when the active app's menu bar reaches the notch.": {
        "pl": "NotchFlow zwęża lewe skrzydełko wyspy idle, gdy menu aktywnej aplikacji podchodzi pod notch.",
        "de": "NotchFlow verengt den linken Idle-Flügel, wenn die Menüleiste der aktiven App die Notch erreicht.",
        "it": "NotchFlow restringe l'ala sinistra in idle quando la barra menu dell'app attiva raggiunge il notch.",
        "es": "NotchFlow estrecha el ala izquierda en reposo cuando la barra de menú de la app activa llega al notch.",
    },
    "Accessibility permission is required to detect the app menu position.": {
        "pl": "Wymagane uprawnienie Dostępności, aby wykrywać pozycję menu aplikacji.",
        "de": "Bedienungshilfen sind erforderlich, um die Menüposition der App zu erkennen.",
        "it": "Serve il permesso Accessibilità per rilevare la posizione del menu app.",
        "es": "Se requiere Accesibilidad para detectar la posición del menú de la app.",
    },
    "Hide island for apps": {"pl": "Ukryj wyspę dla aplikacji", "de": "Insel für Apps ausblenden", "it": "Nascondi isola per app", "es": "Ocultar isla para apps"},
    "The island won't appear when a selected app is active.": {
        "pl": "Wyspa nie pojawi się, gdy aktywna jest wybrana aplikacja.",
        "de": "Die Insel erscheint nicht, wenn eine ausgewählte App aktiv ist.",
        "it": "L'isola non apparirà quando un'app selezionata è attiva.",
        "es": "La isla no aparecerá cuando una app seleccionada esté activa.",
    },
    "No apps selected.": {"pl": "Brak wybranych aplikacji.", "de": "Keine Apps ausgewählt.", "it": "Nessuna app selezionata.", "es": "Ninguna app seleccionada."},
    "Add app…": {"pl": "Dodaj aplikację…", "de": "App hinzufügen…", "it": "Aggiungi app…", "es": "Añadir app…"},
    "Hiding the island for selected apps is a Premium feature — activate your license below.": {
        "pl": "Ukrywanie wyspy dla wybranych aplikacji jest funkcją Premium — aktywuj licencję w sekcji poniżej.",
        "de": "Ausblenden der Insel für ausgewählte Apps ist eine Premium-Funktion — aktiviere deine Lizenz unten.",
        "it": "Nascondere l'isola per app selezionate è Premium — attiva la licenza sotto.",
        "es": "Ocultar la isla para apps seleccionadas es Premium — activa tu licencia abajo.",
    },
    "Premium": {"pl": "Premium", "de": "Premium", "it": "Premium", "es": "Premium"},
    "Camera mirror, themes, larger clipboard, and more require an active license.": {
        "pl": "Lustro kamery, motywy, większy schowek i inne funkcje wymagają aktywacji licencji.",
        "de": "Kameraspiegel, Designs, größere Zwischenablage und mehr erfordern eine aktive Lizenz.",
        "it": "Specchio della fotocamera, temi, appunti più grandi e altro richiedono una licenza attiva.",
        "es": "Espejo de cámara, temas, portapapeles más grande y más requieren licencia activa.",
    },
    "Beta period — all Premium features are unlocked without a key.": {
        "pl": "Okres beta — wszystkie funkcje Premium są odblokowane bez klucza.",
        "de": "Beta-Phase — alle Premium-Funktionen sind ohne Schlüssel freigeschaltet.",
        "it": "Periodo beta — tutte le funzioni Premium sono sbloccate senza chiave.",
        "es": "Periodo beta — todas las funciones Premium están desbloqueadas sin clave.",
    },
    "Enter license key…": {"pl": "Wprowadź klucz licencji…", "de": "Lizenzschlüssel eingeben…", "it": "Inserisci chiave licenza…", "es": "Introducir clave de licencia…"},
    "Remove from list": {"pl": "Usuń z listy", "de": "Aus Liste entfernen", "it": "Rimuovi dall'elenco", "es": "Quitar de la lista"},
    # Appearance
    "Island width": {"pl": "Szerokość wyspy", "de": "Inselbreite", "it": "Larghezza isola", "es": "Ancho de la isla"},
    "Clipboard height": {"pl": "Wysokość schowka", "de": "Zwischenablage-Höhe", "it": "Altezza appunti", "es": "Altura del portapapeles"},
    "Calendar and other tabs adjust height to content automatically.": {
        "pl": "Kalendarz i pozostałe zakładki dopasowują wysokość do treści automatycznie.",
        "de": "Kalender und andere Tabs passen die Höhe automatisch an den Inhalt an.",
        "it": "Calendario e altre schede adattano l'altezza al contenuto automaticamente.",
        "es": "Calendario y otras pestañas ajustan la altura al contenido automáticamente.",
    },
    "Premium unlocks custom island size and themes.": {
        "pl": "Premium odblokowuje własny rozmiar wyspy i motywy.",
        "de": "Premium schaltet individuelle Inselgröße und Designs frei.",
        "it": "Premium sblocca dimensioni isola e temi personalizzati.",
        "es": "Premium desbloquea tamaño de isla y temas personalizados.",
    },
    # Notifications settings
    "Calls in the notch": {"pl": "Połączenia w notchu", "de": "Anrufe in der Notch", "it": "Chiamate nel notch", "es": "Llamadas en el notch"},
    "Show incoming calls in the island": {
        "pl": "Pokazuj połączenia przychodzące w wyspie",
        "de": "Eingehende Anrufe in der Insel anzeigen",
        "it": "Mostra chiamate in arrivo nell'isola",
        "es": "Mostrar llamadas entrantes en la isla",
    },
    "Calls in the notch require a Premium license.": {
        "pl": "Połączenia w notchu wymagają licencji Premium.",
        "de": "Anrufe in der Notch erfordern eine Premium-Lizenz.",
        "it": "Le chiamate nel notch richiedono licenza Premium.",
        "es": "Las llamadas en el notch requieren licencia Premium.",
    },
    "FaceTime and calls relayed from iPhone appear in the island instead of only as a side banner.": {
        "pl": "FaceTime i połączenia przekazywane z iPhone'a pojawią się w wyspie zamiast tylko jako banner z boku.",
        "de": "FaceTime und vom iPhone weitergeleitete Anrufe erscheinen in der Insel statt nur als Seitenbanner.",
        "it": "FaceTime e chiamate inoltrate dall'iPhone compaiono nell'isola invece che solo come banner laterale.",
        "es": "FaceTime y llamadas reenviadas desde el iPhone aparecen en la isla en lugar de solo como banner lateral.",
    },
    "App notifications": {"pl": "Powiadomienia aplikacji", "de": "App-Mitteilungen", "it": "Notifiche app", "es": "Notificaciones de apps"},
    "Show notifications from selected apps in the island": {
        "pl": "Pokazuj powiadomienia wybranych aplikacji w wyspie",
        "de": "Mitteilungen ausgewählter Apps in der Insel anzeigen",
        "it": "Mostra notifiche delle app selezionate nell'isola",
        "es": "Mostrar notificaciones de apps seleccionadas en la isla",
    },
    "Hide message body (show sender only)": {
        "pl": "Ukryj treść wiadomości (pokaż tylko nadawcę)",
        "de": "Nachrichtentext ausblenden (nur Absender anzeigen)",
        "it": "Nascondi testo messaggio (mostra solo mittente)",
        "es": "Ocultar cuerpo del mensaje (solo remitente)",
    },
    "Close the system banner when shown in the island": {
        "pl": "Zamykaj systemowy dymek, gdy powiadomienie jest w wyspie",
        "de": "System-Banner schließen, wenn in der Insel angezeigt",
        "it": "Chiudi il banner di sistema quando mostrato nell'isola",
        "es": "Cerrar el banner del sistema al mostrarse en la isla",
    },
    "The macOS banner in the corner is closed automatically once the notification appears in the notch.": {
        "pl": "Dymek macOS w rogu ekranu jest zamykany automatycznie, gdy tylko powiadomienie pojawi się w notchu.",
        "de": "Das macOS-Banner in der Ecke wird automatisch geschlossen, sobald die Mitteilung in der Notch erscheint.",
        "it": "Il banner di macOS nell'angolo viene chiuso automaticamente non appena la notifica appare nel notch.",
        "es": "El banner de macOS en la esquina se cierra automáticamente en cuanto la notificación aparece en el notch.",
    },
    "Using Rambox? Enable Rambox in the list — WhatsApp, Telegram, and MSN notifications go through Rambox, not native apps.": {
        "pl": "Używasz Rambox? Włącz Rambox na liście — powiadomienia z WhatsApp, Telegram i MSN idą przez Rambox, nie przez natywne apki.",
        "de": "Rambox nutzen? Aktiviere Rambox in der Liste — WhatsApp-, Telegram- und MSN-Mitteilungen laufen über Rambox, nicht native Apps.",
        "it": "Usi Rambox? Abilita Rambox nell'elenco — le notifiche di WhatsApp, Telegram e MSN passano da Rambox, non dalle app native.",
        "es": "¿Usas Rambox? Activa Rambox en la lista — las notificaciones de WhatsApp, Telegram y MSN van por Rambox, no por apps nativas.",
    },
    "Permissions": {"pl": "Uprawnienia", "de": "Berechtigungen", "it": "Permessi", "es": "Permisos"},
    "Accessibility is enabled — NotchFlow can read system notification banners.": {
        "pl": "Dostępność jest włączona — NotchFlow może odczytywać bannery powiadomień systemowych.",
        "de": "Bedienungshilfen sind aktiv — NotchFlow kann System-Mitteilungsbanner lesen.",
        "it": "Accessibilità attiva — NotchFlow può leggere i banner di notifica di sistema.",
        "es": "Accesibilidad activada — NotchFlow puede leer banners de notificaciones del sistema.",
    },
    "Accessibility permission is required to detect calls and Notification Center alerts.": {
        "pl": "Wymagane uprawnienie Dostępności, aby wykrywać połączenia i powiadomienia z Notification Center.",
        "de": "Bedienungshilfen sind erforderlich, um Anrufe und Mitteilungszentrale-Banner zu erkennen.",
        "it": "Serve Accessibilità per rilevare chiamate e avvisi del Centro notifiche.",
        "es": "Se requiere Accesibilidad para detectar llamadas y avisos del Centro de notificaciones.",
    },
    "Notification content is kept in RAM only and is not saved to disk.": {
        "pl": "Treść powiadomień jest trzymana wyłącznie w pamięci RAM i nie jest zapisywana na dysk.",
        "de": "Mitteilungsinhalte werden nur im RAM gehalten und nicht auf der Festplatte gespeichert.",
        "it": "Il contenuto delle notifiche resta solo in RAM e non viene salvato su disco.",
        "es": "El contenido de las notificaciones se guarda solo en RAM y no en disco.",
    },
    # Privacy
    "Monitor clipboard": {"pl": "Monitoruj schowek", "de": "Zwischenablage überwachen", "it": "Monitora appunti", "es": "Monitorizar portapapeles"},
    "Stores recent copied text and links locally. Passwords and concealed pasteboard entries are skipped. Off by default.": {
        "pl": "Zapisuje lokalnie ostatnie skopiowane teksty i linki. Hasła i ukryte wpisy ze schowka są pomijane. Domyślnie wyłączone.",
        "de": "Speichert zuletzt kopierte Texte und Links lokal. Passwörter und verdeckte Zwischenablageeinträge werden übersprungen. Standardmäßig aus.",
        "it": "Salva localmente testi e link copiati di recente. Password e voci nascoste degli appunti vengono ignorate. Disattivato di default.",
        "es": "Guarda localmente textos y enlaces copiados recientemente. Se omiten contraseñas y entradas ocultas del portapapeles. Desactivado por defecto.",
    },
    "Allow URL scheme automation (notchflow://)": {
        "pl": "Zezwól na automatyzację URL scheme (notchflow://)",
        "de": "URL-Schema-Automatisierung erlauben (notchflow://)",
        "it": "Consenti automazione URL scheme (notchflow://)",
        "es": "Permitir automatización URL scheme (notchflow://)",
    },
    "When disabled, other apps cannot control NotchFlow via notchflow://. Camera mirror requires additional confirmation.": {
        "pl": "Gdy wyłączone, inne aplikacje nie mogą sterować NotchFlow przez adres notchflow://. Lustro kamery wymaga dodatkowego potwierdzenia.",
        "de": "Wenn deaktiviert, können andere Apps NotchFlow nicht über notchflow:// steuern. Kameraspiegel erfordert zusätzliche Bestätigung.",
        "it": "Se disattivato, altre app non possono controllare NotchFlow via notchflow://. Lo specchio della fotocamera richiede conferma aggiuntiva.",
        "es": "Si está desactivado, otras apps no pueden controlar NotchFlow vía notchflow://. El espejo de cámara requiere confirmación adicional.",
    },
    "Share track titles for lyrics lookup": {
        "pl": "Udostępniaj tytuły utworów do wyszukiwania tekstów",
        "de": "Tracktitel für Songtext-Suche teilen",
        "it": "Condividi titoli brani per ricerca testi",
        "es": "Compartir títulos para búsqueda de letras",
    },
    "Sends title and artist to lrclib.net only while playing and only when enabled.": {
        "pl": "Wysyła tytuł i artystę do lrclib.net wyłącznie podczas odtwarzania i tylko gdy włączone.",
        "de": "Sendet Titel und Künstler nur während der Wiedergabe und nur wenn aktiviert an lrclib.net.",
        "it": "Invia titolo e artista a lrclib.net solo durante la riproduzione e se abilitato.",
        "es": "Envía título y artista a lrclib.net solo durante la reproducción y si está activado.",
    },
    "NotchFlow does not collect telemetry in version 1.0.": {
        "pl": "NotchFlow nie zbiera telemetrii w wersji 1.0.",
        "de": "NotchFlow sammelt in Version 1.0 keine Telemetrie.",
        "it": "NotchFlow non raccoglie telemetria nella versione 1.0.",
        "es": "NotchFlow no recopila telemetría en la versión 1.0.",
    },
    "Network access is used for license verification, updates, and optional local API.": {
        "pl": "Dostęp do sieci służy weryfikacji licencji, aktualizacjom i opcjonalnemu API lokalnemu.",
        "de": "Netzwerkzugriff dient Lizenzprüfung, Updates und optionaler lokaler API.",
        "it": "L'accesso di rete serve per verifica licenza, aggiornamenti e API locale opzionale.",
        "es": "El acceso a red se usa para verificación de licencia, actualizaciones y API local opcional.",
    },
    "Security and privacy policy": {
        "pl": "Polityka bezpieczeństwa i prywatności",
        "de": "Sicherheits- und Datenschutzrichtlinie",
        "it": "Informativa sicurezza e privacy",
        "es": "Política de seguridad y privacidad",
    },
    # Integrations
    "Enable local API (Raycast)": {
        "pl": "Włącz lokalne API (Raycast)",
        "de": "Lokale API aktivieren (Raycast)",
        "it": "Abilita API locale (Raycast)",
        "es": "Activar API local (Raycast)",
    },
    "API running locally on this Mac": {
        "pl": "API działa lokalnie na tym Macu",
        "de": "API läuft lokal auf diesem Mac",
        "it": "API in esecuzione localmente su questo Mac",
        "es": "API ejecutándose localmente en este Mac",
    },
    "Off by default — enable only if you use Raycast integration.": {
        "pl": "Wyłączone domyślnie — włącz tylko jeśli używasz integracji Raycast.",
        "de": "Standardmäßig aus — nur aktivieren bei Raycast-Integration.",
        "it": "Disattivato di default — abilita solo con integrazione Raycast.",
        "es": "Desactivado por defecto — activa solo si usas integración Raycast.",
    },
    "Raycast": {"pl": "Raycast", "de": "Raycast", "it": "Raycast", "es": "Raycast"},
    "Start API to see address": {
        "pl": "Uruchom API, aby zobaczyć adres",
        "de": "API starten, um Adresse anzuzeigen",
        "it": "Avvia API per vedere l'indirizzo",
        "es": "Inicia la API para ver la dirección",
    },
    "In the Raycast extension, only the API Token is needed — the address is read automatically from api.json. Fixed port: %lld.": {
        "pl": "W rozszerzeniu Raycast wystarczy Token API — adres jest odczytywany automatycznie z api.json. Stały port: %lld.",
        "de": "In der Raycast-Erweiterung reicht das API-Token — die Adresse wird automatisch aus api.json gelesen. Fester Port: %lld.",
        "it": "Nell'estensione Raycast basta il Token API — l'indirizzo viene letto automaticamente da api.json. Porta fissa: %lld.",
        "es": "En la extensión Raycast basta el Token API — la dirección se lee automáticamente de api.json. Puerto fijo: %lld.",
    },
    # License
    "Beta period — all Premium features are unlocked. A key will be required in the stable release; any key entered now will be remembered.": {
        "pl": "Okres beta — wszystkie funkcje Premium są odblokowane. Aktywacja klucza będzie wymagana w wersji stabilnej; wpisany teraz klucz zostanie zapamiętany.",
        "de": "Beta-Phase — alle Premium-Funktionen sind freigeschaltet. Ein Schlüssel wird in der stabilen Version erforderlich sein; ein jetzt eingegebener Schlüssel wird gespeichert.",
        "it": "Periodo beta — tutte le funzioni Premium sono sbloccate. Una chiave sarà richiesta nella versione stabile; una chiave inserita ora verrà memorizzata.",
        "es": "Periodo beta — todas las funciones Premium están desbloqueadas. Se requerirá clave en la versión estable; cualquier clave introducida ahora se recordará.",
    },
    "License status": {"pl": "Status licencji", "de": "Lizenzstatus", "it": "Stato licenza", "es": "Estado de licencia"},
    "Plan": {"pl": "Plan", "de": "Plan", "it": "Piano", "es": "Plan"},
    "Activated": {"pl": "Aktywowano", "de": "Aktiviert", "it": "Attivato", "es": "Activado"},
    "License key": {"pl": "Klucz licencyjny", "de": "Lizenzschlüssel", "it": "Chiave licenza", "es": "Clave de licencia"},
    "Paste the key from your purchase at notchflow.eu (e.g. NOTCHFLOW_… or UUID from Polar email).": {
        "pl": "Wklej klucz z zakupu na notchflow.eu (np. NOTCHFLOW_… lub UUID z e-maila Polar).",
        "de": "Füge den Schlüssel vom Kauf auf notchflow.eu ein (z. B. NOTCHFLOW_… oder UUID aus der Polar-E-Mail).",
        "it": "Incolla la chiave dall'acquisto su notchflow.eu (es. NOTCHFLOW_… o UUID dall'e-mail Polar).",
        "es": "Pega la clave de tu compra en notchflow.eu (p. ej. NOTCHFLOW_… o UUID del correo Polar).",
    },
    "Activate license": {"pl": "Aktywuj licencję", "de": "Lizenz aktivieren", "it": "Attiva licenza", "es": "Activar licencia"},
    "Remove from this Mac": {"pl": "Usuń z tego Maca", "de": "Von diesem Mac entfernen", "it": "Rimuovi da questo Mac", "es": "Quitar de este Mac"},
    "Release activation (Polar)": {"pl": "Zwolnij aktywację (Polar)", "de": "Aktivierung freigeben (Polar)", "it": "Rilascia attivazione (Polar)", "es": "Liberar activación (Polar)"},
    "Buy Premium at notchflow.eu": {"pl": "Kup Premium na notchflow.eu", "de": "Premium auf notchflow.eu kaufen", "it": "Acquista Premium su notchflow.eu", "es": "Comprar Premium en notchflow.eu"},
    "Free": {"pl": "Darmowa", "de": "Kostenlos", "it": "Gratuita", "es": "Gratis"},
    "Annual": {"pl": "Roczna", "de": "Jährlich", "it": "Annuale", "es": "Anual"},
    "Lifetime": {"pl": "Dożywotnia", "de": "Lebenslang", "it": "A vita", "es": "De por vida"},
    "License activated.": {"pl": "Licencja została aktywowana.", "de": "Lizenz wurde aktiviert.", "it": "Licenza attivata.", "es": "Licencia activada."},
    "License removed from this Mac.": {"pl": "Licencja została usunięta z tego Maca.", "de": "Lizenz wurde von diesem Mac entfernt.", "it": "Licenza rimossa da questo Mac.", "es": "Licencia eliminada de este Mac."},
    "Activation released in Polar. You can activate the key on another Mac.": {
        "pl": "Aktywacja została zwolniona w Polar. Możesz aktywować klucz na innym Macu.",
        "de": "Aktivierung in Polar freigegeben. Du kannst den Schlüssel auf einem anderen Mac aktivieren.",
        "it": "Attivazione rilasciata in Polar. Puoi attivare la chiave su un altro Mac.",
        "es": "Activación liberada en Polar. Puedes activar la clave en otro Mac.",
    },
    # License errors
    "The license key is invalid.": {
        "pl": "Klucz licencyjny jest nieprawidłowy.",
        "de": "Der Lizenzschlüssel ist ungültig.",
        "it": "La chiave di licenza non è valida.",
        "es": "La clave de licencia no es válida.",
    },
    "Could not connect to the license server. Check your internet connection and try again.": {
        "pl": "Nie udało się połączyć z serwerem licencji. Sprawdź internet i spróbuj ponownie.",
        "de": "Verbindung zum Lizenzserver fehlgeschlagen. Prüfe die Internetverbindung und versuche es erneut.",
        "it": "Impossibile connettersi al server licenze. Controlla internet e riprova.",
        "es": "No se pudo conectar al servidor de licencias. Comprueba internet e inténtalo de nuevo.",
    },
    "Activation limit reached for this key (max. 2 Macs).": {
        "pl": "Osiągnięto limit aktywacji dla tego klucza (maks. 2 Maci).",
        "de": "Aktivierungslimit für diesen Schlüssel erreicht (max. 2 Macs).",
        "it": "Limite attivazioni raggiunto per questa chiave (max 2 Mac).",
        "es": "Límite de activaciones alcanzado para esta clave (máx. 2 Mac).",
    },
    "The annual license has expired.": {
        "pl": "Roczna licencja wygasła.",
        "de": "Die Jahreslizenz ist abgelaufen.",
        "it": "La licenza annuale è scaduta.",
        "es": "La licencia anual ha caducado.",
    },
    "Cannot deactivate this activation. Try again later or use the Polar portal (Purchases → Deactivate).": {
        "pl": "Nie można dezaktywować tej aktywacji. Spróbuj później lub użyj portalu Polar (Purchases → Deactivate).",
        "de": "Diese Aktivierung kann nicht deaktiviert werden. Versuche es später oder nutze das Polar-Portal (Purchases → Deactivate).",
        "it": "Impossibile disattivare questa attivazione. Riprova più tardi o usa il portale Polar (Purchases → Deactivate).",
        "es": "No se puede desactivar esta activación. Inténtalo más tarde o usa el portal Polar (Purchases → Deactivate).",
    },
    # Sidebar footer
    "Check for updates": {"pl": "Sprawdź aktualizacje", "de": "Nach Updates suchen", "it": "Controlla aggiornamenti", "es": "Buscar actualizaciones"},
    "Updates disabled in local build.": {
        "pl": "Aktualizacje wyłączone w lokalnym buildzie.",
        "de": "Updates im lokalen Build deaktiviert.",
        "it": "Aggiornamenti disabilitati nel build locale.",
        "es": "Actualizaciones desactivadas en compilación local.",
    },
    # HUD
    "Volume": {"pl": "Głośność", "de": "Lautstärke", "it": "Volume", "es": "Volumen"},
    "Brightness": {"pl": "Jasność", "de": "Helligkeit", "it": "Luminosità", "es": "Brillo"},
    # Focus timer
    "Stopwatch": {"pl": "Stoper", "de": "Stoppuhr", "it": "Cronometro", "es": "Cronómetro"},
    "Pomodoro": {"pl": "Pomodoro", "de": "Pomodoro", "it": "Pomodoro", "es": "Pomodoro"},
    "Focus": {"pl": "Skupienie", "de": "Fokus", "it": "Concentrazione", "es": "Enfoque"},
    "Break": {"pl": "Przerwa", "de": "Pause", "it": "Pausa", "es": "Descanso"},
    "Time for a break — breathe": {
        "pl": "Czas na przerwę — oddychaj",
        "de": "Zeit für eine Pause — atme",
        "it": "Tempo di pausa — respira",
        "es": "Hora del descanso — respira",
    },
    "Focus session in progress": {
        "pl": "Sesja skupienia w toku",
        "de": "Fokussitzung läuft",
        "it": "Sessione di concentrazione in corso",
        "es": "Sesión de enfoque en curso",
    },
    "25 min work · 5 min break": {
        "pl": "25 min pracy · 5 min przerwy",
        "de": "25 Min. Arbeit · 5 Min. Pause",
        "it": "25 min lavoro · 5 min pausa",
        "es": "25 min trabajo · 5 min descanso",
    },
    "Start stopwatch": {"pl": "Start stopera", "de": "Stoppuhr starten", "it": "Avvia cronometro", "es": "Iniciar cronómetro"},
    "Start": {"pl": "Start", "de": "Start", "it": "Avvia", "es": "Iniciar"},
    "Pause": {"pl": "Pauza", "de": "Pause", "it": "Pausa", "es": "Pausa"},
    "Resume": {"pl": "Wznów", "de": "Fortsetzen", "it": "Riprendi", "es": "Reanudar"},
    "Timer finished": {"pl": "Minutnik zakończony", "de": "Timer beendet", "it": "Timer terminato", "es": "Temporizador finalizado"},
    "Time is up.": {"pl": "Czas minął.", "de": "Die Zeit ist abgelaufen.", "it": "Tempo scaduto.", "es": "Se acabó el tiempo."},
    "Long break.": {"pl": "Dłuższa przerwa.", "de": "Lange Pause.", "it": "Pausa lunga.", "es": "Descanso largo."},
    "Short break.": {"pl": "Krótka przerwa.", "de": "Kurze Pause.", "it": "Pausa breve.", "es": "Descanso corto."},
    # Shelf
    "Pinned": {"pl": "Przypięte", "de": "Angeheftet", "it": "Fissati", "es": "Fijados"},
    "Add": {"pl": "Dodaj", "de": "Hinzufügen", "it": "Aggiungi", "es": "Añadir"},
    "Add pinned file shortcut": {
        "pl": "Dodaj przypięty skrót do pliku",
        "de": "Angeheftete Dateiverknüpfung hinzufügen",
        "it": "Aggiungi scorciatoia file fissata",
        "es": "Añadir acceso directo fijado",
    },
    "Drop here": {"pl": "Upuść tutaj", "de": "Hier ablegen", "it": "Rilascia qui", "es": "Suelta aquí"},
    "Temporary files": {"pl": "Tymczasowe pliki", "de": "Temporäre Dateien", "it": "File temporanei", "es": "Archivos temporales"},
    "Drag onto the island": {"pl": "Przeciągnij na wyspę", "de": "Auf die Insel ziehen", "it": "Trascina sull'isola", "es": "Arrastra a la isla"},
    "Click to open · right-click to pin or remove": {
        "pl": "Kliknij, aby otworzyć · prawy klik, aby przypiąć lub usunąć",
        "de": "Klicken zum Öffnen · Rechtsklick zum Anheften oder Entfernen",
        "it": "Clic per aprire · clic destro per fissare o rimuovere",
        "es": "Clic para abrir · clic derecho para fijar o quitar",
    },
    "Free: %lld pinned, %lld temporary": {
        "pl": "Free: %lld przypięte, %lld tymczasowe",
        "de": "Free: %lld angeheftet, %lld temporär",
        "it": "Free: %lld fissati, %lld temporanei",
        "es": "Free: %lld fijados, %lld temporales",
    },
    "Open": {"pl": "Otwórz", "de": "Öffnen", "it": "Apri", "es": "Abrir"},
    "Reveal in Finder": {"pl": "Pokaż w Finderze", "de": "Im Finder anzeigen", "it": "Mostra nel Finder", "es": "Mostrar en Finder"},
    "Pin permanently": {"pl": "Przypnij na stałe", "de": "Dauerhaft anheften", "it": "Fissa permanentemente", "es": "Fijar permanentemente"},
    "Remove": {"pl": "Usuń", "de": "Entfernen", "it": "Rimuovi", "es": "Eliminar"},
    "Drop onto shelf": {"pl": "Upuść na półkę", "de": "In Ablage ablegen", "it": "Rilascia sulla mensola", "es": "Suelta en la bandeja"},
    "Cannot open file": {"pl": "Nie można otworzyć pliku", "de": "Datei kann nicht geöffnet werden", "it": "Impossibile aprire il file", "es": "No se puede abrir el archivo"},
    "\"%@\" is unavailable. Remove the shortcut from the shelf and add it again.": {
        "pl": "„%@” jest niedostępny. Usuń skrót z półki i dodaj go ponownie.",
        "de": "„%@“ ist nicht verfügbar. Entferne die Verknüpfung aus der Ablage und füge sie erneut hinzu.",
        "it": "«%@» non è disponibile. Rimuovi la scorciatoia dalla mensola e aggiungila di nuovo.",
        "es": "«%@» no está disponible. Quita el acceso directo de la bandeja y añádelo de nuevo.",
    },
    # Calendar
    "Calendar access denied.": {"pl": "Brak dostępu do kalendarza.", "de": "Kein Kalenderzugriff.", "it": "Accesso calendario negato.", "es": "Sin acceso al calendario."},
    "Grant access": {"pl": "Udziel dostępu", "de": "Zugriff gewähren", "it": "Concedi accesso", "es": "Conceder acceso"},
    "No events on this day": {"pl": "Brak wydarzeń w tym dniu", "de": "Keine Termine an diesem Tag", "it": "Nessun evento in questo giorno", "es": "Sin eventos este día"},
    "Open in Calendar": {"pl": "Otwórz w Kalendarzu", "de": "In Kalender öffnen", "it": "Apri in Calendario", "es": "Abrir en Calendario"},
    "Open meeting": {"pl": "Otwórz spotkanie", "de": "Meeting öffnen", "it": "Apri riunione", "es": "Abrir reunión"},
    "Previous month": {"pl": "Poprzedni miesiąc", "de": "Vorheriger Monat", "it": "Mese precedente", "es": "Mes anterior"},
    "Next month": {"pl": "Następny miesiąc", "de": "Nächster Monat", "it": "Mese successivo", "es": "Mes siguiente"},
    # Clipboard
    "Clipboard disabled": {"pl": "Schowek wyłączony", "de": "Zwischenablage deaktiviert", "it": "Appunti disattivati", "es": "Portapapeles desactivado"},
    "NotchFlow can store recent text and links locally. Data never leaves your Mac.": {
        "pl": "NotchFlow może lokalnie zapisywać ostatnie teksty i linki. Dane nie opuszczają Maca.",
        "de": "NotchFlow kann zuletzt kopierte Texte und Links lokal speichern. Daten verlassen deinen Mac nicht.",
        "it": "NotchFlow può salvare localmente testi e link recenti. I dati non lasciano il Mac.",
        "es": "NotchFlow puede guardar textos y enlaces recientes localmente. Los datos no salen de tu Mac.",
    },
    "Enable clipboard monitoring": {
        "pl": "Włącz monitoring schowka",
        "de": "Zwischenablage-Überwachung aktivieren",
        "it": "Abilita monitoraggio appunti",
        "es": "Activar monitorización del portapapeles",
    },
    "Enable and save now": {"pl": "Włącz i zapisz teraz", "de": "Jetzt aktivieren und speichern", "it": "Abilita e salva ora", "es": "Activar y guardar ahora"},
    "Monitoring enabled": {"pl": "Monitoring włączony", "de": "Überwachung aktiv", "it": "Monitoraggio attivo", "es": "Monitorización activada"},
    "Save now": {"pl": "Zapisz teraz", "de": "Jetzt speichern", "it": "Salva ora", "es": "Guardar ahora"},
    "Copy something — it will appear here.": {
        "pl": "Skopiuj coś — pojawi się tutaj.",
        "de": "Kopiere etwas — es erscheint hier.",
        "it": "Copia qualcosa — apparirà qui.",
        "es": "Copia algo — aparecerá aquí.",
    },
    "Limit: %lld/%lld": {"pl": "Limit: %lld/%lld", "de": "Limit: %lld/%lld", "it": "Limite: %lld/%lld", "es": "Límite: %lld/%lld"},
    "Clipboard monitoring": {"pl": "Monitoring schowka", "de": "Zwischenablage-Überwachung", "it": "Monitoraggio appunti", "es": "Monitorización portapapeles"},
    "Search in Premium": {"pl": "Wyszukiwanie w Premium", "de": "Suche in Premium", "it": "Ricerca in Premium", "es": "Búsqueda en Premium"},
    "Search history…": {"pl": "Szukaj w historii…", "de": "Verlauf durchsuchen…", "it": "Cerca nella cronologia…", "es": "Buscar en historial…"},
    "Paste again": {"pl": "Wklej ponownie", "de": "Erneut einfügen", "it": "Incolla di nuovo", "es": "Pegar de nuevo"},
    "Raycast (optional)": {"pl": "Raycast (opcjonalnie)", "de": "Raycast (optional)", "it": "Raycast (opzionale)", "es": "Raycast (opcional)"},
    "Local API for Raycast": {"pl": "Lokalne API dla Raycast", "de": "Lokale API für Raycast", "it": "API locale per Raycast", "es": "API local para Raycast"},
    "Starting API…": {"pl": "Uruchamianie API…", "de": "API wird gestartet…", "it": "Avvio API…", "es": "Iniciando API…"},
    "Copied": {"pl": "Skopiowano", "de": "Kopiert", "it": "Copiato", "es": "Copiado"},
    "Copy configuration": {"pl": "Kopiuj konfigurację", "de": "Konfiguration kopieren", "it": "Copia configurazione", "es": "Copiar configuración"},
    "More…": {"pl": "Więcej…", "de": "Mehr…", "it": "Altro…", "es": "Más…"},
    "Enable so the Raycast extension can read NotchFlow clipboard history.": {
        "pl": "Włącz, aby rozszerzenie Raycast mogło czytać historię schowka NotchFlow.",
        "de": "Aktivieren, damit die Raycast-Erweiterung den NotchFlow-Zwischenablageverlauf lesen kann.",
        "it": "Abilita così l'estensione Raycast può leggere la cronologia appunti NotchFlow.",
        "es": "Activa para que la extensión Raycast pueda leer el historial del portapapeles NotchFlow.",
    },
    # Notes
    "Notes: %lld/%lld": {"pl": "Notatki: %lld/%lld", "de": "Notizen: %lld/%lld", "it": "Note: %lld/%lld", "es": "Notas: %lld/%lld"},
    "Quick note…": {"pl": "Szybka notatka…", "de": "Schnelle Notiz…", "it": "Nota rapida…", "es": "Nota rápida…"},
    "Add note": {"pl": "Dodaj notatkę", "de": "Notiz hinzufügen", "it": "Aggiungi nota", "es": "Añadir nota"},
    "Capture ideas before they disappear.": {
        "pl": "Zapisuj pomysły, zanim znikną.",
        "de": "Halte Ideen fest, bevor sie verschwinden.",
        "it": "Cattura le idee prima che scompaiano.",
        "es": "Captura ideas antes de que desaparezcan.",
    },
    "Delete note": {"pl": "Usuń notatkę", "de": "Notiz löschen", "it": "Elimina nota", "es": "Eliminar nota"},
    "Free plan allows up to %lld notes.": {
        "pl": "W wersji darmowej możesz zapisać do %lld notatek.",
        "de": "Im kostenlosen Plan sind bis zu %lld Notizen möglich.",
        "it": "Nel piano gratuito puoi salvare fino a %lld note.",
        "es": "En el plan gratuito puedes guardar hasta %lld notas.",
    },
    # Mirror
    "Tap to enable camera": {
        "pl": "Dotknij, aby włączyć kamerę",
        "de": "Tippen, um Kamera zu aktivieren",
        "it": "Tocca per attivare la fotocamera",
        "es": "Toca para activar la cámara",
    },
    "Camera access denied.": {"pl": "Brak dostępu do kamery.", "de": "Kein Kamerazugriff.", "it": "Accesso fotocamera negato.", "es": "Sin acceso a la cámara."},
    "Enable NotchFlow in System Settings → Privacy & Security → Camera.": {
        "pl": "Włącz NotchFlow w Ustawienia systemowe → Prywatność i ochrona → Kamera.",
        "de": "Aktiviere NotchFlow unter Systemeinstellungen → Datenschutz & Sicherheit → Kamera.",
        "it": "Abilita NotchFlow in Impostazioni di Sistema → Privacy e sicurezza → Fotocamera.",
        "es": "Activa NotchFlow en Ajustes del Sistema → Privacidad y seguridad → Cámara.",
    },
    "Open camera settings": {"pl": "Otwórz ustawienia kamery", "de": "Kameraeinstellungen öffnen", "it": "Apri impostazioni fotocamera", "es": "Abrir ajustes de cámara"},
    "Camera mirror is a Premium feature.": {
        "pl": "Lustro kamery jest funkcją Premium.",
        "de": "Kameraspiegel ist eine Premium-Funktion.",
        "it": "Lo specchio della fotocamera è una funzione Premium.",
        "es": "El espejo de cámara es una función Premium.",
    },
    "Activate your license in Settings → License, then return here.": {
        "pl": "Aktywuj licencję w Ustawienia → Licencja, a potem wróć tutaj.",
        "de": "Aktiviere deine Lizenz unter Einstellungen → Lizenz und kehre dann hierher zurück.",
        "it": "Attiva la licenza in Impostazioni → Licenza, poi torna qui.",
        "es": "Activa tu licencia en Ajustes → Licencia y vuelve aquí.",
    },
    "Open license activation": {
        "pl": "Otwórz aktywację licencji",
        "de": "Lizenzaktivierung öffnen",
        "it": "Apri attivazione licenza",
        "es": "Abrir activación de licencia",
    },
    "Live": {"pl": "Na żywo", "de": "Live", "it": "Live", "es": "En vivo"},
    "Enable camera preview?": {
        "pl": "Włączyć podgląd kamery?",
        "de": "Kameravorschau aktivieren?",
        "it": "Attivare anteprima fotocamera?",
        "es": "¿Activar vista previa de cámara?",
    },
    "NotchFlow will request camera access. Continue?": {
        "pl": "NotchFlow poprosi o dostęp do kamery. Kontynuować?",
        "de": "NotchFlow wird Kamerazugriff anfordern. Fortfahren?",
        "it": "NotchFlow richiederà accesso alla fotocamera. Continuare?",
        "es": "NotchFlow solicitará acceso a la cámara. ¿Continuar?",
    },
    "Enable": {"pl": "Włącz", "de": "Aktivieren", "it": "Attiva", "es": "Activar"},
    # Media
    "Previous track": {"pl": "Poprzedni utwór", "de": "Vorheriger Titel", "it": "Brano precedente", "es": "Pista anterior"},
    "Pause playback": {"pl": "Wstrzymaj", "de": "Pause", "it": "Pausa", "es": "Pausar"},
    "Play": {"pl": "Odtwórz", "de": "Wiedergabe", "it": "Riproduci", "es": "Reproducir"},
    "Next track": {"pl": "Następny utwór", "de": "Nächster Titel", "it": "Brano successivo", "es": "Pista siguiente"},
    "Not Playing": {"pl": "Brak odtwarzania", "de": "Keine Wiedergabe", "it": "Nessuna riproduzione", "es": "Sin reproducción"},
    # Live activities
    "Incoming call": {"pl": "Połączenie przychodzące", "de": "Eingehender Anruf", "it": "Chiamata in arrivo", "es": "Llamada entrante"},
    "Decline call": {"pl": "Odrzuć połączenie", "de": "Anruf ablehnen", "it": "Rifiuta chiamata", "es": "Rechazar llamada"},
    "Answer call": {"pl": "Odbierz połączenie", "de": "Anruf annehmen", "it": "Rispondi alla chiamata", "es": "Contestar llamada"},
    "New message": {"pl": "Nowa wiadomość", "de": "Neue Nachricht", "it": "Nuovo messaggio", "es": "Nuevo mensaje"},
    "Messages": {"pl": "Wiadomości", "de": "Nachrichten", "it": "Messaggi", "es": "Mensajes"},
    "Notification": {"pl": "Powiadomienie", "de": "Mitteilung", "it": "Notifica", "es": "Notificación"},
    "Next Pomodoro session.": {
        "pl": "Kolejna sesja Pomodoro.",
        "de": "Nächste Pomodoro-Sitzung.",
        "it": "Prossima sessione Pomodoro.",
        "es": "Siguiente sesión Pomodoro.",
    },
    "Temporary": {"pl": "Tymczasowe", "de": "Temporär", "it": "Temporanei", "es": "Temporales"},
    "Pin": {"pl": "Przypnij", "de": "Anheften", "it": "Fissa", "es": "Fijar"},
    "Today": {"pl": "Dzisiaj", "de": "Heute", "it": "Oggi", "es": "Hoy"},
    "W": {"pl": "T", "de": "W", "it": "S", "es": "S"},
    "API address": {"pl": "Adres API", "de": "API-Adresse", "it": "Indirizzo API", "es": "Dirección API"},
    "API Token": {"pl": "Token API", "de": "API-Token", "it": "Token API", "es": "Token API"},
    "Copy": {"pl": "Kopiuj", "de": "Kopieren", "it": "Copia", "es": "Copiar"},
    "Install NotchFlow extension (repo)": {
        "pl": "Zainstaluj rozszerzenie NotchFlow (repo)",
        "de": "NotchFlow-Erweiterung installieren (Repo)",
        "it": "Installa estensione NotchFlow (repo)",
        "es": "Instalar extensión NotchFlow (repo)",
    },
}


def build_catalog() -> dict:
    strings: dict = {}
    for key, langs in sorted(TRANSLATIONS.items()):
        entry: dict = {"localizations": {}}
        for lang in ("pl", "de", "it", "es"):
            entry["localizations"][lang] = {
                "stringUnit": {"state": "translated", "value": langs[lang]}
            }
        strings[key] = entry
    return {
        "sourceLanguage": "en",
        "strings": strings,
        "version": "1.0",
    }


def validate_catalog(catalog_path: Path) -> list[str]:
    required = ("pl", "de", "it", "es")
    data = json.loads(catalog_path.read_text(encoding="utf-8"))
    strings = data.get("strings", {})
    missing: list[str] = []
    for key, entry in strings.items():
        localizations = entry.get("localizations", {})
        for language in required:
            language_entry = localizations.get(language)
            if not language_entry:
                missing.append(f"{key}: missing {language}")
                continue
            unit = language_entry.get("stringUnit", {})
            value = unit.get("value", "")
            plural = language_entry.get("variations", {}).get("plural", {})
            if not value and not plural:
                missing.append(f"{key}: empty {language}")
    return missing


def main() -> None:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(build_catalog(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {len(TRANSLATIONS)} strings to {OUTPUT}")

    missing = validate_catalog(OUTPUT)
    if missing:
        print("Validation failed:", file=sys.stderr)
        for line in missing:
            print(f"  {line}", file=sys.stderr)
        raise SystemExit(1)
    print("Validation passed for pl, de, it, es")


if __name__ == "__main__":
    main()
