FROM ubuntu:22.04

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive
ENV TERM=xterm-256color
ENV COLORTERM=truecolor
ENV TZ="Asia/Dhaka"

# Cleaner package-manager behavior
ENV PIP_NO_CACHE_DIR=1
ENV PIP_DISABLE_PIP_VERSION_CHECK=1
ENV NPM_CONFIG_AUDIT=false
ENV NPM_CONFIG_FUND=false
ENV NPM_CONFIG_UPDATE_NOTIFIER=false
ENV NPM_CONFIG_CACHE=/tmp/.npm-cache

# Phoenix runtime tuning
ENV PHOENIX_CPU_SAMPLE_SECONDS=2
ENV PHOENIX_MM_CPU_SAMPLE_SECONDS=2
ENV PHOENIX_CPU_FALLBACK_VCPU=
ENV PHOENIX_CPU_HISTORY_FILE=/tmp/.phoenix_cpu_history

# --------------------------------------------------
# Base system packages
# --------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    tzdata openssh-server sudo curl wget git nano procps net-tools iputils-ping dnsutils \
    lsof htop jq speedtest-cli unzip tree python3 python3-pip python3-venv \
    ca-certificates gnupg \
    && pip3 install awscli \
    && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
    && echo $TZ > /etc/timezone \
    && curl -fsSL https://tailscale.com/install.sh | sh \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/* /var/tmp/* /root/.cache/pip

