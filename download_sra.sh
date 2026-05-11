#!/usr/bin/env bash
# ============================================================
# download_sra.sh — ENA FASTQ Downloader
#
# Usage:
#   bash download_sra.sh <ACCESSION> [OPTIONS]
#
#   ACCESSION  PRJNA/PRJEB/PRJDB... (project) or SRR/ERR/DRR... (run)
#
# Options:
#   --output-dir DIR    Output directory (default: ./output)
#   --show-progress     Show wget progress bar (auto-detected if TTY)
#   --background         Launch in screen session, named after ACCESSION
#   -h, --help          Show this help
#
# Examples:
#   bash download_sra.sh PRJNA1074950 --output-dir /mnt/hdd2/metagenome
#   bash download_sra.sh SRR11066123 --output-dir ./data --show-progress
#   bash download_sra.sh PRJNA1074950 --output-dir /mnt/hdd2/metagenome --background
# ============================================================

set -u

# ---- help ----
show_help() {
    sed -n '/^# =/{:a;n;/^# =/q;p;ba}' "$0" | sed 's/^# \{0,1\}//'
}

# ---- logging ----
LOG_FILE=""
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}
echo_log() {
    echo "$@" | tee -a "$LOG_FILE"
}

# ---- human-readable size ----
human_size() {
    local bytes=$1
    if command -v numfmt &>/dev/null; then
        numfmt --to=iec --suffix=B "$bytes" 2>/dev/null || echo "${bytes}B"
    elif [ "$bytes" -lt 1024 ]; then
        echo "${bytes}B"
    elif [ "$bytes" -lt 1048576 ]; then
        echo "$((bytes / 1024))KB"
    elif [ "$bytes" -lt 1073741824 ]; then
        echo "$((bytes / 1048576))MB"
    else
        awk -v b="$bytes" 'BEGIN { printf "%.1fG\n", b / 1073741824 }'
    fi
}

# ---- elapsed time ----
elapsed_str() {
    local s=$1
    printf '%02d:%02d:%02d' $((s/3600)) $((s%3600/60)) $((s%60))
}

# ---- get file size (portable) ----
file_size() {
    local f="$1"
    if [ -f "$f" ]; then
        stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || wc -c < "$f" 2>/dev/null || echo 0
    else
        echo 0
    fi
}

# ---- check dependencies ----
check_deps() {
    local missing=""
    for cmd in curl wget; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "[ERROR] '$cmd' is required but not found in PATH"
            missing=1
        fi
    done
    if [ -n "$missing" ]; then
        exit 1
    fi
}

# ---- query ENA API ----
query_ena() {
    local accession=$1
    local api_url="https://www.ebi.ac.uk/ena/portal/api/filereport"
    local params="accession=${accession}&result=read_run&fields=run_accession,fastq_ftp,fastq_md5,library_layout&format=tsv&download=true"

    echo_log "[INFO] Querying ENA API for: ${accession}"
    log "[INFO] API URL: ${api_url}?${params}"

    local tsv
    tsv=$(curl -sS --retry 3 --connect-timeout 30 "${api_url}?${params}" 2>&1)
    local curl_exit=$?

    if [ $curl_exit -ne 0 ]; then
        echo_log "[ERROR] ENA API query failed (curl exit: ${curl_exit})"
        echo_log "[ERROR] ${tsv}"
        exit 1
    fi

    if [ -z "$tsv" ]; then
        echo_log "[ERROR] ENA API returned empty response for: ${accession}"
        exit 1
    fi

    # clean carriage returns
    tsv=$(echo "$tsv" | tr -d '\r')

    # validate header
    local header
    header=$(echo "$tsv" | head -1)
    if ! echo "$header" | grep -q "run_accession"; then
        echo_log "[ERROR] Unexpected API response format"
        echo_log "[ERROR] Header: ${header}"
        exit 1
    fi

    echo "${tsv}"
}

