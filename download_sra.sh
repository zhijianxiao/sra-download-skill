#!/bin/bash

SRR_ID=$1

if [ -z "${SRR_ID}" ]; then
    echo "Usage: bash download_sra.sh SRR_ID"
    exit 1
fi

BASE_DIR="/mnt/hdd2/cxj-download/metagenome"
OUTDIR="${BASE_DIR}/${SRR_ID}"
LOGDIR="${BASE_DIR}/logs"
mkdir -p "${OUTDIR}" "${LOGDIR}"

exec > >(tee -a "${LOGDIR}/${SRR_ID}.log") 2>&1

echo "[INFO] Downloading SRA..."
prefetch "${SRR_ID}" --output-directory "${OUTDIR}"
echo "[INFO] Download completed"

echo "[INFO] Converting to FASTQ..."
fasterq-dump "${SRR_ID}" --outdir "${OUTDIR}"
echo "[INFO] FASTQ conversion completed"

echo "[INFO] Compressing FASTQ files..."
gzip "${OUTDIR}"/*.fastq
echo "[INFO] Compression completed"

echo "[INFO] All steps completed successfully"
echo "Output:  ${OUTDIR}"
echo "Log:     ${LOGDIR}/${SRR_ID}.log"
