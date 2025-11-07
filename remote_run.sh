#!/usr/bin/env bash

set -euo pipefail

# ssh user che esegue lo script, 
# usato anche per assegnare l'ownership dei remote files.
# l'utente di accesso lo si specifica a runtime, es: "user@localhost"
REMOTE_USER=""
# Folder nella quale uploadere gli scripts
REMOTE_DIR="/tmp"

SCRIPT="$1"
shift

OUTPUT_MODE="log"
HOSTS=()
EXTRA_FILES=()
REMOTE_ARGS=()
TMP_DIR=$(mktemp -d)


# separazione host / argomenti
while [[ "$#" -gt 0 ]]; do
	if [[ "$1" == "--" ]]; then
		shift
		REMOTE_ARGS=("$@")
		break
	elif [[ -f "$1" ]]; then
		EXTRA_FILES+=("$1")
		shift
	elif [[ "$1" == "--to-stdout" ]]; then
		OUTPUT_MODE="hybrid"
		shift
	else
		HOSTS+=("$1")
		shift
	fi
done

log() {
    local host_port="$1"
    local msg="$2"
    local logfile="$3"
	local mode="${4:-hybrid}"

    # timestamp + host + messaggio
	line="[$(date '+%Y-%m-%d %H:%M:%S')] === ${host_port} ${msg} ==="

	case "$mode" in
		log)
            echo "$line" >> "$logfile"
            ;;
        stdout)
            echo "$line"
            ;;
        hybrid)
            echo "$line" | tee -a "$logfile"
            ;;
        *)
            echo "Errore: modalità log sconosciuta '$mode'" >&2
            ;;
    esac

    #echo "[$(date '+%Y-%m-%d %H:%M:%S')] === ${host_port} ${msg} ===" | tee -a "$logfile"
}


run_on_host() {
	local conn_string="$1"
	local host="${conn_string%%:*}"
	local port="${conn_string##*:}"
	[[ "$1" == *:* ]] || local port=22
	local logfile="log_${conn_string//[:\/]/_}.txt"
	local statusfile="$TMP_DIR/${conn_string//[:\/]/_}.status"
	local cmd

	SCP_CMD=(scp
	    -o BatchMode=yes
	    -o ConnectTimeout=5
	    -o ServerAliveInterval=1
	    -o ServerAliveCountMax=5
	    -o StrictHostKeyChecking=no
	    -o UserKnownHostsFile=/dev/null
	    -P "$port")

	SSH_CMD=(ssh
		-o BatchMode=yes
		-o ConnectTimeout=5
		-o ServerAliveInterval=1
		-o ServerAliveCountMax=5
		-o StrictHostKeyChecking=no
		-o UserKnownHostsFile=/dev/null
		-p "$port")

	log "$conn_string" "Inizio" "$logfile"

	# Copia i file sul remote
	if ! "${SCP_CMD[@]}" \
		"$SCRIPT" \
		"${EXTRA_FILES[@]}" \
		"${host}:${REMOTE_DIR}/" \
		2>/dev/null >> "$logfile"; then
			log "$conn_string" "Failure (SCP)" "$logfile"
			echo "FAIL" > "$statusfile"
			return
	fi

	# Se REMOTE_USER e' settato
	# allora cambia il comando remoto per includere lo switch dell'utenza
	# e il cambio dell'ownership dello script caricato
	if [[ -n "$REMOTE_USER" ]]; then
		cmd="sudo -i -u $REMOTE_USER bash ${REMOTE_DIR}/$(basename "$SCRIPT")"
		if ! "${SSH_CMD[@]}" \
			"$host" \
			"chown ${REMOTE_USER}: ${REMOTE_DIR}/$(basename "$SCRIPT") ${EXTRA_FILES[*]}" \
			2>/dev/null >> "$logfile"; then
				log "$conn_string" "Failure (chown)" "$logfile"
				echo "FAIL" > "$statusfile"
				return
		fi
	else
		cmd="bash ${REMOTE_DIR}/$(basename "$SCRIPT")"
	fi

	# Aggiunge, se presenti, gli arguments
	for arg in "${REMOTE_ARGS[@]}"; do
		cmd+=" '$arg'"
	done

	
	# Esegue lo script target sul remote
	if output=$("${SSH_CMD[@]}" \
		"$host" "$cmd" 2>/dev/null); then
			log "$conn_string" "$output" "$logfile" "$OUTPUT_MODE"
			log "$conn_string" "Success" "$logfile"
			echo "OK" > "$statusfile"
	else
		log "$conn_string" "$output" "$logfile" "$OUTPUT_MODE"
		log "$conn_string" "Failure (cmd)" "$logfile"
		echo "FAIL" > "$statusfile"
	fi
}

for host in "${HOSTS[@]}"; do
    run_on_host "$host"
done


# riepilogo finale
echo
echo "==================== RIEPILOGO ===================="
for host in "${HOSTS[@]}"; do
	statusfile="${TMP_DIR}/${host//[:\/]/_}.status"
	if [[ -f "$statusfile" ]]; then
		status=$(<"$statusfile")
	else
		echo "file not file"
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
