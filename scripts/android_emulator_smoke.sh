#!/usr/bin/env bash
# Android API 35 emulator: install debug APK, seed schema-v1 snapshot,
# verify real Flutter UI restore and force-stop/relaunch preservation.
set -euo pipefail
PACKAGE='com.embasicgames.block_plasma_neon_grid'
ACTIVITY="$PACKAGE/.MainActivity"
APK="$(find downloaded-apk -type f -name 'app-debug.apk' -print -quit)"
if [[ -z "$APK" || ! -s "$APK" ]]; then
  echo 'SMOKE-FAIL: APK missing'; exit 2
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
UI_XML="$TMP/window.xml"
SHOT_DIR="${GITHUB_WORKSPACE:-.}/android-gameplay-screens"
mkdir -p "$SHOT_DIR"
capture_screen() {
  local name="$1"
  local output="$SHOT_DIR/$name.png"
  sleep 1
  adb exec-out screencap -p > "$output"
  python3 - "$output" <<'PY'
import os,sys
path=sys.argv[1]
with open(path,'rb') as f: signature=f.read(8)
assert signature == bytes.fromhex('89504e470d0a1a0a'), 'not a genuine PNG'
assert os.path.getsize(path)>10000, 'empty screen capture'
print('REAL-ANDROID-SCREENSHOT-PASS', os.path.basename(path),os.path.getsize(path))
PY
}
adb wait-for-device
adb install -r "$APK"
adb shell pm path "$PACKAGE" | grep -q 'package:'
echo 'SMOKE-APK-INSTALLED'
python3 - "$TMP/fixture.json" <<'PY'
import json,sys
snapshot = dict(schemaVersion=1,board=[1]+[None]*63,
                tray=['single','double_h','triple_v'],
                score=73,bestScore=100,combo=0,
                rngState=314159265,turnId=9,gameOver=False)
with open(sys.argv[1],'w',encoding='utf-8') as f:
    json.dump(snapshot,f)
PY
adb shell am start -W -n "$ACTIVITY"
sleep 4
adb shell pidof "$PACKAGE" >/dev/null
adb shell am force-stop "$PACKAGE"
adb push "$TMP/fixture.json" /data/local/tmp/bp-ng-fixture.json >/dev/null
adb shell run-as "$PACKAGE" cp /data/local/tmp/bp-ng-fixture.json files/game-state.json
adb shell run-as "$PACKAGE" cat files/game-state.json > "$TMP/seeding.json"
python3 - "$TMP/fixture.json" "$TMP/seeding.json" <<'PY'
import json,sys
with open(sys.argv[1],encoding='utf-8') as f: wanted=json.load(f)
with open(sys.argv[2],encoding='utf-8') as f: actual=json.load(f)
assert actual == wanted
PY
echo 'SMOKE-APP-SANDBOX-SEED-PASS'
capture_ui() {
  adb shell uiautomator dump /sdcard/bp-ng-window.xml >/dev/null 2>&1 || true
  adb exec-out cat /sdcard/bp-ng-window.xml > "$UI_XML" 2>/dev/null || true
}
locate_ui() {
  python3 - "$UI_XML" "$1" <<'PY'
import re,sys,xml.etree.ElementTree as ET
try: root=ET.parse(sys.argv[1]).getroot()
except (OSError,ET.ParseError): sys.exit(1)
needle=sys.argv[2].upper()
for node in root.iter('node'):
    label=(node.get('text','')+' '+node.get('content-desc','')).upper()
    if needle not in label: continue
    bounds=[int(x) for x in re.findall(r'\d+',node.get('bounds',''))]
    if len(bounds)==4:
        print((bounds[0]+bounds[2])//2,(bounds[1]+bounds[3])//2)
        sys.exit(0)
sys.exit(1)
PY
}
wait_ui() {
  local needle="$1"
  for _ in $(seq 1 14); do
    capture_ui
    if locate_ui "$needle" >/dev/null; then return 0; fi
    sleep 2
  done
  echo "SMOKE-FAIL: UI text not found: $needle"
  return 1
}
launch_and_check() {
  local sequence="$1"
  adb shell am start -W -n "$ACTIVITY"
  wait_ui 'PLAY'
  if [[ "$sequence" == "first" ]]; then capture_screen "01-real-android-home"; fi
  local click
  click="$(locate_ui 'PLAY')"
  read -r x y <<< "$click"
  adb shell input tap "$x" "$y"
  wait_ui 'SCORE 73'
  adb shell pidof "$PACKAGE" >/dev/null
  if [[ "$sequence" == "first" ]]; then
    capture_screen "02-real-android-gameplay-score73"
  else
    capture_screen "03-real-android-gameplay-restored"
  fi
  echo 'SMOKE-RESTORE-SCORE-73-PASS'
}
launch_and_check first
adb shell input keyevent KEYCODE_HOME
sleep 2
adb shell am force-stop "$PACKAGE"
launch_and_check second
adb shell run-as "$PACKAGE" cat files/game-state.json > "$TMP/reopened.json"
python3 - "$TMP/reopened.json" <<'PY'
import json,sys
with open(sys.argv[1],encoding='utf-8') as f: state=json.load(f)
assert state['score']==73
assert state['rngState']==314159265
assert state['turnId']==9
assert len(state['board'])==64 and len(state['tray'])==3
print('SMOKE-RNG-TURN-SCHEMA-PASS')
PY
echo 'EMULATOR_SAVE_PASS'
