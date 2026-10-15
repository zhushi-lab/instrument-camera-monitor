#!/bin/bash
set -u

here="$(/usr/bin/dirname "$0")"
settings="${CAMERA_MAIL_SETTINGS:-$HOME/Library/Application Support/每秒拍照/mail_settings.json}"
secret_tool="$here/MailSecret"
mail_tool="$here/mail_delivery.py"
python3=""
for candidate in "${CAMERA_PYTHON3:-}" "$(command -v python3 2>/dev/null)" \
    /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do
  [[ -n "$candidate" && -x "$candidate" ]] || continue
  if "$candidate" -c 'import sys; sys.exit(0 if (3, 9) <= sys.version_info[:2] < (4, 0) else 1)' \
      >/dev/null 2>&1; then
    python3="$candidate"
    break
  fi
done
[[ -n "$python3" ]] || { printf 'Python 3.9 or newer is required.\n' >&2; exit 1; }

ask() {
  /usr/bin/osascript - "$1" "$2" "$3" <<'APPLESCRIPT'
on run argv
  if (item 3 of argv) is "hidden" then
    return text returned of (display dialog (item 1 of argv) default answer "" with hidden answer buttons {"取消", "继续"} default button "继续" cancel button "取消" with title "邮件提醒设置")
  end if
  return text returned of (display dialog (item 1 of argv) default answer (item 2 of argv) buttons {"取消", "继续"} default button "继续" cancel button "取消" with title "邮件提醒设置")
end run
APPLESCRIPT
}

mail_defaults=()
while IFS= read -r field; do
  mail_defaults+=("$field")
done < <("$python3" - "$settings" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding='utf-8'))
except (OSError, ValueError):
    d = {}
for key, default in [
    ('recipient', ''),
    ('sender', ''),
    ('host', 'smtp.163.com'),
    ('port', '465'),
    ('security', 'ssl'),
]:
    print(str(d.get(key, default)))
PY
)
(( ${#mail_defaults[@]} == 5 )) || exit 1
old_recipient="${mail_defaults[0]}"
old_sender="${mail_defaults[1]}"
old_host="${mail_defaults[2]}"
old_port="${mail_defaults[3]}"
old_security="${mail_defaults[4]}"

if [[ -s "$settings" ]]; then
  mode=$(/usr/bin/osascript <<'APPLESCRIPT'
set selected to choose from list {"只改收件邮箱", "快速设置 163 邮箱", "高级设置其他发件邮箱"} with title "邮件提醒设置" with prompt "请选择要修改的内容：" default items {"只改收件邮箱"}
if selected is false then error number -128
return item 1 of selected
APPLESCRIPT
  ) || exit 2
else
  mode=$(/usr/bin/osascript -e 'button returned of (display dialog "163 邮箱可快速设置：只需填写邮箱地址和一次客户端授权码。" buttons {"取消", "高级设置", "快速设置"} default button "快速设置" cancel button "取消" with title "邮件提醒设置")') || exit 2
fi

secret=""
case "$mode" in
  "只改收件邮箱")
    recipient=$(ask "接收提醒的邮箱：" "$old_recipient" plain) || exit 2
    sender="$old_sender"
    host="$old_host"
    port="$old_port"
    security="$old_security"
    ;;
  "快速设置"|"快速设置 163 邮箱")
    sender=$(ask "163 邮箱地址（同时作为收件和发件地址）：" "$old_sender" plain) || exit 2
    recipient="$sender"
    host="smtp.163.com"
    port="465"
    security="ssl"
    secret=$(ask "163 客户端授权码（网页版邮箱→设置→POP3/SMTP/IMAP→新增授权密码；只填一次，已保存时留空可沿用）：" "" hidden) || exit 2
    ;;
  "高级设置"|"高级设置其他发件邮箱")
    recipient=$(ask "接收提醒的邮箱：" "$old_recipient" plain) || exit 2
    sender=$(ask "发件邮箱（需已开启 SMTP）：" "$old_sender" plain) || exit 2
    host=$(ask "SMTP 服务器：" "$old_host" plain) || exit 2
    port=$(ask "SMTP 端口：" "$old_port" plain) || exit 2
    if ! security=$(/usr/bin/osascript - "$old_security" <<'APPLESCRIPT'
on run argv
  if (item 1 of argv) is "starttls" then
    set preferred to "STARTTLS（常用 587）"
  else
    set preferred to "SSL/TLS（常用 465）"
  end if
  set selected to choose from list {"SSL/TLS（常用 465）", "STARTTLS（常用 587）"} with title "邮件提醒设置" with prompt "选择 SMTP 加密方式：" default items {preferred}
  if selected is false then error number -128
  if item 1 of selected begins with "STARTTLS" then return "starttls"
  return "ssl"
end run
APPLESCRIPT
    ); then
      exit 2
    fi
    secret=$(ask "SMTP 客户端授权码（已保存时留空可沿用）：" "" hidden) || exit 2
    ;;
  *) exit 2 ;;
