# Master Template for Android Apps

> Conventions for sideloaded, single-developer Android apps that iterate via a
> sprint-feedback loop over Tailscale. Adopt what fits; ignore what doesn't.

---

## New-app checklist (do these before writing any feature code)

1. **Scaffold the Compose + Room + Navigation skeleton** with the standard `gradle/libs.versions.toml` block (see "Standard dependencies").
2. **Use `applicationVariants.all { outputs }`** in `app/build.gradle.kts` to rename APK output to `<app-slug>-${versionName}-${buildType}.apk`. Required so `dist/serve_<app>.py` can pick "newest APK" by mtime and serve it.
3. **Create a `dist/` folder** with:
   - `serve_<app>.py` — the per-app local HTTP server. See "`dist/serve_<app>.py` requirements" below.
   - `sprint.md` seeded with `## Next Version (0/5 implemented)` plus 5 numbered slots.
   - `crashes/` (gitignored).
   - `.gitignore`: `crashes/` and `*.apk`.
4. **Pick a unique port** for the per-app local server. Maintain a small registry (e.g. a `~/PORTS.md` file) so two apps don't collide on the same port.
5. **Wire `CrashReporter.install(this)` as the FIRST line in `Application.onCreate()`**, before the DI container, before Room, before any other init. The crash handler must capture init crashes that happen before the rest of the app boots.
6. **Create three notification channels** in `Application.onCreate()` (or whichever subset you use): regular reminders (HIGH), full-screen alarms (MAX, bypass DND), app updates (DEFAULT). Use stable IDs as `companion object` constants on the `Application` class.
7. **Add an in-app feedback / debug-log FAB or menu item** that calls `CrashReporter.sendLogManually(context, userMessage) { ... }`. This is the channel through which sprint items get collected.
8. **Show the version number in the top app bar of the home screen.** Tappable. Tap → changelog dialog. If a newer version is available, replace it with "v{current} — tap to update to v{next}" linking to the APK download URL.
9. **Configure `network_security_config.xml`** to allow cleartext to your Tailscale IP (or set `usesCleartextTraffic="true"` for the whole app — the former is stricter).
10. **Add a CLAUDE.md** to the repo root with project overview + tech stack + key impl notes (see "README/docs conventions" below).
11. **For any app that's more than a glorified one-screen demo**, add a `SPEC.md` (vision/scope) and a `REFACTOR.md` (anti-patterns / lessons learned).
12. **Launch the sprint server under `Monitor` inside the active Claude Code session** (not in a separate terminal). See § "Running the sprint server in-session" below. This is what wires the in-app debug-log FAB to Claude Code's chat in real time.

---

## Always-on requirements (every Android app should do these)

| # | Requirement | Why |
|---|---|---|
| 1 | **Show app version in UI** (typically TopAppBar subtitle on home screen) | Sideload distribution: nobody knows which build a phone has |
| 2 | **Read version from `PackageManager`, not `BuildConfig` directly** | `BuildConfig` caches across debug builds and lies to you |
| 3 | **In-app debug log / feedback channel** that POSTs to a sideload server, **reachable from every screen** (not just Home). Convention: global debug FAB at `BottomStart`, per-screen FABs (add buttons, etc.) at `BottomEnd` — no overlap, no stacking. Hoist into a `DebugFabHost` composable that wraps the NavHost so a single instance overlays all routes. | Bugs surface anywhere in the UI, so the FAB must be everywhere too. This is how sprint items get collected — type the feedback into the app, server stores it. |
| 4 | **Auto-installed `Thread.setDefaultUncaughtExceptionHandler`** that writes to disk and POSTs on next launch | Crashes during init never reach you otherwise. `CrashReporter.install()` should be line 1 of `Application.onCreate`. |
| 5 | **Offline crash queue** (base64-line file, drained on next launch) | Tailscale server is sometimes asleep; reports must not be lost |
| 6 | **Update banner** polling `/version` every 30 s, replacing version subtitle when newer build is available | Sideload distro means there's no Play Store autoupdate |
| 7 | **Sprint indicator** ("v0.10.8 — sprint 3/5"), tappable for the planned-items list | The UI itself is the sprint dashboard |
| 8 | **Notification when sprint hits X/X and a newer APK is on the server** | Pushes the "ready to test" signal without app being open |
| 9 | **Consistent renamed APK output** (`<app>-<version>-<buildType>.apk`) | The dist server picks newest by mtime/glob |
| 10 | **Same Tailscale IP** as `serverUrl` default across all apps | One Tailscale net, predictable across apps |
| 11 | **Ship a `CHANGELOG.md` asset** at `app/src/main/assets/CHANGELOG.md`. The Home screen's "tap version" affordance loads it via `context.assets.open("CHANGELOG.md")` and renders it in a scrollable monospace dialog. **Update the file in the same diff that bumps `versionName`** — every sprint ship adds a new top-level section. | Without this the user has no way to find out what changed between two installed builds. `sprint.md` is dev-server-only; `CHANGELOG.md` ships with the APK. |

