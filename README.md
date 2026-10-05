# Bash Process Watchdog

A lightweight process watchdog written in Bash that monitors Linux processes, automatically restarts crashed processes, and controls processes that exceed configured CPU or RAM limits.

## Features

- Monitors multiple processes
- Automatically restarts processes that are no longer running
- Monitors CPU usage
- Calculates average CPU usage over multiple measurements
- Monitors RAM usage
- Supports individual CPU and RAM limits for each process
- Includes a startup grace period
- Suspends processes using `SIGSTOP`
- Resumes processes using `SIGCONT`
- Terminates processes using `SIGKILL` if resource limits continue to be exceeded
- Logs process status and watchdog actions
- Resumes suspended processes when the watchdog is stopped

## How It Works

The watchdog checks all configured processes at a fixed interval.

For every process, it:

1. Checks if the process is currently running.
2. Restarts the process if it is not running.
3. Applies a grace period after the process starts.
4. Reads the current CPU and RAM usage.
5. Stores recent CPU measurements.
6. Calculates the average CPU usage.
7. Compares CPU and RAM usage with the configured limits.
8. Suspends the process if a limit is exceeded.
9. Resumes the process if resource usage returns to normal.
10. Forcefully terminates the process if it exceeds the limits again after being suspended.

## Default Configuration

The current configuration monitors the following processes:

| Process | Max CPU | Max RAM | Start Command |
| --- | ---: | ---: | --- |
| `firefox` | 50% | 2048 MB | `firefox` |
| `sleep` | 10% | 50 MB | `sleep 100` |

Other watchdog settings:

```bash
interval=2
cpu_window=5
log_file="watchdog.log"
grace_period=15
```

- `interval` — number of seconds between watchdog checks
- `cpu_window` — number of CPU measurements used for calculating the average
- `log_file` — file where watchdog activity is logged
- `grace_period` — number of seconds during which a newly started process is ignored by the resource limiter

## Requirements

The script is designed for Linux systems and requires:

- Bash
- `top`
- `pgrep`
- `pkill`
- `awk`
- `bc`

On Debian/Ubuntu, `bc` can be installed with:

```bash
sudo apt update
sudo apt install bc
```

## Installation

Clone the repository:

```bash
git clone https://github.com/YOUR_USERNAME/bash-process-watchdog.git
```

Move into the project directory:

```bash
cd bash-process-watchdog
```

Make the script executable:

```bash
chmod +x watchdog.sh
```

## Usage

Run the watchdog:

```bash
./watchdog.sh
```

The watchdog will continue running until it is stopped.

To stop it, press:

```text
Ctrl+C
```

Watchdog activity is written to:

```text
watchdog.log
```

You can monitor the log in real time with:

```bash
tail -f watchdog.log
```

## Process Configuration

Processes are configured inside the `procese` array:

```bash
procese=(
    "firefox:50:2048:export MOZ_CRASHREPORTER_DISABLE=1; firefox &"
    "sleep:10:50:sleep 100 &"
)
```

Each process entry uses the following format:

```text
process_name:max_cpu:max_ram:start_command
```

For example:

```bash
"firefox:50:2048:firefox &"
```

means:

- Process name: `firefox`
- Maximum average CPU usage: `50%`
- Maximum RAM usage: `2048 MB`
- Restart command: `firefox &`

Another process can be added like this:

```bash
procese=(
    "firefox:50:2048:firefox &"
    "sleep:10:50:sleep 100 &"
    "example:80:1024:./example &"
)
```

## CPU Monitoring

CPU usage is stored in a history for each monitored process.

The watchdog keeps the latest measurements according to:

```bash
cpu_window=5
```

The average of those measurements is then compared with the configured CPU limit.

For example, if the latest CPU measurements are:

```text
20 40 60 70 50
```

the watchdog calculates their average before deciding whether the CPU limit has been exceeded.

## Startup Grace Period

When a process is restarted, the watchdog gives it a temporary grace period:

```bash
grace_period=15
```

During these 15 seconds, CPU and RAM limits are not enforced.

This prevents processes from being suspended or terminated because of temporary resource spikes during startup.

## Process Control

The watchdog uses Linux signals to manage processes.

### SIGSTOP

If a process exceeds its CPU or RAM limit for the first time, it is suspended:

```bash
pkill -STOP -x "$pname"
```

### SIGCONT

If the process is suspended and its resource usage is considered normal again, it is resumed:

```bash
pkill -CONT -x "$pname"
```

### SIGKILL

If the process exceeds the limits again after previously being suspended, it is forcefully terminated:

```bash
pkill -KILL -x "$pname"
```

The watchdog will detect the missing process during a later check and automatically restart it.

## Graceful Shutdown

The script handles `SIGINT` and `SIGTERM`:

```bash
trap 'pkill -CONT firefox; pkill -CONT sleep; exit' SIGINT SIGTERM
```

This ensures that monitored processes are resumed before the watchdog exits.

## Example Log

Example output from `watchdog.log`:

```text
--- Verificare la Mon Oct 5 17:30:00 EEST 2026 ---
Status firefox: AVG_CPU=12.4% (Limita: 50%) RAM=850 MB

[WARN] firefox depaseste limitele!
 -> Actiune: Suspendare temporara (SIGSTOP). Resetare istoric.

[ALERT] sleep nu ruleaza. Se reporneste...
```

## Limitations

The current implementation identifies processes by their process name using `pgrep` and `pkill`.

If multiple processes with the same name exist:

- Their resource usage may be combined.
- Signals may be sent to all processes with that name.

The script also currently assumes that memory values returned by `top` can be converted to MB using the implemented calculation.

## Possible Future Improvements

Possible improvements include:

- PID-based process tracking
- Config file support
- Command-line arguments
- Automatic log rotation
- Configurable actions for each process
- Better handling of multiple processes with the same name
- More accurate memory monitoring
- Email or desktop notifications
- Running the watchdog as a `systemd` service

## License

This project was created for educational purposes.
