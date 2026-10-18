GitHub Actions / cloud Mac mouse-input experiment

2026-10-18 subsequent findings: run34's CAD canvas capture/default handling
received all20 edges and four stationary-release+motion sequences in all three
iPad lifecycle phases. The actual CAD gesture-category replay also passes.
This is a LIMITED input-reception pass: sent-report to callback latency still
reached1.410 seconds in its first phase, and original clock timing is unverified.
iPhone run34 passes the first phase only; later phases receive3 and0 edges.
The source now receives GameController callbacks on a dedicated serial queue,
with only UIKit/WebKit access dispatched to main. The original passing source
is preserved at commit29a220e0d1ed39be7592dd9404ffec85dbd5d1d4.

Run35 UniversalHID requests mask3 but native button state becomes only1/2 while
held movement is requested. This experimental injector is not independent proof
of Safari-only chord loss or physical-device incompatibility. Earlier broad
two-transport corroboration is withdrawn. Singles reaching the OS are observed.
Run36 tests the worker queue with that transport; the next comparison uses the
same legacy transport as run34, so input latency and ordering can be assessed.

LATEST 2026-10-18 (supersedes earlier provisional outcomes below):
Native button-edge delivery is implemented, but full stable Jw input is NOT
established. Runs 25/26/27 iPad and both run28 iPad conditions received all four
stationary releases with movement. Run28 iPhone default received all20 edges
and four chords once; repeats failed. Run30 iPad had all20 edges but its first
chord movement was delivered out of order. Run31 requesting direct button
priority still failed first/recreated iPad phases; reused phase passed.
Run31 iPhone received19/10/15 edges, and none of its three phases passed.

Run29's independent UniversalHID transport delivered74 trusted mouse events
on iPad, and0 with accessibility OFF /71 with it ON on iPhone. Both HTML-only
streams still lacked stationary partial release. Wheel was not injected in
that suite. Private accessibility setup modifies only the disposable simulator;
the setting readback is not the same as public AssistiveTouch Running state.

Native UIKit-to-CSS positions had a32pt iPad /62pt iPhone Y offset in run31.
Safe-area constraints and disabled automatic content insets repair the source.
Run32 stopped before input due a missing CoreGraphics link; build-native.sh
fixes that dependency for run33. Inspect run33 recordings for the actual result.
No physical-device, complete clock timing, modifier-key or original-CAD parity
has passed. Native bridge results are NOT a standalone Safari HTML solution.
The simulator .app is not a signed installable product or a final size estimate.

This package contains only an independent input receiver, an experimental
SimulatorKit mouse injector, and a bounded CI job. No Jw executable, drawing,
account details, or private project files are included.

The workflow uses the standard xcode-27 GitHub-hosted runner. Public-repository
standard runners are free under GitHub's published policy. It runs for at most
18 minutes per device job and retains diagnostic artifacts for 7 days. No recurring schedule.

The script chooses the newest installed iOS runtime and records its exact
version. It must not be described as the latest Apple release without checking
that version. iPhone and iPad are tested separately in Safari.

The injector uses private SimulatorKit APIs. This is an EXPERIMENT, not a tested
Apple input backend. It creates pointer/mouse services, sends IOHID mouse events
with a left/right button mask to target 0x36, and records actual DOM events from
Safari via a loopback-only server. Missing APIs, nil messages, no events, touch
conversion and incomplete button sequences all remain explicit failures or
unverified results. Simulator success never proves physical-device parity.

References inspected (not wholesale copied):
- Apple WWDC20 10647: Simulator Capture Pointer.
- raghubetina/tapflow-workshop-lab, contributing/simkit-internals.md:
  SimDeviceLegacyHIDClient, pointer wrapper and mouse target 0x36.
- RandomSasquatch/Simulator-iOS-baguette commit
  4b363e76a19c3f15281bb26b68e247a449ee1e51: service initialization/selectors.
- nanotech/iphoneheaders IOKit/hid/IOHIDEvent.h: mouse/scroll C declarations.
- facebook/idb, FBSimulatorControl/HID/SimulatorHIDTransportSelection.swift
  blob ddda68648cad8a7b7777b3eeba8ded15ecca2150: Xcode 27 legacy suppression.
- facebook/idb, FBSimulatorControl/HID/SimulatorDTUHIDConnection.swift:
  guest service liveness must be checked; successful send alone is insufficient.
- tmoonlight/acecode, src/adapters/tool/ios_simulator/helper/sim_guest.mm
  blob 6f6ec7955e86cd718e0b1c36b0dcfa5bba0bbf3e: simulator XPC connection API.