# ---- download a single file with retry ----
download_file() {
    local url=$1 dest=$2 label=$3

    # skip if already exists and has content
    if [ -f "$dest" ]; then
        local existing_size
        existing_size=$(file_size "$dest")
        if [ "$existing_size" -gt 0 ]; then
            echo_log "  [SKIP] ${label} — already exists ($(human_size "$existing_size"))"
            log "  [SKIP] ${label} — already exists ($(human_size "$existing_size"))"
            return 0
        else
            log "  [WARN] ${label} — file exists but empty, re-downloading"
            rm -f "$dest"
        fi
    fi

    # Determine progress style
    local wget_progress="--progress=dot:mega"
    if [ "$SHOW_PROGRESS" = true ] || [ -t 1 ]; then
        wget_progress="--progress=bar:force"
    fi

    local max_retries=3
    local retry=0
    local download_start download_end

    while [ $retry -lt $max_retries ]; do
        retry=$((retry + 1))
        download_start=$(date +%s)

        if [ $retry -gt 1 ]; then
            echo_log "  [RETRY] ${label} — attempt ${retry}/${max_retries}"
            log "  [RETRY] ${label} — attempt ${retry}/${max_retries}"
            sleep 5
        fi

        log "  [DOWNLOAD] ${label} — attempt ${retry}/${max_retries} — ftp://${url}"

        # wget: -c resume, --tries internal retry for transient errors
        wget -c --tries=3 ${wget_progress} -O "$dest" "ftp://${url}" 2>&1
        local wget_exit=$?

        download_end=$(date +%s)

        if [ $wget_exit -eq 0 ] && [ -f "$dest" ]; then
            local sz
            sz=$(file_size "$dest")
            local elapsed=$((download_end - download_start))
            echo_log "  [OK] ${label} — $(human_size "$sz") ($(elapsed_str "$elapsed"))"
            log "  [OK] ${label} — $(human_size "$sz") ($(elapsed_str "$elapsed"))"
            return 0
        fi

        log "  [FAIL] ${label} — wget exit code: ${wget_exit} (attempt ${retry}/${max_retries})"
    done

    echo_log "  [FAIL] ${label} — after ${max_retries} attempts"
    log "  [FAIL] ${label} — after ${max_retries} attempts"
    return 1
}

# ---- download all runs ----
download_runs() {
    local tsv=$1
    local project_dir=$2
    local total_runs success=0 failed=0
    local skipped_runs=()

    # count non-header lines
    total_runs=$(echo "$tsv" | tail -n +2 | grep -c .)
    if [ "$total_runs" -eq 0 ]; then
        echo_log "[ERROR] No runs found in API response"
        exit 1
    fi

    echo_log "[INFO] Total runs: ${total_runs}"
    echo_log ""
    log ""

    local current=0
    local IFS=$'\t'

    while IFS=$'\t' read -r run_acc fastq_ftp fastq_md5 layout; do
        current=$((current + 1))

        if [ -z "$run_acc" ] || [ "$run_acc" = "run_accession" ]; then
            continue
        fi

        echo_log "============================================================"
        echo_log "[${current}/${total_runs}] ${run_acc}  (${layout:-UNKNOWN})"
        echo_log "============================================================"
        log "[${current}/${total_runs}] ${run_acc} (${layout:-UNKNOWN}) — START"

        if [ -z "$fastq_ftp" ]; then
            echo_log "  [WARN] No FASTQ URLs for ${run_acc}, skipping"
            log "  [WARN] No FASTQ URLs — skipped"
            skipped_runs+=("$run_acc")
            continue
        fi

        local run_start run_end
        run_start=$(date +%s)
        local run_failed=0

        IFS=';' read -ra URLS <<< "$fastq_ftp"
        for url in "${URLS[@]}"; do
            local filename
            filename=$(basename "$url")
            local dest="${project_dir}/${filename}"

            echo_log "[DOWNLOAD] ${filename}"
            log "  URL: ftp://${url}"

            if ! download_file "$url" "$dest" "$filename"; then
                run_failed=1
            fi
            echo_log ""
        done

        run_end=$(date +%s)

        if [ $run_failed -eq 0 ]; then
            success=$((success + 1))
            echo_log "[${current}/${total_runs}] ${run_acc} — DONE ($(elapsed_str $((run_end - run_start))))"
            log "[${current}/${total_runs}] ${run_acc} — DONE"
        else
            failed=$((failed + 1))
            echo_log "[${current}/${total_runs}] ${run_acc} — FAILED"
            log "[${current}/${total_runs}] ${run_acc} — FAILED"
        fi
        echo_log ""

    done < <(echo "$tsv" | tail -n +2)

    # return stats via global vars
    DOWNLOAD_SUCCESS=$success
    DOWNLOAD_FAILED=$failed
    DOWNLOAD_TOTAL=$total_runs
}

# ============================================================
# main
# ============================================================

