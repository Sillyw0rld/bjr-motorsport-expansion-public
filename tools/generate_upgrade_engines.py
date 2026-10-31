#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Fleet-specific engine additions; original part names/slots remain unchanged.

Reuses native Race Intake, engine management, internals and balancing parts.
Only missing choices and extra categories receive generated parts. Source
archives are read only; permissive JBeam is inspected without rewriting it.
"""
import hashlib
import os
import json
import re
import zipfile
from pathlib import Path
from audit_upgrade_sources import uncomment, field
from engine_metadata import automation as engine_metadata

from runtime_paths import ROOT
RESOURCES = Path(os.environ.get('RACEPREP_RESOURCES', 'Resources/Client'))
STATICS = Path(os.environ.get('RACEPREP_STATICS', 'calibration-statics'))  # optional measured car data
VARIABLE_HEADER = ['name', 'type', 'unit', 'category', 'default', 'min', 'max', 'title', 'description']


# radiator stages: core area multiplier, added kg (owner 2026-10-18)
RADIATORS={'sport':(1.5,3,2.0),'race':(2.0,5,2.5)}  # core area x, kg, fan airflow x (rig grid test 2026-10-18)

def ensure_race_intake(root, slot, native, generated):
    """Some exports supply only Stock Intake. Fill that gap in our add-on,
    using the existing engineEffects Race intake, never replacing a donor part.
    Kept separate so existing generated catalogues can be backfilled safely.
    """
    if any(p.get('effect', {}).get('intake') == 'race' for p in native.values()):
        return None
    name = root + '_intake_race'
    generated[name] = {'information': {'authors': 'Sillyw0rld', 'name': 'Race intake'},
                       'slotType': slot, 'raceprepEngine': {'intake': 'race'}}
    native[name] = {'slot': slot, 'title': 'Race intake',
                    'effect': {'intake': 'race'}, 'generated': True}
    return name


def source_parts(archive, model):
    result = {}
    for member in archive.namelist():
        if not member.startswith('vehicles/'+model+'/') or not member.endswith('.jbeam'):
            continue
        source = uncomment(archive.read(member).decode('utf8', errors='replace'))
        matches = list(re.finditer(r'"([^"\n]+)"\s*:\s*\{\s*"information"\s*:', source))
        for index, match in enumerate(matches):
            text = source[match.start():matches[index+1].start() if index+1<len(matches) else len(source)]
            slot = re.search(r'"slotType"\s*:\s*"([^"]+)"', text)
            title = re.search(r'"name"\s*:\s*"([^"]+)"', text)
            if slot and title:
                result[match[1]] = {'slot': slot[1], 'title': title[1], 'source': text, 'member': member}
    return result


def induction_title(level):
    """turbo_small_twin_scroll_race -> "Small turbo, twin-scroll (Race)" """
    if level.startswith('twin_charged_'):
        return 'Twin-charged (Race: adjustable boost, anti-lag)'
    if level.startswith('turbo_sequential_'):
        return 'Sequential twin turbo (Race: adjustable boost, anti-lag)'
    if level=='race_upgrade':
        return 'Race boost upgrade (existing turbo / supercharger)'
    for kind, label in (('turbo_small','Small turbo'),('turbo_large','Large turbo'),
                        ('twin_charged','Twin-charged'),('turbo_sequential','Sequential twin turbo'),
                        ('supercharger_sport','Sport supercharger'),('supercharger_race','Race supercharger')):
        if level.startswith(kind+'_'):
            rest=level[len(kind)+1:]
            tier='race' if rest.endswith('_race') else 'sport'
            variant=rest[:-len('_'+tier)].replace('_','-')
            variant={'roots':'Roots'}.get(variant,variant)
            title=f'{label}, {variant}'
            if kind.startswith('turbo'):
                title+=' (Race: adjustable boost, anti-lag)' if tier=='race' else ''
            elif tier=='race' and not kind.endswith('_race'):
                title+=' (Race)'
            return title
    return level.replace('_',' ').title()


def generate(resources=RESOURCES, output=None, statics=STATICS):
    from fleet import discover, static as car_static
    output = output or ROOT/'client'
    cars = discover(resources)
    models = {m: c['config'] for m, c in cars.items()}
    fleet = {}
    for model, car in cars.items():
        with zipfile.ZipFile(car['archive']) as archive:
            fleet[model] = (car['pc'], source_parts(archive, model), car['archive'])
    catalog = {'models': {}}
    existing = Path(output)/'lua/common/raceprep/engine-parts.json'
    shipped = ROOT/'client/lua/common/raceprep/engine-parts.json'
    for previous in (existing, shipped):
        if previous.exists():
            catalog['nativeEngines'] = json.loads(previous.read_text()).get('nativeEngines', {})
            if catalog['nativeEngines']: break
    for model, (pc, original, archive) in fleet.items():
        stock_engine = pc['parts']['Camso_Engine']
        static = car_static(model, cars[model], statics)
        engine = next((e for e in static['engines'] if e.get('type')=='camsoEngine'), None)
        if not engine or not engine.get('maxRPM') or stock_engine not in original:
            print('engine parts: unsupported engine data for', model, '- skipped')
            continue
        source = original[stock_engine]['source']
        uid = stock_engine.removeprefix('Camso_Engine_')
        ident = hashlib.sha256(model.encode()).hexdigest()[:12]
        root = f'rp_engine_{ident}'
        native = {}
        for name, p in original.items():
            s = name.lower()
            effect = None
            if s.startswith('camso_intake_race_'): effect={'intake':'race'}
            elif s.startswith('camso_enginemanagement_race_'): effect={'ecu':'race'}
            elif s.startswith('camso_engineinternals_stage'): effect={'forged':True}
            elif name=='Camso_BalancingMass_Lightened': effect={'flywheel':'sport'}
            elif name=='Camso_BalancingMass_Race': effect={'flywheel':'race'}
            if effect: native[name]={'slot':p['slot'],'title':p['title'],'effect':effect,'member':p['member']}
        slots={'intake':f'Camso_Intake_{uid}','ecu':f'Camso_EngineManagement_{uid}',
               'forged':f'Camso_EngineInternals_{uid}','flywheel':'Camso_BalancingMass'}
        engine_node=None
        for p in original.values():
            node=re.search(r'\["engine0",\s*([-\d.eE]+),\s*([-\d.eE]+),\s*([-\d.eE]+)',p['source'])
            if node: engine_node=tuple(map(float,node.groups()));break
        assert engine_node, 'No supported engine-block attachment: '+model
        generated={}
        def add(kind, level, effect, slot=None, variables=None, extra=None):
            name=f'{root}_{kind}_{level}'
            title=(level.title()+' '+kind.replace('_',' ')).replace('Ecu','ECU')
            if kind=='induction':
                title=induction_title(level)
            elif kind in ('intercooler','oilcooler'):
                title={'intercooler':'Race intercooler','oilcooler':'Race oil cooler'}[kind]
            elif kind=='radiator':
                title={'sport':'High performance radiator','race':'Race radiator'}[level]
            elif kind=='cam':
                title=level.title()+' camshaft'
            elif kind=='displacement':
                title=level.title()+' displacement (stroker kit)'
            elif kind=='exhaust':
                title=level.title()+' exhaust'
            elif kind in ('intake','ecu'):
                title=level.title()+(' intake' if kind=='intake' else ' ECU tune')
            p={'information':{'authors':'Sillyw0rld','name':title},'slotType':slot or f'{root}_{kind}',
               'raceprepEngine':dict(effect)}
            if effect.get('induction')=='twin_charged':
                p['information']['description']='Supercharger response at low rpm; turbo takes over from 50–65% of the rev limit. Forged internals and upgraded cooling required.'
            elif effect.get('induction')=='turbo_sequential':
                p['information']['description']='Small turbo boosts by 30% of the rev limit; large turbo takes over at 45–60%. Forged internals and upgraded cooling required.'
            if variables: p['variables']=[VARIABLE_HEADER]+variables
            if variables:
                for variable in variables:
                    key={'$rpCamGain':'camGain','$rpBoostGain':'boostGain','$rpAntiLag':'antiLag'}.get(variable[0])
                    if key: p['raceprepEngine'][key]='$='+variable[0]+('' if key=='antiLag' else '/100')
            if extra: p.update(extra)
            kg=5 if effect.get('displacement')=='sport' else 10 if effect.get('displacement')=='race' else 0
            if effect.get('induction') and effect['induction']!='stock_upgrade':
                kg={'twin_charged':35,'turbo_sequential':30,'turbo_large':25,'supercharger_race':25}.get(effect['induction'],15)
            if effect.get('intercooler') or effect.get('oilcooler'): kg=5
            if effect.get('radiator'): kg=RADIATORS[effect['radiator']][1]
            if kg:
                node_id=f'{root}_{kind}_mass'
                position=[f'$={value+.015}+($EngineOffset{axis} or 0)' for value,axis in zip(engine_node,'XYZ')]
                p['nodes']=[['id','posX','posY','posZ'],
                            [node_id,*position,{'nodeWeight':kg,'collision':False,'selfCollision':False,'group':'rp_engine_upgrade_mass'}]]
                p['beams']=[['id1:','id2:'],{'beamSpring':1000000,'beamDamp':100,'beamDeform':1000000000,'beamStrength':1000000000},
                            [node_id,'engine0'],[node_id,'engine1'],[node_id,'engine4']]
            # Sound and afterfire through the export's own engine data (the
            # same modifiers Automation's Race Intake uses): louder exhaust,
            # more pops; anti-lag adds afterfire when switched on.
            sound = {'exhaust': {'sport': (1.4, 1.5), 'race': (1.9, 3.0)}, 'intake': {'sport': (1.0, 0.5)}}
            level_fx = sound.get(kind, {}).get(level)
            if level_fx:
                afterfire, gain = level_fx
                if afterfire != 1.0:
                    p['mainEngine'] = {'$*instantAfterFireCoef': afterfire, '$*sustainedAfterFireCoef': afterfire}
                p['soundConfigExhaust'] = {'$+mainGain': gain}
            if effect.get('inductionRace') and (str(effect.get('induction', '')).startswith('turbo') or effect.get('induction')=='twin_charged'):
                p['mainEngine'] = {'$*instantAfterFireCoef': '$=1+($rpAntiLag or 0)*1.5',
                                   '$*sustainedAfterFireCoef': '$=1+($rpAntiLag or 0)*2'}
            if effect.get('oilcooler'):
                # camsoEngineThermals reads these fields; every export already
                # has an oil radiator (effectiveness 2000, area 7-26): improve
                # it proportionally so it can never end up worse than stock.
                p['mainEngine']={'$*oilRadiatorArea':1.5,'$*oilRadiatorEffectiveness':1.25}
            if effect.get('radiator'):
                # Larger core: BeamNG cools by radiatorArea x radiatorEffectiveness
                # (combustionEngineThermals); merged into the export's engine
                # through the hub, as the oil cooler. Owner 2026-10-18: size.
                # At standstill (grid) only the fan moves air, so each stage also
                # has a stronger fan (rig 2026-10-18: NA->turbo car hit 130 C on
                # the grid in 30 s with a 1.7x core alone).
                area, _, fan = RADIATORS[effect['radiator']]
                p['mainEngine']={'$*radiatorArea':area,'$*radiatorFanMaxAirSpeed':fan}
            generated[name]=p
            native[name]={'slot':p['slotType'],'title':title,'effect':effect,'generated':True}
            return name
        add('intake','sport',{'intake':'sport'},slots['intake'])
        ensure_race_intake(root, slots['intake'], native, generated)
        add('ecu','sport',{'ecu':'sport'},slots['ecu'])
        # Race choices already exist in the export; no duplicate replacement.
        children=[]
        for kind in ['exhaust','cam','displacement']:
            slots[kind]=f'{root}_{kind}'
            children.append([slots[kind],'',{'cam':'Camshaft'}.get(kind,kind.title())])
            for level in ['sport','race']:
                variables=None
                if kind=='cam' and level=='race':
                    variables=[['$rpCamGain','range','%','Engine',100,0,100,'Race cam timing effect','Rated at 100% of the Race cam effect.',{'stepDis':1}]]
                add(kind,level,{kind:level},variables=variables)
        induction_defaults=re.findall(r'\["(Camso_(?:Turbo|Supercharger)_[^"]+)",\s*"([^"]*)"',source)
        # Turbo module files exist on NA exports too. The installed/default
        # part, rather than module-file presence, determines forced induction.
        stock_forced=any(pc['parts'].get(slot,default) for slot,default in induction_defaults)
        if not stock_forced:
            slots['induction']=f'{root}_induction'
            children.append([slots['induction'],'','Forced induction'])
            for kind, variants in [('turbo_small',['single','twin','twin_scroll']),
                                   ('turbo_large',['single','twin','twin_scroll']),
                                   ('twin_charged',['compound']),('turbo_sequential',['sequential']),
                                   ('supercharger_sport',['roots','twin_screw','centrifugal']),
                                   ('supercharger_race',['roots','twin_screw','centrifugal'])]:
                # Supercharger size already specifies its Sport/Race tier.
                tiers=['race'] if kind in ('twin_charged','turbo_sequential') or kind.endswith('_race') else ['sport'] if kind.endswith('_sport') else ['sport','race']
                for variant in variants:
                    for tier in tiers:
                        effect={'induction':kind,'inductionRace':tier=='race',
                                'turboLayout' if kind.startswith('turbo') else 'superchargerType':variant}
                        variables=[['$rpBoostGain','range','%','Engine',100,0,100,'Boost effect','Only the Race version unlocks boost; PI uses maximum.',{'stepDis':1}]]
                        if (kind.startswith('turbo') or kind=='twin_charged') and tier=='race':
                            variables.append(['$rpAntiLag','range','','Engine',0,0,1,'Anti-lag','Halves spool time; adds heat and afterfire.',{'stepDis':1}])
                        add('induction',kind+'_'+variant+'_'+tier,effect,variables=variables)
        else:
            slots['induction']=f'{root}_induction';children.append([slots['induction'],'','Existing forced-induction upgrade'])
            add('induction','race_upgrade',{'induction':'stock_upgrade','inductionRace':True},
                variables=[['$rpFactoryBoost','range','%','Engine',115,0,115,'Factory boost target','Race part only: 100% is stock boost, 0% removes positive boost, 115% is maximum. Power stays within engine potential.',{'stepDis':1}]],
                extra={'raceprepEngine':{'induction':'stock_upgrade','inductionRace':True,'factoryBoostTarget':'$=$rpFactoryBoost'}})
        for kind in ['intercooler','oilcooler']:
            slots[kind]=f'{root}_{kind}';children.append([slots[kind],'',{'oilcooler':'Oil cooler'}.get(kind,kind.title())])
            add(kind,'race',{kind:True})
        slots['radiator']=f'{root}_radiator';children.append([slots['radiator'],'','Radiator'])
        for level in RADIATORS:
            add('radiator',level,{'radiator':level})
        hub=f'{root}_hub'
        generated[hub]={'information':{'authors':'Sillyw0rld','name':'Engine upgrade slots'},
                        'slotType':'camso_tuning_parameters_engine',
                        'slots':[['type','default','description']]+children,
                        'variables':[VARIABLE_HEADER,['$rpECUGain','range','%','Engine',100,0,100,'Race ECU timing effect','Only Race ECU unlocks this setting; rated at 100%.',{'stepDis':1}]],
                        'raceprepVariableOwners':{'$rpECUGain':'ecu'},
                        'raceprepEngine':{'ecuGain':'$=($rpECUGain or 100)/100'},
                        'controller':[['fileName'],['raceprepPower']]}
        dest=Path(output)/'vehicles'/model/'raceprep/rp_engine_parts.jbeam'
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(json.dumps(generated,indent=2)+'\n')
        catalog['models'][model]={'stockRevLimit':engine['maxRPM'],'stockEngine':stock_engine,
                                 'stockInertia':field(source,'inertia'),'stockForcedInduction':stock_forced,
                                 'hub':hub,'slots':slots,'parts':native,'archive':archive}
        catalog['models'][model].update(engine_metadata(archive, model))
        if not catalog['models'][model].get('layout') or not catalog['models'][model].get('litres'):
            print('engine potential fallback: '+stock_engine+' (layout/displacement unavailable)')
        race_parts={}
        for name,p in original.items():
            label=(name+' '+p['title']).lower()
            if 'race' not in label: continue
            s=(p['slot']+' '+p['title']).lower()
            role='differential' if 'diff' in s else 'transmission' if 'transmission' in s or 'gearbox' in s else 'suspension' if any(w in s for w in ['coilover','suspension','spring','shock','damper','sway']) else None
            if role: race_parts[name]=role
        for name,p in native.items():
            if p['effect'].get('radiator'): race_parts[name]='radiator_'+p['effect']['radiator']
        catalog['models'][model]['raceParts']=race_parts
    destination=Path(output)/'lua/common/raceprep/engine-parts.json'
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(catalog,indent=2)+'\n')
    print(f'Generated missing engine parts for {len(fleet)} models; reused native upgrade slots')


if __name__=='__main__':
    generate()
