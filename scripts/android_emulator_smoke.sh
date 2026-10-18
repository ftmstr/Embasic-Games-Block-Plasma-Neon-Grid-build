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


# Exercise a real Android touchscreen drag after the deterministic restore
# smoke; never mutate the save JSON to fake an accepted player move.
wait_ui 'Tray slot 1'
wait_ui 'Drop cell row 8 column 8'
capture_ui
origin="$(locate_ui 'Tray slot 1')"
destination="$(locate_ui 'Drop cell row 8 column 8')"
read -r from_x from_y <<< "$origin"
read -r to_x to_y <<< "$destination"
echo "DRAG-POINTER-FROM $from_x $from_y TO $to_x $to_y"
adb shell input touchscreen draganddrop "$from_x" "$from_y" "$to_x" "$to_y" 1800
wait_ui 'SCORE 78'
echo 'SMOKE-REAL-DRAG-UI-SCORE-78-PASS'

verify_drag_save() {
  local output="$1"
  for _ in $(seq 1 12); do
    adb shell run-as "$PACKAGE" cat files/game-state.json > "$output"
    if python3 - "$output" <<'PY'
import json,sys
with open(sys.argv[1], encoding="utf-8") as f: s=json.load(f)
assert s['schemaVersion']==1 and s['score']==78 and s['bestScore']==100
assert s['turnId']==10 and s['rngState']==314159265 and s['combo']==0
assert len(s['board'])==64 and s['board'][0]==1 and s['board'][63]==1
assert sum(v is not None for v in s['board'])==2
assert s['tray']==[None,'double_h','triple_v']
PY
    then
      return 0
    fi
    sleep 1
  done
  echo "SMOKE-FAIL: actual draggable did not produce canonical saved move"
  return 1
}
verify_drag_save "$TMP/drag-committed.json"
echo 'SMOKE-REAL-DRAG-DISK-SNAPSHOT-PASS'
capture_screen "04-real-android-gameplay-after-drag"

adb shell am force-stop "$PACKAGE"
adb shell am start -W -n "$ACTIVITY"
wait_ui 'PLAY'
capture_ui
click="$(locate_ui 'PLAY')"
read -r replay_x replay_y <<< "$click"
adb shell input tap "$replay_x" "$replay_y"
wait_ui 'SCORE 78'
verify_drag_save "$TMP/drag-relaunched.json"
python3 - "$TMP/drag-committed.json" "$TMP/drag-relaunched.json" <<'PY'
import json,sys
with open(sys.argv[1], encoding='utf-8') as f: before=json.load(f)
with open(sys.argv[2], encoding='utf-8') as f: after=json.load(f)
assert before==after, 'cold relaunch changed committed state'
PY
capture_screen "05-real-android-gameplay-drag-restored"
echo 'SMOKE-REAL-DRAG-RELAUNCH-RNG-TURN-BOARD-PASS'