To publish: copy workflow.yml to .github/workflows/apple-mouse-probe.yml and
the other files to apple-mouse-probe/. No files from other project directories.
The workflow runs on a relevant push or manually, with read-only permissions.
Run locally only on an isolated Mac allocated for these tests:
  bash apple-mouse-probe/run.sh

Run 1 (39031707440): compiled on macOS 26.6.2 / Xcode 26.6. iOS 26.5
simulator boot completed, but Safari openurl timed out before input was sent.
This is not a mouse compatibility result.

Run 2 (39032039498): both Safari pages loaded on iOS/iPadOS 27.0, but the
injector stopped at the old framework path. This is not mouse success.

Run 7 (39033807336): on iPhone 17 Simulator, the complete short legacy mouse
suite sent 60 messages and received 60 completion callbacks; Safari received
only the touch positive control (2 touch PointerEvents, 0 mouse PointerEvents).
The iPad job did not reach Safari page-ready and cannot judge mouse delivery.
Physical iPhone/iPad mouse operation and Jw clock behavior remain unverified.

UniversalHID service experiments query the newer Xcode 27 transport. A service
being present or acknowledging a request is NOT an input compatibility pass.
Inspect assessment.json, actual events.jsonl and injector logs together.

Run 19 (39035301464): iPadOS 27.0 Safari received 54 trusted mouse PointerEvents,
valid left and right clicks, movement with buttons=3, and both wheel directions.
All four chord-release sequences failed: the remaining-held state 1 or 2 did
not arrive between 3 and 0. iPhone received no mouse PointerEvents. This is not
full mouse parity.

Run 20 (39035867608): the button-child-only variant plus a 2-unit movement
after partial release received 61 mouse PointerEvents, all four state orders,
both clicks and both wheel directions on iPad. The remaining button state
appeared on the extra movement, not on the stationary partial release. The raw
iPad job was green under the older classifier, but it is NOT exact-operation
success. The classifier now requires stationary-release transitions as well.
The same saved logs fail this stricter required gate. iPhone still received
no mouse PointerEvents, with 2 touch positive-control events.

Relevant WebKit source: WKMouseInteraction.mm at commit
70826d7c1dcbf58ac38c6e4d7378e5a1806b5052, around line 280, contains a FIXME
for reporting still-held buttons on chord release. This is supporting source
evidence; it does not certify the exact installed Safari binary.

2026-10-18 repair experiments:
- native.m is an independent UIKit/GameController/WKWebView app. Its public-API
  callbacks are logged separately from trusted DOM PointerEvents. It never
  synthesizes a release from a timeout or an extra user movement.
- Use the pressed parameter delivered by GCMouse.pressedChangedHandler rather
  than polling isPressed later. Queued callbacks can otherwise lose edges.
- Runs 25 (39076815684) and 26 (39077319017) received all four stationary
  partial releases through the native bridge on iPadOS 27.0. The Safari and
  WKWebView DOM-only streams still failed this requirement. Native-app success
  is NOT a fix available to a standalone Safari HTML file.
- Run 26 iPhone Safari received 73 trusted mouse PointerEvents, both clicks,
  both wheel directions, but no stationary partial-release state. Native input
  was mixed/incomplete. This followed a warm AssistiveTouch setting change;
  causal dependence is under controlled off/on/off test, not yet established.
- Run 26 iPhone's green job is not a pass: a Bash empty-array/nounset failure
  stopped before the final phase and classifier. run.sh now preserves failures
  through cleanup and avoids that empty-array expansion.
- accessibility-setup.m and universal.m use private APIs ONLY inside disposable
  simulators as test drivers. They are not shipped to user devices. The receiver
  app uses public APIs. Its small Simulator .app is not a signed device build.
- Native pointer lock was requested on iPhone in run 26 but stateAvailable and
  locked were both false. Requesting it is not evidence that it activated.
- Run 27 compares warm Safari with accessibility off/on/off and native app with
  it off/on. It also corrects the new HID descriptor's typed usage-pair array.
  Check the actual received data; accepted sends/service creation alone do not
  certify mouse input. No physical mouse, clock timing or full Jw parity passed.

Additional primary references:
https://developer.apple.com/documentation/gamecontroller/gcmouse
https://developer.apple.com/documentation/gamecontroller/gcdevice/handlerqueue
https://developer.apple.com/documentation/uikit/uipointerlockstate/islocked
https://support.apple.com/en-kw/111775
https://github.com/facebook/idb/blob/main/FBSimulatorControl/HID/SimulatorDTUHIDConnection.swift
https://github.com/ipbtools/ipb/blob/main/docs/protocol.md
https://github.com/nst/iOS-Runtime-Headers/blob/master/PrivateFrameworks/AccessibilityUtilities.framework/AXSettings.h