---

## The sprint-feedback-Tailscale loop

The signature workflow every iterating app should adopt.

### Files involved

- `app/src/main/java/.../util/CrashReporter.kt` — crash capture + offline queue + manual log send + `/version` poll + `/sprint` poll + `/sprint/items` fetch
- `app/src/main/java/.../util/UpdateNotifier.kt` — notification at sprint-complete + APK-ready
- `app/src/main/java/.../ui/screen/HomeScreen.kt` — TopAppBar subtitle, sprint dialog, debug-log FAB/menu item
- `dist/serve_<app>.py` — local Python HTTP server (stdlib only, no deps)
- `dist/sprint.md` — markdown of current sprint items
- `dist/crashes/` — incoming crash reports

### Running the sprint server in-session

The server **must run inside the active Claude Code session** (the one driving the sprint), not in some other terminal. Launch it with the `Monitor` tool, `persistent: true`, so each `[CRASH …]` block the server prints arrives in chat as a notification the moment it lands. That is the entire point of the loop — without it the FAB → server → Claude Code feedback path becomes a "remember to look at the crashes directory" chore.

Invocation pattern:

```text
Monitor(
  description: "<app> sprint server (port <PORT>)",
  command: "cd <repo> && python3 dist/serve_<app>.py",
  persistent: true,
  timeout_ms: 3600000,
)
```

Why `Monitor` and not `Bash run_in_background`:
- The server's `print(..., flush=True)` calls are **already** line-oriented events — no `tail -f`, no `grep` filter is needed. Each crash POST emits a single block ending in a flush. Each line becomes one chat notification.
- Background Bash buffers stdout to a file. You'd have to poll it; events don't surface in real time.
- The Monitor tool's "silence is not success" rule is satisfied because the server prints the startup banner (`<app> server on http://0.0.0.0:<port>`) on launch, prints each crash, and exits noisily on port-conflict / IO errors. Any failure mode produces output.

