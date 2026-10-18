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
  adb shell am start -W -n "$ACTIVITY"
  wait_ui 'PLAY'
  local click
  click="$(locate_ui 'PLAY')"
  read -r x y <<< "$click"
  adb shell input tap "$x" "$y"
  wait_ui 'SCORE 73'
  adb shell pidof "$PACKAGE" >/dev/null
  echo 'SMOKE-RESTORE-SCORE-73-PASS'
}
launch_and_check
adb shell input keyevent KEYCODE_HOME
sleep 2
adb shell am force-stop "$PACKAGE"
launch_and_check
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
