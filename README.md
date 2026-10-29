# AirFrameXR client for Apple Vision Pro

The visionOS client of [AirFrameXR](https://github.com/jfbobier/AirFrameXR), wireless PC VR for NVIDIA cards: the
PC runs the game through AirFrameXR's OpenXR runtime (frame generation, foveated encoding, NVENC), streams it with
the ALVR v20 protocol, and this app shows it on the Vision Pro with hand and PlayStation VR2 Sense controller
tracking.

Version 1.2.0 (numbered with the AirFrameXR streamer it pairs with). Nearly feature complete; what is left is listed at the end.

## Credits

This app is a fork of [ALVR for Apple visionOS](https://github.com/alvr-org/alvr-visionos), written by
[Max Thomas (shinyquagsire23)](https://github.com/shinyquagsire23) and the alvr-org contributors, among them
panthurrr, zhuowei, shadowfacts, dereklucas, sidd, jfenton, svrc and robbiet480. The renderer, the tracking, the
ALVR client core integration, the controller and hand input, the chroma key and the TestFlight-ready project are
theirs. The streaming protocol and the client core are [ALVR](https://github.com/alvr-org/ALVR). Both are MIT
licensed and so is this fork (see `LICENSE`).

## What this fork adds

Everything below is in the `airframexr-client` branch on top of upstream `main`.

**Picture**

- Metal renderer only. The RealityKit renderer and its options are removed, so there is one code path to tune.
- The visible field of view of the Vision Pro panel, measured on a headset, is declared to the streamer per edge
  (left, right, up, down). The PC then renders and encodes only what the panel can show. Details and the
  measurement: `docs/AVP_FOV.md` in the AirFrameXR repository.
- The chroma key is taken from the streamer's settings (`video.passthrough`), so the key colour and distance are
  set once, on the PC.

**Space**

- Floor height: the height the headset reports is shown live in the window, with a manual offset (plus or minus
  50 cm) that is added to it. The sum is what the game sees as your eye height.
- Head pose as stock: the head is sampled at the display time; the client core predicts by the pipeline latency.

**Hands and controllers**

- Hands as controllers (on by default): your hands appear to the game as controllers, a pinch is that hand's
  trigger. Off sends the hand skeleton only.
- PlayStation VR2 Sense controllers: tested in game. The small Create (left) and Options (right) buttons reach the
  game as that hand's menu button, kept distinct because games bind them to different things. The PS button is
  not available to any app: visionOS 27 does not expose it in the controller's input profile, so the Home Button
  Overrides setting has nothing to act on and the PS button opens the Home View whatever you set. The app asks
  for it anyway, which will matter on controllers that do expose their Home button, and writes one `[home]`
  line per controller into the streamer log with what the profile contains.

**Window**

- One column: connection status, floor rows, four switches (Hands as controllers, Proximity chaperone,
  Performance HUD on the left forearm, Auto-connect) and Enter. No settings that duplicate the PC's.
- Auto-connect enters the stream as soon as the streamer connects.
- App name and icon: AirFrameXR.

**Building and shipping**

- GitHub Actions build on an Xcode 27 runner (`.github/workflows/`), including a TestFlight workflow that
  archives, signs with an App Store Connect API key and uploads, with an unsigned check mode that needs no
  account. No Mac is needed. Set-up guide for the account holder: `docs/TESTFLIGHT.md`.
- The ReplayKit eye-broadcast extension and the app group are removed, so a plain developer account suffices.
- Export compliance is declared in `Info.plist` (the stream is unencrypted by design).

## Building

Same as upstream: see the [Building](https://github.com/alvr-org/alvr-visionos/wiki/Building) wiki page. The CI
workflow files show the exact commands (Rust client core, cbindgen, `repack_alvr_client.sh`, then `xcodebuild`).

## Next

- Fully automated optimal field-of-view calibration for the Vision Pro: the client measures what the panel shows
  for the wearer and declares it, instead of the fixed measured values of `docs/AVP_FOV.md`.
