GitHub Actions / cloud Mac mouse-input experiment

This package contains only an independent input receiver, an experimental
SimulatorKit mouse injector, and a bounded CI job. No Jw executable, drawing,
account details, or private project files are included.

The workflow uses the standard macos-26 GitHub-hosted runner. Public-repository
standard runners are free under GitHub's published policy. It runs for at most
25 minutes and retains diagnostic artifacts for 7 days. No recurring schedule.

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

To publish: copy workflow.yml to .github/workflows/apple-mouse-probe.yml and
the other files to apple-mouse-probe/. No files from other project directories.
The workflow runs on a relevant push or manually, with read-only permissions.
Run locally only on an isolated Mac allocated for these tests:
  bash apple-mouse-probe/run.sh

Current status: prepared on Windows; macOS compilation/execution NOT yet done.
