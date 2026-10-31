# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Approved drivetrain conversion library (FWD, RWD, AWD) from owner donors.

Reads the three Elver drivetrain donor archives (fwd_donor_elver, rwd_donor_elver,
awd_donor_elver) without modifying them, verifies their SHA-256 hashes, and
generates namespaced drivetrain conversion JBeam parts per compatible recipient.
The recipient's engine, gearbox, gearing, final-drive ratio, tyres, suspension,
body and aero remain intact; no electric motor or hybrid propulsion is added.
"""
import hashlib
import json
from pathlib import Path
import re
import sys
import zipfile

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
from runtime_paths import TOOLS
import fleet  # noqa: E402
from engine_swaps.catalogue import uncomment, part, number, donor_archive  # noqa: E402

APPROVED = TOOLS / 'drivetrain_conversions/approved-donors.json'
VARIABLE_HEADER = ['name', 'type', 'unit', 'category', 'default', 'min', 'max', 'title', 'description']


def selected_source_parts(z, model, pc):
    """Resolve configured parts and nested slot defaults by identity, not filenames."""
    import generate_upgrade_engines
    source = generate_upgrade_engines.source_parts(z, model)
    selected = dict(pc['parts'])
    for _ in range(12):
        before = len(selected)
        for name in list(selected.values()):
            text = source.get(name, {}).get('source', '')
            for slot, default in re.findall(r'\[\s*"([^"\n]+)"\s*,\s*"([^"\n]*)"', text.split('"slots"', 1)[-1].split('"nodes"', 1)[0]):
                if slot not in selected and default in source:
                    selected[slot] = default
        if len(selected) == before:
            break
    def text(slot, whole=False):
        name = selected.get(slot)
        if name not in source:
            raise ValueError(f'{model}: missing configured part for {slot}')
        return z.read(source[name]['member']).decode('utf8') if whole else source[name]['source']
    return text


def verify_and_extract_donors(approved_path=APPROVED):
    selected = json.loads(Path(approved_path).read_text())
    if selected.get('version') != 1:
        raise ValueError('Unsupported drivetrain donor lineup version')
    donors = {}
    for choice in selected.get('donors', []):
        if choice.get('ownerSelected') is not True:
            raise ValueError(f'Drivetrain donor has not been approved: {choice.get("model")}')
        source = donor_archive(choice['archive'])
        if source is None:
            print(f"drivetrain conversions: donor {choice.get('model')} not installed ({Path(choice['archive']).name}); skipped", flush=True)
            continue
        with source.open('rb') as stream:
            if hashlib.file_digest(stream, 'sha256').hexdigest() != choice['archiveSha256']:
                raise ValueError(f'Drivetrain donor archive changed; revalidate {choice["model"]}')
        with zipfile.ZipFile(source) as z:
            if hashlib.sha256(z.read(choice['carMember'])).hexdigest() != choice['carSha256']:
                raise ValueError(f'Drivetrain donor .car changed; revalidate {choice["model"]}')
            for member, expected_sha in choice.get('membersSha256', {}).items():
                if hashlib.sha256(z.read(member)).hexdigest() != expected_sha:
                    raise ValueError(f'Drivetrain donor member changed ({member}); revalidate {choice["model"]}')
            model, cfg, layout = choice['model'], choice['config'], choice['layout']
            # Verify that the donor's stock engine is an ICE engine and does not
            # activate Camso_ElectricMotor_F or Camso_ElectricMotor_R slots.
            pc = json.loads(z.read(f'vehicles/{model}/{cfg}.pc'))
            text = selected_source_parts(z, model, pc)
            eng_txt = text('Camso_Engine')
            if 'Camso_ElectricMotor' in eng_txt or 'electricMotor' in eng_txt:
                raise ValueError(f'Donor {model} has active electric propulsion in stock engine')
            extracted = {
                'layout': layout,
                'model': model,
                'config': cfg,
                'archiveSha256': choice['archiveSha256'],
                'carSha256': choice['carSha256'],
            }
            if layout in ('FWD', 'AWD'):
                df_txt = text('Camso_differential_front')
                extracted['frontDiffFriction'] = number(df_txt, 'friction') or 5.0202671086967
                extracted['frontDiffLock'] = number(df_txt, 'lsdLockCoef') or 0.40
                extracted['frontDiffRevLock'] = number(df_txt, 'lsdRevLockCoef') or 0.40
                extracted['frontDiffPreload'] = number(df_txt, 'lsdPreload') or 10.0
            if layout in ('RWD', 'AWD'):
                dr_txt = text('Camso_differential_rear')
                extracted['rearDiffFriction'] = number(dr_txt, 'friction') or 6.4594858001108
                extracted['rearDiffLock'] = number(dr_txt, 'lsdLockCoef') or 0.40
                extracted['rearDiffRevLock'] = number(dr_txt, 'lsdRevLockCoef') or 0.40
                extracted['rearDiffPreload'] = number(dr_txt, 'lsdPreload') or 10.0
            if layout == 'AWD':
                tc_txt = text('Camso_TransferCase')
                extracted['centerDiffFriction'] = number(tc_txt, 'friction') or 6.4594858001108
                extracted['centerDiffLock'] = number(tc_txt, 'lsdLockCoef') or 0.40
                extracted['centerDiffRevLock'] = number(tc_txt, 'lsdRevLockCoef') or 0.40
                extracted['centerDiffPreload'] = number(tc_txt, 'lsdPreload') or 10.0
                extracted['centerTorqueSplit'] = 0.65
            # Sum non-engine structural/drivetrain node weights from the donor
            # (Camso_Trim + gearbox nodes + suspension/wheel nodes) so FWD < RWD < AWD
            # mass deltas come directly from the three Elver donor exports.
            dt_mass = 0.0
            for slot in ('Camso_Trim', 'Camso_suspension_F', 'Camso_suspension_R',
                         'Camso_wheels_front', 'Camso_wheels_rear'):
                txt = uncomment(text(slot, whole=True))
                cur_w = 0.0
                for m in re.finditer(r'"nodeWeight"\s*:\s*([-+\d.eE]+)|\["([^"\n]+)",\s*[-+\d.eE]+,\s*[-+\d.eE]+,\s*[-+\d.eE]+', txt):
                    if m.group(1) is not None:
                        cur_w = float(m.group(1))
                    elif m.group(2) != 'id':
                        dt_mass += cur_w
            es_txt = uncomment(text('Camso_engine_structure', whole=True))
            cur_w = 0.0
            for m in re.finditer(r'"nodeWeight"\s*:\s*([-+\d.eE]+)|\["([^"\n]+)",\s*[-+\d.eE]+,\s*[-+\d.eE]+,\s*[-+\d.eE]+', es_txt):
                if m.group(1) is not None:
                    cur_w = float(m.group(1))
                elif m.group(2) != 'id' and not re.match(r'^engine[0-7]$', m.group(2)):
                    dt_mass += cur_w
            extracted['drivetrainMassKG'] = round(dt_mass, 3)
            donors[layout] = extracted
    if set(donors) != {'FWD', 'RWD', 'AWD'}:
        raise ValueError('Approved drivetrain donors must provide FWD, RWD and AWD')
    if not (donors['FWD']['drivetrainMassKG'] < donors['RWD']['drivetrainMassKG'] < donors['AWD']['drivetrainMassKG']):
        raise ValueError('Donor drivetrain masses must satisfy FWD < RWD < AWD')
    return donors


def inspect_recipient(model, car_info):
    cfg = car_info['config']
    pc = car_info['pc']
    parts = pc.get('parts', {})
    vars_ = pc.get('vars', {})
    with zipfile.ZipFile(car_info['archive']) as z:
        names = z.namelist()
        info_path = f'vehicles/{model}/info_{cfg}.json'
        info_json = json.loads(z.read(info_path)) if info_path in names else {}
        stock_drive = info_json.get('Drivetrain')
        if isinstance(stock_drive, str):
            stock_drive = stock_drive.strip().upper()
            if stock_drive == '4WD':
                stock_drive = 'AWD'
        if stock_drive not in ('FWD', 'RWD', 'AWD'):
            stock_drive = None
        stock_engine = parts.get('Camso_Engine', '')
        stock_trans = parts.get('Camso_Transmission', '')
        stock_tc = parts.get('Camso_TransferCase', '')
        stock_df_f = parts.get('Camso_differential_front') or ''
        stock_df_r = parts.get('Camso_differential_rear') or ''
        stock_fd_f = parts.get('Camso_finaldrive_front') or ''
        stock_fd_r = parts.get('Camso_finaldrive_rear') or ''

        engine_device = None
        has_tc_slot = False
        gearbox_type = None
        has_front_diff_slot = False
        has_rear_diff_slot = False
        has_front_hub = False
        has_rear_hub = False
        has_native_front_diff = False
        has_native_rear_diff = False
        axle_beams = set()
        chassis_nodes = []
        stock_defaults = {}
        ratio = vars_.get('$finaldrive_f') or vars_.get('$finaldrive_r')
        if not ratio:
            for fd_p in (stock_fd_f, stock_fd_r):
                m = re.search(r'_([0-9]+\.[0-9]+)$', fd_p or '')
                if m:
                    ratio = float(m.group(1))
                    break

        pattern_var = r'\[\s*"(\$[^"\n]+)"\s*,\s*"range"\s*,\s*"[^"\n]*"\s*,\s*"[^"\n]*"\s*,\s*([-+\d.eE]+)'
        for fn in sorted(names):
            if not fn.startswith(f'vehicles/{model}/') or not fn.endswith('.jbeam'):
                continue
            txt = uncomment(z.read(fn).decode('utf8', 'replace'))
            if stock_engine and f'"{stock_engine}"' in txt and ('camsoEngine' in txt or 'combustionEngine' in txt or 'electricMotor' in txt):
                try:
                    ebody = part(txt, stock_engine)
                    em = re.search(r'\["(camsoEngine|combustionEngine|electricMotor)",\s*"mainEngine"', ebody)
                    if em:
                        engine_device = em.group(1)
                except ValueError:
                    pass
            if stock_trans and f'"{stock_trans}"' in txt:
                try:
                    tbody = part(txt, stock_trans)
                    if '"Camso_TransferCase"' in tbody:
                        has_tc_slot = True
                        if not stock_tc:
                            tm = re.search(r'\["Camso_TransferCase",\s*"([^"]+)"', tbody)
                            if tm:
                                stock_tc = tm.group(1)
                    gm = re.search(r'\["(manualGearbox|sequentialGearbox|dctGearbox|automaticGearbox|cvtGearbox)",\s*"gearbox"', tbody)
                    if gm:
                        gearbox_type = gm.group(1)
                except ValueError:
                    pass
            if fn.endswith(f'/{cfg}_main.jbeam') and f'"Camso_Trim_{cfg}"' in txt:
                try:
                    trim_body = part(txt, f'Camso_Trim_{cfg}')
                    nsec = trim_body.split('"nodes"', 1)[1].split('"beams"', 1)[0]
                    cur_w = None
                    for m in re.finditer(
                        r'"nodeWeight"\s*:\s*([-+\d.eE]+)|\["(a\d+)",\s*([-+\d.eE]+),\s*([-+\d.eE]+),\s*([-+\d.eE]+)\s*(?:,\s*(\{[^\}]*\}))?\s*\]',
                        nsec,
                    ):
                        if m.group(1) is not None:
                            cur_w = float(m.group(1))
                        elif m.group(2) and cur_w is not None:
                            opts_raw = (m.group(6) or '{}').strip()
                            try:
                                opts = json.loads(opts_raw) if opts_raw != '{}' else {}
                            except ValueError:
                                opts = {}
                            chassis_nodes.append({
                                'id': m.group(2),
                                'pos': [float(m.group(3)), float(m.group(4)), float(m.group(5))],
                                'mass': cur_w,
                                'opts': opts,
                            })
                except (ValueError, IndexError):
                    pass
            if '"Camso_differential_front"' in txt and '"slots"' in txt and ('suspension_F' in fn or '_main.jbeam' in fn):
                has_front_diff_slot = True
            if '"Camso_differential_rear"' in txt and '"slots"' in txt and ('suspension_R' in fn or '_main.jbeam' in fn):
                has_rear_diff_slot = True
            if '"Camso_hub_bearings_front"' in txt and '"wheelaxleFL"' in txt and '"halfshaftFL"' in txt:
                has_front_hub = True
            if '"Camso_hub_bearings_rear"' in txt and '"wheelaxleRL"' in txt and '"halfshaftRL"' in txt:
                has_rear_hub = True
            if '"slotType"' in txt and '"Camso_differential_front"' in txt and '"frontDiff"' in txt:
                has_native_front_diff = True
            if '"slotType"' in txt and '"Camso_differential_rear"' in txt and '"rearDiff"' in txt:
                has_native_rear_diff = True
            for bm in re.findall(r'"(axle_[FR][LR])"', txt):
                axle_beams.add(bm)
            if any(k in fn for k in ('transfercase', 'differential', 'finaldrive')):
                for k, v in re.findall(pattern_var, txt):
                    if k in ('$torquesplit', '$finaldrive_f', '$finaldrive_r',
                             '$lsdpreload_F', '$lsdlockcoef_F', '$lsdlockcoefrev_F',
                             '$lsdpreload_R', '$lsdlockcoef_R', '$lsdlockcoefrev_R',
                             '$lsdpreload_C', '$lsdlockcoef_C', '$lsdlockcoefrev_C'):
                        stock_defaults[k] = float(v)
                if not ratio and '"gearRatio"' in txt and ('finaldrive' in fn or 'differential' in fn):
                    rm = re.search(r'"(?:frontDiff|rearDiff)"\s*:\s*\{\s*"gearRatio"\s*:\s*([0-9]+\.[0-9]+)', txt)
                    if rm:
                        ratio = float(rm.group(1))

        for k in list(stock_defaults):
            if isinstance(vars_.get(k), (int, float)):
                stock_defaults[k] = float(vars_[k])

        if not stock_drive and stock_tc:
            u = stock_tc.upper()
            stock_drive = 'AWD' if ('AWD' in u or '4WD' in u) else 'FWD' if 'FWD' in u else 'RWD' if 'RWD' in u else None
        if stock_drive in ('FWD', 'AWD') and not stock_df_f:
            stock_df_f = f'Camso_differential_front_{cfg}'
        if stock_drive in ('RWD', 'AWD') and not stock_df_r:
            stock_df_r = f'Camso_differential_rear_{cfg}'

        return {
            'model': model,
            'config': cfg,
            'stockDrive': stock_drive,
            'stockEngine': stock_engine,
            'engineDevice': engine_device,
            'stockTransmission': stock_trans,
            'gearboxType': gearbox_type,
            'hasTransferCaseSlot': has_tc_slot,
            'stockTransferCase': stock_tc,
            'stockFrontDiff': stock_df_f,
            'stockRearDiff': stock_df_r,
            'stockFinalDrive': round(float(ratio), 4) if ratio else None,
            'hasFrontDiffSlot': has_front_diff_slot,
            'hasRearDiffSlot': has_rear_diff_slot,
            'hasFrontHubBearings': has_front_hub,
            'hasRearHubBearings': has_rear_hub,
            'hasNativeFrontDiff': has_native_front_diff,
            'hasNativeRearDiff': has_native_rear_diff,
            'axleBeams': sorted(axle_beams),
            'chassisNodes': chassis_nodes,
            'chassisMassKG': round(sum(n['mass'] for n in chassis_nodes), 3),
            'stockDefaults': stock_defaults,
        }


def incompatibility(rec, layout):
    if not rec['stockDrive']:
        return 'Stock drivetrain is unknown'
    if rec['stockDrive'] == layout:
        return 'Already the stock drivetrain layout'
    if rec['engineDevice'] == 'electricMotor' or not rec['stockTransmission']:
        return 'Electric or direct-drive architecture has no gearbox/transfer-case slot'
    if not rec['hasTransferCaseSlot'] or not rec['stockTransferCase']:
        return 'Transmission does not expose a Camso_TransferCase slot'
    if layout in ('FWD', 'AWD'):
        if not (rec['hasFrontDiffSlot'] and rec['hasFrontHubBearings']
                and 'axle_FL' in rec['axleBeams'] and 'axle_FR' in rec['axleBeams']):
            return 'Missing front differential suspension slot, hub bearings or front axle beams'
    if layout in ('RWD', 'AWD'):
        if not (rec['hasRearDiffSlot'] and rec['hasRearHubBearings']
                and 'axle_RL' in rec['axleBeams'] and 'axle_RR' in rec['axleBeams']):
            return 'Missing rear differential suspension slot, hub bearings or rear axle beams'
    if not rec['stockFinalDrive'] or rec['stockFinalDrive'] <= 0:
        return 'Stock final-drive ratio could not be determined'
    return None


def build_mass_nodes(chassis_nodes, delta_kg):
    """Adjust the recipient's own chassis structural nodes (a0..a53) by delta_kg.

    Preserves exact recipient node positions, options, and $nodeWeightScale
    compatibility without copying donor chassis nodes or touching engine0..7.
    """
    if not chassis_nodes or abs(delta_kg) < 1e-6:
        return None
    base_mass = sum(n['mass'] for n in chassis_nodes)
    if base_mass + delta_kg <= 20.0:
        raise ValueError(f'Insufficient chassis structural mass ({base_mass:.1f} kg) for delta {delta_kg:+.1f} kg')
    scale = (base_mass + delta_kg) / base_mass
    rows = [
        ['id', 'posX', 'posY', 'posZ'],
        {
            'nodeMove': {'x': 0, 'y': 0, 'z': 0},
            'nodeOffset': {'x': 0, 'y': 0, 'z': 0},
            'frictionCoef': 0.5,
            'nodeMaterial': '|NM_METAL',
            'collision': True,
            'group': 'CarBody',
            'selfCollision': True,
        },
    ]
    for n in chassis_nodes:
        w = round(n['mass'] * scale, 6)
        rows.append({'nodeWeight': w})
        rows.append([n['id'], n['pos'][0], n['pos'][1], n['pos'][2], n['opts']])
    rows.append({'group': ''})
    return rows


def build_recipient_jbeam(rec, donors, ident):
    """Build namespaced JBeam parts for a recipient's compatible conversions."""
    ratio = rec['stockFinalDrive']
    ratio_str = f'{ratio:.2f}'
    stock_dt_mass = donors[rec['stockDrive']]['drivetrainMassKG']
    parts = {}

    # 1. Front differential + halfshafts + final drive if recipient has none (stock RWD)
    if not rec['hasNativeFrontDiff']:
        d_fwd = donors['FWD']
        hs_slot = f'{ident}_halfshafts_front'
        fd_slot = f'{ident}_finaldrive_front'
        fd_stock = f'{ident}_finaldrive_front_stock'
        fd_race = f'{ident}_finaldrive_front_race'
        diff_slots = [
            ['type', 'default', 'description'],
            [hs_slot, hs_slot, 'Front Halfshafts', {'coreSlot': True}],
            [fd_slot, fd_stock, 'Front Final Drive', {'coreSlot': True}],
        ]
        parts[f'{ident}_differential_front_lsd'] = {
            'information': {'authors': 'Sillyw0rld', 'name': 'Helical Front Differential', 'value': 500},
            'slotType': 'Camso_differential_front',
            'slots': diff_slots,
            'powertrain': [
                ['type', 'name', 'inputName', 'inputIndex'],
                ['differential', 'frontDiff', 'frontDriveShaft', 1, {
                    'diffType': 'lsd',
                    'lsdLockCoef': d_fwd['frontDiffLock'],
                    'lsdRevLockCoef': d_fwd['frontDiffRevLock'],
                    'lsdPreload': d_fwd['frontDiffPreload'],
                    'uiName': 'Front Differential',
                    'defaultVirtualInertia': 0.25,
                    'friction': d_fwd['frontDiffFriction'],
                }],
            ],
        }
        parts[f'{ident}_differential_front_race'] = {
            'information': {'authors': 'Sillyw0rld', 'name': 'Race Front Differential', 'value': 1500},
            'slotType': 'Camso_differential_front',
            'slots': diff_slots,
            'variables': [
                VARIABLE_HEADER,
                ['$lsdpreload_F', 'range', 'N/m', 'Differentials', 50, 0, 500, 'Pre-load Torque',
                 'Initial locking torque between left and right wheels', {'subCategory': 'Front'}],
                ['$lsdlockcoef_F', 'range', '', 'Differentials', 0.15, 0, 0.5, 'Power Lock Rate',
                 'Additional locking torque proportional to engine torque', {'minDis': 0, 'maxDis': 100, 'subCategory': 'Front'}],
                ['$lsdlockcoefrev_F', 'range', '', 'Differentials', 0.075, 0, 0.5, 'Coast Lock Rate',
                 'Additional locking torque proportional to engine braking', {'minDis': 0, 'maxDis': 100, 'subCategory': 'Front'}],
            ],
            'powertrain': [
                ['type', 'name', 'inputName', 'inputIndex'],
                ['differential', 'frontDiff', 'frontDriveShaft', 1, {
                    'diffType': 'lsd',
                    'lsdPreload': '$lsdpreload_F',
                    'lsdLockCoef': '$lsdlockcoef_F',
                    'lsdRevLockCoef': '$lsdlockcoefrev_F',
                    'uiName': 'Front Differential',
                    'defaultVirtualInertia': 0.25,
                    'friction': 5,
                }],
            ],
        }
        parts[f'{ident}_differential_front_welded'] = {
            'information': {'authors': 'Sillyw0rld', 'name': 'Welded Front Differential', 'value': 800},
            'slotType': 'Camso_differential_front',
            'slots': diff_slots,
            'powertrain': [
                ['type', 'name', 'inputName', 'inputIndex'],
                ['differential', 'frontDiff', 'frontDriveShaft', 1, {
                    'diffType': 'locked',
                    'lockTorque': 10000,
                    'diffTorqueSplit': 0.5,
                    'uiName': 'Front Differential',
                    'defaultVirtualInertia': 0.25,
                    'friction': 10,
                }],
            ],
        }
        parts[hs_slot] = {
            'information': {'authors': 'Sillyw0rld', 'name': 'Front Halfshafts', 'value': 100},
            'slotType': hs_slot,
            'powertrain': [
                ['type', 'name', 'inputName', 'inputIndex'],
                ['shaft', 'halfshaftFL', 'frontDiff', 1, {'breakTriggerBeam': 'axle_FL', 'uiName': 'Front Left Halfshaft', 'friction': 1}],
                ['shaft', 'halfshaftFR', 'frontDiff', 2, {'breakTriggerBeam': 'axle_FR', 'uiName': 'Front Right Halfshaft', 'friction': 1}],
            ],
        }
        parts[fd_stock] = {
            'information': {'authors': 'Sillyw0rld', 'name': f'{ratio_str} Front Final Drive', 'value': 150},
            'slotType': fd_slot,
            'frontDiff': {'gearRatio': ratio},
        }
        parts[fd_race] = {
            'information': {'authors': 'Sillyw0rld', 'name': 'Race Front Final Drive', 'value': 500},
            'slotType': fd_slot,
            'variables': [
                VARIABLE_HEADER,
                ['$finaldrive_f', 'range', ':1', 'Gearing', ratio, 0.5, 16, 'Front Final Drive',
                 'Gear ratio', {'subCategory': 'Differentials', 'stepDis': 0.01}],
            ],
            'frontDiff': {'gearRatio': '$finaldrive_f'},
        }

    # 2. Rear differential + halfshafts + final drive if recipient has none (stock FWD)
    if not rec['hasNativeRearDiff']:
        d_rwd = donors['RWD']
        hs_slot = f'{ident}_halfshafts_rear'
        fd_slot = f'{ident}_finaldrive_rear'
        fd_stock = f'{ident}_finaldrive_rear_stock'
        fd_race = f'{ident}_finaldrive_rear_race'
        diff_slots = [
            ['type', 'default', 'description'],
            [hs_slot, hs_slot, 'Rear Halfshafts', {'coreSlot': True}],
            [fd_slot, fd_stock, 'Rear Final Drive', {'coreSlot': True}],
        ]
        parts[f'{ident}_differential_rear_lsd'] = {
            'information': {'authors': 'Sillyw0rld', 'name': 'Helical Rear Differential', 'value': 500},
            'slotType': 'Camso_differential_rear',
            'slots': diff_slots,
            'powertrain': [
                ['type', 'name', 'inputName', 'inputIndex'],
                ['differential', 'rearDiff', 'rearDriveShaft', 1, {
                    'diffType': 'lsd',
                    'lsdLockCoef': d_rwd['rearDiffLock'],
                    'lsdRevLockCoef': d_rwd['rearDiffRevLock'],
                    'lsdPreload': d_rwd['rearDiffPreload'],
                    'uiName': 'Rear Differential',
                    'defaultVirtualInertia': 0.25,
                    'friction': d_rwd['rearDiffFriction'],
                }],
            ],
        }
        parts[f'{ident}_differential_rear_race'] = {
            'information': {'authors': 'Sillyw0rld', 'name': 'Race Rear Differential', 'value': 1500},
            'slotType': 'Camso_differential_rear',
            'slots': diff_slots,
            'variables': [
                VARIABLE_HEADER,
                ['$lsdpreload_R', 'range', 'N/m', 'Differentials', 100, 0, 500, 'Pre-load Torque',
                 'Initial locking torque between left and right wheels', {'subCategory': 'Rear'}],
                ['$lsdlockcoef_R', 'range', '', 'Differentials', 0.15, 0, 0.5, 'Power Lock Rate',
                 'Additional locking torque proportional to engine torque', {'minDis': 0, 'maxDis': 100, 'subCategory': 'Rear'}],
                ['$lsdlockcoefrev_R', 'range', '', 'Differentials', 0.075, 0, 0.5, 'Coast Lock Rate',
                 'Additional locking torque proportional to engine braking', {'minDis': 0, 'maxDis': 100, 'subCategory': 'Rear'}],
            ],
            'powertrain': [
                ['type', 'name', 'inputName', 'inputIndex'],
                ['differential', 'rearDiff', 'rearDriveShaft', 1, {
                    'diffType': 'lsd',
                    'lsdPreload': '$lsdpreload_R',
                    'lsdLockCoef': '$lsdlockcoef_R',
                    'lsdRevLockCoef': '$lsdlockcoefrev_R',
                    'uiName': 'Rear Differential',
                    'defaultVirtualInertia': 0.25,
                    'friction': 5,
                }],
            ],
        }
        parts[f'{ident}_differential_rear_welded'] = {
            'information': {'authors': 'Sillyw0rld', 'name': 'Welded Rear Differential', 'value': 800},
            'slotType': 'Camso_differential_rear',
            'slots': diff_slots,
            'powertrain': [
                ['type', 'name', 'inputName', 'inputIndex'],
                ['differential', 'rearDiff', 'rearDriveShaft', 1, {
                    'diffType': 'locked',
                    'lockTorque': 10000,
                    'diffTorqueSplit': 0.5,
                    'uiName': 'Rear Differential',
                    'defaultVirtualInertia': 0.25,
                    'friction': 10,
                }],
            ],
        }
        parts[hs_slot] = {
            'information': {'authors': 'Sillyw0rld', 'name': 'Rear Halfshafts', 'value': 100},
            'slotType': hs_slot,
            'powertrain': [
                ['type', 'name', 'inputName', 'inputIndex'],
                ['shaft', 'halfshaftRL', 'rearDiff', 1, {'breakTriggerBeam': 'axle_RL', 'uiName': 'Rear Left Halfshaft', 'friction': 1}],
                ['shaft', 'halfshaftRR', 'rearDiff', 2, {'breakTriggerBeam': 'axle_RR', 'uiName': 'Rear Right Halfshaft', 'friction': 1}],
            ],
        }
        parts[fd_stock] = {
            'information': {'authors': 'Sillyw0rld', 'name': f'{ratio_str} Rear Final Drive', 'value': 150},
            'slotType': fd_slot,
            'rearDiff': {'gearRatio': ratio},
        }
        parts[fd_race] = {
            'information': {'authors': 'Sillyw0rld', 'name': 'Race Rear Final Drive', 'value': 500},
            'slotType': fd_slot,
            'variables': [
                VARIABLE_HEADER,
                ['$finaldrive_r', 'range', ':1', 'Gearing', ratio, 0.5, 16, 'Rear Final Drive',
                 'Gear ratio', {'subCategory': 'Differentials', 'stepDis': 0.01}],
            ],
            'rearDiff': {'gearRatio': '$finaldrive_r'},
        }

    # 3. Transfer-case conversions (for the 2 non-stock layouts)
    if rec['stockDrive'] != 'FWD':
        delta_fwd = round(donors['FWD']['drivetrainMassKG'] - stock_dt_mass, 3)
        tc_fwd = {
            'information': {'authors': 'Sillyw0rld', 'name': 'FWD Conversion (Front-Wheel Drive)', 'value': 500},
            'slotType': 'Camso_TransferCase',
            'scalenodeWeight': '$=$nodeWeightScale or 1',
            'powertrain': [
                ['type', 'name', 'inputName', 'inputIndex'],
                ['shaft', 'frontDriveShaft', 'gearbox', 1, {'friction': 0}],
            ],
        }
        nodes_fwd = build_mass_nodes(rec.get('chassisNodes'), delta_fwd)
        if nodes_fwd:
            tc_fwd['nodes'] = nodes_fwd
        parts[f'{ident}_transfercase_fwd'] = tc_fwd

    need_rear_driveshaft = False
    if rec['stockDrive'] != 'RWD':
        need_rear_driveshaft = True
        delta_rwd = round(donors['RWD']['drivetrainMassKG'] - stock_dt_mass, 3)
        ds_r = f'{ident}_driveshaft_rear'
        tc_rwd = {
            'information': {'authors': 'Sillyw0rld', 'name': 'RWD Conversion (Rear-Wheel Drive)', 'value': 500},
            'slotType': 'Camso_TransferCase',
            'scalenodeWeight': '$=$nodeWeightScale or 1',
            'slots': [
                ['type', 'default', 'description'],
                [ds_r, ds_r, 'Rear Driveshaft', {'coreSlot': True}],
            ],
            'powertrain': [
                ['type', 'name', 'inputName', 'inputIndex'],
                ['shaft', 'transferCase', 'gearbox', 1, {'friction': 0}],
            ],
        }
        nodes_rwd = build_mass_nodes(rec.get('chassisNodes'), delta_rwd)
        if nodes_rwd:
            tc_rwd['nodes'] = nodes_rwd
        parts[f'{ident}_transfercase_rwd'] = tc_rwd

    if rec['stockDrive'] != 'AWD':
        need_rear_driveshaft = True
        d_awd = donors['AWD']
        delta_awd = round(d_awd['drivetrainMassKG'] - stock_dt_mass, 3)
        split = d_awd['centerTorqueSplit']
        cd_slot = f'{ident}_differential_center'
        cd_lsd = f'{ident}_differential_center_lsd'
        cd_race = f'{ident}_differential_center_race'
        cd_welded = f'{ident}_differential_center_welded'
        ds_f = f'{ident}_driveshaft_front'
        ds_r = f'{ident}_driveshaft_rear'
        cd_slots = [
            ['type', 'default', 'description'],
            [ds_f, ds_f, 'Front Driveshaft', {'coreSlot': True}],
            [ds_r, ds_r, 'Rear Driveshaft', {'coreSlot': True}],
        ]
        tc_awd = {
            'information': {'authors': 'Sillyw0rld', 'name': 'AWD Conversion (All-Wheel Drive)', 'value': 1000},
            'slotType': 'Camso_TransferCase',
            'scalenodeWeight': '$=$nodeWeightScale or 1',
            'slots': [
                ['type', 'default', 'description'],
                [cd_slot, cd_lsd, 'Center Differential', {'coreSlot': True}],
            ],
        }
        nodes_awd = build_mass_nodes(rec.get('chassisNodes'), delta_awd)
        if nodes_awd:
            tc_awd['nodes'] = nodes_awd
        parts[f'{ident}_transfercase_awd'] = tc_awd
        parts[cd_lsd] = {
            'information': {'authors': 'Sillyw0rld', 'name': 'Helical Center Differential', 'value': 300},
            'slotType': cd_slot,
            'slots': cd_slots,
            'variables': [
                VARIABLE_HEADER,
                ['$torquesplit', 'range', '', 'Gearing', split, 0, 1, 'Torque Split',
                 'Power to Rear', {'subCategory': 'Transfer Case', 'stepDis': 0.01, 'minDis': 0, 'maxDis': 100}],
            ],
            'powertrain': [
                ['type', 'name', 'inputName', 'inputIndex'],
                ['differential', 'transferCase', 'gearbox', 1, {
                    'diffType': 'lsd',
                    'lsdLockCoef': d_awd['centerDiffLock'],
                    'lsdRevLockCoef': d_awd['centerDiffRevLock'],
                    'lsdPreload': d_awd['centerDiffPreload'],
                    'diffTorqueSplit': f'$=$torquesplit or {split}',
                    'uiName': 'Center Differential',
                    'defaultVirtualInertia': 0.25,
                    'friction': d_awd['centerDiffFriction'],
                }],
            ],
            'transferCase': {'diffTorqueSplit': f'$=$torquesplit or {split}'},
        }
        parts[cd_race] = {
            'information': {'authors': 'Sillyw0rld', 'name': 'Race Center Differential', 'value': 800},
            'slotType': cd_slot,
            'slots': cd_slots,
            'variables': [
                VARIABLE_HEADER,
                ['$torquesplit', 'range', '', 'Gearing', split, 0, 1, 'Torque Split',
                 'Power to Rear', {'subCategory': 'Transfer Case', 'stepDis': 0.01, 'minDis': 0, 'maxDis': 100}],
                ['$lsdpreload_C', 'range', 'N/m', 'Differentials', 25, 0, 200, 'Pre-load Torque',
                 'Initial cross torque between front and rear wheels', {'subCategory': 'Center'}],
                ['$lsdlockcoef_C', 'range', '', 'Differentials', 0.125, 0, 0.5, 'Power Lock Rate',
                 'Additional locking torque proportional to engine torque', {'minDis': 0, 'maxDis': 100, 'subCategory': 'Center'}],
                ['$lsdlockcoefrev_C', 'range', '', 'Differentials', 0.025, 0, 0.5, 'Coast Lock Rate',
                 'Additional locking torque proportional to engine braking', {'minDis': 0, 'maxDis': 100, 'subCategory': 'Center'}],
            ],
            'powertrain': [
                ['type', 'name', 'inputName', 'inputIndex'],
                ['differential', 'transferCase', 'gearbox', 1, {
                    'diffType': 'lsd',
                    'lsdPreload': '$lsdpreload_C',
                    'lsdLockCoef': '$lsdlockcoef_C',
                    'lsdRevLockCoef': '$lsdlockcoefrev_C',
                    'diffTorqueSplit': f'$=$torquesplit or {split}',
                    'uiName': 'Center Differential',
                    'defaultVirtualInertia': 0.25,
                    'friction': 5,
                }],
            ],
        }
        parts[cd_welded] = {
            'information': {'authors': 'Sillyw0rld', 'name': 'Welded Center Differential', 'value': 350},
            'slotType': cd_slot,
            'slots': cd_slots,
            'variables': [
                VARIABLE_HEADER,
                ['$torquesplit', 'range', '', 'Gearing', split, 0, 1, 'Torque Split',
                 'Power to Rear', {'subCategory': 'Transfer Case', 'stepDis': 0.01, 'minDis': 0, 'maxDis': 100}],
            ],
            'powertrain': [
                ['type', 'name', 'inputName', 'inputIndex'],
                ['differential', 'transferCase', 'gearbox', 1, {
                    'diffType': 'locked',
                    'lockTorque': 10000,
                    'diffTorqueSplit': f'$=$torquesplit or {split}',
                    'uiName': 'Center Differential',
                    'defaultVirtualInertia': 0.25,
                    'friction': 10,
                }],
            ],
        }
        parts[ds_f] = {
            'information': {'authors': 'Sillyw0rld', 'name': 'Front Driveshaft', 'value': 150},
            'slotType': ds_f,
            'powertrain': [
                ['type', 'name', 'inputName', 'inputIndex'],
                ['shaft', 'frontDriveShaft', 'transferCase', 2, {'friction': 1}],
            ],
        }

    if need_rear_driveshaft:
        ds_r = f'{ident}_driveshaft_rear'
        parts[ds_r] = {
            'information': {'authors': 'Sillyw0rld', 'name': 'Rear Driveshaft', 'value': 150},
            'slotType': ds_r,
            'powertrain': [
                ['type', 'name', 'inputName', 'inputIndex'],
                ['shaft', 'rearDriveShaft', 'transferCase', 1, {'friction': 1}],
            ],
        }

    return parts