# --------------------------------------------------
# Install Node.js LTS + Codex at build time
# --------------------------------------------------
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm i -g @openai/codex --cache /tmp/.npm-cache --no-audit --no-fund \
    && npm cache clean --force \
    && rm -rf /tmp/.npm-cache /root/.npm /root/.cache/npm /root/.cache/node-gyp \
    && apt-get purge -y --auto-remove gnupg \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/* /var/tmp/*

# --------------------------------------------------
# SSH + users
# --------------------------------------------------
RUN mkdir -p /var/run/sshd && \
    useradd -m -s /bin/bash -u 1000 devuser && \
    echo "devuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    echo "devuser:123456" | chpasswd && \
    echo "root:123456" | chpasswd && \
    echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config && \
    echo "PermitRootLogin yes" >> /etc/ssh/sshd_config && \
    echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config

# --------------------------------------------------
# Disable default MOTD noise
# --------------------------------------------------
RUN rm -rf /etc/update-motd.d/* && \
    rm -f /etc/legal && \
    rm -f /etc/motd && \
    touch /home/devuser/.hushlogin && \
    touch /root/.hushlogin

# --------------------------------------------------
# Prompt styling
# --------------------------------------------------
RUN echo "export PS1='\[\e[1;32m\]\u@phoenix\[\e[0m\]:\[\e[1;36m\]\w\[\e[0m\]\$ '" >> /home/devuser/.bashrc && \
    echo "export PS1='\[\e[1;31m\]\u@phoenix\[\e[0m\]:\[\e[1;36m\]\w\[\e[0m\]# '" >> /root/.bashrc

# --------------------------------------------------
# Main shell setup
# --------------------------------------------------
RUN cat > /tmp/setup.sh <<'EOF'

export PHOENIX_CPU_HISTORY_FILE="/tmp/.phoenix_cpu_history_${USER}"

# ==========================================
# 🚀 SYSTEM ALIASES (BUILT-IN)
# ==========================================

# Nav & Files
alias c='clear'
alias ..='cd ..'
alias ...='cd ../..'
alias ll='ls -alF --color=auto'
alias la='ls -A --color=auto'
alias md='mkdir -p'
alias sz='du -sh * 2>/dev/null | sort -hr'
alias tree='tree -C'
alias f='find . -name'
alias grep='grep --color=auto'
alias h='history'
alias findbig='find . -type f -size +50M -exec ls -lh {} + 2>/dev/null | awk "{ print \$9 \": \" \$5 }"'

# Extra File & Nav Shortcuts
alias dsize='du -h --max-depth=1 | sort -hr'
alias chmodx='chmod +x'
alias chownme='sudo chown -R $USER:$USER .'
alias path='echo -e ${PATH//:/\\n}'

# System
alias up='sudo apt-get update && sudo apt-get upgrade -y'
alias clean='sudo apt-get autoremove -y && sudo apt-get clean && reclaimram'
alias mem='ram'
alias hostmem='free -h'
alias cpu='cpuuse'
alias cpu5='cpuuse 5'
alias df='df -h'
alias top='htop'
alias ports='sudo netstat -tulpn'
alias logs='sudo tail -f /var/log/syslog'
alias rst='source ~/.bashrc && echo -e "\e[1;32m✔ Terminal Reloaded!\e[0m"'

# Extra System Shortcuts
alias sysinfo='cat /etc/os-release'
alias cpuinfo='lscpu'
alias myports='ss -tuln'
alias histg='history | grep'

# Network & VPN
alias myip='echo -e "\n\e[1;36m🌐 IP Details:\e[0m"; curl -s ipinfo.io; echo'
alias speed='echo -e "\e[1;33m⌛ Testing Speed...\e[0m"; speedtest-cli --simple'
alias ping='ping -c 4'
alias ts='sudo tailscale status'

# Extra Network Shortcuts
alias pinger='ping -c 4 8.8.8.8'
alias serve='python3 -m http.server 8000'

# Dev & Tools
alias gs='git status'
alias ga='git add .'
alias gc='git commit -m'
alias gp='git push'
alias gl='git log --oneline --graph -n 10'
alias get='wget -c'
alias api='curl -s'
alias weather='curl -s wttr.in/Dhaka?0'

# Python Venv Shortcuts
alias mkv='python3 -m venv .venv && echo -e "\e[1;32m✔ .venv created successfully!\e[0m"'
alias onv='source .venv/bin/activate 2>/dev/null || echo -e "\e[1;31m✘ .venv not found! Run mkv first.\e[0m"'
alias offv='deactivate 2>/dev/null || echo -e "\e[1;33mℹ No active virtual environment to deactivate.\e[0m"'

# Apps Management
alias apps='echo -e "\n\e[1;36m▶ Codex / Node / Python Apps:\e[0m"; ps -eo pid,user,%cpu,%mem,command | grep -E "[c]odex|[n]ode|[p]ython" || echo -e "\e[90mNone\e[0m"'
alias kn='sudo pkill -f node 2>/dev/null; echo -e "\e[1;32m✔ All Node apps stopped.\e[0m"'
alias kp='sudo pkill -f python 2>/dev/null; echo -e "\e[1;32m✔ All Python apps stopped.\e[0m"'
alias kcodex='sudo pkill -f codex 2>/dev/null; echo -e "\e[1;32m✔ All Codex processes stopped.\e[0m"'

# ==========================================
# 🛠️ CUSTOM SHORTCUT MANAGER
# ==========================================

CUSTOM_ALIAS_FILE="$HOME/.my_shortcuts"
if [ -f "$CUSTOM_ALIAS_FILE" ]; then
    source "$CUSTOM_ALIAS_FILE"
fi

function addcmd() {
    echo -e "\n\e[1;36m➕ Create a New Shortcut\e[0m"
    echo -e "\e[90m----------------------------------------\e[0m"
    read -p "Shortcut Name (e.g., gohome) : " S_NAME
    if [ -z "$S_NAME" ]; then echo -e "\e[1;31m✘ Cancelled. Name cannot be empty.\e[0m"; return 1; fi

    if grep -q "alias $S_NAME=" "$CUSTOM_ALIAS_FILE" 2>/dev/null; then
        echo -e "\e[1;33mℹ Shortcut '$S_NAME' already exists! Please choose another name.\e[0m"
        return 1
    fi

    read -p "Command to run (e.g., cd ~)  : " S_CMD
    if [ -z "$S_CMD" ]; then echo -e "\e[1;31m✘ Cancelled. Command cannot be empty.\e[0m"; return 1; fi

    echo "alias $S_NAME='$S_CMD'" >> "$CUSTOM_ALIAS_FILE"
    eval "alias $S_NAME='$S_CMD'"
    echo -e "\e[1;32m✔ Shortcut '$S_NAME' has been created and is ready to use!\e[0m\n"
}

function delcmd() {
    echo -e "\n\e[1;31m🗑️ Delete a Custom Shortcut\e[0m"
    echo -e "\e[90m----------------------------------------\e[0m"
    read -p "Shortcut Name to delete : " S_NAME
    if [ -z "$S_NAME" ]; then echo -e "\e[1;31m✘ Cancelled. Name cannot be empty.\e[0m"; return 1; fi

    if ! grep -q "alias $S_NAME=" "$CUSTOM_ALIAS_FILE" 2>/dev/null; then
        echo -e "\e[1;33mℹ Shortcut '$S_NAME' not found in your custom list!\e[0m"
        return 1
    fi

    sed -i "/alias $S_NAME=/d" "$CUSTOM_ALIAS_FILE"
    unalias "$S_NAME" 2>/dev/null
    echo -e "\e[1;32m✔ Shortcut '$S_NAME' has been successfully deleted!\e[0m\n"
}

# ==========================================
# ⚡ MENU
# ==========================================

function pcmd() {
    printf "   \e[1;32m%-14s\e[0m : %s\n" "$1" "$2"
}

function cmds() {
    echo -e "\n\e[1;37m⚡ ALL MAGICAL SHORTCUTS ⚡\e[0m"
    echo -e "\e[90m──────────────────────────────────────────────────────────────\e[0m"

    echo -e "\e[1;33m📁 Navigation & Files\e[0m"
    pcmd "c" "Clear screen"
    pcmd ".." "Go back 1 folder"
    pcmd "..." "Go back 2 folders"
    pcmd "ll" "List files with details & sizes"
    pcmd "sz" "Show size of files/folders here"
    pcmd "md" "Make a new directory"
    pcmd "mkcd <dir>" "Make a directory and enter it"
    pcmd "tree" "Visual tree structure"
    pcmd "dsize" "Sub-folder sizes"
    pcmd "chownme" "Take ownership of current directory"
    pcmd "chmodx" "Make a file executable"
    pcmd "ex <file>" "Extract archive"
    pcmd "findbig" "Find files larger than 50MB"
    pcmd "findtext" "Search text inside files"

    echo -e "\n\e[1;33m💻 System & Processes\e[0m"
    pcmd "up" "Update and upgrade packages"
    pcmd "clean" "Autoremove + apt clean + reclaimram"
    pcmd "mem" "Same as ram"
    pcmd "hostmem" "Raw free -h"
    pcmd "ram" "Container RAM summary"
    pcmd "ramtop" "Top processes by RSS"
    pcmd "ramwhy" "Explain RAM usage"
    pcmd "cachefiles" "Show cache directories"
    pcmd "reclaimram" "Clean cache files"
    pcmd "cpu" "CPU usage (2s avg)"
    pcmd "cpu5" "CPU usage (5s avg)"
    pcmd "cputop" "Top CPU-hungry processes"
    pcmd "cpulive [s]" "Live CPU monitor"
    pcmd "cpuwhy [s]" "Explain CPU spikes / throttling"
    pcmd "cpuavg [s]" "Average saved CPU history"
    pcmd "cginfo" "Show raw cgroup info"
    pcmd "diag" "Quick full diagnostics"
    pcmd "df" "Disk space usage"
    pcmd "top" "Task manager"
    pcmd "cpuinfo" "CPU hardware info"
    pcmd "sysinfo" "OS details"
    pcmd "ports" "Open ports"
    pcmd "logs" "Live syslog"
    pcmd "rst" "Reload terminal settings"
    pcmd "h" "History"
    pcmd "histg <txt>" "Search history"

    echo -e "\n\e[1;33m💾 Disk & Storage\e[0m"
    pcmd "DISK" "Full container disk usage"
    pcmd "disklive" "Live disk I/O monitor"
    pcmd "diskwhy" "Explain disk usage"
    pcmd "bigfiles" "Top 20 largest files"
    pcmd "bigdirs" "Top 20 largest directories"
    pcmd "tmpclean" "Clean /tmp and /var/tmp"

    echo -e "\n\e[1;33m🌐 Network & Traffic\e[0m"
    pcmd "NET" "Network usage since boot"
    pcmd "netlive" "Live network traffic monitor"
    pcmd "netstats" "Detailed connection statistics"
    pcmd "netports" "Active connections with process"
    pcmd "dnslookup" "DNS lookup helper"
    pcmd "cc" "Connect to Tailscale"
    pcmd "cs" "Disconnect Tailscale"
    pcmd "ts" "Tailscale status"
    pcmd "myip" "Public IP details"
    pcmd "pinger" "Internet connectivity test"
    pcmd "speed" "Internet speed test"
    pcmd "serve" "Host current folder on :8000"

    echo -e "\n\e[1;33m🎯 App Management\e[0m"
    pcmd "apps" "List Codex/Node/Python apps"
    pcmd "kn" "Kill all Node.js apps"
    pcmd "kp" "Kill all Python apps"
    pcmd "kcodex" "Kill all Codex processes"
    pcmd "kport <no>" "Kill app on a port"
    pcmd "proctree" "Process tree view"
    pcmd "openfiles" "Show open file count per process"

    echo -e "\n\e[1;33m🛠️ Tools & Dev\e[0m"
    pcmd "weather" "Weather in Dhaka"
    pcmd "gs, ga, gc" "Git shortcuts"
    pcmd "gitlog" "Pretty full git log"
    pcmd "addcmd" "Create personal shortcut"
    pcmd "delcmd" "Delete personal shortcut"
    pcmd "mkv" "Create .venv"
    pcmd "onv" "Activate .venv"
    pcmd "offv" "Deactivate venv"
    pcmd "sv" "Smart activate venv"
    pcmd "dcodex" "Show Codex status"
    pcmd "dpy" "Check Python/Pip/Venv"
    pcmd "dgo" "Install Golang at runtime"
    pcmd "djava" "Install Java 17 at runtime"
    pcmd "syshealth" "Full system health report"
    pcmd "uptime2" "Pretty uptime display"
    pcmd "envlist" "Show all env variables"
    pcmd "bk save <srv> <nm>" "Backup /home/devuser to R2"
    pcmd "bk list <srv>" "List server backups"
    pcmd "bk inspect <srv> <nm>" "Extract latest backup to /tmp"
    pcmd "bk restore <srv> <nm>" "Merge restore latest backup"
    pcmd "bk restore-at <srv> <nm> <ts>" "Restore exact timestamp backup"
    pcmd "bk clean-restore <srv> <nm>" "Clear /home/devuser then restore"

    echo -e "\n\e[1;35m👤 My Personal Shortcuts\e[0m"
    if [ -f "$CUSTOM_ALIAS_FILE" ] && [ -s "$CUSTOM_ALIAS_FILE" ]; then
        cat "$CUSTOM_ALIAS_FILE" | sed "s/alias //g" | sed "s/='/|/g" | sed "s/'//g" | while IFS='|' read -r name cmd; do
            pcmd "$name" "$cmd"
        done
    else
        echo -e "   \e[90mNo personal shortcuts yet. Type 'addcmd' to create one.\e[0m"
    fi

    echo -e "\e[90m──────────────────────────────────────────────────────────────\e[0m\n"
}

# ==========================================
# Helpers
# ==========================================

function mkcd() { mkdir -p "$1" && cd "$1"; }
function findtext() { grep -rnw . -e "$1"; }

function kport() {
    if [ -z "$1" ]; then
        echo -e "\e[1;31m✘ Usage: kport <port>\e[0m"
        return 1
    fi
    PID=$(sudo lsof -t -i:$1)
    if [ -z "$PID" ]; then
        echo -e "\e[1;33mℹ Port $1 is free\e[0m"
    else
        sudo kill -9 $PID
        echo -e "\e[1;32m✔ Killed process on port $1\e[0m"
    fi
}

function ex() {
    if [ -z "$1" ]; then
        echo -e "\e[1;31m✘ Usage: ex <filename>\e[0m"
        return 1
    fi
    if [ -f "$1" ]; then
        case "$1" in
            *.tar.bz2) tar xjf "$1" ;;
            *.tar.gz) tar xzf "$1" ;;
            *.bz2) bunzip2 "$1" ;;
            *.rar) unrar e "$1" ;;
            *.gz) gunzip "$1" ;;
            *.tar) tar xf "$1" ;;
            *.zip) unzip "$1" ;;
            *) echo -e "\e[1;31m✘ Cannot extract '$1'\e[0m" ;;
        esac
    else
        echo -e "\e[1;31m✘ '$1' is not a valid file\e[0m"
    fi
}

# ==========================================
# BACKUP / RESTORE (DEVUSER ONLY)
# ==========================================

function _bk_require_env() {
    if [ -z "$BK_S3_ENDPOINT" ] || [ -z "$BK_S3_BUCKET" ] || [ -z "$BK_AWS_ACCESS_KEY_ID" ] || [ -z "$BK_AWS_SECRET_ACCESS_KEY" ]; then
        echo -e "\e[1;31m✘ Backup env vars missing.\e[0m"
        echo -e "Required:"
        echo -e "  BK_S3_ENDPOINT"
        echo -e "  BK_S3_BUCKET"
        echo -e "  BK_AWS_ACCESS_KEY_ID"
        echo -e "  BK_AWS_SECRET_ACCESS_KEY"
        echo -e "Optional:"
        echo -e "  BK_AWS_REGION=auto"
        return 1
    fi

    export AWS_ACCESS_KEY_ID="$BK_AWS_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$BK_AWS_SECRET_ACCESS_KEY"
    export AWS_DEFAULT_REGION="${BK_AWS_REGION:-auto}"
    return 0
}

function _bk_latest_key() {
    local server="$1"
    local name="$2"
    aws --endpoint-url "$BK_S3_ENDPOINT" s3 ls "s3://${BK_S3_BUCKET}/servers/${server}/${name}/" --recursive 2>/dev/null | sort | tail -n 1 | awk '{print $4}'
}

function _bk_exact_key() {
    local server="$1"
    local name="$2"
    local stamp="$3"
    echo "servers/${server}/${name}/${server}-${name}-${stamp}.tar.gz"
}

function _bk_key_exists() {
    local key="$1"
    aws --endpoint-url "$BK_S3_ENDPOINT" s3 ls "s3://${BK_S3_BUCKET}/${key}" >/dev/null 2>&1
}

function _bk_clean_devuser_home() {
    shopt -s dotglob nullglob
    for item in /home/devuser/* /home/devuser/.[!.]* /home/devuser/..?*; do
        [ -e "$item" ] || continue
        rm -rf "$item"
    done
    shopt -u dotglob nullglob
}

function bk() {
    local action="$1"
    local server="$2"
    local name="$3"
    local stamp="$4"
    local tmp_dir="/tmp/bkwork"
    local inspect_base="/tmp/bk-inspect"
    local archive=""
    local key=""
    local latest_key=""
    local now_stamp=""
    local target_dir=""

    _bk_require_env || return 1
    mkdir -p "$tmp_dir" "$inspect_base"

    case "$action" in
        save)
            if [ -z "$server" ] || [ -z "$name" ]; then
                echo -e "\e[1;31m✘ Usage: bk save <server> <name>\e[0m"
                return 1
            fi

            now_stamp=$(date +"%Y%m%d-%H%M%S")
            archive="${tmp_dir}/${server}-${name}-${now_stamp}.tar.gz"
            key="servers/${server}/${name}/${server}-${name}-${now_stamp}.tar.gz"

            echo -e "\e[1;33m⌛ Creating backup archive from /home/devuser ...\e[0m"
            tar -czpf "$archive" -C / home/devuser

            echo -e "\e[1;33m⌛ Uploading to R2 ...\e[0m"
            aws --endpoint-url "$BK_S3_ENDPOINT" s3 cp "$archive" "s3://${BK_S3_BUCKET}/${key}" --only-show-errors || {
                rm -f "$archive"
                echo -e "\e[1;31m✘ Upload failed.\e[0m"
                return 1
            }

            rm -f "$archive"
            echo -e "\e[1;32m✔ Backup saved successfully.\e[0m"
            echo -e "\e[1;36mKey:\e[0m ${key}"
            ;;
        list)
            if [ -z "$server" ]; then
                echo -e "\e[1;31m✘ Usage: bk list <server>\e[0m"
                return 1
            fi

            echo -e "\n\e[1;36m📦 Backups for server: ${server}\e[0m"
            echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m"
            aws --endpoint-url "$BK_S3_ENDPOINT" s3 ls "s3://${BK_S3_BUCKET}/servers/${server}/" --recursive
            echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m\n"
            ;;
        inspect)
            if [ -z "$server" ] || [ -z "$name" ]; then
                echo -e "\e[1;31m✘ Usage: bk inspect <server> <name>\e[0m"
                return 1
            fi

            latest_key=$(_bk_latest_key "$server" "$name")
            if [ -z "$latest_key" ]; then
                echo -e "\e[1;31m✘ No backup found for server='${server}' name='${name}'.\e[0m"
                return 1
            fi

            archive="${tmp_dir}/inspect-${server}-${name}.tar.gz"
            now_stamp=$(basename "$latest_key" .tar.gz)
            target_dir="${inspect_base}/${server}/${name}/${now_stamp}"

            rm -rf "$target_dir"
            mkdir -p "$target_dir"

            echo -e "\e[1;33m⌛ Downloading latest backup for inspect ...\e[0m"
            aws --endpoint-url "$BK_S3_ENDPOINT" s3 cp "s3://${BK_S3_BUCKET}/${latest_key}" "$archive" --only-show-errors || {
                rm -f "$archive"
                echo -e "\e[1;31m✘ Download failed.\e[0m"
                return 1
            }

            echo -e "\e[1;33m⌛ Extracting to inspect path ...\e[0m"
            tar -xzpf "$archive" -C "$target_dir" || {
                rm -f "$archive"
                echo -e "\e[1;31m✘ Extract failed.\e[0m"
                return 1
            }

            rm -f "$archive"
            echo -e "\e[1;32m✔ Inspect copy is ready.\e[0m"
            echo -e "\e[1;36mPath:\e[0m ${target_dir}"
            echo -e "\e[1;33mTip:\e[0m Run: tree -a \"${target_dir}/home/devuser\" | head -n 100"
            ;;
        restore)
            if [ -z "$server" ] || [ -z "$name" ]; then
                echo -e "\e[1;31m✘ Usage: bk restore <server> <name>\e[0m"
                return 1
            fi

            latest_key=$(_bk_latest_key "$server" "$name")
            if [ -z "$latest_key" ]; then
                echo -e "\e[1;31m✘ No backup found for server='${server}' name='${name}'.\e[0m"
                return 1
            fi

            archive="${tmp_dir}/restore-${server}-${name}.tar.gz"

            echo -e "\e[1;33m⌛ Downloading latest backup ...\e[0m"
            aws --endpoint-url "$BK_S3_ENDPOINT" s3 cp "s3://${BK_S3_BUCKET}/${latest_key}" "$archive" --only-show-errors || {
                rm -f "$archive"
                echo -e "\e[1;31m✘ Download failed.\e[0m"
                return 1
            }

            echo -e "\e[1;33m⌛ Restoring in merge mode ...\e[0m"
            tar -xzpf "$archive" -C / || {
                rm -f "$archive"
                echo -e "\e[1;31m✘ Restore failed.\e[0m"
                return 1
            }

            chown -R devuser:devuser /home/devuser
            rm -f "$archive"
            echo -e "\e[1;32m✔ Restore complete (merge mode).\e[0m"
            echo -e "\e[1;33mBehavior:\e[0m same files overwrite হবে, extra existing files থেকে যাবে."
            ;;
        restore-at)
            if [ -z "$server" ] || [ -z "$name" ] || [ -z "$stamp" ]; then
                echo -e "\e[1;31m✘ Usage: bk restore-at <server> <name> <timestamp>\e[0m"
                echo -e "\e[1;33mExample:\e[0m bk restore-at srv-a test1 20260420-154500"
                return 1
            fi

            key=$(_bk_exact_key "$server" "$name" "$stamp")
            if ! _bk_key_exists "$key"; then
                echo -e "\e[1;31m✘ Exact backup not found.\e[0m"
                echo -e "\e[1;36mExpected key:\e[0m ${key}"
                return 1
            fi

            archive="${tmp_dir}/restore-at-${server}-${name}-${stamp}.tar.gz"

            echo -e "\e[1;33m⌛ Downloading exact backup ...\e[0m"
            aws --endpoint-url "$BK_S3_ENDPOINT" s3 cp "s3://${BK_S3_BUCKET}/${key}" "$archive" --only-show-errors || {
                rm -f "$archive"
                echo -e "\e[1;31m✘ Download failed.\e[0m"
                return 1
            }

            echo -e "\e[1;33m⌛ Restoring exact backup in merge mode ...\e[0m"
            tar -xzpf "$archive" -C / || {
                rm -f "$archive"
                echo -e "\e[1;31m✘ Restore failed.\e[0m"
                return 1
            }

            chown -R devuser:devuser /home/devuser
            rm -f "$archive"
            echo -e "\e[1;32m✔ Exact restore complete (merge mode).\e[0m"
            echo -e "\e[1;36mRestored:\e[0m ${key}"
            ;;
        clean-restore)
            if [ -z "$server" ] || [ -z "$name" ]; then
                echo -e "\e[1;31m✘ Usage: bk clean-restore <server> <name>\e[0m"
                return 1
            fi

            latest_key=$(_bk_latest_key "$server" "$name")
            if [ -z "$latest_key" ]; then
                echo -e "\e[1;31m✘ No backup found for server='${server}' name='${name}'.\e[0m"
                return 1
            fi

            archive="${tmp_dir}/clean-restore-${server}-${name}.tar.gz"

            echo -e "\e[1;33m⌛ Downloading latest backup ...\e[0m"
            aws --endpoint-url "$BK_S3_ENDPOINT" s3 cp "s3://${BK_S3_BUCKET}/${latest_key}" "$archive" --only-show-errors || {
                rm -f "$archive"
                echo -e "\e[1;31m✘ Download failed.\e[0m"
                return 1
            }

            echo -e "\e[1;33m⌛ Clearing /home/devuser ...\e[0m"
            _bk_clean_devuser_home || {
                rm -f "$archive"
                echo -e "\e[1;31m✘ Could not clear /home/devuser.\e[0m"
                return 1
            }

            echo -e "\e[1;33m⌛ Restoring clean copy ...\e[0m"
            tar -xzpf "$archive" -C / || {
                rm -f "$archive"
                echo -e "\e[1;31m✘ Restore failed.\e[0m"
                return 1
            }

            chown -R devuser:devuser /home/devuser
            rm -f "$archive"
            echo -e "\e[1;32m✔ Clean restore complete.\e[0m"
            echo -e "\e[1;33mBehavior:\e[0m /home/devuser আগের content clear করে exact backup restore করা হয়েছে."
            ;;
        *)
            echo -e "\n\e[1;36m📦 Backup Commands\e[0m"
            echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m"
            echo -e "  bk save <server> <name>"
            echo -e "  bk list <server>"
            echo -e "  bk inspect <server> <name>"
            echo -e "  bk restore <server> <name>"
            echo -e "  bk restore-at <server> <name> <timestamp>"
            echo -e "  bk clean-restore <server> <name>"
            echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m\n"
            return 1
            ;;
    esac
}

# ==========================================
# DEV SHORTCUTS
# ==========================================

function sv() {
    if [ -f "venv/bin/activate" ]; then
        source venv/bin/activate
        echo -e "\e[1;32m✔ venv activated!\e[0m"
    elif [ -f ".venv/bin/activate" ]; then
        source .venv/bin/activate
        echo -e "\e[1;32m✔ .venv activated!\e[0m"
    elif [ -f "env/bin/activate" ]; then
        source env/bin/activate
        echo -e "\e[1;32m✔ env activated!\e[0m"
    else
        echo -e "\e[1;31m✘ No virtual environment (venv, .venv, env) found in this directory!\e[0m"
        echo -e "\e[1;33mℹ Run 'mkv' to create one.\e[0m"
    fi
}

function dcodex() {
    echo -e "\n\e[1;36m🤖 Codex Status\e[0m"
    echo -e "\e[90m----------------------------------------\e[0m"
    if command -v codex >/dev/null 2>&1; then
        echo -e "\e[1;32m✔ Codex is already installed in this image.\e[0m"
        echo -e "\e[1;36mCodex Version:\e[0m $(codex --version 2>/dev/null || echo installed)"
        echo -e "\e[1;36mNode Version:\e[0m $(node -v 2>/dev/null || echo missing)"
        echo -e "\e[1;36mNPM Version:\e[0m $(npm -v 2>/dev/null || echo missing)"
        echo -e "\e[1;33mℹ Run 'codex' manually when you want to start it.\e[0m"
    else
        echo -e "\e[1;31m✘ Codex not found. Rebuild the image.\e[0m"
        return 1
    fi
    echo
}

function dpy() {
    echo -e "\n\e[1;36m🐍 Python Environment Status\e[0m"
    echo -e "\e[90m----------------------------------------\e[0m"

    NEED_PKGS=""
    command -v pip3 >/dev/null 2>&1 || NEED_PKGS="$NEED_PKGS python3-pip"
    python3 -m venv --help >/dev/null 2>&1 || NEED_PKGS="$NEED_PKGS python3-venv"

    if [ -z "$NEED_PKGS" ]; then
        echo -e "\e[1;32m✔ Python, pip and venv are already installed.\e[0m"
        echo -e "\e[1;36mPython Version:\e[0m $(python3 --version 2>&1)"
        echo -e "\e[1;36mPip Version:\e[0m $(pip3 --version 2>&1)"
        return 0
    fi

    echo -e "\e[1;33m⚠ Missing packages detected. Runtime install can raise file cache and Railway RAM graph.\e[0m"
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends $NEED_PKGS
    sudo apt-get clean
    sudo rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /var/cache/apt/*.bin
    python3 -m pip cache purge >/dev/null 2>&1 || true
    sync

    echo -e "\e[1;32m✔ Python environment is ready!\e[0m"
    echo -e "\e[1;36mPython Version:\e[0m $(python3 --version 2>&1)"
    echo -e "\e[1;36mPip Version:\e[0m $(pip3 --version 2>&1)"
}

function dgo() {
    echo -e "\n\e[1;36m🐹 Installing Golang...\e[0m"
    echo -e "\e[1;33m⚠ Runtime install can raise file cache and Railway RAM graph.\e[0m"
    sudo apt-get update && sudo apt-get install -y --no-install-recommends golang
    sudo apt-get clean && sudo rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*
    sync
    echo -e "\e[1;32m✔ Go installed successfully!\e[0m"
    go version
}

function djava() {
    echo -e "\n\e[1;36m☕ Installing Java 17 LTS...\e[0m"
    echo -e "\e[1;33m⚠ Runtime install can raise file cache and Railway RAM graph.\e[0m"
    sudo apt-get update && sudo apt-get install -y --no-install-recommends openjdk-17-jdk openjdk-17-jre
    sudo apt-get clean && sudo rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*
    sync
    echo -e "\e[1;32m✔ Java installed successfully!\e[0m"
    java -version
}

# ==========================================
# MEMORY / RAM HELPERS
# ==========================================

_b2h() {
  awk -v b="${1:-0}" 'BEGIN{
    split("B KB MB GB TB",u," ");
    i=1;
    while (b>=1024 && i<5) { b/=1024; i++ }
    printf "%.1f %s", b, u[i]
  }'
}

_mem_mode() {
  if [ -f /sys/fs/cgroup/memory.current ]; then
    echo "v2"
  elif [ -f /sys/fs/cgroup/memory/memory.usage_in_bytes ]; then
    echo "v1"
  else
    echo ""
  fi
}

_cg_base() {
  if [ -f /sys/fs/cgroup/memory.current ]; then
    echo "/sys/fs/cgroup"
    return
  fi
  if [ -f /sys/fs/cgroup/memory/memory.usage_in_bytes ]; then
    echo "/sys/fs/cgroup/memory"
    return
  fi
}

_cg_read() {
  local f="$1"
  [ -f "$f" ] || { echo 0; return; }
  local v
  v=$(cat "$f" 2>/dev/null)
  if [[ "$v" =~ ^[0-9]+$ ]]; then echo "$v"; else echo 0; fi
}

_cg_stat() {
  local key="$1" base alt
  base="$(_cg_base)"
  [ -z "$base" ] && { echo 0; return; }

  case "$key" in
    anon) alt="anon" ;;
    file) alt="file" ;;
    shmem) alt="shmem" ;;
    slab) alt="slab" ;;
    slab_reclaimable) alt="slab_reclaimable" ;;
    pagetables) alt="pgfault" ;;
    kernel_stack) alt="kernel_stack" ;;
    sock) alt="sock" ;;
    *) alt="$key" ;;
  esac

  awk -v k="$alt" '$1==k {print $2}' "$base/memory.stat" 2>/dev/null | head -n 1
}

# ==========================================
# CPU HELPERS
# ==========================================

_cpu_mode() {
  if [ -f /sys/fs/cgroup/cpu.stat ]; then
    echo "v2"
  elif [ -f /sys/fs/cgroup/cpuacct/cpuacct.usage ] || [ -f /sys/fs/cgroup/cpu/cpu.stat ]; then
    echo "v1"
  else
    echo ""
  fi
}

_cpu_limit() {
  local quota period
  if [ -f /sys/fs/cgroup/cpu.max ]; then
    read -r quota period < /sys/fs/cgroup/cpu.max
    if [ "$quota" != "max" ] && [ -n "$period" ] && [ "$period" -gt 0 ] 2>/dev/null; then
      awk -v q="$quota" -v p="$period" 'BEGIN { printf "%.2f\n", q/p }'
      return
    fi
  fi

  if [ -f /sys/fs/cgroup/cpu/cpu.cfs_quota_us ] && [ -f /sys/fs/cgroup/cpu/cpu.cfs_period_us ]; then
    quota=$(cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us 2>/dev/null)
    period=$(cat /sys/fs/cgroup/cpu/cpu.cfs_period_us 2>/dev/null)
    if [ -n "$quota" ] && [ "$quota" -gt 0 ] 2>/dev/null && [ -n "$period" ] && [ "$period" -gt 0 ] 2>/dev/null; then
      awk -v q="$quota" -v p="$period" 'BEGIN { printf "%.2f\n", q/p }'
      return
    fi
  fi

  if [ -n "$PHOENIX_CPU_FALLBACK_VCPU" ] && awk -v v="$PHOENIX_CPU_FALLBACK_VCPU" 'BEGIN { exit !(v>0) }'; then
    printf "%.2f\n" "$PHOENIX_CPU_FALLBACK_VCPU"
    return
  fi

  echo "0"
}

_cpu_limit_label() {
  local l="$(_cpu_limit)"
  if awk -v v="$l" 'BEGIN { exit !(v>0) }'; then
    printf "%s vCPU limit" "$l"
  else
    printf "shared/auto"
  fi
}

_cpu_usage_usec() {
  if [ -f /sys/fs/cgroup/cpu.stat ]; then
    awk '/^usage_usec / {print $2; exit}' /sys/fs/cgroup/cpu.stat 2>/dev/null
    return
  fi
  if [ -f /sys/fs/cgroup/cpuacct/cpuacct.usage ]; then
    awk '{printf "%.0f\n", $1/1000}' /sys/fs/cgroup/cpuacct/cpuacct.usage 2>/dev/null
    return
  fi
  echo 0
}

_cpu_throttled_usec() {
  if [ -f /sys/fs/cgroup/cpu.stat ]; then
    awk '/^throttled_usec / {print $2; found=1} END {if(!found) print 0}' /sys/fs/cgroup/cpu.stat 2>/dev/null
    return
  fi
  if [ -f /sys/fs/cgroup/cpu/cpu.stat ]; then
    awk '/^throttled_time / {printf "%.0f\n", $2/1000; found=1} END {if(!found) print 0}' /sys/fs/cgroup/cpu/cpu.stat 2>/dev/null
    return
  fi
  echo 0
}

_cpu_nr_throttled() {
  if [ -f /sys/fs/cgroup/cpu.stat ]; then
    awk '/^nr_throttled / {print $2; found=1} END {if(!found) print 0}' /sys/fs/cgroup/cpu.stat 2>/dev/null
    return
  fi
  if [ -f /sys/fs/cgroup/cpu/cpu.stat ]; then
    awk '/^nr_throttled / {print $2; found=1} END {if(!found) print 0}' /sys/fs/cgroup/cpu/cpu.stat 2>/dev/null
    return
  fi
  echo 0
}

_cpu_nr_periods() {
  if [ -f /sys/fs/cgroup/cpu.stat ]; then
    awk '/^nr_periods / {print $2; found=1} END {if(!found) print 0}' /sys/fs/cgroup/cpu.stat 2>/dev/null
    return
  fi
  if [ -f /sys/fs/cgroup/cpu/cpu.stat ]; then
    awk '/^nr_periods / {print $2; found=1} END {if(!found) print 0}' /sys/fs/cgroup/cpu/cpu.stat 2>/dev/null
    return
  fi
  echo 0
}

_cpu_pressure_avg() {
  local kind="${1:-some}" window="avg${2:-10}"
  [ ! -f /sys/fs/cgroup/cpu.pressure ] && { echo "0.00"; return; }
  awk -v k="$kind" -v w="$window" '$1==k { for(i=2;i<=NF;i++){ split($i,a,"="); if(a[1]==w){ print a[2]; found=1; exit } } } END { if(!found) print "0.00" }' /sys/fs/cgroup/cpu.pressure 2>/dev/null
}

_cpu_history_file() {
  echo "${PHOENIX_CPU_HISTORY_FILE:-/tmp/.phoenix_cpu_history}"
}

_cpu_record_history() {
  local used="$1" limit="$2" pct="$3" file tmp
  file="$(_cpu_history_file)"
  tmp="${file}.tmp.$$"
  printf '%s|%s|%s|%s\n' "$(date +%s)" "$used" "$limit" "$pct" >> "$file"
  tail -n 120 "$file" > "$tmp" 2>/dev/null && mv -f "$tmp" "$file"
}

_cpu_avg_history() {
  local window="${1:-30}" file now
  file="$(_cpu_history_file)"
  [ ! -f "$file" ] && return 1
  now=$(date +%s)
  awk -F'|' -v cutoff="$((now - window))" '$1>=cutoff {sum+=$2; n++} END { if(n>0) printf "%.3f\n", sum/n; else exit 1 }' "$file"
}

_cpu_measure() {
  local secs="${1:-2}" u1 u2 t1 t2 wall thr1 thr2 n1 n2 used limit pct thr_pct psi_some psi_full
  u1=$(_cpu_usage_usec)
  thr1=$(_cpu_throttled_usec)
  n1=$(_cpu_nr_throttled)
  t1=$(date +%s%N)
  sleep "$secs"
  t2=$(date +%s%N)
  u2=$(_cpu_usage_usec)
  thr2=$(_cpu_throttled_usec)
  n2=$(_cpu_nr_throttled)
  wall=$(( (t2 - t1) / 1000 ))
  [ "$wall" -le 0 ] && wall=1

  used=$(awk -v du="$((u2-u1))" -v dw="$wall" 'BEGIN{ v=du/dw; if(v<0) v=0; printf "%.3f", v }')
  limit=$(_cpu_limit)
  pct=$(awk -v u="$used" -v l="$limit" 'BEGIN{ if(l>0) printf "%.1f", (u/l)*100; else print "-" }')
  thr_pct=$(awk -v dt="$((thr2-thr1))" -v dw="$wall" 'BEGIN{ if(dw>0){ p=(dt/dw)*100; if(p<0)p=0; printf "%.1f", p } else print "0.0" }')
  psi_some=$(_cpu_pressure_avg some 10)
  psi_full=$(_cpu_pressure_avg full 10)

  _cpu_record_history "$used" "$limit" "$pct"
  echo "$used|$limit|$pct|$((thr2-thr1))|$thr_pct|$((n2-n1))|$psi_some|$psi_full|$secs"
}

# ==========================================
# RAM TOOLS
# ==========================================

function ramtop() {
  echo -e "\n\e[1;36m📋 Top Processes by RSS\e[0m"
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m"
  printf "  %-7s │ %-8s │ %-6s │ %-10s │ %s\n" "PID" "USER" "MEM%" "USED" "COMMAND"
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m"
  ps -eo pid=,user=,%mem=,rss=,comm= --sort=-rss | head -n 15 | while read -r pid user mem rss comm; do
    used_bytes=$((rss * 1024))
    used="$(_b2h "$used_bytes")"
    printf "  %-7s │ %-8.8s │ %-6s │ %-10s │ %s\n" "$pid" "$user" "${mem}%" "$used" "$comm"
  done
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m\n"
}

function ramwhy() {
  local base used limit anon file shmem slab pgt kstack sock rss codex_proc node_proc py_proc
  base="$(_cg_base)"
  [ -z "$base" ] && { echo "cgroup memory info not found"; return 1; }

  if [ -f "$base/memory.current" ]; then
    used=$(_cg_read "$base/memory.current")
    limit=$(_cg_read "$base/memory.max")
  else
    used=$(_cg_read "$base/memory.usage_in_bytes")
    limit=$(_cg_read "$base/memory.limit_in_bytes")
  fi

  anon=${_CG_ANON:-$(_cg_stat anon)}; [ -z "$anon" ] && anon=0
  file=${_CG_FILE:-$(_cg_stat file)}; [ -z "$file" ] && file=0
  shmem=${_CG_SHMEM:-$(_cg_stat shmem)}; [ -z "$shmem" ] && shmem=0
  slab=${_CG_SLAB:-$(_cg_stat slab)}; [ -z "$slab" ] && slab=0
  pgt=${_CG_PGT:-$(_cg_stat pagetables)}; [ -z "$pgt" ] && pgt=0
  kstack=${_CG_KSTACK:-$(_cg_stat kernel_stack)}; [ -z "$kstack" ] && kstack=0
  sock=${_CG_SOCK:-$(_cg_stat sock)}; [ -z "$sock" ] && sock=0
  rss=$(ps -eo rss= 2>/dev/null | awk '{s+=$1} END {print s*1024}')
  [ -z "$rss" ] && rss=0

  codex_proc=$(pgrep -af '(^|/)(codex)( |$)|@openai/codex' 2>/dev/null | head -n 3)
  node_proc=$(ps -eo pid=,rss=,comm=,args= --sort=-rss | grep -E '[n]ode|[n]pm' | head -n 5)
  py_proc=$(ps -eo pid=,rss=,comm=,args= --sort=-rss | grep -E '[p]ython' | head -n 5)

  echo -e "\n\e[1;35m🔎 RAM Diagnosis\e[0m"
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m"

  if [ "$file" -gt "$anon" ] && [ "$file" -gt $((150*1024*1024)) ]; then
    echo -e "\e[1;33mMain Cause:\e[0m File/Page cache is dominating memory."
    echo -e "This usually happens after installs, archive extraction, or heavy file reads."
  elif [ "$anon" -gt $((200*1024*1024)) ]; then
    echo -e "\e[1;33mMain Cause:\e[0m Real process/application memory is high (anon memory)."
    echo -e "That means one or more running processes are actually holding RAM."
  else
    echo -e "\e[1;33mMain Cause:\e[0m Mixed usage."
    echo -e "Some RAM is real process memory, some is kernel/cache overhead."
  fi

  if [ -n "$codex_proc" ]; then
    echo -e "\n\e[1;31m⚠ Codex appears to be running:\e[0m"
    echo "$codex_proc"
  fi

  if [ -n "$node_proc" ]; then
    echo -e "\n\e[1;36mNode/NPM related processes:\e[0m"
    echo "$node_proc"
  fi

  if [ -n "$py_proc" ]; then
    echo -e "\n\e[1;36mPython related processes:\e[0m"
    echo "$py_proc"
  fi

  echo -e "\n\e[1;32mWhat to do now:\e[0m"
  echo -e "  1) Run \e[1;36mram\e[0m and check File Cache vs Anon Memory"
  echo -e "  2) Run \e[1;36mcachefiles\e[0m to see cache folders"
  echo -e "  3) If File Cache is high, run \e[1;36mreclaimram\e[0m"
  echo -e "  4) If Anon/Process memory is high, run \e[1;36mramtop\e[0m"
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m\n"
}

function ram() {
  local base used limit anon file shmem slab slab_reclaimable pgt kstack sock rss free limit_txt free_txt used_pct reclaimable
  base="$(_cg_base)"
  [ -z "$base" ] && { echo "cgroup memory info not found"; return 1; }

  if [ -f "$base/memory.current" ]; then
    used=$(_cg_read "$base/memory.current")
    limit=$(_cg_read "$base/memory.max")
  else
    used=$(_cg_read "$base/memory.usage_in_bytes")
    limit=$(_cg_read "$base/memory.limit_in_bytes")
  fi

  anon=$(_cg_stat anon); [ -z "$anon" ] && anon=0
  file=$(_cg_stat file); [ -z "$file" ] && file=0
  shmem=$(_cg_stat shmem); [ -z "$shmem" ] && shmem=0
  slab=$(_cg_stat slab); [ -z "$slab" ] && slab=0
  slab_reclaimable=$(_cg_stat slab_reclaimable); [ -z "$slab_reclaimable" ] && slab_reclaimable=0
  pgt=$(_cg_stat pagetables); [ -z "$pgt" ] && pgt=0
  kstack=$(_cg_stat kernel_stack); [ -z "$kstack" ] && kstack=0
  sock=$(_cg_stat sock); [ -z "$sock" ] && sock=0
  rss=$(ps -eo rss= 2>/dev/null | awk '{s+=$1} END {print s*1024}')
  [ -z "$rss" ] && rss=0
  reclaimable=$((file + slab_reclaimable))

  export _CG_ANON="$anon" _CG_FILE="$file" _CG_SHMEM="$shmem" _CG_SLAB="$slab" _CG_SLAB_REC="$slab_reclaimable" _CG_PGT="$pgt" _CG_KSTACK="$kstack" _CG_SOCK="$sock"

  if [[ "$limit" =~ ^[0-9]+$ ]] && [ "$limit" -gt 0 ]; then
    free=$((limit - used))
    [ "$free" -lt 0 ] && free=0
    limit_txt="$(_b2h "$limit")"
    free_txt="$(_b2h "$free")"
    used_pct=$(awk -v u="$used" -v l="$limit" 'BEGIN { if (l>0) printf "%.1f%%", (u/l)*100; else print "-" }')
  else
    limit_txt="unlimited"
    free_txt="-"
    used_pct="-"
  fi

  echo -e "\n\e[1;36m📊 RAM (Container Accurate)\e[0m"
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m"
  printf "  %-20s : %s\n" "Cgroup Total" "$(_b2h "$used")"
  printf "  %-20s : %s\n" "Memory Limit" "$limit_txt"
  printf "  %-20s : %s\n" "Free to Limit" "$free_txt"
  printf "  %-20s : %s\n" "Usage Percent" "$used_pct"
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m"
  printf "  %-20s : %s\n" "Process RSS Sum" "$(_b2h "$rss")"
  printf "  %-20s : %s\n" "Anon Memory" "$(_b2h "$anon")"
  printf "  %-20s : %s\n" "File Cache" "$(_b2h "$file")"
  printf "  %-20s : %s\n" "Slab" "$(_b2h "$slab")"
  printf "  %-20s : %s\n" "Slab Reclaimable" "$(_b2h "$slab_reclaimable")"
  printf "  %-20s : %s\n" "Likely Reclaimable" "$(_b2h "$reclaimable")"
  printf "  %-20s : %s\n" "Shared Memory" "$(_b2h "$shmem")"
  printf "  %-20s : %s\n" "Page Tables" "$(_b2h "$pgt")"
  printf "  %-20s : %s\n" "Kernel Stack" "$(_b2h "$kstack")"
  printf "  %-20s : %s\n" "Socket Buffers" "$(_b2h "$sock")"
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m"

  if [ "$file" -gt "$anon" ] && [ "$file" -gt $((150*1024*1024)) ]; then
    echo -e "\e[1;33mHint:\e[0m Most RAM is in file/page cache, not in active apps."
  elif [ "$anon" -gt $((200*1024*1024)) ]; then
    echo -e "\e[1;33mHint:\e[0m Active processes are the main RAM users right now."
  else
    echo -e "\e[1;33mHint:\e[0m RAM usage is mixed between processes and cache."
  fi

  echo -e "\n\e[1;36mRun these for details:\e[0m  \e[1;32mramtop\e[0m  |  \e[1;32mramwhy\e[0m  |  \e[1;32mcachefiles\e[0m  |  \e[1;32mreclaimram\e[0m\n"
}

function cachefiles() {
  echo -e "\n\e[1;36m🗂 Common Cache Directories\e[0m"
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m"
  du -sh \
    /var/cache/apt \
    /var/lib/apt/lists \
    "$HOME/.cache" \
    "$HOME/.cache/pip" \
    "$HOME/.cache/npm" \
    "$HOME/.cache/node-gyp" \
    "$HOME/.npm" \
    /tmp/.npm-cache \
    /var/tmp \
    2>/dev/null | sort -hr
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m\n"
}

function reclaimram() {
  echo -e "\n\e[1;33m🧹 Cleaning package/cache files...\e[0m"

  npm cache clean --force >/dev/null 2>&1 || true
  python3 -m pip cache purge >/dev/null 2>&1 || true
  sudo apt-get clean >/dev/null 2>&1 || true

  rm -rf \
    "$HOME/.npm" \
    "$HOME/.cache/npm" \
    "$HOME/.cache/node-gyp" \
    "$HOME/.cache/pip" \
    /tmp/.npm-cache \
    /tmp/pip-* \
    /tmp/pip-build-* \
    /tmp/pip-install-* \
    /var/tmp/* \
    2>/dev/null || true

  sudo rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /var/cache/apt/*.bin 2>/dev/null || true

  sync

  if sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches' 2>/dev/null; then
    echo -e "\e[1;32m✔ Linux page cache dropped.\e[0m"
  else
    echo -e "\e[1;33mℹ Cache files were removed, but this container is not allowed to force-drop kernel page cache.\e[0m"
    echo -e "\e[1;33mℹ If file cache stays high, restart/redeploy the container for the cleanest reset.\e[0m"
  fi

  ram
}

# ==========================================
# CPU TOOLS
# ==========================================

function cputop() {
  echo -e "\n\e[1;36m📈 Top Processes by CPU\e[0m"
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m"
  printf "  %-7s │ %-8s │ %-6s │ %-10s │ %-10s │ %s\n" "PID" "USER" "CPU%" "RSS" "ELAPSED" "COMMAND"
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m"
  ps -eo pid=,user=,%cpu=,etime=,rss=,comm= --sort=-%cpu | head -n 15 | while read -r pid user cpu etime rss comm; do
    used="$(_b2h "$((rss * 1024))")"
    printf "  %-7s │ %-8.8s │ %-6s │ %-10s │ %-10s │ %s\n" "$pid" "$user" "${cpu}%" "$used" "$etime" "$comm"
  done
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m\n"
}

function cpuavg() {
  local win="${1:-30}" avg limit pct label
  avg=$(_cpu_avg_history "$win" 2>/dev/null || true)
  if [ -z "$avg" ]; then
    echo -e "\n\e[1;33mℹ No local CPU history yet. Run \e[1;36mcpu\e[0m or \e[1;36mcpulive\e[0m first.\n"
    return 1
  fi

  limit=$(_cpu_limit)
  pct=$(awk -v u="$avg" -v l="$limit" 'BEGIN{ if(l>0) printf "%.1f", (u/l)*100; else print "-" }')
  label="$(_cpu_limit_label)"

  echo -e "\n\e[1;36m🧠 Local CPU Average\e[0m"
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m"
  printf "  %-20s : %s sec\n" "Window" "$win"
  printf "  %-20s : %s vCPU\n" "Average Used" "$avg"
  printf "  %-20s : %s\n" "Limit" "$label"
  if [ "$pct" != "-" ]; then
    printf "  %-20s : %s%%\n" "Percent of Limit" "$pct"
  fi
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m\n"
}

function cpuuse() {
  local secs="${1:-${PHOENIX_CPU_SAMPLE_SECONDS:-2}}"
  local data used limit pct thr_usec thr_pct thr_n psi_some psi_full sample avg30 limit_label

  data="$(_cpu_measure "$secs")"
  IFS='|' read -r used limit pct thr_usec thr_pct thr_n psi_some psi_full sample <<< "$data"
  avg30=$(_cpu_avg_history 30 2>/dev/null || true)
  limit_label="$(_cpu_limit_label)"

  echo -e "\n\e[1;36m⚙ CPU (cgroup-based)\e[0m"
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m"
  printf "  %-20s : %s sec\n" "Sample Window" "$sample"
  printf "  %-20s : %s vCPU\n" "Used" "$used"
  printf "  %-20s : %s\n" "Limit" "$limit_label"
  if [ "$pct" != "-" ]; then
    printf "  %-20s : %s%%\n" "Percent of Limit" "$pct"
  else
    printf "  %-20s : %s\n" "Percent of Limit" "shared / not fixed"
  fi
  if [ -n "$avg30" ]; then
    printf "  %-20s : %s vCPU\n" "Local Avg (30s)" "$avg30"
  fi
  printf "  %-20s : %s\n" "Throttle Events" "$thr_n"
  printf "  %-20s : %s%%\n" "Throttle Time" "$thr_pct"
  printf "  %-20s : %s%%\n" "CPU PSI some avg10" "$psi_some"
  printf "  %-20s : %s%%\n" "CPU PSI full avg10" "$psi_full"
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m"
  echo -e "\e[1;33mTip:\e[0m For a calmer number closer to dashboard trend, run \e[1;36mcpu 5\e[0m or \e[1;36mcpulive 2\e[0m.\n"
}

function cpuwhy() {
  local secs="${1:-3}" data used limit pct thr_usec thr_pct thr_n psi_some psi_full sample avg30
  data="$(_cpu_measure "$secs")"
  IFS='|' read -r used limit pct thr_usec thr_pct thr_n psi_some psi_full sample <<< "$data"
  avg30=$(_cpu_avg_history 30 2>/dev/null || true)

  echo -e "\n\e[1;35m🔎 CPU Diagnosis\e[0m"
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m"

  if [ "$thr_n" -gt 0 ] || awk -v t="$thr_pct" 'BEGIN { exit !(t>0.1) }'; then
    echo -e "\e[1;33mMain Cause:\e[0m CPU throttling happened during the sample."
    echo -e "Your workload wanted more CPU time than the current cgroup scheduling allowed."
  elif [ "$pct" != "-" ] && awk -v p="$pct" 'BEGIN { exit !(p>=70) }'; then
    echo -e "\e[1;33mMain Cause:\e[0m Real CPU load is high."
    echo -e "The container is actively using a large portion of its available CPU."
  elif awk -v s="$psi_some" 'BEGIN { exit !(s>=5.0) }'; then
    echo -e "\e[1;33mMain Cause:\e[0m CPU pressure is noticeable."
    echo -e "Tasks are waiting to run, so host contention / scheduling delay may be contributing."
  elif [ -n "$avg30" ] && awk -v a="$avg30" -v u="$used" 'BEGIN { exit !(a>0.05 && u<(a/2)) }'; then
    echo -e "\e[1;33mMain Cause:\e[0m Current instant is calmer than recent history."
    echo -e "Dashboard may still show the earlier spike while your latest sample is already lower."
  else
    echo -e "\e[1;33mMain Cause:\e[0m Current CPU usage looks low or moderate."
    echo -e "If Railway shows a higher point, it was likely captured during an earlier time bucket."
  fi

  echo -e "\n\e[1;36mCurrent Sample:\e[0m"
  echo -e "  Used           : ${used} vCPU"
  echo -e "  Sample Window  : ${sample}s"
  if [ "$pct" != "-" ]; then
    echo -e "  Percent Limit  : ${pct}%"
  else
    echo -e "  Percent Limit  : shared / not fixed"
  fi
  echo -e "  Throttle Events: ${thr_n}"
  echo -e "  Throttle Time  : ${thr_pct}%"
  echo -e "  PSI some avg10 : ${psi_some}%"
  echo -e "  PSI full avg10 : ${psi_full}%"
  if [ -n "$avg30" ]; then
    echo -e "  Local Avg 30s  : ${avg30} vCPU"
  fi

  echo -e "\n\e[1;32mWhat to do now:\e[0m"
  echo -e "  1) Run \e[1;36mcpu 5\e[0m for a steadier reading"
  echo -e "  2) Run \e[1;36mcputop\e[0m to catch busy processes"
  echo -e "  3) Run \e[1;36mcpulive 2\e[0m for a live view"
  echo -e "  4) Run \e[1;36mcginfo\e[0m to inspect raw cgroup CPU settings"
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m\n"
}

function cpulive() {
  local secs="${1:-2}"
  echo -e "\e[1;36mLive CPU monitor. Press Ctrl+C to stop.\e[0m"
  sleep 1
  while true; do
    clear
    cpuuse "$secs"
    cputop
  done
}

function cginfo() {
  echo -e "\n\e[1;36m🧩 Raw cgroup info\e[0m"
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m"
  printf "  %-22s : %s\n" "CPU mode" "$(_cpu_mode)"
  printf "  %-22s : %s\n" "CPU limit label" "$(_cpu_limit_label)"
  printf "  %-22s : %s\n" "Fallback vCPU" "${PHOENIX_CPU_FALLBACK_VCPU:-unset}"

  if [ -f /sys/fs/cgroup/cpu.max ]; then
    printf "  %-22s : %s\n" "cpu.max" "$(cat /sys/fs/cgroup/cpu.max 2>/dev/null)"
  fi
  if [ -f /sys/fs/cgroup/cpu.weight ]; then
    printf "  %-22s : %s\n" "cpu.weight" "$(cat /sys/fs/cgroup/cpu.weight 2>/dev/null)"
  fi
  if [ -f /sys/fs/cgroup/cpuset.cpus.effective ]; then
    printf "  %-22s : %s\n" "cpuset effective" "$(cat /sys/fs/cgroup/cpuset.cpus.effective 2>/dev/null)"
  fi
  if [ -f /sys/fs/cgroup/cpu.pressure ]; then
    echo -e "  cpu.pressure            :"
    sed 's/^/    /' /sys/fs/cgroup/cpu.pressure 2>/dev/null
  fi
  if [ -f /sys/fs/cgroup/cpu.stat ]; then
    echo -e "  cpu.stat                :"
    sed 's/^/    /' /sys/fs/cgroup/cpu.stat 2>/dev/null
  fi

  if [ -f /sys/fs/cgroup/memory.current ]; then
    printf "  %-22s : %s\n" "memory.current" "$(cat /sys/fs/cgroup/memory.current 2>/dev/null)"
  fi
  if [ -f /sys/fs/cgroup/memory.max ]; then
    printf "  %-22s : %s\n" "memory.max" "$(cat /sys/fs/cgroup/memory.max 2>/dev/null)"
  fi

  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m\n"
}

function diag() {
  mm
  cpuwhy 3
  ramwhy
  cachefiles
}

# ==========================================
# UI / DASHBOARD
# ==========================================

function custom_motd() {
    OS_VERSION=$(grep PRETTY_NAME /etc/os-release | cut -d '"' -f 2)
    KERNEL_VERSION=$(uname -r)
    ARCH=$(uname -m)
    CPU_MODEL=$(awk -F': ' '/model name/ {print $2; exit}' /proc/cpuinfo | sed 's/^[ \t]*//')
    [ -z "$CPU_MODEL" ] && CPU_MODEL="Unknown Virtual CPU"

    LAST_LOGIN_FILE="$HOME/.last_login_info"
    if [ -f "$LAST_LOGIN_FILE" ]; then
        LAST_LOGIN_DATA=$(cat "$LAST_LOGIN_FILE")
        LAST_LOGIN_TIME=$(echo "$LAST_LOGIN_DATA" | cut -d'|' -f1)
        LAST_LOGIN_IP=$(echo "$LAST_LOGIN_DATA" | cut -d'|' -f2)
    else
        LAST_LOGIN_TIME="First Login"
        LAST_LOGIN_IP="---"
    fi

    CURRENT_IP=$(echo $SSH_CLIENT | awk '{print $1}')
    echo "$(date +"%A, %d %B %Y %I:%M:%S %p")|${CURRENT_IP:-Local}" > "$LAST_LOGIN_FILE"

    UPTIME_SEC=$(ps -o etimes= -p 1 2>/dev/null | xargs)
    if [ -n "$UPTIME_SEC" ] && [[ "$UPTIME_SEC" =~ ^[0-9]+$ ]]; then
        d=$((UPTIME_SEC / 86400))
        h=$(((UPTIME_SEC % 86400) / 3600))
        m=$(((UPTIME_SEC % 3600) / 60))
        if [ $d -gt 0 ]; then
            MY_UPTIME="${d} days, ${h} hours, ${m} mins"
        elif [ $h -gt 0 ]; then
            MY_UPTIME="${h} hours, ${m} mins"
        else
            MY_UPTIME="${m} mins"
        fi
    else
        MY_UPTIME="Just started"
    fi

    echo -e "\e[1;36m╭────────────────────────────────────────────────────────────────────────╮\e[0m"
    echo -e "\e[1;36m│ \e[1;37m🔥 Welcome to Phoenix Server 🔥\e[0m                                        "
    echo -e "\e[1;36m├────────────────────────────────────────────────────────────────────────┤\e[0m"
    echo -e "\e[1;36m│ \e[1;32m💻 OS\e[0m         : ${OS_VERSION}"
    echo -e "\e[1;36m│ \e[1;32m🐧 Kernel\e[0m     : ${KERNEL_VERSION} (${ARCH})"
    echo -e "\e[1;36m│ \e[1;32m⚙️  CPU\e[0m        : ${CPU_MODEL}"
    echo -e "\e[1;36m│ \e[1;32m⏳ Uptime\e[0m     : ${MY_UPTIME}"
    echo -e "\e[1;36m│ \e[1;32m🕒 Last Login\e[0m : ${LAST_LOGIN_TIME}"
    echo -e "\e[1;36m│ \e[1;32m🌐 Login IP\e[0m   : ${LAST_LOGIN_IP}"
    echo -e "\e[1;36m╰────────────────────────────────────────────────────────────────────────╯\e[0m"
}

