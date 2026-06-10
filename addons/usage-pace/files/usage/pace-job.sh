#!/data/data/com.termux/files/usr/bin/sh
# Cel termux-job-scheduler: odpala pace.sh w trybie harmonogramu (fetch gdy
# cache stary + ewentualne powiadomienie). Dziala w natywnym Termuksie.
export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:$PATH
exec bash "$HOME/.claude/usage/pace.sh" --scheduled >> "$HOME/.claude/usage/pace-job.log" 2>&1