def generate(resources=fleet.RESOURCES, output=None, approved=APPROVED, strict=False, namespace="", offered_layout=None):
    output = Path(output or (TOOLS.parent / 'client'))
    resources = Path(resources)
    try:
        donors = verify_and_extract_donors(approved)
    except (ValueError, OSError) as e:
        if strict:
            raise
        # donor cars are separate mods; without them the conversions are simply not offered
        print(f'drivetrain conversions skipped: {e}', flush=True)
        return {'parts': 0, 'models': 0}
    cars = fleet.discover(resources)
    catalog = {
        'version': 1,
        'donors': [
            {k: donors[layout][k] for k in ('layout', 'model', 'config', 'drivetrainMassKG', 'archiveSha256', 'carSha256')}
            for layout in ('FWD', 'RWD', 'AWD')
        ],
        'models': {},
    }
    generated_count = 0
    for model in sorted(cars):
        rec = inspect_recipient(model, cars[model])
        ident = 'rp_dt_' + hashlib.sha256((model + namespace).encode()).hexdigest()[:12]
        default_front_diff = rec['stockFrontDiff'] if rec['hasNativeFrontDiff'] and rec['stockFrontDiff'] else f'{ident}_differential_front_lsd'
        default_rear_diff = rec['stockRearDiff'] if rec['hasNativeRearDiff'] and rec['stockRearDiff'] else f'{ident}_differential_rear_lsd'
        model_entry = {
            'ident': ident,
            'stockDrive': rec['stockDrive'],
            'stockTransferCase': rec['stockTransferCase'],
            'stockFrontDiff': rec['stockFrontDiff'],
            'stockRearDiff': rec['stockRearDiff'],
            'defaultFrontDiff': default_front_diff,
            'defaultRearDiff': default_rear_diff,
            'stockFinalDrive': rec['stockFinalDrive'],
            'gearboxType': rec['gearboxType'],
            'stockDefaults': rec['stockDefaults'],
            'options': [],
        }
        catalog['models'][model] = model_entry
        has_compatible = False
        for layout in ('FWD', 'RWD', 'AWD'):
            if offered_layout and layout != offered_layout:
                continue
            reason = incompatibility(rec, layout)
            donor = donors[layout]
            opt = {
                'layout': layout,
                'donor': donor['model'],
                'reason': reason,
            }
            if not reason:
                has_compatible = True
                tc_part = f'{ident}_transfercase_{layout.lower()}'
                ratio = rec['stockFinalDrive']
                mass_delta = round(donor['drivetrainMassKG'] - donors[rec['stockDrive']]['drivetrainMassKG'], 3)
                if layout == 'FWD':
                    title = f'FWD: Front-wheel drive ({mass_delta:+.1f} kg, helical LSD, {ratio:.2f}:1 final drive)'
                    reset_vars = {'$finaldrive_f': ratio, '$lsdpreload_F': 50.0, '$lsdlockcoef_F': 0.15, '$lsdlockcoefrev_F': 0.075}
                elif layout == 'RWD':
                    title = f'RWD: Rear-wheel drive ({mass_delta:+.1f} kg, helical LSD, {ratio:.2f}:1 final drive)'
                    reset_vars = {'$finaldrive_r': ratio, '$lsdpreload_R': 100.0, '$lsdlockcoef_R': 0.15, '$lsdlockcoefrev_R': 0.075}
                else:
                    title = f'AWD: All-wheel drive ({mass_delta:+.1f} kg, 35/65 split, helical LSDs, {ratio:.2f}:1 final drive)'
                    reset_vars = {
                        '$torquesplit': 0.65,
                        '$finaldrive_f': ratio,
                        '$finaldrive_r': ratio,
                        '$lsdpreload_C': 25.0, '$lsdlockcoef_C': 0.125, '$lsdlockcoefrev_C': 0.025,
                        '$lsdpreload_F': 50.0, '$lsdlockcoef_F': 0.15, '$lsdlockcoefrev_F': 0.075,
                        '$lsdpreload_R': 100.0, '$lsdlockcoef_R': 0.15, '$lsdlockcoefrev_R': 0.075,
                    }
                opt.update({
                    'part': tc_part,
                    'title': title,
                    'frontDiff': default_front_diff if layout in ('FWD', 'AWD') else '',
                    'rearDiff': default_rear_diff if layout in ('RWD', 'AWD') else '',
                    'centerDiffSlot': f'{ident}_differential_center' if layout == 'AWD' else None,
                    'defaultCenterDiff': f'{ident}_differential_center_lsd' if layout == 'AWD' else None,
                    'finalDriveRatio': ratio,
                    'massDeltaKG': mass_delta,
                    'resetVars': reset_vars,
                })
                generated_count += 1
            model_entry['options'].append(opt)
        if has_compatible:
            jbeam_parts = build_recipient_jbeam(rec, donors, ident)
            folder = output / 'vehicles' / model / 'raceprep'
            folder.mkdir(parents=True, exist_ok=True)
            (folder / f'{ident}_drivetrain.jbeam').write_text(json.dumps(jbeam_parts, indent=2) + '\n')

    destination = output / 'vehicles/rp_drivetrain_conversions/raceprep/rp_drivetrain_library.json'
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(catalog, indent=2) + '\n')
    return {'parts': generated_count, 'models': len(catalog['models'])}


if __name__ == '__main__':
    print(json.dumps(generate(), indent=2))
