# Macchina 🚗🎵

App iOS che mostra il **testo della canzone in riproduzione su Spotify** su **CarPlay**, riga per riga e sincronizzato, tramite una Live Activity e un widget.

> ⚠️ **Sicurezza:** leggere mentre si guida distrae. Usa l'app come faresti con un navigatore: solo un'occhiata, oppure lasciala ai passeggeri. Il progetto è pensato per **uso personale**: l'App Store non accetterebbe un'app così.

## Come funziona

```
Spotify Web API ──► brano + posizione ──┐
                                        ├──► Macchina (app) ──► Live Activity ──► CarPlay
LRCLIB (lrclib.net) ──► testo LRC ──────┘          │
                                                   └──► Widget (WidgetKit)
```

- **Spotify Web API** (`/me/player/currently-playing`): dice quale brano suona e a che punto è. Il login usa OAuth PKCE, quindi non serve nessun client secret.
- **[LRCLIB](https://lrclib.net)**: database libero e gratuito di testi sincronizzati in formato LRC. I testi vengono salvati sul telefono, così ogni brano si scarica una volta sola.
- **Modalità guida**: l'app resta attiva in background (con un audio silenzioso mixato con Spotify più una sessione di posizione in background, che sopravvive alle telefonate). Controlla Spotify ogni 3 secondi e aggiorna la **Live Activity** a ogni riga. iOS 26 mostra le Live Activity anche su CarPlay.
- **Widget**: alternativa più semplice, ma meno precisa, perché iOS non garantisce l'aggiornamento al secondo.
- **Offset per brano**: se una canzone ha il testo sfasato (per esempio perché è di un'altra versione), lo correggi solo per quel brano.
- **Diagnostica**: un registro degli eventi dentro l'app (interruzioni dell'audio, errori, riallineamenti) per capire cosa è successo durante un viaggio.

## Requisiti

- Mac con **Xcode 26** o successivo
- iPhone con **iOS 26** e un'auto con CarPlay
- **Account Apple Developer**. Con l'Apple ID gratuito l'app scade dopo 7 giorni e l'App Group potrebbe non essere disponibile.
- **Spotify Premium** per chi crea l'app sulla dashboard Spotify, perché la Web API lo richiede
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), solo se modifichi `project.yml`

## Installazione

### 1. Crea l'app Spotify

1. Vai su [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard) e premi **Create app**.
2. Compila i campi:
   - **Redirect URI**: `macchina://callback`
   - **API**: spunta solo **Web API**
3. In **Settings → User Management** aggiungi l'email Spotify di chi userà l'app. In development mode è obbligatorio.
4. Copia il **Client ID**.

### 2. Configura il progetto

```sh
git clone https://github.com/Gennaro0408-bit/macchina.git
cd macchina
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

Apri `Config/Local.xcconfig` e inserisci i tuoi valori. Il file è nel `.gitignore`, quindi non finisce su GitHub.

```
DEVELOPMENT_TEAM = ABCDE12345          // il tuo Team ID Apple
APP_BUNDLE_ID = com.tuonome.macchina   // un Bundle ID univoco
SPOTIFY_CLIENT_ID = ...                // il Client ID Spotify
```

Widget e App Group vengono derivati da `APP_BUNDLE_ID`.

### 3. Installa sull'iPhone

1. Apri `Macchina.xcodeproj`.
2. Collega l'iPhone e attiva la **Modalità sviluppatore** (Impostazioni → Privacy e sicurezza).
3. Premi **▶︎ Run**. La firma è automatica.

### 4. Primo avvio

1. Apri l'app, premi **Accedi con Spotify** e consenti l'accesso alla **posizione** ("mentre usi l'app").
2. Fai partire una canzone: il testo deve scorrere nell'app e sulla schermata di blocco.
3. Facoltativo: crea due automazioni nell'app **Comandi**:
   - **CarPlay → Si connette → "Avvia testi in auto"**
   - **CarPlay → Si disconnette → "Ferma testi in auto"**

## Struttura

```
App/       app: login Spotify, motore dei testi, modalità guida, diagnostica
Widget/    widget WidgetKit + Live Activity
Shared/    codice comune: API Spotify, LRCLIB e parser LRC, Keychain, impostazioni
Config/    xcconfig (Local.xcconfig con i tuoi dati non viene pubblicato)
project.yml  definizione del progetto per XcodeGen
```

## Limiti noti

- Se il testo su LRCLIB è di una versione diversa del brano può essere sfasato: usa l'offset per brano.
- Spotify Web API in development mode è limitata agli utenti aggiunti in User Management.
- I testi appartengono ai rispettivi autori: il progetto li legge da LRCLIB per uso personale e non li ridistribuisce.

## Crediti

- Testi: [LRCLIB](https://lrclib.net)
- Dati di riproduzione: [Spotify Web API](https://developer.spotify.com/documentation/web-api)

Progetto non affiliato a Spotify né ad Apple.

## Licenza

[MIT](LICENSE)
