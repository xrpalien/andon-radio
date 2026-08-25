# Andon Radio

An Android remote for [Andon FM](https://andonlabs.com/radio) — four radio stations
run by four AI DJs — that sends any station to any Sonos speaker in the house.

Grew out of `dj-claude.sh`, which did the same thing for one station and one
hardcoded speaker IP.

## What it does

- Lists all four Andon stations with live now-playing info for each
- Discovers every Sonos room on the network, no configuration
- Routes playback correctly through Sonos groups
- Per-room volume via a rotary knob, plus mute
- Groups and ungroups rooms so several play together
- Remembers the last room and station
- Updates itself from GitHub Releases

## How it talks to Sonos

No Sonos account, no cloud, no official app required. Sonos players expose a
UPnP/SOAP control endpoint on **port 1400**, which is the same interface the
players use among themselves.

### Discovery is a two-step

Finding *one* player is the expensive part. After that, a single
`GetZoneGroupState` call to that player returns **the entire household** —
every room, its IP, and who is grouped with whom.

```
1. seed host from last run   (instant on a warm start)
2. SSDP M-SEARCH             (multicast, ~3s)
3. TCP sweep of the /24       (last resort; multicast blocked)
   └─> GetZoneGroupState  →  whole household
```

SSDP replies arrive as **unicast** to an ephemeral port, so no Android
multicast lock is needed. The lock is only required for multicast `NOTIFY`
announcements, which this app doesn't use.

### Grouping is the thing that bites

Only the **group coordinator** accepts transport commands. A room grouped
behind another is slaved with an `x-rincon:RINCON_<coordinator-uuid>` URI and
will silently ignore a stream sent directly to it.

```
Kitchen        PLAYING   x-rincon-mp3radio://streaming.live365.com/a15419   ← coordinator
Family Room    PLAYING   x-rincon:RINCON_00000000000801400                  ← slaved
```

So the app splits the two concerns deliberately:

| Command        | Sent to               | Why |
|----------------|-----------------------|-----|
| play / stop    | the group coordinator | anything else is a no-op |
| volume / mute  | the room you picked   | turning the knob on "Family Room" should change that room |

### Parsing the topology

`GetZoneGroupState` returns an XML document **escaped inside** an XML
document, so it needs parsing twice. Two things to filter:

- `Invisible="1"` members
- `<Satellite>` elements — a Sub or surround pair, which are nested *inside* a
  `ZoneGroupMember` and must not appear as rooms of their own

### Grouping rooms

Both halves are plain AVTransport actions, verified against real players:

| Action | Call |
|--------|------|
| join   | `SetAVTransportURI` on the joiner, `CurrentURI = x-rincon:RINCON_<coordinator>` |
| leave  | `BecomeCoordinatorOfStandaloneGroup` on the room |

A joined room immediately adopts whatever the group is playing. Leaving drops
it to standalone and silent. Clearing the transport by hand instead of using
`BecomeCoordinatorOfStandaloneGroup` leaves the player half-detached.

A group's coordinator cannot be removed from its own group, so the UI offers no
toggle for it rather than a control that does nothing.

### Stream URIs

Sonos wants `x-rincon-mp3radio://` for a continuous broadcast, so it never
tries to seek or report a duration:

```
x-rincon-mp3radio://streaming.live365.com/<mount>
```

| Station              | DJ               | Mount    |
|----------------------|------------------|----------|
| Thinking Frequencies | Claude Opus 5    | `a46431` |
| OpenAIR              | GPT 5.6 Sol      | `a81044` |
| Grok and Roll        | Grok 4.6         | `a15419` |
| Backlink Broadcast   | Gemini 3.7 Flash | `a13541` |

Each `SetAVTransportURI` carries a DIDL-Lite blob with the station title and
artwork, so the name and art show up in the Sonos app and on players with
displays. The `<desc id="cdudn">SA_RINCON65031_</desc>` marker identifies it as
third-party internet radio; some players refuse the item without it.

### A stopped player keeps its URI

`GetMediaInfo` still reports the last stream after a stop. So transport state
and station identity are read separately: the URI says *which* station the room
is set to, `GetTransportInfo` says whether it is actually playing.

Playback is likewise never assumed. The app waits for the player to report
`PLAYING` before saying so — a player accepts the URI, then goes away to open
the stream, and that is where a dead mount actually surfaces.

## Layout: the controls never scroll

**The cabinet is pinned and only the station grid scrolls.** This is a
correctness rule, not a style choice.

When the knob sat inside the scroll view, turning it and scrolling the page
competed for the same drag. The first attempt at a fix was a
`PanGestureRecognizer` whose `rejectGesture` accepts instead — but that does
not stop the scrollable from winning the arena, it only keeps the knob
processing events as well. Both fired: the knob turned *and* the page scrolled.
Taking the cabinet out of the scrollable removes the competition at the source,
and the workaround was deleted with it.

A widget test asserts the knob has no `Scrollable` ancestor, because this is
easy to undo by accident.

Layout follows from that rule:

| Viewport            | Arrangement                                  |
|---------------------|----------------------------------------------|
| portrait            | cabinet on top, grid scrolling beneath       |
| landscape / wide    | cabinet left, grid scrolling right           |
| short (< 700dp)     | cabinet drawn compact so it still fits       |

Stacking them vertically in landscape leaves the grid a few pixels tall, hence
the side-by-side case. `SafeArea` keeps the knob clear of the gesture bar,
which in landscape sits exactly where the knob wants to be.

## The volume knob

It is a real control, not a readout, and getting it to feel that way took two
more fixes beyond keeping it out of the scrollable:

- **Hit-test behaviour.** A `GestureDetector` defaults to `deferToChild`, so a
  drag starting on the centre readout arrived with `localPosition` measured
  from the `Text` rather than the knob, and every angle came out wrong. Needs
  `HitTestBehavior.opaque`.
- **Radial motion isn't rotation.** Grabbing the middle and pulling outwards
  barely changes the angle, so the knob sat still. The grip mode is decided
  once from the `onDown` point — rim turns it, centre works it like a fader —
  and held for the whole gesture. Deciding per-event flipped modes mid-drag,
  because the drag threshold has already moved the pointer ~18px by the time
  `onStart` fires.

The rim knurling is not decoration: it is the cue that says "turn me".

Volume also re-syncs on the poll, so changing it from the Sonos app or the
speaker's own buttons doesn't leave the dial stale — with a short suppression
window so a poll in flight can't snap the dial back under your finger.

## Two phones at once

The house has more than one person in it, so the app is built on the
assumption that the state it is showing may have been changed by someone
else a second ago — from the other phone, the Sonos app, or the buttons on
the speaker itself.

Every poll re-reads the household, in this order:

1. what each station is playing (Andon's API)
2. **grouping** — which decides who coordinates
3. transport state and current station, asked of that coordinator
4. volume and mute for the selected room

Grouping has to come first: it determines which player is the coordinator,
and the coordinator is who gets asked about transport and who receives
commands. A stale group meant commands addressed to a player that had
quietly become a follower, where they are silently dropped.

Polling runs at 5s while the app is in front and **stops entirely** in the
background, with an immediate refresh on resume — the moment the screen is
most likely to be out of date is the moment it comes back into view. That is
both livelier and cheaper than the slower always-on timer it replaced.

Two details worth keeping:

- The room list only rebuilds when the grouping actually changed, compared
  via a cheap signature. Rebuilding on every poll fights the user while they
  are looking at it.
- A volume poll is suppressed for 3s after the knob is touched, so a reply
  already in flight cannot snap the dial back under their finger.

Ticks are asynchronous, so one can still be in flight when the app closes.
All notifications go through a disposal guard; without it, closing the app
mid-poll threw.

## Android specifics

- Sonos control is plain HTTP, which Android blocks by default.
  `network_security_config.xml` permits cleartext and pins the known remote
  hosts back to HTTPS-only. CIDR ranges are *not* supported in `<domain>`
  elements, so private subnets can't be expressed there.
- Needs `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`,
  `CHANGE_WIFI_MULTICAST_STATE`.

## Layout

```
lib/
  models/     Station catalogue, zones, groups, household
  services/   SSDP + topology discovery, SOAP control, Andon metadata API
  state/      RadioController — the single ChangeNotifier the UI watches
  theme/      Material 3 theme, palette sampled from the Andon radio cabinet
  ui/         Cabinet, station grid, room picker, rotary knob, grille painter
```

## Distribution

The app is sideloaded rather than published to Play, and updates itself from
GitHub Releases.

```
tool/release.sh 1.1.0 "What changed."
```

That bumps the version, runs the tests, builds a signed APK, tags the commit
and publishes the release. The app reads
`api.github.com/repos/<owner>/<repo>/releases/latest` on launch and shows an
update banner when the tag is newer than the running version — so **publishing
a release is the update**. There is no separate version manifest to keep in
step, and no way for the two to disagree.

Two things this depends on:

- **The repository must be public.** The releases API is read unauthenticated;
  the app ships no token.
- **`UpdateChecker.defaultRepository` must match the repo.** It is a single
  constant in `lib/services/update_checker.dart`.

Hand `docs/for-deborah.md` to whoever is installing it.

### When the phone has Advanced Protection

Google's Advanced Protection (Android 16+) blocks sideloading outright, and
deliberately offers **no per-app exception** — the "Allow from this source"
toggles stay greyed out. The in-app update banner still appears on such a
phone, but tapping **Update** leads nowhere: the download succeeds and the
install is refused.

ADB is unaffected, because it does not go through that permission at all:

```
tool/push-to-device.sh                    # the only connected device
tool/push-to-device.sh 192.168.1.33:39839
```

It reads the latest release, compares it against what is installed, downloads
the APK if needed and installs it with `-r` so saved settings survive.
Verified on a Pixel 10 Pro running Android 17 with Advanced Protection on.

This does mean updates need someone at a terminal. If that becomes a chore,
a Play Console internal testing track (a one-off $25) is the clean fix:
apps from Play install and update normally under Advanced Protection, and the
signing key and release flow here carry over unchanged.

### Signing — the part that bites later

Android only installs an update over an existing app when both are signed with
the **same key**. Get this wrong and the only way forward is uninstalling,
which throws away the saved room and station:

```
INSTALL_FAILED_UPDATE_INCOMPATIBLE: signatures do not match newer version
```

Credentials live in `android/key.properties` (gitignored), pointing at a
keystore kept outside the repo. **Back up both.** Losing the keystore means
every existing install has to be removed by hand before it can be replaced.

`tool/release.sh` refuses to publish an APK signed with debug keys, which is
the failure mode you would otherwise only discover from the other end of a
phone call.

Release builds are **not** minified. R8 only touches the small Java/Kotlin
embedding layer — the bulk of a Flutter APK is native engine libraries it
cannot shrink — so it saves about a megabyte out of fifty while adding a class
of runtime failure that only appears on a real device. Use
`flutter build apk --split-per-abi` if size matters; arm64 alone is ~17MB.

## Build

```sh
flutter test
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Tests run against a captured real-household `GetZoneGroupState` in
`test/fixtures/`, including the grouped-room and satellite cases.

**Don't launch with `adb shell monkey`** — it injects random UI events, which
in an app that controls real speakers means randomly starting playback. Use
`adb shell am start -n com.jameslosh.andon_radio/.MainActivity`.
