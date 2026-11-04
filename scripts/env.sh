# source first, keeps cache / temp files in the chapter folder (home is small)
export CH=/nesi/nobackup/uow04177/ch4_therm_stress_rnaseq
export TMPDIR=$CH/tmp
export XDG_CACHE_HOME=$CH/.cache
export MPLCONFIGDIR=$CH/.cache/matplotlib
mkdir -p $TMPDIR $XDG_CACHE_HOME