function mm() {
  local base used limit free used_mb limit_mb free_mb used_pct
  local anon file rss reclaimable slab_rec
  local cpu_data cpu_used cpu_limit cpu_pct cpu_thr cpu_thr_pct cpu_thr_n cpu_psi_some cpu_psi_full cpu_sample
  local avg30
  local disk_total disk_used disk_free
  local home_items
  local C_C="\e[36m" C_G="\e[90m" C_W="\e[1;37m" C_R="\e[0m"

  echo -e "\n${C_W}▶ SYSTEM MONITOR (Container Accurate)${C_R}\n${C_G}------------------------------------------------------------${C_R}"

  print_row() {
    echo -e " $1   ${C_W}$(printf "%-6s" "$2")${C_R} ${C_G}::${C_R}  ${C_C}$(printf "%-16s" "$3")${C_R} ${C_G}|${C_R}  ${C_C}$(printf "%-16s" "$4")${C_R} ${C_G}|${C_R}  ${C_C}$(printf "%-16s" "$5")${C_R}"
  }

  base="$(_cg_base)"
  if [ -n "$base" ]; then
    if [ -f "$base/memory.current" ]; then
      used=$(_cg_read "$base/memory.current")
      limit=$(_cg_read "$base/memory.max")
    else
      used=$(_cg_read "$base/memory.usage_in_bytes")
      limit=$(_cg_read "$base/memory.limit_in_bytes")
    fi
  else
    used=0
    limit="max"
  fi

  anon=$(_cg_stat anon); [ -z "$anon" ] && anon=0
  file=$(_cg_stat file); [ -z "$file" ] && file=0
  slab_rec=$(_cg_stat slab_reclaimable); [ -z "$slab_rec" ] && slab_rec=0
  rss=$(ps -eo rss= 2>/dev/null | awk '{s+=$1} END {print int(s/1024) "MB"}')
  [ -z "$rss" ] && rss="0MB"
  reclaimable=$(((file + slab_rec) / 1024 / 1024))

  used_mb=$((used / 1024 / 1024))
  if [[ "$limit" =~ ^[0-9]+$ ]] && [ "$limit" -gt 0 ]; then
    limit_mb=$((limit / 1024 / 1024))
    free_mb=$(((limit - used) / 1024 / 1024))
    [ "$free_mb" -lt 0 ] && free_mb=0
    used_pct=$(awk -v u="$used" -v l="$limit" 'BEGIN { if (l>0) printf "%.1f%%", (u/l)*100; else print "-" }')
    print_row "❖" "RAM" "${limit_mb}MB Max" "${used_mb}MB Used" "${free_mb}MB Free"
  else
    print_row "❖" "RAM" "Unknown Max" "${used_mb}MB Used" "cgroup mode"
    used_pct="unknown"
  fi

  print_row "≣" "CACHE" "$((file / 1024 / 1024))MB File" "$((anon / 1024 / 1024))MB Anon" "${rss} RSS"

  cpu_data="$(_cpu_measure "${PHOENIX_MM_CPU_SAMPLE_SECONDS:-2}")"
  IFS='|' read -r cpu_used cpu_limit cpu_pct cpu_thr cpu_thr_pct cpu_thr_n cpu_psi_some cpu_psi_full cpu_sample <<< "$cpu_data"
  avg30=$(_cpu_avg_history 30 2>/dev/null || true)

  if awk -v v="$cpu_limit" 'BEGIN { exit !(v>0) }'; then
    print_row "⚙" "CPU" "${cpu_limit} vCPU Max" "${cpu_used} vCPU ${cpu_sample}s" "${cpu_pct}% Limit"
  else
    print_row "⚙" "CPU" "shared/auto" "${cpu_used} vCPU ${cpu_sample}s" "no fixed cap"
  fi

  if [ -z "$avg30" ]; then avg30="$cpu_used"; fi
  print_row "⌁" "CPU+" "${avg30} vCPU 30s" "${cpu_thr_pct}% Throttle" "${cpu_psi_some}% PSI10"

  disk_used=$(du -sh / --exclude=/proc --exclude=/sys --exclude=/dev 2>/dev/null | cut -f1)
  disk_free=$(df -h / 2>/dev/null | awk 'NR==2 {print $4}')
  [ -z "$disk_used" ] && disk_used="?"
  [ -z "$disk_free" ] && disk_free="?"
  print_row "⛁" "DISK" "Container Use" "${disk_used} Used" "${disk_free} Free"

  home_items=$(find "$HOME" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
  [ -z "$home_items" ] && home_items="0"
  print_row "▣" "HOME" "${home_items} Items" "$USER" "$HOME"

  echo -e "${C_G}------------------------------------------------------------${C_R}"
  echo -e " ${C_W}RAM%${C_R}    ${C_G}::${C_R}  ${C_C}${used_pct}${C_R}"
  echo -e " ${C_W}CACHE${C_R}   ${C_G}::${C_R}  ${C_C}${reclaimable}MB likely reclaimable${C_R}"
  echo -e " ${C_W}CPU NOW${C_R} ${C_G}::${C_R}  ${C_C}${cpu_used} vCPU (${cpu_sample}s avg)${C_R}"
  echo -e "${C_G}------------------------------------------------------------${C_R}\n"
}

# ==========================================
# Tailscale commands
# ==========================================

function cc() {
    if pgrep -x "tailscaled" > /dev/null; then
        echo -e "\e[1;33mℹ Tailscale daemon is running.\e[0m"
    else
        echo -e "\e[1;33m⌛ Starting Tailscale in background...\e[0m"
        nohup sudo tailscaled --tun=userspace-networking --socks5-server=localhost:1055 > /dev/null 2>&1 &
        sleep 3
    fi

    TS_KEY_FILE="$HOME/.ts_auth_key"
    TS_KEY=""

    if [ -f "$TS_KEY_FILE" ]; then
        echo -e "\n\e[1;36m🔑 Previous Key found!\e[0m"
        echo -e "  \e[1;32m1) Use previous Key\e[0m"
        echo -e "  \e[1;33m2) Enter new Key\e[0m"
        read -p "Option [1/2]: " OPTION
        if [ "$OPTION" == "1" ]; then
            TS_KEY=$(cat "$TS_KEY_FILE")
        elif [ "$OPTION" == "2" ]; then
            read -p "New Key: " TS_KEY
            [ -n "$TS_KEY" ] && echo "$TS_KEY" > "$TS_KEY_FILE"
        else
            return 1
        fi
    else
        echo -e "\e[1;36m"
        read -p "Enter Tailscale Auth Key: " TS_KEY
        echo -e "\e[0m"
        [ -n "$TS_KEY" ] && echo "$TS_KEY" > "$TS_KEY_FILE"
    fi

    [ -z "$TS_KEY" ] && return 1
    sudo tailscale up --authkey="$TS_KEY" --hostname=phoenix
    if [ $? -eq 0 ]; then
        echo -e "\n\e[1;32m✔ Success! Phoenix is online.\e[0m\n"
    else
        echo -e "\n\e[1;31m✘ Failed.\e[0m\n"
    fi
}

function cs() {
    sudo tailscale logout 2>/dev/null
    sudo tailscale down 2>/dev/null
    sudo pkill -f tailscaled
    echo -e "\e[1;32m✔ Tailscale stopped.\e[0m\n"
}

# ==========================================
# 💾 DISK TOOLS (NEW)
# ==========================================

function DISK() {
  local C_C="\e[36m" C_G="\e[90m" C_W="\e[1;37m" C_R="\e[0m" C_Y="\e[1;33m" C_GR="\e[1;32m" C_RE="\e[1;31m"

  echo -e "\n${C_W}💾 DISK USAGE (Full Container View)${C_R}"
  echo -e "${C_G}────────────────────────────────────────────────────────────────────${C_R}"

  # Root filesystem totals
  local fs_total fs_used fs_free fs_pct
  fs_total=$(df -h / 2>/dev/null | awk 'NR==2 {print $2}')
  fs_used=$(df -h / 2>/dev/null | awk 'NR==2 {print $3}')
  fs_free=$(df -h / 2>/dev/null | awk 'NR==2 {print $4}')
  fs_pct=$(df / 2>/dev/null | awk 'NR==2 {print $5}')

  printf "  ${C_W}%-22s${C_R} : ${C_C}%s${C_R}\n" "Filesystem Total" "${fs_total}"
  printf "  ${C_W}%-22s${C_R} : ${C_C}%s${C_R}\n" "Used" "${fs_used} (${fs_pct})"
  printf "  ${C_W}%-22s${C_R} : ${C_C}%s${C_R}\n" "Free" "${fs_free}"

  echo -e "${C_G}────────────────────────────────────────────────────────────────────${C_R}"

  # Container actual usage (what WE have written)
  echo -e " ${C_Y}📂 Container Directory Usage:${C_R}"
  printf "  ${C_W}%-22s${C_R} : ${C_C}%s${C_R}\n" "Home ($HOME)" "$(du -sh "$HOME" 2>/dev/null | cut -f1)"
  printf "  ${C_W}%-22s${C_R} : ${C_C}%s${C_R}\n" "/tmp" "$(du -sh /tmp 2>/dev/null | cut -f1)"
  printf "  ${C_W}%-22s${C_R} : ${C_C}%s${C_R}\n" "/var/log" "$(du -sh /var/log 2>/dev/null | cut -f1)"
  printf "  ${C_W}%-22s${C_R} : ${C_C}%s${C_R}\n" "/var/cache" "$(du -sh /var/cache 2>/dev/null | cut -f1)"
  printf "  ${C_W}%-22s${C_R} : ${C_C}%s${C_R}\n" "/root" "$(du -sh /root 2>/dev/null | cut -f1)"

  echo -e "${C_G}────────────────────────────────────────────────────────────────────${C_R}"

  # All mounted filesystems
  echo -e " ${C_Y}📊 All Mounted Filesystems:${C_R}"
  df -h --output=source,size,used,avail,pcent,target 2>/dev/null | awk 'NR==1 {printf "  %-20s %-7s %-7s %-7s %-6s %s\n", $1,$2,$3,$4,$5,$6} NR>1 && /^\// {printf "  %-20s %-7s %-7s %-7s %-6s %s\n", $1,$2,$3,$4,$5,$6}'

  echo -e "${C_G}────────────────────────────────────────────────────────────────────${C_R}"

  # Inode usage
  local inode_used inode_total inode_pct
  inode_used=$(df -i / 2>/dev/null | awk 'NR==2 {print $3}')
  inode_total=$(df -i / 2>/dev/null | awk 'NR==2 {print $2}')
  inode_pct=$(df -i / 2>/dev/null | awk 'NR==2 {print $5}')
  printf "  ${C_W}%-22s${C_R} : ${C_C}%s / %s (%s)${C_R}\n" "Inodes Used" "${inode_used}" "${inode_total}" "${inode_pct}"

  echo -e "${C_G}────────────────────────────────────────────────────────────────────${C_R}"
  echo -e " ${C_GR}Run: bigfiles | bigdirs | diskwhy | tmpclean${C_R}\n"
}

function diskwhy() {
  echo -e "\n\e[1;35m🔎 Disk Usage Diagnosis\e[0m"
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m"

  local pct
  pct=$(df / 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}')

  if [ -n "$pct" ] && [ "$pct" -ge 90 ] 2>/dev/null; then
    echo -e "\e[1;31m⚠ CRITICAL: Disk is ${pct}% full!\e[0m"
    echo -e "Immediate action needed. Run \e[1;36mbigfiles\e[0m and \e[1;36mtmpclean\e[0m now."
  elif [ -n "$pct" ] && [ "$pct" -ge 70 ] 2>/dev/null; then
    echo -e "\e[1;33m⚠ WARNING: Disk is ${pct}% full.\e[0m"
    echo -e "Consider cleaning up logs, cache, or unused files."
  else
    echo -e "\e[1;32m✔ Disk usage is healthy (${pct}% used).\e[0m"
  fi

  echo -e "\n\e[1;36mTop space consumers:\e[0m"
  du -sh /home /root /tmp /var /usr 2>/dev/null | sort -hr | head -n 8 | while read -r s p; do
    printf "  %-8s  %s\n" "$s" "$p"
  done

  echo -e "\n\e[1;36mLog files:\e[0m"
  find /var/log -type f -name "*.log" -exec du -sh {} + 2>/dev/null | sort -hr | head -n 5

  echo -e "\n\e[1;32mWhat to do:\e[0m"
  echo -e "  1) Run \e[1;36mbigfiles\e[0m to find largest files"
  echo -e "  2) Run \e[1;36mbigdirs\e[0m to find largest directories"
  echo -e "  3) Run \e[1;36mtmpclean\e[0m to clean /tmp"
  echo -e "  4) Run \e[1;36mreclaimram\e[0m to clean apt/pip/npm cache"
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m\n"
}

function bigfiles() {
  echo -e "\n\e[1;36m📦 Top 20 Largest Files (container-wide)\e[0m"
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m"
  find / -xdev -type f -printf '%s %p\n' 2>/dev/null | sort -rn | head -n 20 | while read -r size path; do
    human=$(awk -v b="$size" 'BEGIN{
      split("B KB MB GB",u," "); i=1;
      while(b>=1024&&i<4){b/=1024;i++}
      printf "%.1f %s", b, u[i]
    }')
    printf "  %-10s  %s\n" "$human" "$path"
  done
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m\n"
}

function bigdirs() {
  echo -e "\n\e[1;36m📁 Top 20 Largest Directories\e[0m"
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m"
  du -hx --max-depth=4 / 2>/dev/null | sort -hr | grep -v "^0" | head -n 20 | while read -r size path; do
    printf "  %-10s  %s\n" "$size" "$path"
  done
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m\n"
}

function tmpclean() {
  echo -e "\n\e[1;33m🧹 Cleaning temporary files...\e[0m"
  local before after
  before=$(du -sh /tmp /var/tmp 2>/dev/null | awk '{sum+=$1} END{print sum}')
  rm -rf /tmp/* /tmp/.* /var/tmp/* 2>/dev/null || true
  sync
  echo -e "\e[1;32m✔ /tmp and /var/tmp cleaned.\e[0m"
  echo -e "\n\e[1;36mCurrent disk status:\e[0m"
  df -h / 2>/dev/null | awk 'NR<=2'
  echo
}

function disklive() {
  echo -e "\e[1;36mLive disk I/O monitor. Press Ctrl+C to stop.\e[0m"
  sleep 1
  while true; do
    clear
    echo -e "\e[1;37m⛁ LIVE DISK I/O  —  $(date '+%H:%M:%S')\e[0m"
    echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m"
    if command -v iostat >/dev/null 2>&1; then
      iostat -xh 1 1 2>/dev/null | tail -n +3
    else
      cat /proc/diskstats 2>/dev/null | awk '{printf "  %-12s rd:%s wr:%s\n", $3, $6, $10}' | head -n 10
    fi
    echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m"
    DISK
    sleep 2
  done
}

# ==========================================
# 🌐 NETWORK TOOLS (NEW)
# ==========================================

function NET() {
  local C_C="\e[36m" C_G="\e[90m" C_W="\e[1;37m" C_R="\e[0m" C_Y="\e[1;33m" C_GR="\e[1;32m"

  echo -e "\n${C_W}🌐 NETWORK USAGE (Since Container Boot)${C_R}"
  echo -e "${C_G}────────────────────────────────────────────────────────────────────${C_R}"

  # Per-interface RX/TX from /proc/net/dev
  echo -e " ${C_Y}📡 Interface Traffic:${C_R}"
  printf "  ${C_W}%-12s %-18s %-18s %-12s %-12s${C_R}\n" "Interface" "RX (Download)" "TX (Upload)" "RX Packets" "TX Packets"
  echo -e "  ${C_G}$(printf '%.0s─' {1..68})${C_R}"

  awk 'NR>2 {
    iface=$1; gsub(/:/, "", iface)
    rx_bytes=$2; tx_bytes=$10
    rx_pkts=$3; tx_pkts=$11
    if (rx_bytes+tx_bytes > 0) {
      split("B KB MB GB TB", u, " ")
      # RX human
      rx=rx_bytes; ri=1; while(rx>=1024 && ri<5){rx/=1024; ri++}
      # TX human
      tx=tx_bytes; ti=1; while(tx>=1024 && ti<5){tx/=1024; ti++}
      printf "  %-12s %-18s %-18s %-12s %-12s\n", iface, sprintf("%.1f %s",rx,u[ri]), sprintf("%.1f %s",tx,u[ti]), rx_pkts, tx_pkts
    }
  }' /proc/net/dev 2>/dev/null

  echo -e "${C_G}────────────────────────────────────────────────────────────────────${C_R}"

  # Active connections summary
  local tcp_count udp_count listen_count
  tcp_count=$(ss -t 2>/dev/null | grep -c ESTAB || echo 0)
  udp_count=$(ss -u 2>/dev/null | grep -v "^Netid" | wc -l || echo 0)
  listen_count=$(ss -tln 2>/dev/null | grep -c LISTEN || echo 0)

  echo -e " ${C_Y}🔌 Connection Summary:${C_R}"
  printf "  ${C_W}%-22s${C_R} : ${C_C}%s${C_R}\n" "TCP Established" "${tcp_count}"
  printf "  ${C_W}%-22s${C_R} : ${C_C}%s${C_R}\n" "UDP Sockets" "${udp_count}"
  printf "  ${C_W}%-22s${C_R} : ${C_C}%s${C_R}\n" "Listening Ports" "${listen_count}"

  echo -e "${C_G}────────────────────────────────────────────────────────────────────${C_R}"

  # DNS info
  echo -e " ${C_Y}🔍 DNS Resolvers:${C_R}"
  grep "^nameserver" /etc/resolv.conf 2>/dev/null | awk '{printf "  %s\n", $2}' | head -n 3

  echo -e "${C_G}────────────────────────────────────────────────────────────────────${C_R}"

  # IP addresses
  echo -e " ${C_Y}🏠 IP Addresses:${C_R}"
  ip -4 addr show 2>/dev/null | awk '/inet / {printf "  %-12s : %s\n", $NF, $2}' | head -n 5

  echo -e "${C_G}────────────────────────────────────────────────────────────────────${C_R}"
  echo -e " ${C_GR}Run: netlive | netstats | netports | myip${C_R}\n"
}

function netlive() {
  echo -e "\e[1;36mLive network monitor. Press Ctrl+C to stop.\e[0m"
  local prev_rx prev_tx cur_rx cur_tx iface
  iface=$(ip -o link show 2>/dev/null | awk -F': ' '!/lo/{print $2; exit}')
  [ -z "$iface" ] && iface="eth0"

  prev_rx=$(awk -v iface="${iface}:" '$1==iface {print $2}' /proc/net/dev 2>/dev/null)
  prev_tx=$(awk -v iface="${iface}:" '$1==iface {print $10}' /proc/net/dev 2>/dev/null)

  while true; do
    sleep 1
    cur_rx=$(awk -v iface="${iface}:" '$1==iface {print $2}' /proc/net/dev 2>/dev/null)
    cur_tx=$(awk -v iface="${iface}:" '$1==iface {print $10}' /proc/net/dev 2>/dev/null)

    local dl ul
    dl=$(awk -v d="$((cur_rx - prev_rx))" 'BEGIN{
      split("B/s KB/s MB/s GB/s",u," "); i=1; b=d;
      if(b<0)b=0;
      while(b>=1024&&i<4){b/=1024;i++}
      printf "%.1f %s", b, u[i]
    }')
    ul=$(awk -v d="$((cur_tx - prev_tx))" 'BEGIN{
      split("B/s KB/s MB/s GB/s",u," "); i=1; b=d;
      if(b<0)b=0;
      while(b>=1024&&i<4){b/=1024;i++}
      printf "%.1f %s", b, u[i]
    }')

    printf "\r\e[1;36m[%s]\e[0m  \e[1;32m↓ DL: %-12s\e[0m  \e[1;33m↑ UL: %-12s\e[0m  iface: %s   " \
      "$(date '+%H:%M:%S')" "$dl" "$ul" "$iface"

    prev_rx="$cur_rx"
    prev_tx="$cur_tx"
  done
}

function netstats() {
  echo -e "\n\e[1;36m📊 Detailed Network Statistics\e[0m"
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m"

  echo -e "\e[1;33mTCP States:\e[0m"
  ss -tan 2>/dev/null | awk 'NR>1 {states[$1]++} END {for(s in states) printf "  %-18s: %d\n", s, states[s]}' | sort -k2 -rn

  echo -e "\n\e[1;33mTop Remote IPs by connections:\e[0m"
  ss -tan 2>/dev/null | awk 'NR>1 && $1=="ESTAB" {split($5,a,":"); ips[a[1]]++} END {for(i in ips) printf "  %-20s: %d connections\n", i, ips[i]}' | sort -k2 -rn | head -n 10

  echo -e "\n\e[1;33mSocket Buffers:\e[0m"
  cat /proc/net/sockstat 2>/dev/null | sed 's/^/  /'

  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m\n"
}

function netports() {
  echo -e "\n\e[1;36m🔌 Active Ports & Processes\e[0m"
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m"
  printf "  %-8s %-10s %-25s %-20s %s\n" "Proto" "Port" "Address" "State" "Process"
  echo -e "  \e[90m$(printf '%.0s─' {1..68})\e[0m"
  sudo ss -tulpn 2>/dev/null | awk 'NR>1 {
    proto=$1; state=$2; addr=$5; proc=$7
    split(addr,a,":")
    port=a[length(a)]
    printf "  %-8s %-10s %-25s %-20s %s\n", proto, port, addr, state, proc
  }' | sort -k2 -n
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m\n"
}

function dnslookup() {
  if [ -z "$1" ]; then
    echo -e "\e[1;31m✘ Usage: dnslookup <domain>\e[0m"
    return 1
  fi
  echo -e "\n\e[1;36m🔍 DNS Lookup: $1\e[0m"
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m"
  echo -e "\e[1;33mA Records:\e[0m"
  host -t A "$1" 2>/dev/null | grep "has address" | sed 's/^/  /'
  echo -e "\e[1;33mMX Records:\e[0m"
  host -t MX "$1" 2>/dev/null | grep "mail" | sed 's/^/  /'
  echo -e "\e[1;33mNS Records:\e[0m"
  host -t NS "$1" 2>/dev/null | grep "name server" | sed 's/^/  /'
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m\n"
}

# ==========================================
# 🛠️ EXTRA SYSTEM TOOLS (NEW)
# ==========================================

function proctree() {
  echo -e "\n\e[1;36m🌳 Process Tree\e[0m"
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m"
  ps -eo pid=,ppid=,user=,%cpu=,%mem=,comm= --sort=ppid | awk '
  BEGIN { printf "  %-7s %-7s %-8s %-6s %-6s %s\n", "PID", "PPID", "USER", "CPU%", "MEM%", "COMMAND" }
  { printf "  %-7s %-7s %-8.8s %-6s %-6s %s\n", $1,$2,$3,$4,$5,$6 }
  ' | head -n 30
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m\n"
}

function openfiles() {
  echo -e "\n\e[1;36m📂 Open File Descriptors per Process\e[0m"
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m"
  printf "  %-7s %-8s %-8s %s\n" "PID" "FD Count" "USER" "COMMAND"
  echo -e "  \e[90m$(printf '%.0s─' {1..50})\e[0m"
  for pid in $(ls /proc 2>/dev/null | grep -E '^[0-9]+$' | sort -n); do
    fd_count=$(ls /proc/$pid/fd 2>/dev/null | wc -l)
    comm=$(cat /proc/$pid/comm 2>/dev/null || echo "?")
    user=$(stat -c '%U' /proc/$pid 2>/dev/null || echo "?")
    if [ "$fd_count" -gt 5 ] 2>/dev/null; then
      printf "  %-7s %-8s %-8s %s\n" "$pid" "$fd_count" "$user" "$comm"
    fi
  done | sort -k2 -rn | head -n 20
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m\n"
}

function gitlog() {
  git log --oneline --graph --decorate --all -n 20 2>/dev/null || echo -e "\e[1;31m✘ Not a git repository.\e[0m"
}

function uptime2() {
  local secs d h m s
  secs=$(awk '{print int($1)}' /proc/uptime 2>/dev/null)
  d=$((secs/86400)); h=$(((secs%86400)/3600)); m=$(((secs%3600)/60)); s=$((secs%60))
  echo -e "\n\e[1;36m⏱ System Uptime\e[0m"
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m"
  printf "  %-20s : %s days, %s hours, %s mins, %s secs\n" "Host Uptime" "$d" "$h" "$m" "$s"
  local c_secs
  c_secs=$(ps -o etimes= -p 1 2>/dev/null | xargs)
  if [ -n "$c_secs" ] && [[ "$c_secs" =~ ^[0-9]+$ ]]; then
    local cd ch cm cs
    cd=$((c_secs/86400)); ch=$(((c_secs%86400)/3600)); cm=$(((c_secs%3600)/60)); cs=$((c_secs%60))
    printf "  %-20s : %s days, %s hours, %s mins, %s secs\n" "Container PID1 Up" "$cd" "$ch" "$cm" "$cs"
  fi
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m\n"
}

function envlist() {
  echo -e "\n\e[1;36m🌍 Environment Variables\e[0m"
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m"
  env | sort | while IFS='=' read -r key val; do
    printf "  \e[1;32m%-28s\e[0m = %s\n" "$key" "$val"
  done
  echo -e "\e[90m────────────────────────────────────────────────────────────────────\e[0m\n"
}

function syshealth() {
  echo -e "\n\e[1;37m══════════════════════════════════════════════════════\e[0m"
  echo -e "\e[1;37m  🏥 FULL SYSTEM HEALTH REPORT\e[0m"
  echo -e "\e[1;37m══════════════════════════════════════════════════════\e[0m"
  uptime2
  mm
  DISK
  NET
  netstats
  ramwhy
  cpuwhy 2
  echo -e "\e[1;37m══════════════════════════════════════════════════════\e[0m\n"
}

# ==========================================
# Clean login screen
# ==========================================

if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
    clear
    custom_motd
    mm
    echo -e "\e[1;33m🔥 Quick Actions:\e[0m"
    printf "   \e[1;32m%-10s\e[0m : %s\n" "cc" "Connect VPN"
    printf "   \e[1;32m%-10s\e[0m : %s\n" "ram" "Detailed RAM Info"
    printf "   \e[1;32m%-10s\e[0m : %s\n" "cpu5" "Steady CPU view"
    printf "   \e[1;32m%-10s\e[0m : %s\n" "DISK" "Full disk usage"
    printf "   \e[1;32m%-10s\e[0m : %s\n" "NET" "Network traffic info"
    printf "   \e[1;32m%-10s\e[0m : %s\n" "dcodex" "Show Codex status"
    printf "   \e[1;32m%-10s\e[0m : %s\n" "bk" "Backup/Restore helper"
    printf "   \e[1;36m%-10s\e[0m : \e[1;36m%s\e[0m\n\n" "cmds" "View ALL Shortcuts ⚡"
fi
EOF

RUN cat /tmp/setup.sh >> /home/devuser/.bashrc && \
    cat /tmp/setup.sh >> /root/.bashrc && \
    printf '\nif [ -f /etc/profile.d/railway_env.sh ]; then\n    source /etc/profile.d/railway_env.sh\nfi\n' >> /home/devuser/.bashrc && \
    printf '\nif [ -f /etc/profile.d/railway_env.sh ]; then\n    source /etc/profile.d/railway_env.sh\nfi\n' >> /root/.bashrc && \
    chown devuser:devuser /home/devuser/.bashrc && \
    rm /tmp/setup.sh

# --------------------------------------------------
# Startup script
# --------------------------------------------------
RUN cat > /start.sh <<'SH'
#!/bin/bash
set -e

cat > /etc/profile.d/railway_env.sh <<EOF
export BK_S3_ENDPOINT="${BK_S3_ENDPOINT}"
export BK_S3_BUCKET="${BK_S3_BUCKET}"
export BK_AWS_ACCESS_KEY_ID="${BK_AWS_ACCESS_KEY_ID}"
export BK_AWS_SECRET_ACCESS_KEY="${BK_AWS_SECRET_ACCESS_KEY}"
export BK_AWS_REGION="${BK_AWS_REGION:-auto}"
EOF

chmod 644 /etc/profile.d/railway_env.sh
chown root:root /etc/profile.d/railway_env.sh

/usr/sbin/sshd
tail -f /dev/null
SH

RUN sed -i 's/\r$//' /start.sh && chmod +x /start.sh

WORKDIR /home/devuser
EXPOSE 22
CMD ["/start.sh"]
