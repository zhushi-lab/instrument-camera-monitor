#!/bin/bash

# The app launcher runs this script after the user opens the app.
# One directory is created per run so ImageSnap's numbered filenames never
# overwrite photos from an earlier run.

find_tool() {
  local candidate
  if [[ -n "$1" ]]; then
    [[ -x "$1" ]] && { printf '%s\n' "$1"; return 0; }
    return 1
  fi
  shift
  for candidate in "$@"; do
    [[ -x "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
  done
  return 1
}
IMAGE_SNAP=$(find_tool "${CAMERA_IMAGE_SNAP:-}" /opt/homebrew/bin/imagesnap /usr/local/bin/imagesnap) || IMAGE_SNAP=""
find_python3() {
  local candidate
  for candidate in "${CAMERA_PYTHON3:-}" "$(command -v python3 2>/dev/null)" \
      /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do
    [[ -n "$candidate" && -x "$candidate" ]] || continue
    if "$candidate" -c 'import sys; sys.exit(0 if (3, 9) <= sys.version_info[:2] < (4, 0) else 1)' \
        >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}
PYTHON3=$(find_python3) || PYTHON3=""
MENU_HELPER="${CAMERA_MENU_HELPER:-$(/usr/bin/dirname "$0")/CaptureMenu.app/Contents/MacOS/CaptureMenu}"
CAPACITY_HELPER="$(/usr/bin/dirname "$0")/capacity_estimate.py"
PHOTO_STORAGE_HELPER="$(/usr/bin/dirname "$0")/photo_storage.py"
RESOURCE_DIR="$(/usr/bin/dirname "$0")"
REGION_HELPER="$RESOURCE_DIR/RegionPicker"
OCR_HELPER="$RESOURCE_DIR/InstrumentOCR"
MONITOR_HELPER="$RESOURCE_DIR/monitor_instrument.py"
MAIL_CONFIG_HELPER="$RESOURCE_DIR/configure_mail.sh"
MAIL_DELIVERY_HELPER="$RESOURCE_DIR/mail_delivery.py"
SECRET_HELPER="$RESOURCE_DIR/MailSecret"
MAIL_SETTINGS="${CAMERA_MAIL_SETTINGS:-$HOME/Library/Application Support/每秒拍照/mail_settings.json}"
if [[ -z "$IMAGE_SNAP" ]]; then
  /usr/bin/osascript -e 'display dialog "没有找到 imageSnap。请先安装 Homebrew，再运行 brew install imagesnap。" buttons {"好"} default button "好" with icon stop'
  exit 1
fi
if [[ -z "$PYTHON3" ]]; then
  /usr/bin/osascript -e 'display dialog "没有找到可用的 Python 3.9 或更新版本。请安装 Python 3，或运行 brew install python 后重试。" buttons {"好"} default button "好" with icon stop'
  exit 1
fi
if [[ ! -x "$MENU_HELPER" ]]; then
  /usr/bin/osascript -e 'display dialog "没有找到菜单栏控制程序 CaptureMenu。" buttons {"好"} default button "好" with icon stop'
  exit 1
fi
if [[ ! -f "$CAPACITY_HELPER" ]]; then
  /usr/bin/osascript -e 'display dialog "没有找到磁盘容量估算程序。" buttons {"好"} default button "好" with icon stop'
  exit 1
fi
if [[ ! -f "$PHOTO_STORAGE_HELPER" ]]; then
  /usr/bin/osascript -e 'display dialog "没有找到照片保存位置设置程序。" buttons {"好"} default button "好" with icon stop'
  exit 1
fi
if [[ "${CAMERA_AUTOTEST:-}" != "1" ]]; then
  for helper in "$REGION_HELPER" "$OCR_HELPER" "$MONITOR_HELPER" "$MAIL_CONFIG_HELPER" "$MAIL_DELIVERY_HELPER" "$SECRET_HELPER"; do
    if [[ ! -f "$helper" ]]; then
      /usr/bin/osascript -e 'display dialog "数值识别组件缺失，请重新安装应用。" buttons {"好"} default button "好" with icon stop'
      exit 1
    fi
  done
fi

if [[ "${CAMERA_AUTOTEST:-}" == "1" ]]; then
  interval=1
  duration="${CAMERA_AUTOTEST_MINUTES:-0.05}"
else
  if ! interval=$(/usr/bin/osascript -e 'text returned of (display dialog "拍照间隔（秒，例如 1 或 0.5）：" default answer "1" buttons {"取消", "继续"} default button "继续" with title "定时拍照设置")'); then
    exit 0
  fi

  if ! /usr/bin/awk -v x="$interval" 'BEGIN { exit !(x ~ /^[0-9]+([.][0-9]+)?$/ && x+0 > 0) }'; then
    /usr/bin/osascript -e 'display dialog "拍照间隔必须是大于 0 的数字，单位为秒。" buttons {"好"} default button "好" with icon stop'
    exit 1
  fi
fi

if ! /usr/bin/awk -v x="$interval" 'BEGIN { exit !(x ~ /^[0-9]+([.][0-9]+)?$/ && x+0 > 0) }'; then
  /usr/bin/osascript -e 'display dialog "拍照间隔必须是大于 0 的数字，单位为秒。" buttons {"好"} default button "好" with icon stop'
  exit 1
fi
# If a higher-resolution external camera or Continuity Camera is connected,
# let the user select it. With only the built-in camera, no extra prompt appears.
devices=$("$IMAGE_SNAP" -l 2>/dev/null | /usr/bin/sed -n 's/^=> //p')
device_count=$(printf '%s\n' "$devices" | /usr/bin/awk 'NF { n++ } END { print n+0 }')
device_args=()
if (( device_count > 1 )); then
  if ! selected_device=$(/usr/bin/osascript - "$devices" <<'APPLESCRIPT'
on run argv
  set cameraNames to paragraphs of (item 1 of argv)
  set picked to choose from list cameraNames with title "选择摄像头" with prompt "选择拍摄设备：" default items {item 1 of cameraNames}
  if picked is false then error number -128
  return item 1 of picked
end run
APPLESCRIPT
  ); then
    exit 0
  fi
  device_args=(-d "$selected_device")
fi

if [[ "${CAMERA_AUTOTEST:-}" != "1" && -z "${CAMERA_OUTPUT_ROOT:-}" ]]; then
  default_root=$("$PYTHON3" "$PHOTO_STORAGE_HELPER" get) || exit 1
  while :; do
    if ! storage_choice=$(/usr/bin/osascript - "$default_root" <<'APPLESCRIPT'
on run argv
  set choices to {"使用默认位置", "本次另存到指定文件夹", "更改默认保存位置"}
  set picked to choose from list choices with title "照片保存位置" with prompt ("当前默认位置：" & return & (item 1 of argv) & return & return & "请选择本次照片的保存位置：") default items {item 1 of choices}
  if picked is false then error number -128
  return item 1 of picked
end run
APPLESCRIPT
    ); then
      exit 0
    fi
    if [[ "$storage_choice" == "使用默认位置" ]]; then
      if [[ "$default_root" == "$HOME/Pictures/每秒拍照" ]]; then
        /bin/mkdir -p "$default_root" || exit 1
      fi
      if chosen_root=$("$PYTHON3" "$PHOTO_STORAGE_HELPER" check "$default_root" 2>/dev/null); then
        break
      fi
      /usr/bin/osascript -e 'display dialog "默认保存位置不可用，请检查磁盘和权限，或选择其他文件夹。" buttons {"好"} default button "好" with icon caution'
      continue
    fi
    picker_initial="$default_root"
    while [[ ! -d "$picker_initial" && "$picker_initial" != "/" ]]; do
      picker_initial=$(/usr/bin/dirname "$picker_initial")
    done
    if ! chosen_root=$(/usr/bin/osascript - "$picker_initial" <<'APPLESCRIPT'
on run argv
  return POSIX path of (choose folder with prompt "请选择照片保存文件夹；可在此创建新文件夹。" default location (POSIX file (item 1 of argv)))
end run
APPLESCRIPT
    ); then
      exit 0
    fi
    if [[ "$storage_choice" == "更改默认保存位置" ]]; then
      storage_action=set
    else
      storage_action=check
    fi
    if chosen_root=$("$PYTHON3" "$PHOTO_STORAGE_HELPER" "$storage_action" "$chosen_root" 2>/dev/null); then
      break
    fi
    /usr/bin/osascript -e 'display dialog "所选文件夹无法写入，请检查磁盘连接和访问权限。" buttons {"好"} default button "好" with icon caution'
  done
  CAMERA_OUTPUT_ROOT="$chosen_root"
  export CAMERA_OUTPUT_ROOT
fi

monitor_enabled=0
if [[ "${CAMERA_AUTOTEST:-}" != "1" ]]; then
  probe_dir=$(/usr/bin/mktemp -d) || exit 1
  "$IMAGE_SNAP" "${device_args[@]}" -w 1 -t "$interval" -n 3 "$probe_dir/probe.jpg" > "$probe_dir/probe.log" 2>&1
  if ! compgen -G "$probe_dir/*.jpg" > /dev/null; then
    /usr/bin/osascript -e 'display dialog "摄像头试拍失败，请检查摄像头权限和连接。" buttons {"好"} default button "好" with icon stop'
    /bin/rm -rf "$probe_dir"
    exit 1
  fi
  capacity_hint=$(CAMERA_OUTPUT_ROOT="${CAMERA_OUTPUT_ROOT:-$HOME/Pictures/每秒拍照}" "$PYTHON3" "$CAPACITY_HELPER" "$interval" "$probe_dir") || exit 1
  if ! capture_mode=$(/usr/bin/osascript -e 'button returned of (display dialog "选择本次拍摄方式：" buttons {"取消", "仅拍照", "拍照并监控数字"} default button "仅拍照" cancel button "取消" with title "定时拍照设置")'); then
    /bin/rm -rf "$probe_dir"
    exit 0
  fi
  if [[ "$capture_mode" == "拍照并监控数字" ]]; then
    monitor_enabled=1
    # The last image is closest to the camera position the user sees now.
    probe_photo=$(find "$probe_dir" -maxdepth 1 -name '*.jpg' -type f | /usr/bin/sort | /usr/bin/tail -1)
    retry_number=0
    refresh_probe_photo() {
      local fresh_dir
      while :; do
        retry_number=$((retry_number + 1))
        fresh_dir="$probe_dir/retry-$retry_number"
        /bin/mkdir "$fresh_dir" || return 1
        if "$IMAGE_SNAP" "${device_args[@]}" -w 1 -n 1 "$fresh_dir/probe.jpg" > "$fresh_dir/probe.log" 2>&1; then
          probe_photo=$(find "$fresh_dir" -maxdepth 1 -name '*.jpg' -type f | /usr/bin/sort | /usr/bin/tail -1)
          [[ -n "$probe_photo" && -s "$probe_photo" ]] && return 0
        fi
        if ! /usr/bin/osascript -e 'button returned of (display dialog "重新试拍失败。请检查摄像头连接和权限，调整后再拍一次。" buttons {"取消", "再试一次"} default button "再试一次" cancel button "取消" with title "重新试拍")' >/dev/null; then
          return 1
        fi
      done
    }
    while :; do
      if region=$("$REGION_HELPER" "$probe_photo"); then
        :
      else
        picker_status=$?
        if (( picker_status == 3 )); then
          if refresh_probe_photo; then continue; fi
        fi
        /bin/rm -rf "$probe_dir"
        exit 0
      fi
      if preview=$("$OCR_HELPER" "$probe_photo" "$region" 2>"$probe_dir/ocr.error"); then
        recognized_value="${preview%%$'\t'*}"
        if ! selection=$(/usr/bin/osascript - "$recognized_value" <<'APPLESCRIPT'
on run argv
  return button returned of (display dialog "试拍照片中识别到：" & (item 1 of argv) & return & "确认这是你要监控的读数。" buttons {"取消", "重新拍照并框选", "使用此区域"} default button "使用此区域" cancel button "取消" with title "确认数字识别区域")
end run
APPLESCRIPT
        ); then
          /bin/rm -rf "$probe_dir"
          exit 0
        fi
        [[ "$selection" == "使用此区域" ]] && break
      else
        if ! /usr/bin/osascript -e 'button returned of (display dialog "方框内无法唯一识别出数字。调整摄像头后可重新拍照并框选。" buttons {"取消", "重新拍照并框选"} default button "重新拍照并框选" cancel button "取消" with title "数字识别区域")' >/dev/null; then
          /bin/rm -rf "$probe_dir"
          exit 0
        fi
      fi
      if ! refresh_probe_photo; then
        /bin/rm -rf "$probe_dir"
        exit 0
      fi
    done
    capacity_hint=$(CAMERA_OUTPUT_ROOT="${CAMERA_OUTPUT_ROOT:-$HOME/Pictures/每秒拍照}" "$PYTHON3" "$CAPACITY_HELPER" "$interval" "$(/usr/bin/dirname "$probe_photo")") || exit 1
  fi
  /bin/rm -rf "$probe_dir"
  if (( monitor_enabled )); then
    if ! condition=$(/usr/bin/osascript -e 'text returned of (display dialog "邮件提醒条件：范围填 10~20；单个数值填 49；多个数值填 49、199、299。支持负数和小数，范围含边界。" default answer "0~100" buttons {"取消", "继续"} default button "继续" cancel button "取消" with title "数值提醒设置")'); then
      exit 0
    fi
    if ! condition_error=$("$PYTHON3" "$MONITOR_HELPER" --check-condition "$condition" 2>&1); then
      /usr/bin/osascript - "$condition_error" <<'APPLESCRIPT'
on run argv
  display dialog "提醒条件无效：" & (item 1 of argv) & return & "示例：10~20；49；49、199、299" buttons {"好"} default button "好" with icon stop
end run
APPLESCRIPT
      exit 1
    fi
    if [[ ! -s "$MAIL_SETTINGS" ]]; then
      CAMERA_PYTHON3="$PYTHON3" "$MAIL_CONFIG_HELPER" || exit 1
    elif ! "$PYTHON3" "$MAIL_DELIVERY_HELPER" check "$MAIL_SETTINGS" "$SECRET_HELPER" >/dev/null 2>&1; then
      /usr/bin/osascript -e 'display dialog "SMTP 设置无法登录。请检查网络、发件邮箱和授权码。" buttons {"取消", "重新设置"} default button "重新设置" cancel button "取消" with icon caution' >/dev/null || exit 1
      CAMERA_PYTHON3="$PYTHON3" "$MAIL_CONFIG_HELPER" || exit 1
    fi
    while :; do
      current_recipient=$("$PYTHON3" -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["recipient"])' "$MAIL_SETTINGS") || exit 1
      if ! duration_choice=$(/usr/bin/osascript - "$capacity_hint" "$current_recipient" <<'APPLESCRIPT'
on run argv
  set answer to display dialog ((item 1 of argv) & return & return & "提醒邮箱：" & (item 2 of argv)) default answer "10" buttons {"取消", "邮件设置", "开始拍照"} default button "开始拍照" cancel button "取消" with title "定时拍照设置"
  return (button returned of answer) & tab & (text returned of answer)
end run
APPLESCRIPT
      ); then
        exit 0
      fi
      IFS=$'\t' read -r action duration <<< "$duration_choice"
      if [[ "$action" == "邮件设置" ]]; then
        CAMERA_PYTHON3="$PYTHON3" "$MAIL_CONFIG_HELPER" || exit 1
        continue
      fi
      break
    done
  else
    if ! duration=$(/usr/bin/osascript - "$capacity_hint" <<'APPLESCRIPT'
on run argv
  return text returned of (display dialog (item 1 of argv) default answer "10" buttons {"取消", "开始拍照"} default button "开始拍照" cancel button "取消" with title "定时拍照设置")
end run
APPLESCRIPT
    ); then
      exit 0
    fi
  fi
fi
if ! /usr/bin/awk -v x="$duration" 'BEGIN { exit !(x ~ /^[0-9]+([.][0-9]+)?$/ && x+0 > 0) }'; then
  /usr/bin/osascript -e 'display dialog "总拍照时长必须是大于 0 的数字，单位为分钟。" buttons {"好"} default button "好" with icon stop'
  exit 1
fi

# Small batches bound imageSnap's memory use. Keep one absolute deadline so
# camera restarts do not shorten the requested total recording time.
deadline=$("$PYTHON3" -c 'import sys,time; print(time.time()+float(sys.argv[1])*60)' "$duration")
batch_size="${CAMERA_BATCH_SIZE:-60}"
[[ "$batch_size" =~ ^[1-9][0-9]*$ ]] || batch_size=60

root="${CAMERA_OUTPUT_ROOT:-$HOME/Pictures/每秒拍照}"
session="$root/$(/bin/date '+%Y%m%d_%H%M%S')-$$"
/bin/mkdir -p "$session" || exit 1

echo "拍照间隔：$interval 秒；计划时长：$duration 分钟；输出：$session"
printf '开始：%s；间隔：%s 秒；计划：%s 分钟\n' "$(/bin/date '+%F %T')" "$interval" "$duration" > "$session/capture.log"
snap_pid=0
publisher_pid=0
monitor_pid=0
stop_requested=0
if (( monitor_enabled )); then
  "$PYTHON3" "$MONITOR_HELPER" -- "$session" "$region" "$condition" "$MAIL_SETTINGS" "$$" "$OCR_HELPER" "$MAIL_DELIVERY_HELPER" "$SECRET_HELPER" &
  monitor_pid=$!
fi
if (( monitor_enabled )); then
  CAMERA_PYTHON3="$PYTHON3" "$MENU_HELPER" "$$" "$session" "$MAIL_CONFIG_HELPER" &
else
  "$MENU_HELPER" "$$" "$session" &
fi
menu_pid=$!

cleanup() {
  if (( snap_pid > 0 )); then /bin/kill "$snap_pid" 2>/dev/null || true; fi
  if (( publisher_pid > 0 )); then /bin/kill "$publisher_pid" 2>/dev/null || true; fi
  if (( monitor_pid > 0 )); then /bin/kill "$monitor_pid" 2>/dev/null || true; fi
  /bin/kill "$menu_pid" 2>/dev/null || true
}
trap cleanup EXIT
on_stop() {
  stop_requested=1
  if (( snap_pid > 0 )); then /bin/kill "$snap_pid" 2>/dev/null || true; fi
}
trap on_stop INT TERM

# imageSnap writes images sequentially. Once the next file exists, the previous
# file has finished saving and can be moved to the visible session directory.
# The last image is moved after imageSnap exits.
publish_chunk() {
  local dir="$1" offset="$2" child="$3" final="$4"
  local files file target i moved=0
  while :; do
    files=("$dir"/IMG-*.jpg)
    if [[ ! -e "${files[0]}" ]]; then files=(); fi
    if /bin/kill -0 "$child" 2>/dev/null; then
      final=0
    else
      final=1
    fi
    for ((i=0; i<${#files[@]}-1+final; i++)); do
      file="${files[i]}"
      # imageSnap may skip a source number after a failed frame. Renumber the
      # completed photos contiguously so the OCR monitor cannot stall at a gap.
      target="$session/$(printf 'IMG-%05d.jpg' "$((offset + moved + 1))")"
      if [[ -e "$target" ]]; then
        printf '编号冲突，保留临时文件：%s\n' "$file" >> "$session/capture.log"
        return 1
      fi
      /bin/mv "$file" "$target" || return 1
      moved=$((moved + 1))
    done
    if (( final )); then break; fi
    /bin/sleep 0.25
  done
  printf '%d\n' "$moved" > "$dir/.published"
}

seq=0
batch=0
failures=0
exit_status=0
while :; do
  if (( stop_requested )); then
    printf '用户停止：%s\n' "$(/bin/date '+%F %T')" >> "$session/capture.log"
    break
  fi
  remaining=$("$PYTHON3" -c 'import sys,time; print(max(0,float(sys.argv[1])-time.time()))' "$deadline")
  requested=$(/usr/bin/awk -v r="$remaining" -v i="$interval" -v cap="$batch_size" 'BEGIN { n=int(r/i); if (n*i<r-0.000001) n++; if(n>cap)n=cap; print n }')
  (( requested > 0 )) || break
  free_kib=$(/bin/df -Pk "$session" | /usr/bin/awk 'NR==2 {print $4}')
  if [[ ! "$free_kib" =~ ^[0-9]+$ ]]; then
    printf '无法读取磁盘剩余空间，已停止：%s\n' "$(/bin/date '+%F %T')" >> "$session/capture.log"
    exit_status=1
    break
  fi
  if (( free_kib < 10485760 )); then
    printf '磁盘空间低于预留的 10 GiB，已停止：%s\n' "$(/bin/date '+%F %T')" >> "$session/capture.log"
    exit_status=1
    break
  fi
  batch=$((batch + 1))
  chunk=$(printf '%s/.chunk-%05d' "$session" "$batch")
  if ! /bin/mkdir "$chunk"; then
    printf '无法创建临时拍摄文件夹：%s\n' "$chunk" >> "$session/capture.log"
    exit_status=1
    break
  fi
  printf '第 %d 段开始：%s；目标 %d 张\n' "$batch" "$(/bin/date '+%F %T')" "$requested" >> "$session/capture.log"
  "$IMAGE_SNAP" "${device_args[@]}" -w 1 -t "$interval" -n "$requested" "$chunk/IMG.jpg" >> "$session/capture.log" 2>&1 &
  snap_pid=$!
  publish_chunk "$chunk" "$seq" "$snap_pid" 0 &
  publisher_pid=$!
  wait "$snap_pid"
  status=$?
  snap_pid=0
  wait "$publisher_pid"
  publish_status=$?
  publisher_pid=0
  published=$(/bin/cat "$chunk/.published" 2>/dev/null || printf '0')
  seq=$((seq + published))
  /bin/rm -f "$chunk/.published"
  /bin/rmdir "$chunk" 2>/dev/null || true
  printf '第 %d 段结束：%s；退出码 %d；保存 %d 张；累计 %d 张\n' "$batch" "$(/bin/date '+%F %T')" "$status" "$published" "$seq" >> "$session/capture.log"
  if (( publish_status != 0 )); then
    printf '照片发布失败，临时文件保留在 %s\n' "$chunk" >> "$session/capture.log"
    exit_status=1
    break
  fi
  if (( stop_requested )); then
    printf '用户停止：%s\n' "$(/bin/date '+%F %T')" >> "$session/capture.log"
    break
  fi
  if (( status != 0 || published == 0 )); then
    failures=$((failures + 1))
    if (( failures >= 3 )); then
      printf '连续 3 次拍摄失败，已停止。\n' >> "$session/capture.log"
      exit_status=1
      break
    fi
    /bin/sleep 2
  else
    failures=0
  fi
done
printf '结束：%s；共 %d 张；请检查上述分段记录。\n' "$(/bin/date '+%F %T')" "$seq" >> "$session/capture.log"
if (( monitor_pid > 0 )); then
  /usr/bin/touch "$session/.capture_finished"
  wait "$monitor_pid" || printf '数值监控程序异常退出，请查看 monitor.log。\n' >> "$session/capture.log"
  monitor_pid=0
fi
exit "$exit_status"
