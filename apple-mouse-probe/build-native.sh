#!/bin/bash
set -euo pipefail
mkdir -p output/NativeProbe.app
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
arch="$(uname -m)"
xcrun clang -fobjc-arc -fblocks -target "$arch-apple-ios17.0-simulator" -isysroot "$sdk" -framework UIKit -framework Foundation -framework GameController -framework WebKit native.m -o output/NativeProbe.app/NativeProbe
xcrun clang -fobjc-arc -target "$arch-apple-ios17.0-simulator" -isysroot "$sdk" -framework UIKit -framework Foundation accessibility-setup.m -o output/accessibility-setup
codesign --force --sign - output/accessibility-setup
python3 - <<'PY'
import plistlib
from pathlib import Path
d={'CFBundleExecutable':'NativeProbe','CFBundleIdentifier':'org.jwprobe.nativeinput','CFBundleName':'Native input probe','CFBundleVersion':'1','CFBundleShortVersionString':'1.0','CFBundlePackageType':'APPL','MinimumOSVersion':'17.0','UIDeviceFamily':[1,2],'UIApplicationSupportsIndirectInputEvents':True,'UILaunchScreen':{},'NSAppTransportSecurity':{'NSAllowsLocalNetworking':True,'NSAllowsArbitraryLoads':True},'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False,'UISceneConfigurations':{'UIWindowSceneSessionRoleApplication':[{'UISceneConfigurationName':'Default','UISceneDelegateClassName':'ProbeScene'}]}}}
Path('output/NativeProbe.app/Info.plist').write_bytes(plistlib.dumps(d))
PY
codesign --force --sign - output/NativeProbe.app
