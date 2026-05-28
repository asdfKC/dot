#!/usr/bin/env bash
set -euo pipefail

if ! command -v fzf >/dev/null 2>&1; then
  if command -v btop >/dev/null 2>&1; then
    exec btop
  fi
  exec top
fi

render_header() {
  local cpu mem swap procs
  cpu=$(top -bn1 | awk -F',' '/%Cpu\(s\)/{gsub(" ","",$0); for(i=1;i<=NF;i++) if($i ~ /id/) {sub("id","",$i); print 100-$i; exit}}')
  mem=$(free -m | awk '/^Mem:/{printf("%.1f", ($3/$2)*100)}')
  swap=$(free -m | awk '/^Swap:/{if($2==0){print "0.0"}else{printf("%.1f", ($3/$2)*100)}}')
  procs=$(ps -e --no-headers | wc -l | tr -d ' ')

  printf '♔ Chess Task Manager\n'
  printf 'CPU %s%%   MEM %s%%   SWAP %s%%   PROCS %s\n' "$cpu" "$mem" "$swap" "$procs"
  printf 'Enter: Inspect  |  Ctrl-K: End Task  |  Ctrl-R: Refresh  |  Esc: Exit\n\n'
}

process_list() {
  ps -eo pid,comm,%cpu,%mem,user --sort=-%cpu \
    | awk 'NR==1{printf "%s\n",$0; next} {printf "%6s  %-28s  %6s  %6s  %s\n",$1,$2,$3,$4,$5}'
}

show_details() {
  local pid=$1
  clear
  echo "♞ Process Details"
  echo
  ps -p "$pid" -o pid,ppid,user,stat,%cpu,%mem,etime,comm,args
  echo
  read -r -p "Press Enter to return..." _
}

while true; do
  selection=$( (render_header; process_list) | fzf \
    --ansi \
    --height=95% \
    --layout=reverse \
    --border=rounded \
    --header-lines=3 \
    --prompt='♞ Select process > ' \
    --color='fg:#f2e7c9,bg:#0b0d10,hl:#d4af37,fg+:#f7ecd0,bg+:#1a1f27,hl+:#f1d27c,prompt:#d4af37,pointer:#d4af37,header:#caa55a,border:#d4af37' \
    --bind='ctrl-r:reload(ps -eo pid,comm,%cpu,%mem,user --sort=-%cpu | awk '\''NR==1{printf "%s\\n",$0; next} {printf "%6s  %-28s  %6s  %6s  %s\\n",$1,$2,$3,$4,$5}'\'')' \
    --bind='ctrl-k:execute-silent(pid=$(echo {} | awk '\''{print $1}'\''); kill -15 "$pid" 2>/dev/null || true)+reload(ps -eo pid,comm,%cpu,%mem,user --sort=-%cpu | awk '\''NR==1{printf "%s\\n",$0; next} {printf "%6s  %-28s  %6s  %6s  %s\\n",$1,$2,$3,$4,$5}'\'')' ) || break

  pid=$(echo "$selection" | awk '{print $1}')
  [[ -z "${pid:-}" || "$pid" == "PID" ]] && continue
  show_details "$pid"

done
