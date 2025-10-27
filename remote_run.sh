#!/usr/bin/env bash

SCRIPT="$1"
shift

REMOTE_DIR="/tmp"
MAX_JOBS=5
HOSTS=()
REMOTE_ARGS=()
TMP_DIR=$(mktemp -d)

# separazione host / argomenti
while [[ "$#" -gt 0 ]]; do
    if [[ "$1" == "--" ]]; then
        shift
        REMOTE_ARGS=("$@")
        break
    else
        HOSTS+=("$1")
        shift
    fi
done

run_on_host() {
    local host="$1"
    local logfile="log_${host//[:\/]/_}.txt"
    local statusfile="$TMP_DIR/${host//[:\/]/_}.status"

    echo "[$(date "+%Y-%m-%d %H:%M:%S")] === $host: Inizio ===" | tee -a "$logfile"

    if ! scp "$SCRIPT" "$host:$REMOTE_DIR/" &>> "$logfile"; then
        echo "[$(date "+%Y-%m-%d %H:%M:%S")] === $host: Errore SCP ===" | tee -a "$logfile"
        echo "FAIL" > "$statusfile"
        return
    fi

    local cmd="bash $REMOTE_DIR/$(basename "$SCRIPT")"
    for arg in "${REMOTE_ARGS[@]}"; do
        cmd+=" '$arg'"
    done

    if ssh "$host" "$cmd" &>> "$logfile"; then
        echo "[$(date "+%Y-%m-%d %H:%M:%S")] === $host: Successo ===" | tee -a "$logfile"
        echo "OK" > "$statusfile"
    else
        echo "[$(date "+%Y-%m-%d %H:%M:%S")] === $host: Fallito ===" | tee -a "$logfile"
        echo "FAIL" > "$statusfile"
    fi
}

# parallelo limitato
running_jobs=0
for host in "${HOSTS[@]}"; do
    run_on_host "$host" &

    ((running_jobs++))
    if (( running_jobs >= MAX_JOBS )); then
        wait -n
        ((running_jobs--))
    fi
done
wait

# riepilogo finale
echo
echo "==================== RIEPILOGO ===================="
for host in "${HOSTS[@]}"; do
    statusfile="$TMP_DIR/${host//[:\/]/_}.status"
    if [[ -f "$statusfile" ]]; then
        status=$(<"$statusfile")
    else
        status="FAIL"
    fi
    if [[ "$status" == "OK" ]]; then
        echo -e "$host : \e[32mOK\e[0m"
    else
        echo -e "$host : \e[31mFAIL\e[0m"
    fi
done
echo "==================================================="
rm -rf "$TMP_DIR"