main() {
    # ---- parse args ----
    ACCESSION=""
    OUTPUT_DIR="./output"
    SHOW_PROGRESS=false
    BACKGROUND=false

    while [ $# -gt 0 ]; do
        case "$1" in
            --output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --show-progress)
                SHOW_PROGRESS=true
                shift
                ;;
            --background)
                BACKGROUND=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            -*)
                echo "[ERROR] Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                ACCESSION="$1"
                shift
                ;;
        esac
    done

    if [ -z "$ACCESSION" ]; then
        echo "[ERROR] ACCESSION is required"
        show_help
        exit 1
    fi

    # ---- detect accession type ----
    if [[ "$ACCESSION" =~ ^(PRJ|ERP|SRP|DRP) ]]; then
        MODE="project"
    elif [[ "$ACCESSION" =~ ^(SRR|ERR|DRR|SRX|ERX|DRX) ]]; then
        MODE="run"
    else
        echo "[ERROR] Unrecognized accession format: ${ACCESSION}"
        echo "  Expected: PRJNA..., PRJEB..., SRR..., ERR..., DRR..., etc."
        exit 1
    fi

    # ---- setup directories ----
    PROJECT_DIR="${OUTPUT_DIR%/}/${ACCESSION}"
    mkdir -p "$PROJECT_DIR"
    LOG_FILE="${PROJECT_DIR}/download.log"
    START_TIME=$(date +%s)
    START_DATE=$(date '+%Y-%m-%d %H:%M:%S')

    # ---- handle background mode ----
    if [ "$BACKGROUND" = true ]; then
        check_deps

        if ! command -v screen &>/dev/null; then
            echo "[ERROR] 'screen' is required for background mode"
            echo "  Install: sudo apt install screen"
            exit 1
        fi

        # kill existing session with same name
        screen -S "$ACCESSION" -X quit 2>/dev/null || true

        local script_dir
        script_dir="$(cd "$(dirname "$0")" && pwd)"
        local script_path="${script_dir}/download_sra.sh"

        # Reconstruct command from parsed variables (avoids $@ consumed issue)
        local cmd="bash '${script_path}' '${ACCESSION}'"
        cmd+=" --output-dir '${OUTPUT_DIR}'"
        if [ "$SHOW_PROGRESS" = true ]; then
            cmd+=" --show-progress"
        fi

        echo "[INFO] Launching screen session: ${ACCESSION}"
        echo "[INFO] Command: ${cmd}"
        echo ""

        screen -dmS "$ACCESSION" bash -c "
            echo '============================================================'
            echo ' Screen Session: ${ACCESSION}'
            echo ' Host:           \$(hostname)'
            echo ' Start:          \$(date '+%Y-%m-%d %H:%M:%S')'
            echo ' Log:            ${LOG_FILE}'
            echo '============================================================'
            echo ''
            ${cmd}
            EXIT_CODE=\$?
            echo ''
            echo '============================================================'
            echo ' Exit code:      \${EXIT_CODE}'
            echo ' Finished:       \$(date '+%Y-%m-%d %H:%M:%S')'
            echo ' Log:            ${LOG_FILE}'
            echo '============================================================'
            echo ''
            echo 'Press Enter to close this screen session.'
            echo 'Or detach with Ctrl+A D.'
        "

        sleep 1

        if screen -list 2>/dev/null | grep -q "\.${ACCESSION}"; then
            echo "[OK] Screen session '${ACCESSION}' is running."
            echo ""
            echo "  Reattach:  screen -r ${ACCESSION}"
            echo "  List:      screen -list"
            echo "  Kill:      screen -S ${ACCESSION} -X quit"
            echo "  Log:       ${LOG_FILE}"
        else
            echo "[WARN] Screen session may have exited immediately."
            echo "  Check log: ${LOG_FILE}"
        fi

        exit 0
    fi

    # ---- foreground execution ----
    check_deps

    # ---- write log header ----
    {
        echo "============================================================"
        echo "Download Started:  ${START_DATE}"
        echo "Accession:         ${ACCESSION}"
        echo "Accession Type:    ${MODE}"
        echo "Output Directory:  ${PROJECT_DIR}"
        echo "============================================================"
        echo ""
    } | tee "$LOG_FILE"

    # ---- query ENA ----
    TSV=$(query_ena "$ACCESSION")
    echo ""

    # ---- download ----
    DOWNLOAD_SUCCESS=0
    DOWNLOAD_FAILED=0
    DOWNLOAD_TOTAL=0

    download_runs "$TSV" "$PROJECT_DIR"

    # ---- summary ----
    END_TIME=$(date +%s)
    END_DATE=$(date '+%Y-%m-%d %H:%M:%S')
    ELAPSED=$((END_TIME - START_TIME))

    {
        echo "============================================================"
        echo "Download Finished: ${END_DATE}"
        echo "Elapsed:           $(elapsed_str "$ELAPSED")"
        echo "Success:           ${DOWNLOAD_SUCCESS}/${DOWNLOAD_TOTAL}"
        if [ "$DOWNLOAD_FAILED" -gt 0 ]; then
            echo "Failed:            ${DOWNLOAD_FAILED}/${DOWNLOAD_TOTAL}"
        fi
        echo "Output:            ${PROJECT_DIR}"
        echo "Log:               ${LOG_FILE}"
        echo "============================================================"
    } | tee -a "$LOG_FILE"
}

# ---- entry point ----
main "$@"
