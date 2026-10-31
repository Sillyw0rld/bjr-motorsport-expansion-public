import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_gap_hud_shows_estimates_or_actionable_packet_and_match_reasons():
    js = (ROOT / "client/ui/modModules/raceprepBJR/raceprepBJR.js").read_text()

    def block(name, next_name):
        start = js.index(f"    vm.{name}=")
        end = js.index(f"    vm.{next_name}=", start)
        return js[start:end]

    script = r"""
const opponent={playerName:'Ben',displayName:'Ben'};
const vm={
  driving:{race:{state:'RACE',raceName:'S-bend',phaseIndex:2,gaps:{selfName:'Ana',raceName:'S-bend',phaseIndex:2,
    ahead:{playerName:'Ben',distanceM:8,estimated:true,liveReason:'Not crossed yet'}}}},
  hud:{raceName:'S-bend',phaseIndex:2,self:{playerName:'Ana'}},
  hudOpponent:side=>side==='ahead'?opponent:null,
  gapText:()=>'+1 lap'
};
""" + block("liveGaps", "hudOpponent") + block("localGap", "liveGapText") + block("liveGapText", "gapDistance") + block("gapDistance", "opponentPosition") + r"""
if(vm.liveGapText('ahead')!=='Live: Not crossed yet') throw new Error(vm.liveGapText('ahead'));
if(vm.gapDistance('ahead')!=='~8 m') throw new Error(vm.gapDistance('ahead'));
vm.driving.race.gaps.ahead.distanceReason='No vehicle found for player ID 2';
vm.driving.race.gaps.ahead.liveReason='History reset: car jumped between samples';
vm.driving.race.gaps.ahead.distanceM=undefined;vm.driving.race.gaps.ahead.liveMs=undefined;
if(vm.liveGapText('ahead')!=='Live: History reset: car jumped between samples') throw new Error(vm.liveGapText('ahead'));
if(vm.gapDistance('ahead')!=='Distance: No vehicle found for player ID 2') throw new Error(vm.gapDistance('ahead'));
vm.driving.race.gaps.reason='Layout branches; route distance unavailable';
if(vm.gapDistance('ahead')!=='Distance: Layout branches; route distance unavailable') throw new Error(vm.gapDistance('ahead'));
delete vm.driving.race.gaps.reason;
vm.driving.race.gaps.selfName='Other';
if(vm.gapDistance('ahead')!=='Distance: Driver name mismatch') throw new Error(vm.gapDistance('ahead'));
vm.driving.race.gaps.selfName='Ana';vm.driving.race.raceName='Other';
if(vm.gapDistance('ahead')!=='Distance: Race name mismatch') throw new Error(vm.gapDistance('ahead'));
vm.driving.race.raceName='S-bend';vm.driving.race.gaps.phaseIndex=1;
if(vm.gapDistance('ahead')!=='Distance: Race phase mismatch') throw new Error(vm.gapDistance('ahead'));
"""
    subprocess.run(["node", "-e", script], check=True, cwd=ROOT)

    html = (ROOT / "client/ui/modModules/raceprepBJR/overlays.html").read_text()
    assert "local time and distance estimates · BJR interval official" in html
    assert ".rp-gap-values b{max-width:50%;white-space:normal;overflow-wrap:anywhere" in html
