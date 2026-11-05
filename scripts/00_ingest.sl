#!/bin/bash
# unpack novogene deliveries in raw_data and check md5s
# the rna batch may also hold the 48 non-thermal sif samples, they're left as they are
# takes every *.tar in raw_data (or the ones given) plus any delivery folder not checked yet
# usage: sbatch scripts/00_ingest.sl [--rm-tar] [raw_data/X201SC....tar ...]
#   --rm-tar  delete each tar once its files pass md5
#SBATCH --job-name=ingest
#SBATCH --account=uow04177
#SBATCH --time=04:00:00
#SBATCH --mem=8G
#SBATCH --cpus-per-task=8
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err

set -euo pipefail
cd /nesi/nobackup/uow04177/ch4_therm_stress_rnaseq
RAW=$PWD/raw_data
T=${SLURM_CPUS_PER_TASK:-4}

RM_TAR=0
if [ "${1:-}" = "--rm-tar" ]; then RM_TAR=1; shift; fi
if [ $# -gt 0 ]; then TARS=("$@"); else mapfile -t TARS < <(find $RAW -maxdepth 1 -name '*.tar' | sort); fi

# 1. unpack. novogene tars hold one top folder (X201SC...), anything else goes in raw_data/<tar name>
for tar in "${TARS[@]}"; do
    batch=$(basename "$tar" .tar)
    if [ -e "$RAW/.$batch.unpacked" ]; then echo ">> $batch already unpacked"; continue; fi
    tops=$(tar -tf "$tar" | cut -d/ -f1 | sort -u)
    if [ "$(echo "$tops" | wc -l)" -eq 1 ]; then
        tar -xf "$tar" -C $RAW
        dir=$RAW/$tops
    else
        mkdir -p $RAW/$batch
        tar -xf "$tar" -C $RAW/$batch
        dir=$RAW/$batch
    fi
    echo "$tar -> $dir" > "$RAW/.$batch.unpacked"
    echo ">> unpacked $tar -> $dir"
done

# 2. md5 for every delivery folder without a passed check
# per-sample MD5.txt where there are some, otherwise the top one, checked in parallel
check_one() { cd "$(dirname "$1")" && md5sum -c "$(basename "$1")"; }
export -f check_one
for dir in $(find $RAW -mindepth 1 -maxdepth 1 -type d | sort); do
    batch=$(basename $dir)
    log=$RAW/$batch.md5check.txt
    if [ -s $log ] && ! grep -qv ': OK$' $log; then echo ">> $batch md5 already ok"; continue; fi
    mapfile -t sums < <(find $dir -mindepth 2 -name 'MD5*.txt' | sort)
    [ ${#sums[@]} -eq 0 ] && mapfile -t sums < <(find $dir -maxdepth 1 -name 'MD5*.txt')
    if [ ${#sums[@]} -eq 0 ]; then echo "!! $batch: no MD5.txt found, not checked"; continue; fi
    printf '%s\n' "${sums[@]}" | xargs -P $T -I{} bash -c 'check_one "$@"' _ {} > $log 2>&1 || true
    nf=$(find $dir -name '*.f*q.gz' | wc -l)
    nok=$(grep -c ': OK$' $log || true)
    if grep -qv ': OK$' $log; then
        echo "!! $batch: md5 problems, see $log"; grep -v ': OK$' $log | head
        continue
    fi
    echo ">> $batch: $nok files OK ($nf fastq on disk)"
    if [ $RM_TAR -eq 1 ]; then
        for tar in "${TARS[@]}"; do
            if grep -q " -> $dir\$" "$RAW/.$(basename "$tar" .tar).unpacked" 2>/dev/null; then rm -f "$tar" && echo ">> removed $tar"; fi
        done
    fi
done

du -sh $RAW
echo ">> next: python3 scripts/make_samplesheet.py"
