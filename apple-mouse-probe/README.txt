GitHub Actions / cloud Mac mouse-input experiment

This package contains only an independent input receiver, an experimental
SimulatorKit mouse injector, and a bounded CI job. No Jw executable, drawing,
account details, or private project files are included.

The workflow uses the standard xcode-27 GitHub-hosted runner. Public-repository
standard runners are free under GitHub's published policy. It runs for at most
12 minutes per device job and retains diagnostic artifacts for 7 days. No recurring schedule.

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