Lifecycle:
- Start the monitor at the beginning of a sprint (or whenever resuming work).
- Leave it running for the lifetime of the session — the `persistent: true` flag means it won't time out at 5 minutes.
- Use `TaskStop` to kill it when bumping versionCode/versionName so the rebuilt APK gets picked up cleanly by `find_newest_apk()`. (`find_newest_apk` reads from disk, not the running server, so technically a restart isn't required — but stopping + restarting is the cleanest signal that "we're now on the next sprint.")
- If the session ends or compacts, restart the monitor on the next turn. Do **not** keep multiple servers running on the same port across sessions.

Avoid:
- Running the server outside the session ("I'll start it in another tmux pane"). Crash reports still land in `dist/crashes/` but Claude Code never sees them, so triaging into `sprint.md` becomes manual.
- Wrapping the script in `tail -f` or `grep --line-buffered`. The server already emits exactly the lines you want; piping just adds buffer-flush risk.
- Setting a low `timeout_ms`. Sprints last hours; use the 1-hour max (3600000) and re-arm on the next turn if needed, or accept the limit and restart.

### How it loops

1. **User notices something while using the app** → taps debug-log icon (FAB or menu item) → types one-line message → `CrashReporter.sendLogManually` POSTs the message + recent logs + crash log + queued reports to `http://<tailscale-ip>:<port>/crash`.
2. **Sideload server writes the report** to `dist/crashes/crash_YYYYMMDD_HHMMSS.log` AND prints it to stdout. Because the server is running under `Monitor` inside this Claude Code session (see § "Running the sprint server in-session"), the printed block arrives as a chat notification the moment it lands — Claude Code reads it and triages without you having to point at the file.
3. **Claude Code session triages the report**:
   - Bug → fix immediately and ship as a single-item sprint.
   - Feature request → add a numbered item to `dist/sprint.md` under `## Next Version` AND **start implementing it right away.** The cadence is "implement as items arrive," not "queue 5 then build all 5." The line format is the user's verbatim quote first, then a one-paragraph implementation summary; once the work lands in code, prefix the title with `✅ **Title**` so the item is visually marked done.
4. **App polls `/sprint`** every 30 s; when `X/Y` increments (because a new item just got its `✅`), the home-screen subtitle updates: `v0.10.8 — sprint 3/5`. The X count grows incrementally during the sprint as work lands.
5. **At 5/5 — DO NOT push yet.** First do two passes:
   1. **Code review pass** — look for unused imports, orphaned dead code from earlier items, hard-coded strings that should be resources, missing null-checks, accidentally-broken existing tests. Treat it as a self-review of the sprint's combined diff.
   2. **Conflict review pass** — items implemented in isolation often break each other (classic example: two items both writing to the same store and ghosting each other). Walk every implemented item against every other; resolve any cross-talk before building.

   Only after both passes pass: bump `versionCode`+`versionName`, build with `./gradlew assembleDebug`, and the renamed APK lands in `app/build/outputs/apk/debug/`.
6. **Server's `find_newest_apk()` picks it up by mtime.** `/version` now returns `0.10.9|<app>-0.10.9-debug.apk`.
7. **App's update poller sees the new version** → `UpdateNotifier.maybeNotifySprintComplete` fires a notification: "Sprint 5/5 complete — v0.10.9 ready to install. Tap to download." Tap → opens download URL in browser → user installs.
8. **`sprint.md` rotates**: `## Next Version` becomes `## Previous Sprint (v0.10.9)`, a new empty `## Next Version (0/5 implemented)` is added.

### Server endpoints (all stdlib HTTP, no deps)

| Method | Path | Returns |
|---|---|---|
| `GET` | `/version` | `0.10.8\|<app>-0.10.8-debug.apk` |
| `GET` | `/version/beta` | same as above (beta-channel alias) |
| `GET` | `/sprint` | `3/5` |
| `GET` | `/sprint/items` | The `## Next Version` section of `sprint.md` as plain text |
| `POST` | `/crash` | Writes body to `crashes/crash_<ts>.log` and prints it; returns `OK` |
| `GET` | `/` | HTML download page with the latest beta APK |
| `GET` | `/<app>-<version>.apk` | The APK with `Content-Type: application/vnd.android.package-archive` |

### Critical sprint-loop conventions

- **Every sprint item starts with the user's verbatim quote and a timestamp.** Format: `User (May 1 16:24): "..."` then a one-paragraph fix description. Never paraphrase the complaint.
- **Implement items as they arrive, not in a batch at the end.** The 5/5 trigger is for the *build/push* step, not the implementation work. By the time the 5th item lands the previous four should already be in `✅` state — so the only fresh work at 5/5 is finishing the last item, then the two review passes, then the build.
- **Mark done items with `✅ **Title**`** prefix so the file's progress is visible at a glance and the `/sprint` count parser stays accurate (it counts ✅).
- **At 5/5, do code review THEN conflict review BEFORE building.** Two distinct passes, in that order. Code review looks at the diff per-item; conflict review walks pairs of items for cross-talk. Items often break each other when implemented in isolation.
- **Critical bugs ship immediately as a single-item sprint.** Treat them as one-line hotfixes shipped same-day.
- **Wrong-sprint-size detection:** if you ever ship a single non-critical item, retroactively note "should have queued" in `sprint.md` so the next sprint absorbs more.

---

## Recommended structure

```
<app>/
├── app/
│   ├── build.gradle.kts                    # alias plugins, BuildConfig on, applicationVariants APK rename
│   ├── proguard-rules.pro
│   └── src/main/
│       ├── AndroidManifest.xml
│       ├── java/<package>/
│       │   ├── <App>Application.kt         # CrashReporter.install + notification channels + DI container by lazy
│       │   ├── MainActivity.kt             # ComponentActivity + ComposeContent + setContent { <App>Theme { NavGraph(...) } }
│       │   ├── data/
│       │   │   ├── <App>Database.kt        # Room: getInstance() singleton with INSTANCE/synchronized
│       │   │   ├── *Dao.kt
│       │   │   ├── *Entity.kt
│       │   │   ├── SettingsStore.kt        # DataStore preferences OR SharedPreferences object
│       │   │   └── <App>Container.kt       # If app has > 3 deps; holds db + client + settings + scope
│       │   ├── service/                    # Foreground services
│       │   ├── receiver/                   # BroadcastReceivers (alarm, boot)
│       │   ├── network/                    # OkHttp client, WS, REST
│       │   ├── navigation/ (or ui/nav/)    # NavGraph, route constants
│       │   ├── ui/
│       │   │   ├── screen/                 # HomeScreen.kt, SettingsScreen.kt, etc. (each one composable per file)
│       │   │   ├── component/              # Reusable widgets
│       │   │   └── theme/                  # Theme.kt + Color.kt + Type.kt (Material 3)
│       │   ├── viewmodel/                  # AndroidViewModel + StateFlow
│       │   └── util/
│       │       ├── CrashReporter.kt        # Mandatory — see template
│       │       ├── UpdateNotifier.kt       # Mandatory if sprint loop is active
│       │       ├── DebugLogger.kt          # Optional — periodic state dump POSTed to server
│       │       └── AppSettings.kt          # Optional — small SharedPreferences wrapper + CompositionLocal
│       └── res/
│           ├── drawable/ic_notification.xml  # MUST exist — used as smallIcon for ALL notifications
│           ├── values/{strings,colors,themes}.xml
│           └── xml/network_security_config.xml  # Tailscale IP cleartext exception
├── gradle/
│   ├── libs.versions.toml                   # See "Standard dependencies" below
│   └── wrapper/
├── dist/
│   ├── serve_<app>.py                       # Sprint server
│   ├── sprint.md                            # Current sprint state (see template)
│   └── crashes/                             # Gitignored
├── build.gradle.kts                         # Top-level: just `apply false` plugins
├── settings.gradle.kts
├── gradle.properties
├── gradlew / gradlew.bat
├── README.md
├── CLAUDE.md                                # Project context for Claude Code
├── SPEC.md                                  # Vision + non-goals (for non-trivial apps)
└── REFACTOR.md                              # Anti-patterns + lessons (for apps that have evolved)
```

### Naming conventions

- **Package:** `com.app.<slug>` or `com.<brand>.<slug>`. Pick one and stick with it across your apps.
- **Application class:** `<Slug>Application`.
- **Theme:** `<Slug>Theme` Composable in `ui/theme/Theme.kt`.
- **Database:** `<App>Database` with `getInstance(ctx)` and a single DAO accessor.
- **APK filename:** `<slug>-<versionName>-<buildType>.apk`. Set via `applicationVariants.all { outputs.all { outputFileName = ... } }`.

---

## Standard dependencies (`gradle/libs.versions.toml`)

```toml
[versions]
agp = "8.5.2"
kotlin = "2.0.0"
ksp = "2.0.0-1.0.24"           # only if using Room
compose-bom = "2024.10.01"
navigation = "2.8.5"
room = "2.6.1"                  # only if persistent state
lifecycle = "2.8.6"
activity-compose = "1.9.2"
core-ktx = "1.13.1"
# Optional based on app needs:
okhttp = "4.12.0"
datastore = "1.1.1"
coil = "2.7.0"
coroutines = "1.8.1"

[libraries]
compose-bom = { group = "androidx.compose", name = "compose-bom", version.ref = "compose-bom" }
compose-ui = { group = "androidx.compose.ui", name = "ui" }
compose-ui-graphics = { group = "androidx.compose.ui", name = "ui-graphics" }
compose-ui-tooling-preview = { group = "androidx.compose.ui", name = "ui-tooling-preview" }
compose-ui-tooling = { group = "androidx.compose.ui", name = "ui-tooling" }
compose-material3 = { group = "androidx.compose.material3", name = "material3" }
compose-material-icons-extended = { group = "androidx.compose.material", name = "material-icons-extended" }
compose-animation = { group = "androidx.compose.animation", name = "animation" }
navigation-compose = { group = "androidx.navigation", name = "navigation-compose", version.ref = "navigation" }
room-runtime = { group = "androidx.room", name = "room-runtime", version.ref = "room" }
room-ktx = { group = "androidx.room", name = "room-ktx", version.ref = "room" }
room-compiler = { group = "androidx.room", name = "room-compiler", version.ref = "room" }
lifecycle-viewmodel-compose = { group = "androidx.lifecycle", name = "lifecycle-viewmodel-compose", version.ref = "lifecycle" }
lifecycle-runtime-compose = { group = "androidx.lifecycle", name = "lifecycle-runtime-compose", version.ref = "lifecycle" }
lifecycle-service = { group = "androidx.lifecycle", name = "lifecycle-service", version.ref = "lifecycle" }
activity-compose = { group = "androidx.activity", name = "activity-compose", version.ref = "activity-compose" }
core-ktx = { group = "androidx.core", name = "core-ktx", version.ref = "core-ktx" }
okhttp = { group = "com.squareup.okhttp3", name = "okhttp", version.ref = "okhttp" }
datastore-preferences = { group = "androidx.datastore", name = "datastore-preferences", version.ref = "datastore" }
coroutines-android = { group = "org.jetbrains.kotlinx", name = "kotlinx-coroutines-android", version.ref = "coroutines" }
junit = { group = "junit", name = "junit", version = "4.13.2" }
json = { group = "org.json", name = "json", version = "20240303" }   # required for any code that uses org.json from JVM unit tests; android.jar's stubs throw "not mocked"

[plugins]
android-application = { id = "com.android.application", version.ref = "agp" }
kotlin-android = { id = "org.jetbrains.kotlin.android", version.ref = "kotlin" }
kotlin-compose = { id = "org.jetbrains.kotlin.plugin.compose", version.ref = "kotlin" }
ksp = { id = "com.google.devtools.ksp", version.ref = "ksp" }
```

### `app/build.gradle.kts` skeleton

```kotlin
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.ksp)               // only if using Room
}

android {
    namespace = "com.app.<slug>"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.app.<slug>"
        minSdk = 26                       // Android 8.0
        targetSdk = 34
        versionCode = 1
        versionName = "0.1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        resValue("string", "app_name", "<App Display Name>")
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"   // OPTIONAL: lets debug + release coexist on the same device (useful for "beta channel")
            isMinifyEnabled = false
        }
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures {
        compose = true
        buildConfig = true                // Required so BuildConfig.VERSION_NAME is generated
    }

    applicationVariants.all {
        val variant = this
        outputs.all {
            val output = this as com.android.build.gradle.internal.api.BaseVariantOutputImpl
            output.outputFileName = "<slug>-${variant.versionName}-${variant.buildType.name}.apk"
        }
    }
}
```

---

## Build / release conventions

- **Versioning:** `versionCode` is a monotonic integer; `versionName` is `MAJOR.MINOR.PATCH` with PATCH bumped per sprint, MINOR bumped at major feature gates. Bumped manually in `app/build.gradle.kts` at the end of each sprint. No fastlane / no semantic-release / no CI bumping.
- **Always `clean` for sprint ships.** Use `./gradlew clean assembleDebug`, not `./gradlew assembleDebug`. Gradle's `generateDebugBuildConfig` task reports UP-TO-DATE even when `defaultConfig.versionName` changes, so the BuildConfig.java carries over from the previous build and crash reports show the wrong `app version` line. The user-facing version banner reads from `PackageManager` so it's correct either way, but diagnostic logs become misleading.
- **Update `CHANGELOG.md` in the same diff as the version bump.** Every sprint ship adds a new top-level `## vX.Y.Z — YYYY-MM-DD` section to `app/src/main/assets/CHANGELOG.md`. The Home screen's "tap version" affordance loads it from assets, so without an update the user sees stale content for the new build.
- **Build channel:** Debug only. No signed release builds. APK lands in `app/build/outputs/apk/debug/<slug>-<version>-debug.apk` and gets symlinked or `find_newest_apk()`-discovered by the dist server.
- **No CI/CD by default.** All builds are local `./gradlew assembleDebug` or via Claude Code.
- **Distribution:** Tailscale + sideload. The local Python server at `<tailscale-ip>:<port>` exposes the APK. Browse to it from your phone, tap download, tap install. No Play Store, no internal testing track.
- **Conflict-review pass at end of sprint:** Walk every implemented item against every other; resolve any cross-talk (state stores, shared keys, lifecycle order) BEFORE building.

---

## Logging, telemetry, and crash reporting conventions

### Crash reporter contract

- Lives in `util/CrashReporter.kt`.
- `install(context)` is called as the FIRST line of `Application.onCreate`, before any DI / Room / DataStore.
- Captures: timestamp, device manufacturer/model, Android version, app version, build type, package name, thread name, full stack trace, recent log file contents.
- Writes the report to disk synchronously (cache or external files dir).
- Posts to `<server>/crash` on a self-owned `SupervisorJob` scope (independent of the rest of the app).
- On `install`, drains any queued reports from previous sessions.
- Hardcoded fallback URLs (Tailscale relay + sideload server). Optional configured override resolved at upload time.
- `sendLogManually(context, userMessage, onResult)` is the API that the in-app feedback FAB calls.
- Compares versions with naive `split(".").mapNotNull { it.toIntOrNull() }`-style comparator. Good enough.

### Two valid implementations — pick one per app

| | Style A (no-deps) | Style B (OkHttp app) |
|---|---|---|
| HTTP client | `HttpURLConnection` (zero deps) | OkHttp (already needed for WebSocket) |
| Queue format | base64-line file in external files dir | Log files in `cacheDir/crashes/` |
| URL config | Hardcoded constants | Hardcoded fallback list + DataStore override |

**Recommendation:** Style B if you're already pulling in OkHttp; Style A if the app would otherwise have no networking dep.

### Optional: `DebugLogger` for state-machine apps

For apps with non-trivial scheduled / async behaviour, ship a `DebugLogger` that, when enabled from a Settings toggle, posts a 5-second-cadence state dump (alarm registration, scheduled times, permissions) to the server.

---

## Settings / preferences conventions

Two valid choices:

- **DataStore preferences** — preferred for typed, observed, suspend-edited config like `serverUrl + token`.
- **SharedPreferences** — fine for small bag-of-flags state, especially when you also want a `compositionLocalOf<Boolean>` so any composable can read it without prop-drilling.

**Settings screen UI conventions:**
- Always a separate screen (not a dialog) for connection-type settings; an `AlertDialog` is fine for app-internal toggles.
- Show "saved" inline next to the Save button after edit.
- Include a "How to find these:" footer with literal commands when settings reference an external system (Tailscale IP, server token, etc.).

---

## Theming / Compose conventions

- **Material 3 only.** `androidx.compose.material3.*`. No Material 2.
- **Single-activity** (`ComponentActivity`) + Compose Navigation. Each top-level destination is a route in one `NavGraph` Composable.
- **Theme structure:** `ui/theme/{Theme,Color,Type}.kt`. The Composable is named `<Slug>Theme`.
- **`enableEdgeToEdge()`** in `MainActivity.onCreate`.
- **`collectAsStateWithLifecycle`**, not `collectAsState`. ViewModels expose `StateFlow`.
- **No nested NavGraphs for ViewModel sharing.** Use a repository singleton on the Application.
- **`Companion object` MutableStateFlow as shared state is an anti-pattern.** Use a Container-owned repository instead.

---

## Notification patterns

- **Channels are created in `Application.onCreate`**, not lazily. IDs as `companion object` constants.
- **Channel taxonomy:**
  - `<feature>_reminders` — `IMPORTANCE_HIGH`, regular reminders
  - `<feature>_alarms` — `IMPORTANCE_MAX`, vibrate, alarm sound, `setBypassDnd(true)` for full-screen alarm experiences
  - `app_updates` — `IMPORTANCE_DEFAULT`, fired by `UpdateNotifier` when a sprint completes and a new APK is available
  - `<feature>_connection` — `IMPORTANCE_LOW`, `setShowBadge(false)` for foreground-service status notifications
- **`POST_NOTIFICATIONS` permission** is requested in `MainActivity.onCreate` only when `SDK_INT >= TIRAMISU` (33). Result is intentionally ignored — users can grant later. Or use a permission banner.
- **`smallIcon` always references `R.drawable.ic_notification`** (vector). Always present.
- **`PendingIntent.FLAG_IMMUTABLE` is mandatory** on Android 12+.
- **If you bump a channel's importance**, you MUST rename the channel ID. Android won't raise importance on existing channels.

---

## Background-work patterns

- **Foreground service** is the universal answer. Both event-driven and persistent-connection apps benefit from one.
- **No WorkManager required.** Could be added; not necessary for the patterns described here.
- **AlarmManager:** `setExactAndAllowWhileIdle()` with manual reschedule in the receiver. **Never `setRepeating()`.**
- **`AlarmReceiver.onReceive` must be synchronous:** wake lock → `startForegroundService()` → `startActivity()`. Async work in `goAsync()` AFTER. Calling `startForegroundService` from a coroutine **loses the exact-alarm exemption.**
- **`BootReceiver`** for `BOOT_COMPLETED` re-registers all scheduled alarms.
- **`USE_FULL_SCREEN_INTENT` + `SYSTEM_ALERT_WINDOW`** + `singleInstance` activity with `setShowWhenLocked` / `setTurnScreenOn` for full-screen alarm takeover.

---

## Networking conventions

- **OkHttp** is the standard. No Retrofit, no Ktor.
- **One `OkHttpClient` per app process.** Configured at construction with timeouts.
- **Auth:** Bearer token in `Authorization` header. Token stored in DataStore. UI hides it behind a password field with a `show/hide` toggle.
- **Default base URL** is the Tailscale IP `http://<tailscale-ip>:<port>`.
- **`network_security_config.xml`** with `<domain><tailscale-ip></domain>` cleartext exception is preferred over app-wide `usesCleartextTraffic="true"`.
- **WebSocket reconnect:** owned by a foreground service. Never reconnect from a Composable.
- **Polling pattern:** 30 s `LaunchedEffect(Unit) { while (true) { ...; delay(30_000) } }`. Pair with a `LifecycleEventObserver` ON_RESUME re-poll so foregrounding is snappy.

---

## Permissions UX

- **Recheck on resume** with a `LifecycleEventObserver` so the user sees the banner clear immediately after they return from system settings.
- **Single "Setup required" card** linking to a permission screen — not stacking three banners.
- **Standard runtime permissions to plan for:** `POST_NOTIFICATIONS` (Tiramisu+), `RECORD_AUDIO`, `USE_EXACT_ALARM` (33+) / `SCHEDULE_EXACT_ALARM` (31+), `SYSTEM_ALERT_WINDOW`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`.
- **`MainActivity.onCreate` requests `POST_NOTIFICATIONS` once**, ignores answer; users can grant later from settings.

---

## README / docs conventions

Every app has at minimum:

- **`README.md`**: 1-2 paragraph what-this-is, tech stack list, build/run commands, project layout (sometimes ASCII tree).
- **`CLAUDE.md`**: Project overview, project status, build/run commands, tech stack as bullets, architecture summary, data model, key impl details, "What is NOT in MVP" section.
- **`SPEC.md`** (non-trivial apps): vision, app flow per screen, "Alternatives considered and rejected" section, "Do NOT copy" list when referencing other apps as templates.
- **`REFACTOR.md`** (mature apps): "What's working", "What's broken (root causes)", phased refactor plan with Files Touched / Risk table, "What NOT to change", "Critical Architecture Rules (Learned the Hard Way)".

Tone: terse, technical, second-person occasional.

---

## Critical Architecture Rules (Learned the Hard Way)

New Android apps following this template should treat these as gospel:

1. `AlarmReceiver.onReceive()` must be synchronous: wake lock → `startForegroundService()` → `startActivity()`. Async work goes in `goAsync()` AFTER.
2. Never call `startForegroundService()` from a coroutine — loses the exact-alarm exemption.
3. Don't use `setRepeating()` — use `setExactAndAllowWhileIdle()` and reschedule in the receiver.
4. Don't advance the deadline date until the DEADLINE has passed, not the start time.
5. Don't use nested nav graphs for ViewModel sharing — use a repository singleton on the `Application`.
6. Show version from `PackageManager`, not `BuildConfig` (caches across debug builds).
7. Timer tick interval 250 ms, not 50 ms — 50 ms causes visible flickering on foldables.
8. `DatePicker` returns UTC midnight — parse with UTC `Calendar`, not local.

---

## Open questions for your template

Areas where existing implementations of this template diverge. Pick a default for your own apps and bake it in.

1. **Settings persistence:** DataStore vs SharedPreferences. DataStore is more modern/typed, SharedPreferences is simpler for tiny bag-of-flags. Reasonable default: **DataStore for connection config, SharedPreferences for app-internal toggles.**
2. **Cleartext config:** `usesCleartextTraffic="true"` vs `network_security_config.xml` IP whitelist. The latter is strictly safer. Reasonable default: **standardize on `network_security_config.xml`**.
3. **`debug` build type with `applicationIdSuffix = ".debug"`:** Lets debug + release coexist on the same device (used for "beta channel"). Useful when you want side-by-side beta + stable installs; otherwise omit.
4. **Version surface in UI:** Show version in TopAppBar (recommended for any user-facing app) vs only logging it (defensible for connection-only utility apps).
5. **Sprint loop scope:** The full sprint/feedback/Tailscale loop is high-overhead. Reasonable to skip for connection-only utilities; reasonable to demand for any app you actually iterate on.
6. **OkHttp vs `HttpURLConnection` for the crash reporter:** Use OkHttp for any app that already pulls it in for other reasons; `HttpURLConnection` only if the app would otherwise have no networking dep.
7. **`DebugLogger` periodic state dump:** Useful for any app where bugs are timing-dependent. Document as optional.
8. **Server-port allocation:** No central registry by default. Maintain a personal `~/PORTS.md` or similar so two apps don't collide.

---

## `dist/serve_<app>.py` requirements (write your own; stdlib only)

The dist server should be standard-library only (`http.server`, `glob`, `os`, `datetime`, `re`). No Flask, no FastAPI. This makes it run anywhere Python 3 runs without a venv.

It must implement the endpoints listed under "Server endpoints" above, plus:

- **APK discovery:** a `find_newest_apk()` function that globs `app/build/outputs/apk/debug/<slug>-*.apk` and picks the newest by mtime.
- **`PROD_VERSION` constant:** the version officially "promoted" to prod. Updated whenever a build is promoted.
- **Print on every event:** startup banner (`<app> server on http://0.0.0.0:<port>`), every `/crash` POST as a single block ending in a flush, and any failure mode (port conflict, IO error). The Monitor tool relies on these prints to surface activity in chat.
- **Sprint stubs:** if the app doesn't use the sprint workflow, keep `/sprint` and `/sprint/items` stubbed (returning `0/0` and empty) so the in-app poller doesn't 404 noisily.

---

## `dist/sprint.md` template

```markdown
# Current Sprint

## Next Version (0/5 implemented)

1. (open)
2. (open)
3. (open)
4. (open)
5. (open)

## Workflow
1. Debug log with user message → implement immediately
2. Track here under "Next Version"
3. At 5/5 → code review pass, conflict review pass, build, deploy
4. Critical bugs ship immediately
```
