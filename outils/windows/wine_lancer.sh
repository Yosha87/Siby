#!/bin/bash
# Runs one test scenario in the Windows package under Wine: a first start
# sets the configuration up, then options.dat redirects puts to a UTF-8 log,
# loads the heartbeat (pouls.tcl) and sources the scenario. Expects the
# unzipped package in $SCRATCH/wine/Siby and a Wine prefix in $SCRATCH/wine/prefix.
# The same options.dat works on a real Windows machine (paths without Z:).
# usage: lancer.sh <scenario name> <out dir>
S=${SCRATCH:?set SCRATCH to a work folder}
CAPT=$(cd "$(dirname "$0")/../captures" && pwd)
NOM=$1; OUT=$2; mkdir -p $OUT
W=$S/wine/run_$NOM; rm -rf $W; mkdir -p $W; cp -r $S/wine/Siby $W/
export WINEDEBUG=-all WINEPREFIX=$S/wine/prefix
# (language: read from the environment at start-up, French by default here)
export SIBY_LANG=${SIBY_LANG:-F}
# (the test settings next to Siby.exe: the user folder kept there)
export SIBY_DOCUMENTS="Z:$W/Siby/bin"
# (a first start in a fresh folder sets the configuration up: then ours)
wineserver -k 2>/dev/null; sleep 1
(cd $W/Siby/bin && DISPLAY=:95 timeout 30 wine Siby.exe >/dev/null 2>&1)
wineserver -k 2>/dev/null; sleep 1
mkdir -p $W/Siby/bin/config
cat > $W/Siby/bin/config/options.dat <<FIN
set ::splash::keepopen 0
set ::capture_sortie {Z:$OUT}
set ::journalTest [open {Z:$OUT/scid.log} w]
fconfigure \$::journalTest -buffering line -encoding utf-8
rename puts ::putsOrig
proc puts {args} {
  if {[llength \$args] == 1} { ::putsOrig \$::journalTest [lindex \$args 0] ; return }
  if {[llength \$args] == 2 && [lindex \$args 0] in {stdout stderr}} { ::putsOrig \$::journalTest [lindex \$args 1] ; return }
  if {[llength \$args] == 2 && [lindex \$args 0] eq "-nonewline"} { ::putsOrig -nonewline \$::journalTest [lindex \$args 1] ; return }
  uplevel 1 [list ::putsOrig {*}\$args]
}
namespace eval ::moderne {}
set ::moderne::theme sombre

after 0 [list source {Z:$CAPT/pouls.tcl}]
proc ::lancerScenario {} { if {![llength [info commands ::updateBoard]] || ![winfo exists .main.board]} { after 1000 ::lancerScenario ; return } ; after 3000 [list source -encoding utf-8 {Z:$CAPT/scenario_$NOM.tcl}] }
after 2500 ::lancerScenario
FIN
cd $W/Siby/bin
DISPLAY=:95 timeout ${DUREE:-120} wine Siby.exe ${FICHIERS_W:-} "Z:$CAPT/partie.pgn" >/dev/null 2>&1
wineserver -k 2>/dev/null
grep -a -E "^OK |ECHEC|ERREUR|BLOCAGE|BILAN" $OUT/scid.log | head -20
