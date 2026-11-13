# Lyricar: the complete guide

This guide explains **how Lyricar works** and walks you through **every step of the setup**, including where to find each ID. It also covers the most common problems.

**Contents**

1. [How Lyricar works](#1-how-lyricar-works)
2. [What you need](#2-what-you-need)
3. [Setup, step by step](#setup-step-by-step)
   - [Step 1: Create the Spotify app and get the Client ID](#step-1-create-the-spotify-app-and-get-the-client-id)
   - [Step 2: Find your Apple Team ID](#step-2-find-your-apple-team-id)
   - [Step 3: Choose a Bundle ID](#step-3-choose-a-bundle-id)
   - [Step 4: Configure the project](#step-4-configure-the-project)
   - [Step 5: Install on your iPhone](#step-5-install-on-your-iphone)
   - [Step 6: First launch](#step-6-first-launch)
   - [Step 7: Set it up for the car](#step-7-set-it-up-for-the-car)
4. [Using the app](#4-using-the-app)
5. [Troubleshooting](#5-troubleshooting)
6. [How long does the installed app last?](#6-how-long-does-the-installed-app-last)
7. [FAQ](#7-faq)

---

## 1. How Lyricar works

### The big picture

```
                    every 3 s
 ┌──────────────┐  "what's playing,      ┌─────────────────────────────┐
 │ Spotify      │   and where?"          │ Lyricar app (iPhone)        │
 │ Web API      │ ─────────────────────► │                             │
 └──────────────┘                        │  1. knows the song + time   │
                                         │  2. finds the current line  │      ┌──────────┐
 ┌──────────────┐  once per song         │  3. updates the Live        │ ───► │ CarPlay  │
 │ LRCLIB       │  "lyrics with          │     Activity on each line   │      │ dashboard│
 │ (lrclib.net) │   timestamps"          │                             │      └──────────┘
 └──────────────┘ ─────────────────────► └─────────────────────────────┘
```

Lyricar has two data sources:

- **Spotify Web API.** iOS does not let one app see what another app is playing, so Lyricar asks Spotify's servers directly through the `currently-playing` endpoint. Spotify returns the song, whether it is playing, and the **position in milliseconds**. This is why you have to sign in with Spotify.
- **LRCLIB.** Spotify does not give lyrics to third-party apps. Lyricar downloads them from [LRCLIB](https://lrclib.net), a free and open database of **LRC** lyrics, a format where each line carries a timestamp:
  ```
  [00:12.40] First line of the song
  [00:15.90] Second line
  ```
  Lyrics are cached on the phone, so each song is downloaded only once.

### Keeping in sync

When Spotify reports that a song is at position `p`, Lyricar works out the moment the song started:

```
song start = (time of the request) − p
```

Five times a second, the app compares the current time with that start time and picks the line whose timestamp has just passed. Every 3 seconds it checks with Spotify again:

- If the estimate has drifted by **less than 1 second**, it is corrected gently. This smooths out network jitter.
- If it is off by **more than 1 second**, you skipped, seeked or resumed, so the app re-aligns immediately.
- If the **song ID** changed, it fetches the new lyrics.

The **per-song offset** is added on top of all this, for songs whose LRCLIB lyrics are slightly off.

### Why a Live Activity and not just a widget?

The first version used only a **widget**. It drifted out of sync and sometimes froze. Here is why:

- A widget cannot run code continuously. It gives iOS a *timeline* of pre-computed "pages" with timestamps, and iOS decides when to actually redraw. On CarPlay these redraws can be **seconds late**.
- iOS also gives every widget a **daily budget** of refreshes. Once it is used up, the widget stops updating.

A **Live Activity** (the same technology behind food-delivery and sports-score banners) can be updated directly by the app whenever it wants. Since iOS 26, Live Activities are also shown on **CarPlay**. Lyricar updates it every time the line changes. The widget is still included as a simpler fallback.

### Driving Mode: staying alive in the background

To update the Live Activity, the app must keep running while it is in the background, with the screen locked and the phone in your pocket. iOS normally suspends background apps after a few seconds. **Driving Mode** uses two techniques at once:

| Technique | What it does | Weak spot |
|---|---|---|
| **Silent audio** | Plays silence, mixed with Spotify (it never interrupts or lowers your music). iOS keeps apps that play audio alive. | A **phone call** or Siri interrupts it, and iOS may not let it resume. |
| **Background location** | Uses the same mechanism as navigation apps. You will see the location arrow in the status bar. | Needs location permission. |

With both active, a phone call no longer freezes the lyrics. The location is **never stored or sent anywhere**: it is only used to keep the app awake.

Driving Mode turns itself off when there has been **no music for 15 minutes and CarPlay is disconnected**. You can also stop it manually or with an automation.

> These techniques are why Lyricar is a personal project: App Store review does not accept apps that use them just to stay awake.

### Where your data goes

| Data | Where it lives |
|---|---|
| Spotify login (tokens) | iOS Keychain, on your phone only |
| Lyrics | Cache on your phone |
| Settings, offsets, diagnostics | On your phone only |
| Network requests | Only to `accounts.spotify.com`, `api.spotify.com` and `lrclib.net` |

There is no Lyricar server and no analytics.

---

## 2. What you need

- [ ] A **Mac** with **Xcode 26** or later (free on the Mac App Store)
- [ ] An **iPhone** with **iOS 26** or later and a USB cable
- [ ] A car with **CarPlay**, wired or wireless
- [ ] An **Apple Developer Program** membership. A free Apple ID technically works, but the app stops working after 7 days and App Groups (needed here) may be unavailable.
- [ ] A **Spotify account**, plus access to a **Spotify Premium** account to create the Spotify app (see [Step 1](#step-1-create-the-spotify-app-and-get-the-client-id))

---

## Setup, step by step

You will collect three values and put them in one file:

| Value | Example | Where it comes from |
|---|---|---|
| `SPOTIFY_CLIENT_ID` | `1a2b3c4d5e6f…` (32 characters) | Spotify Developer Dashboard ([Step 1](#step-1-create-the-spotify-app-and-get-the-client-id)) |
| `DEVELOPMENT_TEAM` | `ABCDE12345` (10 characters) | Apple Developer account ([Step 2](#step-2-find-your-apple-team-id)) |
| `APP_BUNDLE_ID` | `com.yourname.lyricar` | You choose it ([Step 3](#step-3-choose-a-bundle-id)) |

### Step 1: Create the Spotify app and get the Client ID

The **Client ID** tells Spotify which app is asking for access. It is **not a secret**: no password is needed, because Lyricar uses the secure *PKCE* login flow.

1. Go to **[developer.spotify.com/dashboard](https://developer.spotify.com/dashboard)** and log in with your Spotify account.
2. If asked, accept the **Developer Terms of Service**.
3. Click **Create app** and fill in the form:

   | Field | What to enter |
   |---|---|
   | **App name** | `Lyricar` (anything works) |
   | **App description** | `Synced lyrics on CarPlay` (anything works) |
   | **Website** | leave empty |
   | **Redirect URIs** | `lyricar://callback`, then click **Add** |
   | **Which API/SDKs…** | ✅ **Web API** only. Do **not** tick iOS, Android or the others. |

4. Tick the Terms checkbox and click **Save**.
5. On the app page, click **Settings** (top right).
6. Under **Basic Information**, copy the **Client ID**, a 32-character string of letters and numbers. You do **not** need the *Client secret*, so never share it.
7. Still in **Settings**, open the **User Management** tab and add the **name and email of every Spotify account** that will sign in to Lyricar, **including your own** if it differs from the account that owns the app. Use the email shown on [spotify.com/account](https://www.spotify.com/account) for each account.

> [!IMPORTANT]
> **"I can't tick Web API" / "Upgrade to Spotify Premium to access the Web API"**
>
> Spotify only lets **Premium** accounts use the Web API in development mode.
> - Check that you are logged in with the right account: compare the top-right corner of the dashboard with [spotify.com/account](https://www.spotify.com/account). Try a private browser window.
> - **Family / Duo plan members:** the checkbox may stay disabled. Ask the **plan manager** to create the app with their account and add *you* in **User Management**.
> - **Using someone else's Premium account works too.** Whoever has Premium creates the app and adds your email in User Management. You then sign in to Lyricar with **your own** account and see **your own** music. They need to keep their Premium and keep the app on their dashboard.

### Step 2: Find your Apple Team ID

The **Team ID** is a 10-character code that identifies your Apple developer account. Xcode uses it to sign the app.

**Option A: website (easiest)**
1. Go to **[developer.apple.com/account](https://developer.apple.com/account)** and sign in.
2. Scroll to **Membership details**.
3. Copy the **Team ID**, for example `ABCDE12345`.

While you are there, check the **Expiration Date** of your membership (see [section 6](#6-how-long-does-the-installed-app-last)).

**Option B: Keychain Access on your Mac**
1. Open **Keychain Access** and search for `Apple Development`.
2. Double-click the certificate.
3. The **Organizational Unit** field is your Team ID.

**Option C: Xcode**
1. **Xcode → Settings → Accounts.** Add your Apple ID if it is not there.
2. Open any project, go to a target → **Signing & Capabilities**, and pick your team. The Team ID then appears in **Build Settings → Development Team**.

### Step 3: Choose a Bundle ID

The **Bundle ID** is the app's unique identifier, written in reverse-domain style. You **make it up**, but it must be unique across all of Apple. Good examples:

```
com.yourname.lyricar
io.github.yourgithubname.lyricar
```

Use only letters, numbers, dots and hyphens. Lyricar derives the other identifiers from it automatically:

| Identifier | Value |
|---|---|
| App | `com.yourname.lyricar` |
| Widget | `com.yourname.lyricar.widget` |
| App Group (lets the app and widget share the login) | `group.com.yourname.lyricar` |

If Xcode later says the Bundle ID *"is not available"* or is *"already in use"*, just pick another one.

### Step 4: Configure the project

1. Download the project:
   ```sh
   git clone https://github.com/Gennaro0408-bit/lyricar.git
   cd lyricar
   ```
   No git? On GitHub click **Code → Download ZIP** and unzip it.
2. Create your personal configuration file from the template:
   ```sh
   cp Config/Local.xcconfig.example Config/Local.xcconfig
   ```
   Or, in Finder, duplicate `Config/Local.xcconfig.example` and rename the copy to `Local.xcconfig`.
3. Open `Config/Local.xcconfig` in any text editor and fill in your three values:
   ```
   DEVELOPMENT_TEAM = ABCDE12345
   APP_BUNDLE_ID = com.yourname.lyricar
   SPOTIFY_CLIENT_ID = 1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d
   ```
   No quotes, and nothing else on those lines.

`Local.xcconfig` is listed in `.gitignore`, so your IDs **never end up on GitHub**, even if you publish your fork.

> **Custom redirect URI (optional):** if your Spotify app already uses a different redirect, for example `myapp://callback`, add `CALLBACK_SCHEME = myapp` to `Local.xcconfig`. The redirect URI on the Spotify dashboard must always be `<CALLBACK_SCHEME>://callback`.

### Step 5: Install on your iPhone

1. Double-click **`Lyricar.xcodeproj`** to open it in Xcode.
2. Connect your iPhone with the cable, unlock it, and tap **Trust** if asked.
3. On the iPhone, turn on **Developer Mode**: **Settings → Privacy & Security → Developer Mode**. The iPhone restarts.
4. In Xcode's toolbar, select your iPhone as the run destination.
5. Click **▶︎ Run** (or press ⌘R).

The first time, Xcode registers the Bundle IDs and the App Group on your account. This is the **Automatically manage signing** option, which should stay on. Leave it to Xcode: you do **not** need to download or import provisioning profiles by hand.

If your iPhone says *"Untrusted Developer"*, go to **Settings → General → VPN & Device Management**, tap your developer account and tap **Trust**.

### Step 6: First launch

The app's interface is in Italian. Here is a quick glossary:

| In the app | Meaning |
|---|---|
| **Accedi con Spotify** | Sign in with Spotify |
| **Modalità guida** | Driving Mode |
| **Avvia all'apertura dell'app** | Start when the app opens |
| **Sincronia di questo brano / Offset** | Sync for this song / Offset |
| **Azzera** | Reset |
| **Diagnostica** | Diagnostics |
| **Nessun brano in riproduzione** | Nothing playing |
| **Testo sincronizzato non disponibile** | No synced lyrics available |

1. Open **Lyricar** and tap **Accedi con Spotify**.
2. Sign in with **your** Spotify account, the one added in User Management. The login page always lets you choose the account.
3. When asked for **location**, choose **Allow While Using App**.
4. When asked about **Live Activities**, allow them. If you missed it: **Settings → Lyricar → Live Activities**.
5. Play a song on Spotify. Within a few seconds you should see:
   - the lyrics scrolling inside the app;
   - after you lock the phone, the lyrics on the **Lock Screen** and in the **Dynamic Island**.

### Step 7: Set it up for the car

**See the lyrics on CarPlay**

1. Connect the iPhone to the car, by cable or wirelessly.
2. Make sure **Driving Mode** (*Modalità guida*) is on in Lyricar. By default it turns on whenever you open the app.
3. The Live Activity appears on the CarPlay dashboard or on the widgets page (the first page on the left). If you don't see it, check **iPhone Settings → General → CarPlay → [your car]** and make sure widgets and Live Activities are enabled.

**Optional: start and stop automatically**

iOS only allows a Live Activity to be *started* while the app is open. These two automations open Lyricar for you when you get in the car and stop it when you get out:

1. Open the **Shortcuts** app → **Automation** tab → **+**.
2. Choose **CarPlay → Connects → Run Immediately → Next**.
3. Search for the **Avvia testi in auto** action (*Start lyrics in the car*) from Lyricar and add it. Tap **Done**.
4. Repeat with **CarPlay → Disconnects** and the **Ferma testi in auto** action (*Stop lyrics in the car*).

**Optional: add the widget**

Lyricar also includes a small widget, *Testi Spotify*. It is less precise than the Live Activity, but needs no app running. Add it from the CarPlay widgets page (long-press → **+**) or from the iPhone Home Screen.

---

## 4. Using the app

- **Driving Mode switch.** Turns on background updates and the Live Activity.
- **Per-song offset.** If a song's lyrics run **late**, increase the offset. If they run **early**, decrease it. The value is saved **for that song only**. Use **Azzera** (Reset) to undo it, or reset all songs at the bottom of the screen.
- **Diagnostics** (*Diagnostica*). A log of what happened: song changes, re-alignments, audio interruptions (calls, Siri), Live Activity state, and network errors. The share button sends it as text, which is handy when reporting a bug.
- **Pull to refresh.** Forces an immediate check with Spotify.

---

## 5. Troubleshooting

### Spotify / login

| Symptom | Cause and fix |
|---|---|
| Web API checkbox greyed out / "Upgrade to Spotify Premium" | The account creating the app is not Premium. See the box in [Step 1](#step-1-create-the-spotify-app-and-get-the-client-id). |
| `INVALID_CLIENT: Invalid redirect URI` | The redirect on the dashboard doesn't match. It must be exactly `lyricar://callback`, or `<CALLBACK_SCHEME>://callback` if you changed it. |
| `INVALID_CLIENT: Invalid client` | `SPOTIFY_CLIENT_ID` is missing or wrong in `Local.xcconfig`. Rebuild after fixing it. |
| *"Account non autorizzato…"* (HTTP 403) after login | Your Spotify account is not in the app's **User Management** list on the dashboard. Add it. |
| *"Nessun brano in riproduzione"* while music plays | Music is playing from a source other than your Spotify account (radio, another app, or another account), or Spotify is paused. |

### Xcode / installation

| Error | Fix |
|---|---|
| *Signing for "Lyricar" requires a development team* | `DEVELOPMENT_TEAM` is missing in `Config/Local.xcconfig`, or Xcode overrode it. Check the file, then in **Signing & Capabilities** make sure *Automatically manage signing* is on and no team is set by hand. |
| *Embedded binary's bundle identifier is not prefixed with the parent app's bundle identifier* | Someone edited the Bundle IDs by hand in Xcode. Remove the manual edits (or regenerate the project with `xcodegen generate`) and set only `APP_BUNDLE_ID` in `Local.xcconfig`. |
| *Failed to register bundle identifier* / *not available* | Another developer already uses that Bundle ID. Choose a different `APP_BUNDLE_ID`. |
| Errors about **App Groups** or a profile that *doesn't support* them | You selected a downloaded or wildcard profile ("XC Wildcard"). Wildcard profiles can't contain App Groups. Use **Automatically manage signing** instead. |
| *Untrusted Developer* on the iPhone | **Settings → General → VPN & Device Management → Trust**. |
| *Developer Mode required* | **Settings → Privacy & Security → Developer Mode**. |

### Lyrics and sync

| Symptom | Cause and fix |
|---|---|
| Lyrics are always early or late on **one** song | LRCLIB has lyrics for a different version of that song. Use the **per-song offset**. The Diagnostics log shows `⚠️ … durata diversa` (different duration) when this is likely. |
| Lyrics are off on **every** song | Usually a constant CarPlay display delay. Set a small offset, or check that you don't have old offsets saved (use *Azzera gli offset di tutti i brani*). |
| *"Testo sincronizzato non disponibile"* | LRCLIB has no time-stamped lyrics for that song. You can contribute them at [lrclib.net](https://lrclib.net). |
| Lyrics **freeze** on one line | iOS suspended the app. Check that location permission is granted and Driving Mode is on, then look in Diagnostics for `⚠️ Nessun aggiornamento per … s` (no updates for … s) or audio interruptions. |
| No Live Activity on CarPlay | Enable Live Activities in **Settings → Lyricar**, turn Driving Mode off and on, and check the CarPlay settings in [Step 7](#step-7-set-it-up-for-the-car). |
| Widget is late or frozen | Expected: iOS limits widget refreshes. Use the Live Activity (Driving Mode). |

---

## 6. How long does the installed app last?

An app installed from Xcode is signed with a **certificate** and a **provisioning profile**. It keeps working until **the first** of these dates:

1. the **certificate** expiry (check in Keychain Access → *Apple Development* certificate → *Expires*);
2. the **provisioning profile** expiry (Xcode creates them with a one-year validity on paid accounts);
3. the end of your **Apple Developer Program membership** (developer.apple.com/account → *Membership details*), if it isn't renewed;
4. revocation of the certificate, or removal of the iPhone from your account.

With a **free Apple ID**, it's only **7 days**.

**To extend it:** before the expiry date, connect the iPhone and press **▶︎ Run** in Xcode again. Xcode renews the certificate and profile automatically, as long as your membership is active.

---

## 7. FAQ

**Can I see the lyrics without a Spotify Premium account?**
You can *use* Lyricar with any Spotify account added in User Management. The Spotify app itself, however, must be **created** by a Premium account, which can be someone else's.

**Does Lyricar work with Apple Music, YouTube Music, etc.?**
Not at the moment. Lyricar reads playback from Spotify's Web API.

**Does it drain the battery?**
Driving Mode uses about as much power as a navigation app running in the background. In the car the phone is usually charging, and Driving Mode turns itself off when CarPlay is disconnected and nothing has played for 15 minutes.

**Why isn't it on the App Store?**
It relies on background techniques (silent audio and background location) that App Review rejects when they are used only to stay awake, and it shows text to drivers. It's meant as a personal, sideloaded project.

**Is my Client ID secret? Can I publish my fork?**
The Client ID isn't a password. Still, keep it in `Config/Local.xcconfig`, which is git-ignored, so your fork stays clean and others create their own Spotify app.