esac
if [[ ! "$recipient" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ || ! "$sender" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ || ! "$host" =~ ^[A-Za-z0-9.-]+$ || ! "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
  /usr/bin/osascript -e 'display dialog "邮箱、服务器或端口格式无效。" buttons {"好"} default button "好" with icon stop'
  exit 1
fi

previous_secret=$("$secret_tool" get "$sender" 2>/dev/null) || previous_secret=""
if [[ -z "$secret" && -z "$previous_secret" ]]; then
  /usr/bin/osascript -e 'display dialog "请填写 SMTP 授权码。若使用 163 邮箱，请先在网页版开启 SMTP 并生成客户端授权码。" buttons {"好"} default button "好" with icon stop'
  exit 1
fi

directory="$(/usr/bin/dirname "$settings")"
/bin/mkdir -p "$directory" || exit 1
candidate=$(/usr/bin/mktemp "$directory/.mail-settings.XXXXXX") || exit 1
secret_changed=0
committed=0
cleanup_candidate() {
  if (( secret_changed && ! committed )); then
    if [[ -n "$previous_secret" ]]; then
      /usr/bin/printf '%s\n' "$previous_secret" | "$secret_tool" set "$sender" >/dev/null 2>&1
    else
      "$secret_tool" delete "$sender" >/dev/null 2>&1
    fi
  fi
  /bin/rm -f "$candidate" "$candidate.error"
}
trap cleanup_candidate EXIT
"$python3" - "$candidate" "$recipient" "$sender" "$host" "$port" "$security" <<'PY'
import json, sys
with open(sys.argv[1], 'w', encoding='utf-8') as f:
    json.dump(dict(zip(('recipient', 'sender', 'host', 'port', 'security'), sys.argv[2:])), f, ensure_ascii=False)
    f.write('\n')
PY
if [[ -n "$secret" ]]; then
  if ! /usr/bin/printf '%s\n' "$secret" | "$secret_tool" set "$sender"; then
    exit 1
  fi
  secret_changed=1
fi
unset secret
if ! "$python3" "$mail_tool" check "$candidate" "$secret_tool" >/dev/null 2>"$candidate.error"; then
  /usr/bin/osascript - "$(/bin/cat "$candidate.error")" <<'APPLESCRIPT'
on run argv
  display dialog "SMTP 登录验证失败，原设置已保留。请检查授权码、服务器和网络。" & return & return & (item 1 of argv) buttons {"好"} default button "好" with icon stop
end run
APPLESCRIPT
  exit 1
fi
test_choice=$(/usr/bin/osascript - "$recipient" <<'APPLESCRIPT'
on run argv
  return button returned of (display dialog "SMTP 登录已通过。要向 " & (item 1 of argv) & " 发送一封测试邮件吗？" buttons {"取消", "仅保存", "发送测试邮件"} default button "发送测试邮件" cancel button "取消" with title "邮件提醒设置")
end run
APPLESCRIPT
) || {
  exit 2
}
if [[ "$test_choice" == "发送测试邮件" ]]; then
  if ! "$python3" "$mail_tool" test "$candidate" "$secret_tool" >/dev/null 2>"$candidate.error"; then
    /usr/bin/osascript - "$(/bin/cat "$candidate.error")" <<'APPLESCRIPT'
on run argv
  display dialog "测试邮件发送失败，邮件设置没有更改。" & return & return & (item 1 of argv) buttons {"好"} default button "好" with icon stop
end run
APPLESCRIPT
    exit 1
  fi
fi
/bin/chmod 600 "$candidate"
/bin/mv "$candidate" "$settings" || exit 1
committed=1
unset previous_secret
if [[ "$test_choice" == "发送测试邮件" ]]; then
  /usr/bin/osascript -e 'display dialog "设置已保存，测试邮件已交给发件服务器。请到收件箱确认；若未看到，请检查垃圾邮件。" buttons {"好"} default button "好" with title "邮件提醒设置"' >/dev/null
else
  /usr/bin/osascript -e 'display notification "邮件设置已保存，后续提醒将使用新配置。" with title "每秒拍照"'
fi
