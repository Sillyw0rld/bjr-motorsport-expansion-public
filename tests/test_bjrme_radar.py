import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_radar_side_mapping_and_remote_vehicle_standin():
    source = (ROOT / "client/ui/modModules/raceprepBJR/raceprepBJR.js").read_text()
    match = re.search(r"const RacePrepRadarFrame=data=>\{.*?\n\};", source, re.S)
    assert match, "production radar frame function not found"
    script = match.group(0) + r"""
const player = {centerX:0,centerY:0,centerZ:0,sizeX:4,sizeY:2,sizeZ:1,rotX:0};
function frameAt(x,y,type='vehicle',proximityDistance=null) {
  return RacePrepRadarFrame({playerVehicleId:1,objects:{
    1:player,
    2:{centerX:x,centerY:y,centerZ:0,sizeX:4,sizeY:2,sizeZ:1,rotX:0,type,proximityDistance}
  }});
}
const left=frameAt(3,0);
const right=frameAt(-3,0);
const frontLeft=frameAt(3,-3);
const sector=frame=>frame.sectors.find(s=>s.level>0)?.label;
if(sector(left)!=='Left') throw new Error(`car on left mapped to ${sector(left)}`);
if(sector(right)!=='Right') throw new Error(`car on right mapped to ${sector(right)}`);
if(sector(frontLeft)!=='Front left') throw new Error(`front-left car mapped to ${sector(frontLeft)}`);
if(!(left.cars[0].x<0) || !(right.cars[0].x>0)) throw new Error('radar dots do not match side mapping');
const remote=frameAt(0,-3,'vehicle',0.5);
if(sector(remote)!=='Front' || remote.cars[0].level!==3) throw new Error('remote vehicle stand-in was not shown as near');
"""
    subprocess.run(["node", "-e", script], check=True, cwd=ROOT)
