#!/usr/bin/env bash

interval=2
cpu_window=5 
log_file="watchdog.log"
grace_period=15 # Secundele de imunitate

# Lista procese
procese=(
	"firefox:50:2048:export MOZ_CRASHREPORTER_DISABLE=1; firefox &"
	"sleep:10:50:sleep 100 &"
)

declare -A cpu_history
declare -A suspendat_state
declare -A start_time # Dictionar pentru a retine cand a pornit procesul

check_process() {
	local pname="$1"
	# Folosim pgrep pentru a verifica daca exista PID-uri
	# Daca nu exista, returnam NA NA direct
	if ! pgrep -x "$pname" > /dev/null; then
		echo "NA NA"
		return
	fi

	top -b -n 1 | grep -w "$pname" | awk '
	{
		cpu += $9
		mem += $6
		count++
	}
	END {
		if (count > 0)
			printf "%.1f %d", cpu, mem / 1024
		else
			print "NA NA"
	}'
}

trap 'pkill -CONT firefox; pkill -CONT sleep; exit' SIGINT SIGTERM

while true; do
	echo "--- Verificare la $(date) ---" >> "$log_file"
	current_ts=$(date +%s) # Timpul curent in secunde
	
	for entry in "${procese[@]}"; do
		IFS=':' read -r pname max_cpu max_ram start_cmd <<< "$entry"
		read cur_cpu cur_ram <<< "$(check_process "$pname")"

		# 1. LOGICA DE RESTART 
		if [[ "$cur_cpu" == "NA" ]]; then
			echo "[ALERT] $pname nu ruleaza. Se reporneste..." >> "$log_file"
			
			# Executam comanda
			eval "$start_cmd" > /dev/null 2>&1 &
			
			# Resetam variabilele
			unset cpu_history[$pname]
			unset suspendat_state[$pname]
			
			# SETAM TIMPUL DE PORNIRE (pentru Grace Period)
			start_time[$pname]=$current_ts
			continue
		fi

		# 2. VERIFICARE GRACE PERIOD (Imunitate la start)
		# Daca procesul a pornit acum mai putin de X secunde, il ignoram
		p_start=${start_time[$pname]:-0}
		diff_time=$((current_ts - p_start))
		
		if (( diff_time < grace_period )); then
			echo "Status $pname: STARTUP (Imunitate activa: ${diff_time}s / ${grace_period}s)" >> "$log_file"
			continue # Sarim peste verificarea limitelor
		fi

		# 3. CALCUL MEDIE SI VERIFICARE
		cpu_history[$pname]="${cpu_history[$pname]} $cur_cpu"
		cpu_history[$pname]=$(echo "${cpu_history[$pname]}" | awk -v n="$cpu_window" '{
			for (i = (NF > n ? NF-n+1 : 1); i <= NF; i++) printf "%s ", $i
		}')

		avg_cpu=$(echo "${cpu_history[$pname]}" | awk '{
			sum=0; for(i=1;i<=NF;i++) sum+=$i; 
			if (NF>0) print sum/NF; else print 0;
		}')

		echo "Status $pname: AVG_CPU=$avg_cpu% (Limita: $max_cpu%) RAM=$cur_ram MB" >> "$log_file"

		is_cpu_high=$(echo "$avg_cpu > $max_cpu" | bc -l)
		is_ram_high=$(( cur_ram > max_ram ))

		if (( is_cpu_high == 1 || is_ram_high == 1 )); then
			echo "[WARN] $pname depaseste limitele!" >> "$log_file"
			
			if [[ -z "${suspendat_state[$pname]}" ]]; then
				echo " -> Actiune: Suspendare temporara (SIGSTOP). Resetare istoric." >> "$log_file"
				pkill -STOP -x "$pname"
				suspendat_state[$pname]=1
				cpu_history[$pname]="" # Resetam istoricul pentru a nu il omori imediat
			else
				echo " -> Actiune: Fortare oprire (SIGKILL)." >> "$log_file"
				pkill -KILL -x "$pname"
				unset suspendat_state[$pname]
			fi
		else
			if [[ -n "${suspendat_state[$pname]}" ]]; then
				echo " -> Actiune: Revenire la normal. Reluare proces (SIGCONT)" >> "$log_file"
				pkill -CONT -x "$pname"
				unset suspendat_state[$pname]
				cpu_history[$pname]=""
			fi
		fi
	done

	sleep "$interval"
done
