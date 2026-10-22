// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Sillyw0rld
// Native BJR components, shared Angular root and normal BeamNG Lua bridge.
// Original part illustrations and contextual advice. These describe mechanisms;
// numerical gains stay in the car-specific option labels and performance panel.
const RacePrepWorkshop = (() => {
  const guides={
    engine:['Engine packages','piston','Combines supported engine upgrades into a matched package. The fitted parts determine the torque curve and available tuning.','Check the dyno for where torque is gained, not just the peak. Packages fit immediately; individual parts wait for Apply upgrades.'],
    conversion:['Engine conversion','engine','Fits the selected donor’s torque curve, rotational inertia and engine-block mass. A heavier or larger engine can change balance and eligibility.','Only supported donors are offered; Automation bay dimensions screen block size and orientation (accessory clearance is not verified). Apply the conversion separately, then choose upgrades for the new engine. The original engine visuals and sound remain.'],
    turbo:['Turbocharger','turbo','Exhaust energy drives a compressor to raise intake pressure. Boost can increase torque, but response depends on turbo layout, engine speed and load.','Use the selected part’s actual gain and boost limits. Where fitted, Race boost controls keep their maximum-rated PI even when detuned. More boost also increases engine load.'],
    supercharger:['Supercharger','supercharger','A mechanically driven compressor raises intake pressure. Roots and screw designs favour low-speed torque; centrifugal boost builds toward high rpm.','Response and power depend on the fitted design. Compare the whole dyno curve and keep shifts within its useful rpm range.'],
    intake:['Intake and air filter','intake','Changes the inlet path and its restriction. The power benefit depends on the current engine and the other fitted parts.','Read this car’s option gains. An intake label alone does not guarantee more power; the dyno updates after the part is fitted.'],
    exhaust:['Exhaust','exhaust','Changes the engine’s exhaust flow path. On supported engines this can reduce restriction and change where torque is produced.','Compare the fitted curve against stock. Peak power alone will not show whether the upgrade helps the rpm range used on this track.'],
    cooling:['Cooling','cooling','Radiators, intercoolers and ducts manage heat. An intercooler cools compressed intake air; oil and water cooling protect the engine under sustained load.','Cooling capacity does not guarantee more peak power. Watch temperatures over several laps; only effects actually defined by the fitted part apply.'],
    fuel:['Fuel system','fuel','Changes fuel delivery or management where the engine supports it. Adequate fuel supply matters when airflow and boost increase.','Use the option’s car-specific effect. This upgrade does not set the amount of fuel in the tank; use Setup → Fuel for race fuel load.'],
    piston:['Engine internals','piston','Pistons, rods and related internals affect the engine’s strength and supported operating range. Some packages require stronger internals before more boost is available.','A stronger component does not necessarily add power by itself. Use the displayed gains and fit any prerequisites before selecting higher boost.'],
    camshaft:['Camshaft and valvetrain','camshaft','Valve timing and lift change how the engine breathes across its rpm range. A high-rpm gain may trade away low-speed torque.','Compare the curve at corner-exit rpm as well as the peak. A higher rev limit is useful only while the engine still makes useful power.'],
    gearbox:['Transmission and gearing','gearbox','Gear ratios determine wheel torque, rpm after shifts and speed in each gear. The conversion retains the engine unless you also select an engine conversion.','Use Setup → Gearing to avoid falling below the useful power band. Shorter ratios can improve acceleration while adding shifts or limiting top speed.'],
    differential:['Differential','differential','Controls how torque reaches outputs turning at different speeds. Race parts unlock their corresponding differential setup controls.','Open favours wheel-speed freedom; LSD adds controlled locking; locked keeps outputs together. Tune front, rear and centre only where those devices exist.'],
    drivetrain:['Drivetrain conversion','drivetrain','Changes which axles are driven and installs the supported differential and shaft configuration. Layout changes traction and the mass estimate.','Apply conversions separately before selecting differential upgrades. FWD, RWD and AWD can need different driving and setup; keep the performance figures in view.'],
    tyres:['Tyre compound','tyre','Compound changes grip and, with a supported tyre simulation, operating temperature and wear. Front and rear choices use the car’s own tyre parts.','Choose for the race length and conditions. Slicks are not a wet-weather solution. Follow the displayed compound notes and the race’s allowed-compound rules.'],
    width:['Tyre width','tyre','Changes the selected axle’s tyre width relative to its original tyre. The option shows the resulting width in millimetres.','Wider does not guarantee better performance in every condition. Compare the applied car’s grip and balance; front and rear widths can be selected independently.'],
    brakes:['Brakes','brakes','Supported stages change brake torque, pads and cooling. Once stock brakes can reach the tyre’s grip limit, more torque alone may barely shorten a stop.','Compare braking distance and repeated-stop temperatures. A brake upgrade does not add ABS to a car that lacks it. Use bias to keep braking stable.'],
    suspension:['Suspension','springs','Springs, dampers and anti-roll bars control wheel travel and load transfer. Race parts unlock the matching tuning controls.','Stiffer is not always faster: bumps, kerbs and downforce loads matter. Change one area at a time and compare corner balance and tyre contact.'],
    body:['Weight reduction','body','Reduces mass, improving the power-to-weight ratio and reducing the work needed to accelerate, brake and change direction.','Stages fit immediately. These stages distribute the reduction evenly to retain front/rear balance; PI follows the lower weight.'],
    aero:['Aerodynamics','aero','Downforce grows with speed and adds tyre load; the associated drag can reduce straight-line speed. Front/rear balance changes high-speed handling.','Kit values are shown at 200 km/h. Tune the fitted kit in Setup → Aero. Its rating remains at maximum downforce even when the sliders are lower.'],
    nitrous:['Nitrous system','nitrous','Supplies additional oxidiser and fuel when the supported system is active. Bottle capacity and activation determine how long the extra output lasts.','The steady-state dyno does not promise bottle-on output. Race rules can prohibit nitrous; use only the controls supported by this car.']
  };
  const get=key=>{const g=guides[key]||guides.engine;return {title:g[0],image:g[1],description:g[2],advice:g[3]};};
  function shop(type,group){
    if(type?.kind==='width')return get('width');
    if(type?.kind==='compound')return get('tyres');
    if(type?.kind==='body')return get('body');
    if(type?.kind==='packages')return get('engine');
    if(group==='conversion')return get('conversion');
    const text=(String(type?.title||'')+' '+String(type?.row?.slot||'')).toLowerCase();
    for(const [pattern,key] of [
      [/drivetrain conversion|transfercase|transfer case/,'drivetrain'],[/differential|final.drive/,'differential'],
      [/supercharg/,'supercharger'],[/turbo|boost/,'turbo'],[/intercool|radiator|cooling|oil cooler/,'cooling'],
      [/exhaust|header/,'exhaust'],[/intake|air.?filter/,'intake'],[/fuel|inject|ignition|management/,'fuel'],
      [/camshaft|valve/,'camshaft'],[/internals|piston|forged|connecting.rod|crankshaft/,'piston'],
      [/brake|pad|disc|rotor/,'brakes'],[/transmission|gearbox|clutch|flywheel/,'gearbox']
    ])if(pattern.test(text))return get(key);
    return get(group==='airfuel'?'intake':group);
  }
  const tuneImages={tyres:'tyre',gearing:'gearbox',alignment:'alignment',antiroll:'antiroll',springs:'springs',damping:'springs',aero:'aero',brakes:'brakes',differential:'differential',fuel:'fuel',engine:'engine',advanced:'body',other:'engine'};
  const tuning={
    pressure:['Tyre pressure','Higher pressure changes carcass support and response; lower pressure increases flex. Grip is not a simple “lower is better” relationship.','Use hot tyre temperatures, wear and handling to judge the setting. Front and rear apply independently; changing one preserves the other.'],
    camber:['Camber','Negative camber leans the top of the wheel inward to support the outside tyre during cornering. Too much can reduce the contact available under braking.','Use small steps and compare tyre temperatures across the tread. The sign and units follow this car’s slider.'],
    toe:['Toe','Toe changes where the wheels point relative to the car. It trades steering response against stability, rolling resistance and tyre scrub.','Small changes matter. Read this car’s displayed units and direction; numeric signs are not consistent across every mod.'],
    caster:['Caster','Caster changes steering self-centring and the camber gained as the wheels steer. It also changes steering effort and feel.','Make small changes and check both steering response and clearance. The best setting depends on suspension geometry.'],
    rebound:['Rebound damping','Rebound resists the suspension extending after compression. Excessive rebound can hold the wheel up over repeated bumps, reducing contact.','Adjust with bump damping and springs in mind. Fast damping refers to suspension shaft movement, not road speed.'],
    bump:['Bump damping','Bump resists the suspension compressing over bumps, kerbs and weight transfer. Excessive bump damping can make the tyre skip across rough surfaces.','Fast and slow refer to suspension shaft speed. Keep enough movement to follow the track; damping does not set static ride height.'],
    bias:['Brake balance','Moves braking effort between the axles. Too much rear effort can cause rear lock or instability; excessive front effort can waste rear grip.','Start with a stable setting, then test straight-line and trail braking. The slider’s label states whether the number represents front or rear share.'],
    ride:['Ride height','Changes suspension position and ground clearance. A low car can bottom out over kerbs or under high-speed aero load.','Check clearance while braking and at speed, not just when stationary. Keep enough travel for the track surface.'],
    preload:['Differential preload','Adds baseline resistance to wheel-speed difference even when drive torque is low. More preload can improve consistency but resist rotation.','Tune in small steps and check corner entry as well as exit. Power and coast locking are separate controls.'],
    coast:['Coast locking','Controls differential locking off throttle. More coast lock can stabilise deceleration but can also resist corner-entry rotation.','Compare braking and turn-in with the same entry speed. Combine with preload rather than using coast lock alone.'],
    lock:['Power locking','Controls how strongly the LSD resists wheel-speed difference under power. It can limit inside-wheel spin but change power-on balance.','Test corner exits. Too much locking may encourage understeer or make both driven tyres break traction together.']
  };
  function tune(section,row,base){
    const text=(String(row?.name||'')+' '+String(row?.title||'')).toLowerCase();
    let key;
    for(const [pattern,k] of [[/pressure|psi/,'pressure'],[/camber/,'camber'],[/caster/,'caster'],[/toe/,'toe'],[/rebound/,'rebound'],[/bump|compression/,'bump'],[/bias|balance/,'bias'],[/ride.?height/,'ride'],[/preload/,'preload'],[/coast|revlock/,'coast'],[/lock/,'lock']])if(pattern.test(text) && (!['preload','coast','lock'].includes(k)||section==='differential')){key=k;break;}
    const copy=key&&tuning[key]||base;
    return {title:copy[0],description:copy[1],advice:copy[2],image:tuneImages[section]||'engine'};
  }
  return {shop,tune,get};
})();

const mod = angular.module('raceprepBJR', ['beamjoy']);
// BeamNG's Angular 1.5 treats range inputs as text. Keep Race Prep slider
// models numeric before ng-change/validation and Lua serialization run.
mod.directive('rpNumberRange',function(){
  return {restrict:'A',require:'ngModel',priority:1,link:function(scope,element,attrs,model){
    model.$parsers.push(value=>value!=='' && Number.isFinite(Number(value))?Number(value):undefined);
    // min/max/step are often Angular expressions: the browser first places the
    // handle against its defaults (0-100) and never moves it when the real range
    // arrives (handles at the wrong end while the number was right). Re-apply.
    const sync=()=>{const v=model.$viewValue;if(v!==undefined && v!==null && Number.isFinite(Number(v)))element[0].value=v;};
    for(const a of ['min','max','step'])attrs.$observe(a,()=>scope.$evalAsync(sync));
  }};
});
// Queue requests across the independently mounted BJR and Race Prep windows.
mod.service('raceprepRaceRules', function ($rootScope) {
  let pending;
  this.open = raceID => {
    if(raceID==null)return;
    pending=String(raceID);
    $rootScope.$broadcast('RacePrepBJROpenRules');
  };
  this.take = () => {const id=pending;pending=undefined;return id;};
});
// Add to BJR's real race-start component without replacing its template,
// controller or callbacks. Its startingId is the selected race, not the grid.
mod.directive('bjMainRaces', function ($compile, raceprepRaceRules) {
  return {restrict:'E',require:'bjMainRaces',link:function(scope,element,attrs,native){
    const child=scope.$new();
    child.rpRaceStart=native;
    child.rpOpenRules=event=>{event.stopPropagation();raceprepRaceRules.open(native.startingId);};
    const panel=angular.element('<div class="rp-native-race-settings"><div class="p-2 mb-2" ng-if="rpRaceStart.startingId != null"><button class="btn info" ng-click="rpOpenRules($event)">Motorsport race settings</button><div class="small opacity-70">Class / PI limits, allowed parts, preparation and race rules. Save before starting.</div></div></div>');
    element.prepend(panel);
    $compile(panel)(child);
    scope.$on('$destroy',()=>{if(!child.$$destroyed)child.$destroy();});
  }};
});
// Setup values in readable units. JBeam units as written by car authors
// ("+m", "Deg", ":1", "PSI"); decimals follow the slider step (display only).
const SETUP_UNITS={'+m':['mm',1000,true],m:['mm',1000],Deg:['°',1],deg:['°',1],PSI:['psi',1],Kg:['kg',1],'+Kg':['kg',1,true],S:['s',1],'Km/h':['km/h',1],RPM:['rpm',1],'coef.':['',1]};
const stepDecimals=step=>Math.min(4,(Math.abs(step||1).toFixed(6).replace(/0+$/,'').split('.')[1]||'').length);
const setupFormat=(n,v)=>{
  if(!Number.isFinite(n))return '—';
  const [unit,scale,signed]=SETUP_UNITS[v.unit]||[v.unit||'',1];
  const value=n*scale,text=value.toFixed(stepDecimals((v.displayStep || v.step || 0.01)*scale));
  if(unit===':1')return text+':1';
  return (signed&&value>0?'+':'')+text+(unit?(unit==='°'?'':' ')+unit:'');
};
const setupShown=v=>v.displayValue??v.value;
const setupStock=v=>Number.isFinite(v.minDis)&&Number.isFinite(v.maxDis)&&v.max!==v.min?v.minDis+(v.default-v.min)*(v.maxDis-v.minDis)/(v.max-v.min):v.default;
// Gearing: ratios from the tuning sliders (live while dragging), else the
// fitted gearbox; top speed per gear at the rev limit on the driven wheels.
const Gearing={
  gearNo:v=>{const m=/\$gear_(\d+|r)(?:_|$)/i.exec(v.name);return m?(m[1].toUpperCase()==='R'?'R':Number(m[1])):null;},
  isFinal:v=>/final ?drive|finaldrive/i.test(v.name+' '+v.title),
  value:(v,values,stock)=>stock?v.default:(Number.isFinite(values?.[v.name])?values[v.name]:setupShown(v)),
  final:(rows,values,info,stock)=>{
    const finals=rows.filter(Gearing.isFinal);
    const pick=finals.find(v=>v.side===(info?.drive==='FWD'?'front':'rear'))||finals[0];
    const n=pick&&Gearing.value(pick,values,stock);
    return Number.isFinite(n)&&n>0?n:info?.finalDrive;
  },
  ratios:(rows,values,info,stock)=>{
    const gears=rows.filter(v=>Number.isInteger(Gearing.gearNo(v))).sort((a,b)=>Gearing.gearNo(a)-Gearing.gearNo(b));
    if(gears.length)return gears.map(v=>({n:Gearing.gearNo(v),ratio:Gearing.value(v,values,stock)}));
    return (info?.gears||[]).map((ratio,i)=>({n:i+1,ratio}));
  },
  rpm:(revRow,values,info,stock)=>{const n=revRow&&Gearing.value(revRow,values,stock);return Number.isFinite(n)&&n>0?n:info?.rpm;},
  // speed at `rpm` for an overall ratio, in the game's unit
  speed:(rpm,ratio,info)=>{const kmh=rpm/ratio*2*Math.PI*info.radius*60/1000;return info.unit==='mph'?kmh/1.609344:kmh;}
};
// BJR's player list labels a car by its model, which carries the model's
// stock rating; show each car's own class/PI instead (Race Prep state).
mod.service('raceprepBadges',function(){this.map={};});
// The collapsed Players row is separate from bjVehicleLine in current BJR.
// Decorate its projected label too, without replacing a BJR controller/template.
mod.directive('bjPlayersList',function(raceprepBadges){
  return {restrict:'E',require:'?bjPlayersList',link:function(scope,element,attrs,native){
    if(!native)return;
    scope.$watch(()=>{
      const stamps=[];
      for(const p of native.players||[]){
        const badge=raceprepBadges.map[`${p.playerID}-${p.currentVehicle}`];
        if(badge===undefined)continue;
        const base=String(p.currentLabel||'').replace(/\s*\[[EDCBASRPX] \d+\]$/,'');
        const label=base+(badge?`  [${badge}]`:'');
        if(p.currentLabel!==label)p.currentLabel=label;
        stamps.push(label);
      }
      return stamps.join('|');
    });
  }};
});
mod.directive('bjVehicleLine',function(raceprepBadges){
  return {restrict:'E',require:'?bjVehicleLine',link:function(scope,element,attrs,native){
    if(!native)return;
    const strip=label=>String(label||'').replace(/\s*\[[EDCBASRPX] \d+\]$/,'');
    scope.$watch(()=>{
      const v=native.vehicle,o=native.owner;
      if(!v||!o||o.playerID===undefined)return null;
      const badge=raceprepBadges.map[`${o.playerID}-${v.vid}`];
      if(badge===undefined)return null; // not reported (yet): leave BJR's label
      const want=strip(v.label)+(badge?`  [${badge}]`:'');
      if(v.label!==want)v.label=want;
      return want;
    });
  }};
});
mod.component('bjRacePrep', {
  templateUrl: '/ui/modModules/raceprepBJR/raceprep.html',
  controller: function ($rootScope, raceprepRaceRules, raceprepBadges) {
    const vm = this;
    vm.state = {}; vm.driving={};vm.hudVisible=true;vm.towerVisible=true;vm.leaderGap=false;vm.hiddenSession=null; vm.open = false; vm.tab = 'setup'; vm.group = 'engine'; vm.setupSection = 'tyres';
    // Motorsport settings is the last tab: everyone can read it, editing follows
    // the server's permissions (greyed out without them).
    vm.tabGroups = [{label:'Race',tabs:['grid','results','sessions']},{label:'My car',tabs:['upgrades','setup']},{label:'Server',tabs:['drivers','championship']}];
    vm.tabs = [...vm.tabGroups.flatMap(g=>g.tabs),'settings'];
    vm.tabNames={sessions:'Race weekend',settings:'Motorsport settings'};
    vm.tabTitle=tab=>vm.tabNames[tab]||vm.title(tab);
    // what this player may do (server: Motorsport settings > Permissions)
    vm.can=action=>!!vm.state.abilities?.[action];
    // Motorsport settings sections; Race rules has its own sub-sections
    vm.settingsSection='rules';vm.rulesSection='eligibility';
    vm.settingsSections=[['permissions','Permissions'],['weekend','Race weekend'],['rules','Race rules'],['track','Track settings']];
    // staff see an Optional mods section while a mod needs attention (stable arrays for ng-repeat)
    const sectionsWithOptional=vm.settingsSections.concat([['optional','Optional mods']]);
    vm.settingsSectionList=()=>list(vm.state.motorsport?.optional).length||vm.settingsSection==='optional'?sectionsWithOptional:vm.settingsSections;
    vm.optionalState=m=>({missing:'Not installed',outdated:'Installed '+m.installed+', tested with '+m.latest,unknown:'Version not recognised; tested with '+m.latest,'plugin-missing':'Its BeamMP server plugin is missing'})[m.state]||m.state;
    vm.rulesSections=[['eligibility','Eligibility'],['start','Start and grid'],['limits','Track limits and flags'],['aids','Aids and conditions'],['tuning','Tuning'],['upgrades','Upgrades']];
    vm.rulesSectionOf={piMin:'eligibility',piMax:'eligibility',allowedClasses:'eligibility',
      startType:'start',paceSpeed:'start',startLights:'start',falseStartPenaltySeconds:'start',falseStartTolerance:'start',gridOrder:'start',gridReverseTop:'start',practiceMinutes:'start',qualifyingMinutes:'start',
      trackLimits:'limits',cutPenaltyAfter:'limits',cutPenaltySeconds:'limits',yellowFlags:'limits',safetyRating:'limits',
      abs:'aids',tc:'aids',esc:'aids',tyreWear:'aids',trackTempFixed:'aids',trackTemp:'aids',
      tuning:'tuning',fuel:'tuning',diff:'tuning',centreSplit:'tuning',centreSplitMin:'tuning',centreSplitMax:'tuning',maxPreload:'tuning',maxLock:'tuning',diffModes:'tuning',
      aero:'upgrades',nitrous:'upgrades',slickCompounds:'upgrades',parts:'upgrades'};
    vm.rulesSectionIndex=()=>Math.max(0,vm.rulesSections.findIndex(s=>s[0]===vm.rulesSection));
    vm.openSettings=(section,sub)=>{vm.tab='settings';if(section)vm.settingsSection=section;if(sub)vm.rulesSection=sub;vm.send('tab',{name:'settings'});};
    // Race rules > Upgrades: caps per race (raceprep/upgradeRules.lua)
    vm.upgradeRuleRows=[
      {key:'engine',label:'Engine parts',hint:'intake, exhaust, ECU, cams, internals',options:[['none','None'],['street','Street'],['sport','Sport'],['race','Race']]},
      {key:'induction',label:'Forced induction',hint:'turbo and supercharger kits',options:[['none','None'],['factory','Keep factory'],['allow','Allow fitting']]},
      {key:'engineConversion',label:'Engine conversions',hint:'swap in a donor engine',options:[[false,'Off'],[true,'On']]},
      {key:'drivetrainConversion',label:'Drivetrain conversions',hint:'change the driven wheels',options:[['off','Off'],['fwdrwd','FWD↔RWD'],['any','Any + AWD']]},
      {key:'compound',label:'Tyre compound',hint:'softest allowed',options:[['road','Road'],['sport','Sport'],['semi','Semi-slick'],['slick','Slick']]},
      {key:'width',label:'Tyre width',hint:'wider tyre and rim',options:[[0,'Off'],[20,'+20 mm'],[40,'+40 mm']]},
      {key:'weight',label:'Weight reduction',hint:'body stages',options:[['none','None'],['street','Street'],['sport','Sport'],['race','Race']]},
      {key:'brakes',label:'Brakes',hint:'brake packages',options:[['factory','Factory'],['sport','Sport'],['race','Race']]},
      {key:'radiators',label:'Radiators and coolers',hint:'cooling parts',options:[[false,'Off'],[true,'On']]}];
    vm.setUpgradeRule=(key,value)=>{if(!vm.can('rules'))return;vm.ruleDraft.upgrades=vm.ruleDraft.upgrades||{};vm.ruleDraft.upgrades[key]=value;};
    // Motorsport settings draft (permissions by BeamJoy group, weekend defaults)
    vm.permissionRows=[['weekend','Start a race weekend','Start, advance and end practice, qualifying and the race'],['rules','Edit rules and track settings','Race rules, track settings and these Motorsport settings'],['raceControl','Race control','Full-course yellow and other race control']];
    vm.groupChoices=()=>['everyone',...list(vm.state.motorsport?.groups)];
    vm.groupLabel=g=>g==='everyone'?'Everyone':vm.title(g)+' and up';
    vm.saveMotorsport=()=>{if(vm.can('rules')&&vm.msDraft)vm.send('motorsport',angular.copy(vm.msDraft));};
    // Race weekend tab
    vm.weekendForm={};
    vm.weekendRunning=()=>{const s=vm.state.weekend?.stage;return !!s&&s!=='ended';};
    vm.weekendSteps=()=>{
      const w=vm.state.weekend;if(!w)return [];
      const order=['practice','qualifying','grid','race'];const at=order.indexOf(w.stage==='grid'?'race':w.stage);
      return [['practice','Practice',w.practiceMinutes],['qualifying','Qualifying',w.qualifyingMinutes],['race','Race',0]].filter(([id,,m])=>id==='race'||m>0).map(([id,label,m])=>{
        const i=order.indexOf(id);
        return {id,label,state:i<at?'done':(w.stage===id||(id==='race'&&w.stage==='grid'))?'now':'next',
          detail:i<at?'Done':(w.stage===id?(id==='race'?'Running':vm.clock(vm.state.sessionRemaining)+' left'):(id==='race'&&w.stage==='grid'?'Grid set · open the race lobby':(m?m+' min':'')))};
      });
    };
    vm.clock=ms=>Number.isFinite(ms)?Math.floor(ms/60000)+':'+String(Math.floor(ms/1000)%60).padStart(2,'0'):'—';
    vm.weekendGridChoice=()=>vm.state.motorsport?.settings?.weekend?.gridSource==='weekend';
    vm.startWeekend=()=>{const f=vm.weekendForm;if(!vm.can('weekend')||!f.raceID)return;vm.send('weekendStart',{raceID:Number(f.raceID),practiceMinutes:f.practiceMinutes,qualifyingMinutes:f.qualifyingMinutes,gridOrder:vm.weekendGridChoice()?f.gridOrder:undefined});};
    vm.sectorClass=(row,i)=>{const rows=list(vm.state.practice?.rows);const t=row.bestSectors?.[i];if(!Number.isFinite(t))return '';const best=Math.min(...rows.map(r=>r.bestSectors?.[i]).filter(Number.isFinite));return t===best?'rp-sector-best':'rp-sector-own';};
    vm.fuel={};vm.tyres={};vm.tuneDirty=false;vm.diffDirty=false;
    vm.vars = {}; vm.partChoices = {}; vm.diff = {}; vm.scope = 'default';
    vm.rubberLevel=null;vm.practiceMinutes = 10; vm.qualifyingMinutes = 10; vm.seriesName = ''; vm.setupName = 'Race setup';
    vm.groups = [['airfuel','Fuel & air'],['engine','Engine'],['conversion','Engine conversion'],['drivetrain','Drivetrain'],['suspension','Suspension & brakes'],['tyres','Wheels & tyres'],['body','Body'],['aero','Aero'],['nitrous','Nitrous']];
    vm.send = (action, payload = {}) => {
      if (typeof bngApi !== 'undefined') bngApi.engineLua(`raceprepBJR.dispatch(${bngApi.serializeToLua({action,payload})})`);
    };
    // BJR:ME's race HUD shows BJR's own race data (BJRaceHud, ~20/s); BJR's
    // race HUD is hidden (CSS only, the player's BJR settings are untouched)
    vm.hud=null;
    vm.raceHudShown=()=>!vm.open && !!vm.driving.active && !!vm.hud?.active && !!vm.hud.self;
    vm.sessionHudShown=()=>!vm.open && !!vm.driving.active && !!vm.driving.practice && !vm.raceHudShown() && vm.hiddenSession!==vm.driving.practice.id;
    vm.syncNativeHUD=()=>document.body.classList.toggle('raceprep-native-hud-replaced',vm.raceHudShown() && (vm.hudVisible || vm.towerVisible));
    const offHud=$rootScope.$on('BJRaceHud',(_,data)=>$rootScope.$evalAsync(()=>{vm.hud=data&&data.active?data:null;vm.syncNativeHUD();}));
    vm.isNum=Number.isFinite;
    vm.badge=row=>vm.driving.race?.badges?.[row.playerName]||{};
    vm.hudLap=()=>{const s=vm.hud?.self;return s?Math.min(s.currentLap||1,vm.hud.totalLaps||1):1;};
    vm.gapText=(d,sign)=>!d?'—':(d.lapsDiff?sign+Math.abs(d.lapsDiff)+' lap'+(Math.abs(d.lapsDiff)>1?'s':''):Number.isFinite(d.gapMs)?sign+(Math.abs(d.gapMs)/1000).toFixed(3):'—');
    vm.towerGap=(r,i)=>r.dnf?'DNF':r.disqualified?'DSQ':i===0?(r.finished&&Number.isFinite(r.totalMs)?vm.time(r.totalMs):'Leader'):r.leaderLapsDiff?'+'+r.leaderLapsDiff+' lap'+(r.leaderLapsDiff>1?'s':''):Number.isFinite(r.leaderGapMs)?'+'+(r.leaderGapMs/1000).toFixed(3):'—';
    // sector strip: finished sectors purple (race best) or white, the one being driven orange, yellow under a flag
    vm.hudSectors=()=>{
      const h=vm.hud,n=Math.max(1,h?.totalSectors||1),out=[];
      for(let i=1;i<=n;i++){
        const ms=h?.self?.lapSectors?.['s'+i],best=h?.fastestSectorMs?.['s'+i];
        if(Number.isFinite(ms))out.push(Number.isFinite(best)&&ms<=best?'best':'done');
        else if(out.length===i-1&&!out.includes('live'))out.push(vm.driving.signals?.yellow?'yellow':'live');
        else out.push('');
      }
      return out;
    };
    vm.sectorWord=state=>({best:'· SESSION BEST',own:'· YOUR BEST',slower:'· SLOWER',live:'· LIVE'})[state]||'';
    vm.myBest=()=>{let b;for(const l of list(vm.driving.practice?.laps))if(l.valid&&(!b||l.time<b))b=l.time;return b;};
    vm.limitsText=()=>{const l=vm.driving.signals?.limits;if(!l)return '';return l.mode==='penalty'&&Number.isFinite(l.after)?'Track limits '+l.cuts+'/'+l.after:'Track limits';};
    vm.limitsSub=()=>{const l=vm.driving.signals?.limits;if(!l)return '';if(l.mode!=='penalty')return 'lap invalid';return l.cuts>=l.after?'+'+l.seconds+' s penalty':'next cut over '+l.after+': +'+l.seconds+' s';};
    vm.toggle = () => { vm.open = !vm.open;vm.syncNativeHUD(); vm.send('show', {value:vm.open}); };
    // Drop focus after a click: BeamNG styles focused buttons, which left the
    // previous tab looking selected next to the active one.
    vm.blur = event => event?.currentTarget?.blur?.();
    vm.selectTab = (tab,event) => { vm.tab = tab; vm.blur(event); vm.send('tab',{name:tab});if(tab==='results')vm.loadHistory(); };
    vm.selfReady = () => !!(vm.state.grid?.rows || []).find(r=>r.isSelf)?.ready;
    vm.tankName = t => ({mainTank:'Fuel tank',mainBattery:'Battery',n2oTank:'Nitrous bottle'})[t.name] || vm.title(t.name);
    vm.energyName = e => ({gasoline:'Gasoline',diesel:'Diesel',electricEnergy:'Electric',n2o:'Nitrous',kerosine:'Kerosene',lpg:'LPG',cng:'CNG'})[e] || vm.title(e);
    vm.champStatus = s => ({draft:'Draft: add rounds, then start',running:'Running',stopped:'Stopped',completed:'Completed'})[s] || 'No championship';
    vm.champOpen = () => ['draft','running'].includes(vm.state.control?.championship?.status);
    vm.title = s => String(s || '').replace(/([a-z])([A-Z])/g,'$1 $2').replace(/_/g,' ').replace(/^./,x=>x.toUpperCase());
    vm.signed=ms=>Number.isFinite(ms)?(ms>=0?'+':'')+(ms/1000).toFixed(3):'—';
    vm.classColor=c=>({E:'#8a96a3',D:'#22b2e6',C:'#b48e00',B:'#b45400',A:'#b02028',S:'#7034a4',R:'#2f63e6',P:'#af2575',X:'#247c31'})[c] || '#49545b';
    let endedID,endedAt;
    const offDriving=$rootScope.$on('RacePrepBJRDriving',(_,packet)=>$rootScope.$evalAsync(()=>{
      const view={...packet};
      if(!packet.active){endedID=undefined;endedAt=undefined;}
      if(packet.practice?.state==='ended'){
        if(endedID!==packet.practice.id){endedID=packet.practice.id;endedAt=Date.now();}
        if(Date.now()-endedAt>=120000) delete view.practice;
      }
      vm.driving=view;vm.syncNativeHUD();
    }));
    vm.time = ms => Number.isFinite(ms) ? `${Math.floor(ms/60000)}:${(ms/1000%60).toFixed(3).padStart(6,'0')}` : '—';
    vm.isBool = v => typeof v === 'boolean'; vm.isNumber = v => typeof v === 'number';
    vm.enums = {tyreWear:['driver','on','off'],abs:['driver','on','off'],tc:['driver','on','off'],esc:['driver','on','off'],startType:['standing','rolling'],gridOrder:['join','qualifying','reverse','handicap'],trackLimits:['off','invalid','penalty']};
    // Event limits match the server sanitizer; car setup uses its own JBeam metadata.
    vm.ruleSpecs={
      centreSplitMin:{min:0,max:1,step:0.01,unit:'%',scale:100},
      centreSplitMax:{min:0,max:1,step:0.01,unit:'%',scale:100},
      maxPreload:{min:0,max:5000,step:1,unit:'Nm'},maxLock:{min:0,max:100,step:1,unit:'%'},
      trackTemp:{min:0,max:70,step:1,unit:'°C'},paceSpeed:{min:40,max:150,step:1,unit:'km/h'},
      falseStartPenaltySeconds:{min:0,max:60,step:1,unit:'s'},falseStartTolerance:{min:0.25,max:3,step:0.05,unit:'m'},
      practiceMinutes:{min:0,max:120,step:1,unit:'min'},qualifyingMinutes:{min:0,max:120,step:1,unit:'min'},
      gridReverseTop:{min:2,max:30,step:1,unit:'drivers'},cutPenaltyAfter:{min:0,max:50,step:1,unit:'cuts'},
      cutPenaltySeconds:{min:1,max:60,step:1,unit:'s'}
    };
    // Rules: readable names, in a sensible order; unknown keys fall back to title case.
    vm.ruleNames={tuning:'Car setup changes',fuel:'Fuel load changes',aero:'Aero adjustments',diff:'Differential changes',nitrous:'Nitrous allowed',
      centreSplit:'Centre split adjustable',centreSplitMin:'Centre split, rearmost',centreSplitMax:'Centre split, frontmost',maxPreload:'Maximum diff preload',maxLock:'Maximum diff lock',
      abs:'ABS',tc:'Traction control',esc:'Stability control',tyreWear:'Tyre wear',trackTempFixed:'Fixed track temperature',trackTemp:'Track temperature',
      practiceMinutes:'Practice length',qualifyingMinutes:'Qualifying length',gridOrder:'Grid order',gridReverseTop:'Reverse grid, top',
      startType:'Start type',paceSpeed:'Rolling start pace speed',startLights:'Start lights',falseStartPenaltySeconds:'False start penalty',falseStartTolerance:'False start tolerance',
      trackLimits:'Track limits',cutPenaltyAfter:'Time penalty after',cutPenaltySeconds:'Time penalty per cut',yellowFlags:'Yellow flags',safetyRating:'Safety rating',
      allowedClasses:'Allowed classes',slickCompounds:'Allowed slick compounds',diffModes:'Allowed differential types',parts:'Allowed upgrades'};
    const ruleOrder=Object.keys(vm.ruleNames);
    vm.ruleLabel=key=>vm.ruleNames[key] || vm.title(key);
    vm.optionLabel=(group,key)=>group==='diffModes'?({open:'Open',lsd:'LSD',locked:'Locked'})[key]:group==='parts'&&key==='body'?'Body (weight reduction)':vm.title(key);
    vm.enumLabel=(key,v)=>(({driver:"Driver's choice",on:'On',off:'Off',standing:'Standing',rolling:'Rolling',join:'Join order',qualifying:'Qualifying result',reverse:'Reversed top N',handicap:'Handicap: lowest PI first',invalid:'Lap invalid',penalty:'Lap invalid + time penalty'})[v]) || vm.title(v);
    vm.valueText=(value,step=1,unit='')=>{
      if(!Number.isFinite(value))return '—';
      // Decimal steps can be scientific notation; precision is bounded for display only.
      const decimals=(Math.abs(step||1).toFixed(6).replace(/0+$/,'').split('.')[1]||'').length;
      return value.toFixed(decimals)+(unit?' '+unit:'');
    };
    // centre split as front / rear torque, e.g. "F 40 % · R 60 %"
    vm.splitText=front=>Number.isFinite(Number(front))?`F ${Math.round(Number(front)*100)} % · R ${100-Math.round(Number(front)*100)} %`:'—';
    vm.ruleValue=key=>{const s=vm.ruleSpecs[key];if(key==='centreSplitMin'||key==='centreSplitMax')return vm.splitText(vm.ruleDraft?.[key]);return s?vm.valueText(vm.ruleDraft?.[key]*(s.scale||1),s.step*(s.scale||1),s.unit):'—';};
    vm.togglePI=bound=>{vm.ruleDraft[bound]=vm.piEnabled[bound]?(bound==='piMin'?100:999):null;vm.piChanged(bound);};
    vm.piChanged=bound=>{if(vm.piEnabled.piMin&&vm.piEnabled.piMax){if(bound==='piMin')vm.ruleDraft.piMax=Math.max(vm.ruleDraft.piMax,vm.ruleDraft.piMin);else vm.ruleDraft.piMin=Math.min(vm.ruleDraft.piMin,vm.ruleDraft.piMax);}};
    vm.splitRuleChanged=key=>{if(key==='centreSplitMin')vm.ruleDraft.centreSplitMax=Math.max(vm.ruleDraft.centreSplitMax,vm.ruleDraft.centreSplitMin);else if(key==='centreSplitMax')vm.ruleDraft.centreSplitMin=Math.min(vm.ruleDraft.centreSplitMin,vm.ruleDraft.centreSplitMax);};
    vm.ruleObjects = ['allowedClasses','slickCompounds','diffModes','parts','upgrades'];
    vm.scopeName=()=>vm.scope==='default'?'all races using server defaults':(vm.state.races || []).find(r=>String(r.id)===vm.scope)?.name || 'the selected race';
    vm.ruleOptions={allowedClasses:['E','D','C','B','A','S','R','P','X'],slickCompounds:['supersoft','soft','medium','hard'],diffModes:['open','lsd','locked'],parts:['drivetrain','suspension','tyres']};
    // object rules shown per Race rules sub-section (upgrades has its own rows)
    vm.ruleObjectsIn=section=>vm.ruleObjects.filter(g=>g!=='upgrades'&&vm.rulesSectionOf[g]===section);
    const ruleRank=k=>{const i=ruleOrder.indexOf(k);return i<0?ruleOrder.length:i;};
    vm.ruleKeys = section => Object.keys(vm.ruleDraft || {}).filter(k=>!vm.ruleObjects.includes(k) && !k.startsWith('rubber') && !k.startsWith('wind') && k!=='piMin' && k!=='piMax' && (!section || (vm.rulesSectionOf[k]||'aids')===section)).sort((a,b)=>ruleRank(a)-ruleRank(b) || a.localeCompare(b));
    vm.changeScope = () => {
      const store = vm.state.ruleStore || {};
      const layers=[vm.state.ruleDefaults || {},store.default || {},vm.scope==='default'?{}:(store.races || {})[vm.state.level+':'+vm.scope] || {}];
      vm.ruleDraft = angular.copy(Object.assign({},...layers));
      // Match the Lua rule inheritance: partial nested overrides retain their
      // other default keys, including explicit false bans from earlier layers.
      for(const group of vm.ruleObjects){
        const base=group==='upgrades'?{}:Object.fromEntries(vm.ruleOptions[group].map(key=>[key,group==='parts'?'any':true]));
        vm.ruleDraft[group]=Object.assign(base,...layers.map(r=>r[group] || {}));
      }
      for(const key of ['piMin','piMax']) if(vm.ruleDraft[key]===false) vm.ruleDraft[key]=null;
      vm.piEnabled={piMin:Number.isFinite(vm.ruleDraft.piMin),piMax:Number.isFinite(vm.ruleDraft.piMax)};
    };
    const openRaceRules=()=>{
      const id=raceprepRaceRules.take();if(id===undefined)return;
      vm.scope=id;vm.changeScope();vm.open=true;vm.syncNativeHUD();
      vm.send('show',{value:true});vm.openSettings('rules','eligibility');
    };
    const offOpenRules=$rootScope.$on('RacePrepBJROpenRules',()=>openRaceRules());
    vm.shown=v=>v.displayValue ?? v.value;
    vm.native=(v,n)=>Number.isFinite(v.minDis)&&Number.isFinite(v.maxDis)&&v.maxDis!==v.minDis?v.min+(n-v.minDis)*(v.max-v.min)/(v.maxDis-v.minDis):n;
    vm.markDraft=()=>{
      vm.tuneDirty=list(vm.state.variables).some(v=>v.allowed && (!Number.isFinite(vm.vars[v.name]) || Math.abs(vm.vars[v.name]-vm.shown(v))>1e-7));
      vm.send('draft',{revision:vm.state.car?.revision,tune:vm.tuneDirty,diff:vm.diffDirty,upgrades:vm.upgradeCount()>0});
    };
    vm.invalidTune=()=>list(vm.state.variables).some(v=>v.allowed && !Number.isFinite(vm.vars[v.name]));
    vm.hasCooling=()=>list(vm.state.variables).some(v=>/coolingduct/i.test(v.name));
    vm.markDiff=()=>{vm.diffDirty=true;vm.markDraft();};
    vm.applyTune = () => {const vars={};for(const v of list(vm.state.variables)) if(v.allowed && vm.vars[v.name]!==vm.shown(v)) vars[v.name]=vm.native(v,vm.vars[v.name]);vm.send('tune',{vars});};
    vm.resetDraft=()=>{vm.vars={};vm.diff={};vm.tuneDirty=false;vm.diffDirty=false;for(const v of list(vm.state.variables))vm.vars[v.name]=vm.shown(v);vm.loadDiff();};
    vm.discard=()=>{vm.resetDraft();vm.send('discard');};
    vm.toggleFull=()=>{vm.full=!vm.full;if(vm.tab==='results')vm.loadHistory();};
    // Lua sends an empty table as {} (not []), which for..of cannot iterate
    const list=x=>Array.isArray(x)?x:[];
    vm.loadDiff=()=>{for(const d of (Array.isArray(vm.state.differentials)?vm.state.differentials:[]))if(!vm.diff[d.name])vm.diff[d.name]={mode:d.applied?d.mode:'stock',preload:d.preload,lock:d.lock,coast:d.coast,frontShare:d.frontShare};};
    // Setup sub-tabs in Forza's order. Differential variables belong to the
    // differential editor; fuel uses the tank sliders when the car has tanks.
    vm.sections=[['tyres','Tyres'],['gearing','Gearing'],['alignment','Alignment'],['antiroll','Anti-roll bars'],['springs','Springs'],['damping','Damping'],['aero','Aero'],['brakes','Brakes'],['differential','Differential'],['fuel','Fuel'],['engine','Engine'],['advanced','Advanced'],['other','Other']];
    let sectionSource,sectionTanks,sectionCache={};
    vm.sectionRows=section=>{
      if(sectionSource!==vm.state.variables||sectionTanks!==!!vm.state.fuelTanks?.length){sectionSource=vm.state.variables;sectionTanks=!!vm.state.fuelTanks?.length;sectionCache={};}
      return sectionCache[section]||=list(vm.state.variables).filter(v=>v.section===section&&!v.diffKind&&!(v.fuel&&sectionTanks));
    };
    let pairCache={};
    // Front and rear versions of one setting share a row ("Spring rate: F | R")
    vm.sectionPairs=section=>{
      const rows=vm.sectionRows(section);
      if(pairCache[section]?.rows===rows)return pairCache[section].pairs;
      const pairs=[],byKey={};
      for(const v of rows){
        const label=String(v.title||v.name).replace(/\b(front|rear)\b\s*/ig,'').trim().replace(/^./,c=>c.toUpperCase());
        const key=label.toLowerCase();
        let p=byKey[key];
        if(!p){p={key:section+':'+key,label,cells:[]};byKey[key]=p;pairs.push(p);}
        p.cells.push(v);
      }
      for(const p of pairs){
        const front=p.cells.find(v=>v.side==='front'),rear=p.cells.find(v=>v.side==='rear');
        p.paired=p.cells.length===2&&front&&rear;
        if(p.paired)p.cells=[front,rear];else if(p.cells.length===1&&p.cells[0].side)p.label=p.cells[0].title;
        const reasons=[...new Set(p.cells.filter(v=>!v.allowed).map(v=>v.reason).filter(Boolean))];
        p.reason=reasons.join(' · ');
      }
      pairCache[section]={rows,pairs};return pairs;
    };
    vm.visibleSections=()=>vm.sections.filter(([id])=>id==='fuel'?vm.state.fuelTanks?.length:id==='differential'?(vm.state.differentials||[]).length||vm.sectionRows(id).length:vm.sectionRows(id).length);
    vm.setupHelp={
      tyres:['Tyre pressure','Pressure changes the contact patch, response and heat. Front and rear pressures can be set independently.','Use tyre temperature and wear to judge the result. Apply your setup before comparing the performance figures.'],
      gearing:['Gear ratios','Shorter gears trade road speed for acceleration. Longer gears can reduce shifting but may drop the engine below its useful power band.','The graph shows road speed, engine rpm and the rpm after each shift. Stock gearing is shown as a reference.'],
      alignment:['Alignment','Camber changes how the tread meets the road as the car rolls in a corner. Toe changes response and straight-line stability.','Large settings can cost braking grip, increase scrub and make the car less stable. Start with small changes.'],
      antiroll:['Anti-roll bars','Stiffer bars resist body roll and change how cornering load is shared between the tyres.','Changing front versus rear stiffness changes the car’s balance. More front stiffness generally encourages understeer; more rear can encourage rotation.'],
      springs:['Springs','Spring rate controls support and wheel travel. Ride height changes clearance and suspension position.','Very stiff or very low settings can lose contact over bumps or bottom out. Consider the track and the downforce load.'],
      damping:['Damping','Bump damping controls compression; rebound controls how quickly the suspension extends.','Damping manages motion rather than static ride height. Too much can prevent the wheels following an uneven surface.'],
      aero:['Aerodynamics','Balance front and rear downforce against drag. More downforce helps at speed but can reduce straight-line performance.','Aero kits keep their maximum PI rating at every slider setting. The race’s aero rule still applies.'],
      brakes:['Brakes','Balance moves braking effort between the front and rear. Available power and cooling controls depend on the fitted parts.','Too much rear bias can destabilise braking. Too much front bias can lock the front tyres early.'],
      differential:['Differential','Preload supplies baseline locking; power and coast settings control locking on and off the throttle.','An open diff allows different wheel speeds. A locked diff keeps its outputs together. Centre split changes the front/rear torque distribution.'],
      fuel:['Fuel and energy','Set the amount in each tank independently. Fuel applies when you release the slider.','Your selected fuel level is restored after a parts or setup reload. Ready and race rules can lock fuel editing.'],
      engine:['Engine tuning','The fitted engine parts determine which controls are available. Race parts unlock their matching adjustments.','Changing a tuning slider does not lower the car’s parts-based PI. Apply the setup to refresh its actual performance figures.'],
      advanced:['Personal settings','Camera, force feedback and sound settings are personal preferences.','Structural beam and node scaling must stay at the car defaults for racing.'],
      other:['Car-specific settings','These controls come from this car’s tuning data. Units and limits follow the part that defines them.','Apply changes before comparing performance, and save a setup once you are happy with the result.']
    };
    vm.setupFocus=null;
    vm.focusSetup=v=>{vm.setupFocus=v;};
    vm.setupGuide=()=>RacePrepWorkshop.tune(vm.setupSection,vm.setupFocus?.section===vm.setupSection?vm.setupFocus:null,vm.setupHelp[vm.setupSection]||vm.setupHelp.other);
    vm.currentSetupHelp=()=>{const g=vm.setupGuide();return [g.title,g.description,g.advice];};
    vm.artwork=key=>'/ui/modModules/raceprepBJR/images/'+key+'.webp';
    // Performance panel (Setup): rig-anchored figures for the car as tuned
    vm.perfRows=[['zeroTo60','0–60 mph','s'],['sixtyTo100','60–100 mph','s'],['brake60','Braking 60–0','dist'],['brake120','Braking 120–0','dist'],['lat60','Lateral g @ 60 mph','g'],['lat120','Lateral g @ 120 mph','g']];
    vm.perfValue=(key,unit,which)=>{
      const p=vm.state.performance,v=p&&p[which||'now']&&p[which||'now'][key];
      if(!Number.isFinite(v))return '—';
      if(unit==='s')return v.toFixed(1)+' s';
      if(unit==='g')return v.toFixed(2)+' g';
      return p.imperial?Math.round(v*3.28084)+' ft':Math.round(v)+' m';
    };
    // change since the previous version of this car; lower is better except g
    vm.perfDelta=(key,unit)=>{
      const p=vm.state.performance,a=p&&p.prev&&p.prev[key],b=p&&p.now&&p.now[key];
      if(!Number.isFinite(a)||!Number.isFinite(b))return null;
      let d=b-a;if(unit==='dist'&&p.imperial)d*=3.28084;
      const small=unit==='g'?0.005:unit==='s'?0.05:0.5;
      if(Math.abs(d)<small)return null;
      const better=unit==='g'?d>0:d<0;
      return {text:(d>0?'+':'−')+(unit==='g'?Math.abs(d).toFixed(2):unit==='s'?Math.abs(d).toFixed(1):Math.round(Math.abs(d))),better};
    };
    vm.revRow=()=>(vm.state.variables||[]).find(v=>/revlimitrpm$/i.test(v.name));
    vm.gearNote=v=>{
      const info=vm.state.gearing,n=Gearing.gearNo(v);
      if(!info||!Number.isInteger(n))return '';
      const rows=vm.sectionRows('gearing'),fd=Gearing.final(rows,vm.vars,info),rpm=Gearing.rpm(vm.revRow(),vm.vars,info),ratio=Gearing.value(v,vm.vars);
      return fd&&rpm&&ratio>0?'Top '+Math.round(Gearing.speed(rpm,ratio*fd,info))+' '+info.unit:'';
    };
    vm.setFuel=tank=>vm.send('fuel',{name:tank.name,percent:vm.fuel[tank.name]});
    vm.hasOverride=()=>vm.scope!=='default'&&!!vm.state.ruleStore?.races?.[vm.state.level+':'+vm.scope];
    vm.clearRules=()=>{if(vm.hasOverride())vm.send('rules',{scope:vm.scope,rules:false});};
    vm.diffOptions=()=>['stock',...['open','lsd','locked'].filter(mode=>vm.state.rules?.diffModes?.[mode]!==false)];
    vm.diffChanged=name=>{const d=vm.diff[name];if(d.mode==='lsd'){d.preload??=100;d.lock??=.3;d.coast??=.15;}vm.markDiff();};
    vm.diffHelp=mode=>({stock:'Uses the original differential and its factory settings.',open:'Allows different wheel speeds. Power can be limited by the wheel with less grip.',lsd:'Limited slip: preload supplies baseline locking; power and coast control locking on and off throttle.',locked:'Both outputs turn together. Strong traction, with more tyre scrub and resistance to tight turns.'})[mode]||'';
    vm.tyreNote=c=>({race_supersoft:'Qualifying: 2x wear, 85–105 °C',race_soft:'1.55x wear, 95–115 °C',race_medium:'Normal wear, 105–130 °C',race_hard:'0.8x wear, 115–140 °C'})[c]||'Grip comes from Automation tyre data.';
    vm.status=row=>(row.status||'—')+(row.falseStart?' · FALSE START':'')+(row.cuts?' · '+row.cuts+' cuts':'');
    vm.resultGap=row=>row.position===1?'Winner':row.lapsDown?'+'+row.lapsDown+' laps':vm.signed(row.gap);
    vm.history={items:[],records:{}};vm.historySelection=null;
    let historyRequested;
    vm.loadHistory=()=>{historyRequested=vm.state.level;vm.send('history');};
    vm.raceKey=r=>String(r?.runID||r?.key||'');
    vm.latest=()=>vm.state.results && (!vm.state.results.level || vm.state.results.level===vm.state.level)?vm.state.results:vm.history.items?.[0];
    vm.result=()=> (vm.full && vm.historySelection && (vm.history.items||[]).find(r=>vm.raceKey(r)===vm.historySelection)) || vm.latest();
    vm.record=()=>vm.history.records?.[String(vm.result()?.raceID??vm.result()?.raceName)];
    vm.carLabel=r=>String(r?.car||r?.model||'Car not recorded').replace(/\s*\(custom\)\s*$/i,'').replace(/_/g,' ').trim();
    vm.winner=r=>(r?.rows||[]).find(p=>p.status==='FIN' && p.position===1);
    vm.bestOfRace=r=>{let best;for(const p of r?.rows||[])if(p.best?.time>0 && !p.best.invalid && (!best || p.best.time<best.best.time))best=p;return best;};
    vm.raceDate=r=>{const d=new Date(r?.date);return Number.isFinite(d.getTime())?d.toLocaleString():r?.date||'Date not recorded';};
    vm.skill=pid=>{const s=vm.state.skills?.[pid];return s?Math.round(s.rating)+(s.races<5?'?':'')+(Number.isFinite(s.delta)?' ('+(s.delta>=0?'+':'')+s.delta.toFixed(1)+')':''):'—';};
    // Upgrades are chosen first and fitted together (Apply upgrades: one reload)
    // draft choices are keyed by slot path, not row position: the list changes
    // while a car loads or when a stage adds engine slots, and positional
    // choices then landed on other slots (blank dropdowns, phantom pending
    // changes, Apply refused until every row was set back by hand)
    vm.rowKey=row=>row?(Array.isArray(row.path)&&row.path.length?row.path.join('/'):String(row.slot||row.title)):'';
    // Shop navigation is keyed by real slot path. Browsing never fits a part
    // or loses drafts in another category, even when a reload inserts rows.
    vm.shopSelection={};
    vm.shopLocked=()=>!vm.state.partsEditable || vm.state.applying;
    vm.partCategory=row=>row.group==='engine' && /fuel|exhaust|intake|inject|air.?filter|turbo|supercharg|boost|intercooler/i.test(row.title+' '+row.slot)?'airfuel':row.group;
    let shopSource,shopGroup,shopBodies,shopTyres,shopPackages,shopTypes=[];
    vm.shopTypes=()=>{
      if(shopSource===vm.state.parts && shopGroup===vm.group && shopBodies===vm.state.bodyStages && shopTyres===vm.state.tyreControls && shopPackages===vm.state.enginePackages)return shopTypes;
      shopSource=vm.state.parts;shopGroup=vm.group;shopBodies=vm.state.bodyStages;shopTyres=vm.state.tyreControls;shopPackages=vm.state.enginePackages;shopTypes=[];
      if(vm.group==='engine' && list(vm.state.enginePackages).length)shopTypes.push({id:'packages',kind:'packages',title:'Engine packages',subtitle:'Complete engine combinations'});
      if(vm.group==='body' && list(vm.state.bodyStages).length)shopTypes.push({id:'body',kind:'body',title:'Weight reduction',subtitle:'Stock / Street / Sport / Race'});
      if(vm.group==='tyres')for(const t of list(vm.state.tyreControls))for(const field of ['compound','width'])shopTypes.push({id:t.axle+':'+field,kind:field,tyre:t,title:(t.axle==='front'?'Front':'Rear')+' '+field,subtitle:field==='width'?'Tyre section width':'Tyre compound'});
      list(vm.state.parts).forEach((row,index)=>{
        if(vm.partCategory(row)!==vm.group || (vm.group==='tyres' && list(vm.state.tyreControls).length) || (vm.group==='body' && list(vm.state.bodyStages).length))return;
        shopTypes.push({id:'part:'+vm.rowKey(row),kind:'part',row,index,title:row.title,subtitle:row.currentTitle||'Choose a part'});
      });
      return shopTypes;
    };
    vm.shopType=()=>{const types=vm.shopTypes();return types.find(t=>t.id===vm.shopSelection[vm.group])||types[0];};
    vm.selectShopType=t=>{vm.shopSelection[vm.group]=t.id;};
    let optionsType,optionList=[];
    vm.shopOptions=()=>{
      const t=vm.shopType();if(t===optionsType)return optionList;optionsType=t;
      if(!t)return optionList=[];
      // unsafe: why it cannot be fitted (part limits, or a race rule: ruleBlock / blocked)
      if(t.kind==='part')optionList=list(t.row.options).map(o=>({id:o.name,value:o.name,title:o.title,tooltip:o.tooltip,unsafe:o.unsafe||o.ruleBlock}));
      else if(t.kind==='packages')optionList=list(vm.state.enginePackages).map(o=>({id:String(o.number),value:o.number,title:o.title,fitted:o.fitted,immediate:true,unsafe:o.blocked}));
      else if(t.kind==='body')optionList=list(vm.state.bodyStages).map(o=>({id:o.key,value:o.key,title:o.label+(o.percent?' · −'+o.percent+' %'+(o.kg?' (−'+o.kg+' kg)':''):'')+(o.bonus?' · +'+o.bonus+' % PI bonus':''),fitted:o.fitted,immediate:true,unsafe:o.blocked}));
      else if(t.kind==='compound')optionList=list(t.tyre.compounds).map(o=>({id:o.value,value:o.value,title:o.label,unsafe:o.blocked||(o.allowed===false?'Banned by this race':undefined)}));
      else optionList=[-20,0,20,40].map(w=>({id:String(w),value:w,title:(t.tyre.widthMM+w)+' mm',detail:w===0?'Stock width':(w>0?'+':'')+w+' mm vs stock',unsafe:(t.tyre.widthBlocked||{})[String(w)]}));
      return optionList;
    };
    vm.shopFitted=o=>{const t=vm.shopType();return t?.kind==='part'?o.value===(t.row.current||''):t?.kind==='compound'?o.value===t.tyre.compound:t?.kind==='width'?o.value===Number(t.tyre.offset):!!o.fitted;};
    vm.shopChosen=o=>{const t=vm.shopType();return t?.kind==='part'?o.value===(vm.partChoices[vm.rowKey(t.row)]??t.row.current??''):t?.kind==='compound'?o.value===vm.tyres[t.tyre.axle]?.compound:t?.kind==='width'?o.value===Number(vm.tyres[t.tyre.axle]?.offset):!!o.fitted;};
    vm.chooseShopOption=o=>{
      const t=vm.shopType();if(!t || o.unsafe || vm.shopLocked())return;
      if(t.kind==='part'){vm.partChoices[vm.rowKey(t.row)]=o.value;vm.markDraft();}
      else if(t.kind==='packages'){if(!o.fitted)vm.send('enginePackage',{number:o.value});}
      else if(t.kind==='body'){if(!o.fitted)vm.send('bodyStage',{key:o.value});}
      else {vm.tyres[t.tyre.axle][t.kind==='width'?'offset':'compound']=o.value;vm.markDraft();}
    };
    vm.chosenShopOption=()=>vm.shopOptions().find(o=>vm.shopChosen(o));
    vm.optionHeading=o=>String(o?.title||'').split(':')[0];
    vm.optionEffect=o=>o?.detail||String(o?.title||'').split(':').slice(1).join(':').trim();
    vm.shopIsPower=()=>vm.group==='engine'||vm.group==='airfuel'||vm.group==='nitrous'||vm.group==='conversion';
    vm.shopUsesDyno=()=>vm.shopIsPower() && !!vm.state.engineCurves?.current;
    vm.shopGuide=()=>RacePrepWorkshop.shop(vm.shopType(),vm.group);
    vm.shopHelp=()=>{const g=vm.shopGuide();return [g.title,g.description,g.advice];};
    vm.partChanged=i=>{const row=(vm.state.parts||[])[i];const c=row&&vm.partChoices[vm.rowKey(row)];return !!row&&c!==undefined&&c!==(row.current||'');};
    vm.tyreChanged=t=>{const w=vm.tyres[t.axle];return !!w&&(w.compound!==t.compound||Number(w.offset)!==Number(t.offset));};
    vm.upgradeList=()=>{
      const out=[];
      list(vm.state.parts).forEach((row,i)=>{if(vm.partChanged(i)){const c=vm.partChoices[vm.rowKey(row)];const o=list(row.options).find(x=>x.name===c);out.push(row.title+': '+String(o?o.title:c).replace(/:.*$/,''));}});
      for(const t of list(vm.state.tyreControls))if(vm.tyreChanged(t))out.push((t.axle==='front'?'Front':'Rear')+' tyres');
      return out;
    };
    vm.upgradeCount=()=>vm.upgradeList().length;
    vm.upgradeSummary=()=>vm.upgradeList().join(', ');
    vm.applyUpgrades=()=>{
      const parts=[],tyres=[];
      list(vm.state.parts).forEach((row,i)=>{if(vm.partChanged(i))parts.push({index:i+1,path:vm.rowKey(row),name:vm.partChoices[vm.rowKey(row)]});});
      for(const t of list(vm.state.tyreControls))if(vm.tyreChanged(t))tyres.push({axle:t.axle,compound:vm.tyres[t.axle].compound,offset:Number(vm.tyres[t.axle].offset)});
      if(parts.length||tyres.length)vm.send('upgrades',{parts,tyres});
    };
    vm.discardUpgrades=()=>{
      list(vm.state.parts).forEach(row=>{vm.partChoices[vm.rowKey(row)]=row.current||'';});
      for(const t of list(vm.state.tyreControls))vm.tyres[t.axle]={compound:t.compound,offset:t.offset};
      vm.markDraft();
    };
    vm.saveRules = () => {const rules=angular.copy(vm.ruleDraft);for(const key of ['piMin','piMax']) if(rules[key]==null) rules[key]=false;vm.send('rules',{scope:vm.scope,rules});};
    vm.saveTrack = () => vm.send('track',vm.trackDraft);
    const trackFields={rubber:['lapsToFull','dryBonus','wetPenalty','marbleSize','marbleSizeFar'],wind:['speedKmh','direction','gustKmh','gustPeriod'],weather:['cloudCover','fogDensity','rainDrops','tempNoon','tempDusk','tempMidnight','tempDawn']};
    // live wind: compass sector of a bearing (clockwise from north)
    vm.compass=b=>Number.isFinite(b)?['N','NE','E','SE','S','SW','W','NW'][Math.round(b/45)%8]:'—';
    // air temperature presets: noon, dusk, midnight, dawn (°C)
    vm.tempPresets=[{name:'Winter',temps:[3,0,-4,-3]},{name:'Autumn',temps:[14,10,6,7]},{name:'Spring',temps:[19,15,9,10]},{name:'Summer',temps:[28,23,16,18]},{name:'Heatwave',temps:[37,31,24,25]}];
    // weather presets: cloud cover, fog density, rain drops; fields BeamJoy owns
    // or the map lacks (e.g. rain) are left alone
    vm.weatherPresets=[{name:'Clear',cloud:0.1,fog:0.0001,rain:0},{name:'Cloudy',cloud:0.6,fog:0.0004,rain:0},{name:'Overcast',cloud:1.2,fog:0.0008,rain:0},
      {name:'Foggy',cloud:0.9,fog:0.012,rain:0},{name:'Light rain',cloud:1.3,fog:0.0015,rain:800},{name:'Heavy rain',cloud:1.8,fog:0.004,rain:3000},{name:'Storm',cloud:2.0,fog:0.006,rain:5000}];
    vm.applyWeatherPreset=p=>{
      const w=vm.trackDraft&&vm.trackDraft.weather;if(!w)return;
      if(!vm.weatherLocked('cloud'))w.cloudCover=p.cloud;
      if(!vm.weatherLocked('fog'))w.fogDensity=p.fog;
      if(!vm.weatherLocked('rain'))w.rainDrops=p.rain;
      w.enabled=true;
    };
    vm.applyTempPreset=p=>{const w=vm.trackDraft&&vm.trackDraft.weather;if(!w)return;[w.tempNoon,w.tempDusk,w.tempMidnight,w.tempDawn]=p.temps;w.enabled=true;};
    vm.weatherOwner=(field)=>(vm.state.weather||{})[field]||'map default';
    // BeamJoy syncs it, or this map has no such object (e.g. no rain): nothing to set
    // BJR's weather sync carries this preset (the server sends it there), so
    // those fields stay editable here; only fields the map lacks are locked
    vm.weatherLocked=(field)=>{const o=vm.weatherOwner(field);return o.startsWith('no ') || o.startsWith('not available');};
    // weather is optional: a server without the weather update must not lock the Track tab
    vm.trackLoaded=()=>!!vm.trackDraft?.level && (!vm.state.level || vm.trackDraft.level===vm.state.level) && Object.entries(trackFields).every(([g,keys])=>(g==='weather' && !vm.trackDraft.weather) || keys.every(k=>Number.isFinite(vm.trackDraft[g]?.[k])));
    vm.trackEditable=()=>vm.can('rules') && vm.state.serverBridgeReady===true && vm.trackLoaded();
    vm.trackWaiting=()=>vm.state.serverBridgeReady!==true?'Waiting for the BeamJoy-Revived plugin API (BJR 2.0 or newer, started with the server).':'Waiting for server track settings for the current map.';
    vm.setRubberLevel=()=>{if(Number.isFinite(vm.rubberLevel))vm.send('track',{amount:Math.round(Math.max(0,Math.min(100,vm.rubberLevel)))/100});};
    let carID,level,lastTrackData,lastRulesStatus,lastRuleData,lastNotice=0,lastOpen=0,lastReset,lastDiffApplied,lastMotorsport,lastDynoCar,lastDynoCurve,lastDynoRows;
    const offHistory=$rootScope.$on('RacePrepBJRHistory',(_,data)=>{
      $rootScope.$evalAsync(()=>{
        if(data.level && vm.state.level && data.level!==vm.state.level)return;
        vm.history={...data,items:Array.isArray(data.items)?data.items:[],records:data.records||{}};
        if(vm.historySelection && !vm.history.items.some(r=>vm.raceKey(r)===vm.historySelection))vm.historySelection=null;
      });
    });
    const off=$rootScope.$on('RacePrepBJRState',(_,state)=>{
      $rootScope.$evalAsync(()=>{
        vm.state=state;raceprepBadges.map=state.vehicleBadges||{};
        // BJR's menu rail (Motorsport page) asked to open a section
        if(state.openRequest && state.openRequest!==lastOpen){
          lastOpen=state.openRequest;vm.open=true;vm.full=!!state.openFull;vm.tab=state.tab||vm.tab;
          // BJR's menu rail: Race rules / Track & weather open their settings section
          if(vm.tab==='rules'){vm.tab='settings';vm.settingsSection='rules';}else if(vm.tab==='track'){vm.tab='settings';vm.settingsSection='track';}
          vm.syncNativeHUD();
        }
        if(state.resultNotice && state.resultNotice!==lastNotice){lastNotice=state.resultNotice;vm.historySelection=null;vm.open=true;vm.tab='results';vm.syncNativeHUD();vm.send('show',{value:true});}
        if(vm.open && vm.tab==='results' && state.serverBridgeReady && historyRequested!==state.level)vm.loadHistory();
        if(state.draftReset!==lastReset){lastReset=state.draftReset;vm.resetDraft();}
        if(carID!==state.car?.revision){carID=state.car?.revision;vm.resetDraft();vm.partChoices={};vm.tyres={};vm.fuel={};}
        // dyno: the curve before the last engine change on this car (another car: forget it)
        const dynoCar=String(state.car?.id)+':'+String(state.car?.model),dynoNow=state.engineCurves?.current;
        if(dynoCar!==lastDynoCar){lastDynoCar=dynoCar;vm.dynoBefore=null;lastDynoCurve=dynoNow?JSON.stringify(dynoNow):null;lastDynoRows=dynoNow;}
        else if(dynoNow){const sig=JSON.stringify(dynoNow);if(lastDynoCurve&&sig!==lastDynoCurve)vm.dynoBefore=lastDynoRows;lastDynoCurve=sig;lastDynoRows=dynoNow;}
        for(const row of list(state.variables)) if(vm.vars[row.name]===undefined) vm.vars[row.name]=vm.shown(row);
        for(const row of list(state.parts)){
          const k=vm.rowKey(row),c=vm.partChoices[k];
          if(c===undefined||!list(row.options).some(o=>o.name===c)) vm.partChoices[k]=row.current||'';
        }
        if(state.diffApplied!==lastDiffApplied){lastDiffApplied=state.diffApplied;vm.diff={};vm.diffDirty=false;}
        vm.loadDiff();
        for(const t of list(state.tyreControls))if(!vm.tyres[t.axle])vm.tyres[t.axle]={compound:t.compound,offset:t.offset};
        for(const t of list(state.fuelTanks))if(vm.fuel[t.name]===undefined)vm.fuel[t.name]=Math.round(t.energy/t.maxEnergy*100);
        const ruleData=JSON.stringify([state.level,state.ruleDefaults,state.ruleStore]);
        if(!vm.ruleDraft || ruleData!==lastRuleData || state.rulesStatus!==lastRulesStatus){vm.changeScope();lastRulesStatus=state.rulesStatus;lastRuleData=ruleData;}
        const track=state.control?.track;
        const trackData=JSON.stringify(track && {level:track.level,rubber:track.rubber,wind:track.wind,weather:track.weather});
        if(trackData!==lastTrackData || !vm.trackDraft){
          if(level!==track?.level){level=track?.level;vm.rubberLevel=state.rubberPeakPercent || 0;}
          vm.trackDraft=angular.copy(track);lastTrackData=trackData;
        }
        if(!vm.selectedRace && state.races?.length) vm.selectedRace=String(state.session?.raceId || state.races[0].id);
        // Motorsport settings draft and the weekend start form follow the server
        const msData=JSON.stringify(state.motorsport?.settings||null);
        if(msData!==lastMotorsport){lastMotorsport=msData;vm.msDraft=angular.copy(state.motorsport?.settings||null);
          const w=state.motorsport?.settings?.weekend||{};
          vm.weekendForm={raceID:vm.weekendForm.raceID||vm.selectedRace,practiceMinutes:w.practiceMinutes??10,qualifyingMinutes:w.qualifyingMinutes??10,gridOrder:w.gridOrder||'qualifying'};}
        if(!vm.weekendForm.raceID && vm.selectedRace)vm.weekendForm.raceID=vm.selectedRace;
        if(vm.tab==='rules'||vm.tab==='track'){vm.settingsSection=vm.tab;vm.tab='settings';}
        const sections=vm.visibleSections();if(sections.length && !sections.some(([id])=>id===vm.setupSection))vm.setupSection=sections[0][0];
      });
    });
    vm.$onInit=()=>{vm.send('refresh');openRaceRules();}; vm.$onDestroy=()=>{off();offHistory();offDriving();offHud();offOpenRules();document.body.classList.remove('raceprep-native-hud-replaced');};
  }
});

// One escaped, keyboard-accessible rating description for the summary and grid.
let ratingTipID=0;
mod.component('rpRating',{
  bindings:{entry:'<',status:'<'},
  template:`<span ng-if="!$ctrl.entry" class="rp-muted">{{$ctrl.status || 'Rating pending'}}</span><span ng-if="$ctrl.entry" class="rp-rating" tabindex="0" role="button" aria-label="{{$ctrl.description}}" aria-describedby="{{$ctrl.tipID}}" ng-mouseenter="$ctrl.show($event)" ng-mouseleave="$ctrl.visible=false" ng-focus="$ctrl.show($event)" ng-blur="$ctrl.visible=false" ng-keydown="$event.key==='Escape' &amp;&amp; ($ctrl.visible=false)"><b class="rp-rating-badge" ng-style="{'background-color':$ctrl.color}">{{$ctrl.entry.class || $ctrl.classOf($ctrl.entry.pi)}} {{$ctrl.entry.pi}}</b><small ng-if="$ctrl.entry.tuningPotentialPI"> +{{$ctrl.entry.tuningPotentialPI}} PI tuning potential</small><span role="tooltip" ng-if="$ctrl.visible" id="{{$ctrl.tipID}}" class="rp-rating-tooltip" ng-style="$ctrl.tipStyle">{{$ctrl.description}}</span></span>`,
  controller:function(){
    this.tipID='rp-rating-tip-'+(++ratingTipID);
    this.classOf=pi=>!Number.isFinite(pi)?'—':pi>=999?'X':pi>=901?'P':pi>=801?'R':pi>=701?'S':pi>=601?'A':pi>=501?'B':pi>=401?'C':pi>=301?'D':'E';
    this.$onChanges=()=>{
      const e=this.entry;if(!e){this.description='Rating pending';return;}
      const badge=n=>Number.isFinite(n)?this.classOf(n)+' '+n:'Pending';
      this.description=['General '+badge(e.pi),'Speed '+badge(e.pi_speed),'Technical '+badge(e.pi_technical),
        'Source: '+(e.source||'computed')+(e.anchored?' · anchored to stock':'')+(e.method?' · '+e.method:''),
        Number.isFinite(e.performancePI)?'Performance PI: '+e.performancePI:null,
        e.tuningPotentialPI?'+'+e.tuningPotentialPI+' PI tuning potential (included in displayed PI)':null,
        e.weightBonusPI?'+'+e.weightBonusPI+' PI race weight reduction bonus (included in displayed PI)':null,
        e.assumptions||'Sport mode, 40 kg fuel, warm KTS tyres',e.flag].filter(Boolean).join('\n');
      this.color=({E:'#6d7782',D:'#1484ad',C:'#847000',B:'#a94c00',A:'#b02028',S:'#7034a4',R:'#2f63e6',P:'#af2575',X:'#247c31'})[e.class||this.classOf(e.pi)];
    };
    this.show=event=>{
      const r=event.currentTarget.getBoundingClientRect();
      this.tipStyle={left:Math.max(8,Math.min(r.left,window.innerWidth-348))+'px'};
      if(window.innerHeight-r.bottom>240)this.tipStyle.top=(r.bottom+6)+'px';
      else this.tipStyle.bottom=(window.innerHeight-r.top+6)+'px';
      this.visible=true;
    };
  }
});

// Setup section as a Forza-style grid: one row per setting, front and rear
// side by side; single settings span both columns.
mod.component('rpPerformance',{
  bindings:{performance:'<',summary:'<',dirty:'<',compact:'<'},
  template:`<fieldset class="rp-perf rp-performance-sheet" ng-class="{'rp-performance-compact':$ctrl.compact}"><legend>Performance</legend>
<div class="rp-car-figures"><div><span>Power</span><b>{{$ctrl.summary.hp!==undefined?($ctrl.summary.hp | number:0)+' hp':'—'}}</b></div><div><span>Weight</span><b>{{$ctrl.summary.massKG!==undefined?($ctrl.summary.massKG | number:0)+' kg':'—'}}</b></div><div><span>Balance · front / rear</span><b ng-if="$ctrl.summary.frontShare!==undefined">{{$ctrl.summary.frontShare*100 | number:0}} / {{(1-$ctrl.summary.frontShare)*100 | number:0}} %</b><b ng-if="$ctrl.summary.frontShare===undefined">—</b></div></div>
<div class="rp-performance-groups"><div class="rp-performance-group" ng-repeat="g in $ctrl.groups"><h4>{{g.title}}</h4><div class="rp-performance-line" ng-repeat="r in g.rows track by r[0]"><span>{{r[1]}}</span><div><b ng-class="$ctrl.delta(r)===null?'':($ctrl.delta(r).better?'rp-better':'rp-worse')">{{$ctrl.value(r)}}<sup ng-if="$ctrl.performance.now.estimated[r[0]]" title="Estimate, not directly measured on the rig">*</sup></b><small ng-if="$ctrl.delta(r)!==null" ng-class="$ctrl.delta(r).better?'rp-better':'rp-worse'">{{$ctrl.delta(r).text}}</small></div></div></div></div>
<p class="rp-performance-caption">{{$ctrl.performance.now.measured?'Rig-anchored figures':'Estimates from car data'}}<span ng-if="!$ctrl.performance.now"> · waiting for performance data</span>. <span ng-if="$ctrl.dirty">Apply changes to update.</span><span ng-if="!$ctrl.dirty">Fitted car · changes shown versus previous setup.</span> Tuning never changes PI.</p></fieldset>`,
  controller:function(){
    this.groups=[{title:'Acceleration',rows:[['zeroTo60','0–60 mph','s'],['sixtyTo100','60–100 mph','s'],['topSpeed','Top speed','speed']]},
      {title:'Braking distance',rows:[['brake60','60–0 mph','dist'],['brake120','120–0 mph','dist']]},
      {title:'Lateral grip',rows:[['lat60','60 mph','g'],['lat120','120 mph','g']]}];
    this.value=r=>{
      const v=this.performance?.now?.[r[0]];if(!Number.isFinite(v))return '—';
      if(r[2]==='speed')return Math.round(v*(this.performance?.imperial?2.2369362921:3.6))+(this.performance?.imperial?' mph':' km/h');
      return r[2]==='s'?v.toFixed(1)+' s':r[2]==='g'?v.toFixed(2)+' g':this.performance?.imperial?Math.round(v*3.28084)+' ft':Math.round(v)+' m';
    };
    this.delta=r=>{
      const p=this.performance,a=p?.prev?.[r[0]],b=p?.now?.[r[0]];if(!Number.isFinite(a)||!Number.isFinite(b))return null;
      let d=b-a;if(r[2]==='dist' && p.imperial)d*=3.28084;
      if(r[2]==='speed'){d*=p.imperial?2.2369362921:3.6;if(Math.abs(d)<.5)return null;return {better:d>0,text:(d>0?'+':'−')+Math.abs(d).toFixed(0)+(p.imperial?' mph':' km/h')};}
      if(Math.abs(d)<(r[2]==='g'?.005:r[2]==='s'?.05:.5))return null;
      return {better:r[2]==='g'?d>0:d<0,text:(d>0?'+':'−')+(r[2]==='g'?Math.abs(d).toFixed(2)+' g':r[2]==='s'?Math.abs(d).toFixed(1)+' s':Math.abs(d).toFixed(0)+(p.imperial?' ft':' m'))};
    };
  }
});
mod.component('rpSetupGrid',{
  bindings:{pairs:'<',values:'=',onChange:'&',disabled:'<',note:'&?',onFocus:'&?'},
  template:`<div class="rp-setup-grid"><div class="rp-setup-head" ng-if="$ctrl.hasSides()"><span></span><b>Front</b><b>Rear</b></div>
<div class="rp-setup-row" ng-repeat="p in $ctrl.pairs track by p.key"><div class="rp-setup-label"><b>{{p.label | translate}}</b><b class="rp-changed" ng-if="$ctrl.changed(p)"> *</b><small class="rp-muted" ng-if="p.reason">🔒 {{p.reason}}</small></div>
<div class="rp-setup-cell" ng-repeat="v in p.cells track by v.name" ng-class="{'rp-span':!p.paired}" title="{{v.description | translate}}"><span class="rp-slider-control"><input type="range" rp-number-range ng-model="$ctrl.values[v.name]" min="{{v.displayMin===undefined?v.min:v.displayMin}}" max="{{v.displayMax===undefined?v.max:v.displayMax}}" step="{{v.displayStep || v.step || 0.01}}" ng-change="$ctrl.onChange()" ng-focus="$ctrl.onFocus({v:v})" ng-mouseenter="$ctrl.onFocus({v:v})" ng-disabled="!v.allowed || $ctrl.disabled" aria-label="{{v.title | translate}}"><output>{{$ctrl.format($ctrl.values[v.name],v)}}</output></span><small class="rp-muted"><span ng-if="v.default!==undefined">Stock {{$ctrl.format($ctrl.stock(v),v)}}</span><span class="rp-gear-note" ng-if="$ctrl.note &amp;&amp; $ctrl.note({v:v})"> · {{$ctrl.note({v:v})}}</span></small></div></div></div>`,
  controller:function(){
    this.format=setupFormat;this.stock=setupStock;
    this.hasSides=()=>(this.pairs||[]).some(p=>p.paired);
    this.changed=p=>p.cells.some(v=>Number.isFinite(this.values?.[v.name])&&Math.abs(this.values[v.name]-setupShown(v))>1e-7);
  }
});
// Gearing chart: engine rpm against road speed through the gears, shifting at
// the rev limit (Forza's gearing screen). Marks each shift point, the rpm the
// next gear drops to, and the engine's peak torque to peak power band, so a
// gear that drops below the band shows. Stock gearing is drawn faint behind.
mod.component('rpGearChart',{
  bindings:{rows:'<',values:'<',info:'<',revRow:'<',curves:'<'},
  template:`<div class="rp-gear-chart" ng-if="$ctrl.ok"><svg viewBox="0 0 640 250" role="img" aria-label="Gearing: engine rpm against speed with shift points, current and stock"><rect x="52" y="14" width="560" height="196" fill="#0006"/>
<rect class="rp-gear-band" ng-if="$ctrl.band" x="52" width="560" ng-attr-y="{{$ctrl.band.y}}" ng-attr-height="{{$ctrl.band.h}}"/>
<g class="rp-dyno-grid"><line ng-repeat="t in $ctrl.yTicks" x1="52" x2="612" ng-attr-y1="{{t.y}}" ng-attr-y2="{{t.y}}"/><line ng-repeat="t in $ctrl.xTicks" y1="14" y2="210" ng-attr-x1="{{t.x}}" ng-attr-x2="{{t.x}}"/></g>
<g class="rp-dyno-axis"><text ng-repeat="t in $ctrl.yTicks" x="46" ng-attr-y="{{t.y+4}}" text-anchor="end">{{t.label}}</text><text ng-repeat="t in $ctrl.xTicks" ng-attr-x="{{t.x}}" y="227" text-anchor="middle">{{t.v}}</text><text x="332" y="245" text-anchor="middle">{{$ctrl.unit}}</text><text x="12" y="112" text-anchor="middle" transform="rotate(-90 12 112)">rpm</text><text ng-if="$ctrl.band" class="rp-gear-band-label" x="606" ng-attr-y="{{$ctrl.band.y+12}}" text-anchor="end">power band</text></g>
<polyline class="rp-gear-stock" ng-attr-points="{{$ctrl.stockPath}}"/><polyline class="rp-gear-current" ng-attr-points="{{$ctrl.path}}"/>
<g ng-repeat="g in $ctrl.gears"><circle class="rp-gear-shift" r="4" ng-attr-cx="{{g.x}}" ng-attr-cy="{{$ctrl.topY}}"/><circle class="rp-gear-drop" ng-if="g.dropY" r="3.5" ng-attr-cx="{{g.x}}" ng-attr-cy="{{g.dropY}}"/><text class="rp-gear-label" ng-attr-x="{{g.labelX}}" ng-attr-y="{{$ctrl.topY-6}}" text-anchor="middle">{{g.n}}</text><text class="rp-gear-drop-label" ng-if="g.dropY" ng-attr-x="{{g.x+5}}" ng-attr-y="{{g.dropY+14}}">{{g.after | number:0}}</text></g></svg>
<table class="rp-gear-table"><tr><th>Gear</th><th>Ratio</th><th>Shift at</th><th>Top speed</th><th>Next gear starts at</th></tr><tr ng-repeat="g in $ctrl.gears" ng-class="{'rp-gear-low':g.low}"><td>{{g.n}}</td><td>{{g.ratio | number:2}}:1</td><td>{{$ctrl.rpm | number:0}} rpm</td><td>{{g.top | number:0}} {{$ctrl.unit}}</td><td>{{g.after?((g.after | number:0)+' rpm'+(g.low?' · below power band':'')):'—'}}</td></tr></table>
<small class="rp-muted">Solid: current gearing · faint dashed: stock · shaded: peak torque ({{$ctrl.band.torqueRpm | number:0}} rpm) to peak power ({{$ctrl.band.powerRpm | number:0}} rpm). Final drive {{$ctrl.fd | number:2}}:1. Top speeds are at the rev limit and ignore drag.</small></div>`,
  controller:function(){
    const X0=52,X1=612,Y0=210,Y1=14;let key;
    const sawtooth=(gears,fd,rpm,info,x,y)=>{
      const pts=[[0,0]];
      gears.forEach((g,i)=>{const top=Gearing.speed(rpm,g.ratio*fd,info);pts.push([top,rpm]);const next=gears[i+1];if(next)pts.push([top,rpm*next.ratio/g.ratio]);});
      return pts.map(p=>x(p[0]).toFixed(1)+','+y(p[1]).toFixed(1)).join(' ');
    };
    // peak torque and peak power rpm of the current engine curve
    const band=curves=>{
      const rows=(curves?.current||[]).filter(p=>Number.isFinite(p[0])&&Number.isFinite(p[1])&&p[0]>0);
      if(rows.length<2)return null;
      let t=rows[0],w=rows[0];for(const p of rows){if(p[1]>t[1])t=p;if(p[0]*p[1]>w[0]*w[1])w=p;}
      return t[0]<w[0]?{torqueRpm:t[0],powerRpm:w[0]}:null;
    };
    this.$doCheck=()=>{
      const info=this.info,rows=this.rows||[];
      if(!info||!(info.radius>0)){this.ok=false;key=undefined;return;}
      const cur={gears:Gearing.ratios(rows,this.values,info).filter(g=>g.ratio>0),fd:Gearing.final(rows,this.values,info),rpm:Gearing.rpm(this.revRow,this.values,info)};
      const stock={gears:Gearing.ratios(rows,this.values,info,true).filter(g=>g.ratio>0),fd:Gearing.final(rows,this.values,info,true),rpm:Gearing.rpm(this.revRow,this.values,info,true)};
      const pb=band(this.curves);
      const k=JSON.stringify([cur,stock,info,pb]);if(k===key)return;key=k;
      this.ok=cur.gears.length>0&&cur.fd>0&&cur.rpm>0;if(!this.ok)return;
      if(!(stock.gears.length&&stock.fd>0&&stock.rpm>0))stock.gears=[];
      const last=g=>Gearing.speed(g.rpm,g.gears[g.gears.length-1].ratio*g.fd,info);
      const vMax=Math.max(last(cur),stock.gears.length?last(stock):0)*1.05;
      const vStep=[10,20,25,50,100].find(s=>vMax/s<=10)||100,top=Math.ceil(vMax/vStep)*vStep;
      const rTop=Math.ceil(Math.max(cur.rpm,stock.rpm||0)*1.08/1000)*1000;
      const x=v=>X0+(X1-X0)*v/top,y=r=>Y0-(Y0-Y1)*r/rTop;
      this.unit=info.unit;this.rpm=cur.rpm;this.fd=cur.fd;this.topY=y(cur.rpm).toFixed(1);
      this.path=sawtooth(cur.gears,cur.fd,cur.rpm,info,x,y);
      this.stockPath=stock.gears.length?sawtooth(stock.gears,stock.fd,stock.rpm,info,x,y):'';
      this.band=pb&&{...pb,y:y(Math.min(pb.powerRpm,rTop)).toFixed(1),h:(y(pb.torqueRpm)-y(Math.min(pb.powerRpm,rTop))).toFixed(1)};
      let prevX=X0;
      this.gears=cur.gears.map((g,i)=>{
        const speed=Gearing.speed(cur.rpm,g.ratio*cur.fd,info),gx=x(speed),next=cur.gears[i+1];
        const after=next?cur.rpm*next.ratio/g.ratio:null;
        const row={n:g.n,ratio:g.ratio,top:speed,x:gx.toFixed(1),labelX:((prevX+gx)/2).toFixed(1),after,dropY:after?y(after).toFixed(1):null,low:!!(after&&pb&&after<pb.torqueRpm)};
        prevX=gx;return row;
      });
      this.xTicks=[];for(let v=0;v<=top;v+=vStep)this.xTicks.push({v,x:x(v).toFixed(1)});
      this.yTicks=[];const rStep=rTop>12000?2000:1000;for(let r=0;r<=rTop;r+=rStep)this.yTicks.push({label:r?(r/1000)+'k':'0',y:y(r).toFixed(1)});
    };
  }
});
// One dyno sheet: torque and power share a scale (so they cross at 5252 rpm,
// as on a real dyno), stock drawn faint behind the current curves.
mod.component('rpDyno',{
  // before: the curve before the last engine change on this car (dotted)
  bindings:{curves:'<',before:'<'},
  template:`<div class="rp-dyno" ng-if="$ctrl.ok"><div class="rp-dyno-head"><span><b class="rp-dyno-hp">{{$ctrl.cur.hp.peak | number:0}} hp</b> <small>@ {{$ctrl.cur.hp.rpm | number:0}} rpm</small> <small class="rp-dyno-delta" ng-class="{'rp-dyno-loss':$ctrl.delta.hp<0}" ng-if="$ctrl.delta.hp">{{$ctrl.delta.hp>0?'+':''}}{{$ctrl.delta.hp | number:0}} hp vs {{$ctrl.deltaRef}}</small></span><span><b class="rp-dyno-tq">{{$ctrl.cur.tq.peak | number:0}} lb-ft</b> <small>@ {{$ctrl.cur.tq.rpm | number:0}} rpm</small> <small class="rp-dyno-delta" ng-if="$ctrl.delta.tq">{{$ctrl.delta.tq>0?'+':''}}{{$ctrl.delta.tq | number:0}} vs stock</small></span></div>
<svg viewBox="0 0 640 270" role="img" aria-label="Dyno: torque and power against rpm, stock and current"><rect x="48" y="24" width="544" height="206" fill="#0006"/>
<g class="rp-dyno-grid"><line ng-repeat="t in $ctrl.yTicks" x1="48" x2="592" ng-attr-y1="{{t.y}}" ng-attr-y2="{{t.y}}"/><line ng-repeat="t in $ctrl.xTicks" y1="24" y2="230" ng-attr-x1="{{t.x}}" ng-attr-x2="{{t.x}}"/></g>
<g class="rp-dyno-axis"><text ng-repeat="t in $ctrl.yTicks" x="42" ng-attr-y="{{t.y+4}}" text-anchor="end">{{t.v}}</text><text ng-repeat="t in $ctrl.yTicks" x="598" ng-attr-y="{{t.y+4}}">{{t.v}}</text><text ng-repeat="t in $ctrl.xTicks" ng-attr-x="{{t.x}}" y="247" text-anchor="middle">{{t.label}}</text><text x="320" y="265" text-anchor="middle">rpm x 1000</text><text x="42" y="12" text-anchor="end">lb-ft</text><text x="598" y="12">hp</text></g>
<polyline class="rp-dyno-tq rp-dyno-stock" ng-attr-points="{{$ctrl.stock.tq.points}}"/><polyline class="rp-dyno-hp rp-dyno-stock" ng-attr-points="{{$ctrl.stock.hp.points}}"/>
<polyline class="rp-dyno-tq rp-dyno-before" ng-if="$ctrl.hasBefore" ng-attr-points="{{$ctrl.prev.tq.points}}"/><polyline class="rp-dyno-hp rp-dyno-before" ng-if="$ctrl.hasBefore" ng-attr-points="{{$ctrl.prev.hp.points}}"/>
<polyline class="rp-dyno-tq rp-dyno-current" ng-attr-points="{{$ctrl.cur.tq.points}}"/><polyline class="rp-dyno-hp rp-dyno-current" ng-attr-points="{{$ctrl.cur.hp.points}}"/>
<circle class="rp-dyno-tq" r="4" ng-attr-cx="{{$ctrl.cur.tq.x}}" ng-attr-cy="{{$ctrl.cur.tq.y}}"/><circle class="rp-dyno-hp" r="4" ng-attr-cx="{{$ctrl.cur.hp.x}}" ng-attr-cy="{{$ctrl.cur.hp.y}}"/></svg>
<small class="rp-muted"><b class="rp-dyno-tq">━ Torque</b> · <b class="rp-dyno-hp">━ Power</b> · <span ng-if="$ctrl.hasBefore">dotted: before your last change · </span><span ng-if="$ctrl.hasStock">faint dashed: stock · solid: current.</span><span ng-if="!$ctrl.hasStock">solid: current engine; stock reference unavailable.</span> Steady-state curve; turbo lag affects driving, not this curve.</small></div>`,
  controller:function(){
    const X0=48,X1=592,Y0=230,Y1=24;
    const nice=max=>[10,20,25,50,100,200,250,500,1000].find(s=>max/s<=8)||Math.ceil(max/8/1000)*1000;
    this.$onChanges=()=>{
      const clean=rows=>(rows||[]).filter(p=>Number.isFinite(p[0])&&Number.isFinite(p[1])&&p[0]>0).sort((a,b)=>a[0]-b[0]);
      const stock=clean(this.curves?.stock),current=clean(this.curves?.current),before=clean(this.before);
      this.hasStock=stock.length>1;this.ok=current.length>1;if(!this.ok)return;
      this.hasBefore=before.length>1;
      const tq=p=>p[1]*0.73756214928,hp=p=>p[0]*p[1]*Math.PI/30/745.699871582;
      const all=stock.concat(current,before);
      const rpmMax=Math.ceil(Math.max(...all.map(p=>p[0]))/1000)*1000;
      const vMax=Math.max(1,...all.map(tq),...all.map(hp));
      const step=nice(vMax*1.05),top=Math.ceil(vMax*1.05/step)*step;
      const x=r=>X0+(X1-X0)*r/rpmMax,y=v=>Y0-(Y0-Y1)*Math.max(0,v)/top;
      const curve=(rows,f)=>{let best=rows[0];for(const r of rows)if(f(r)>f(best))best=r;
        return {points:rows.map(r=>x(r[0]).toFixed(1)+','+y(f(r)).toFixed(1)).join(' '),peak:f(best),rpm:best[0],x:x(best[0]).toFixed(1),y:y(f(best)).toFixed(1)};};
      this.stock=this.hasStock?{tq:curve(stock,tq),hp:curve(stock,hp)}:{tq:{points:"",peak:0},hp:{points:"",peak:0}};this.cur={tq:curve(current,tq),hp:curve(current,hp)};
      this.prev=this.hasBefore?{tq:curve(before,tq),hp:curve(before,hp)}:null;
      // the change shown: against the curve before the last change when there is one, else stock
      const ref=this.prev||(this.hasStock?this.stock:null);this.deltaRef=this.prev?'before':'stock';
      this.delta=ref?{tq:Math.round(this.cur.tq.peak-ref.tq.peak),hp:Math.round(this.cur.hp.peak-ref.hp.peak)}:{tq:0,hp:0};
      this.yTicks=[];for(let v=0;v<=top;v+=step)this.yTicks.push({v,y:y(v).toFixed(1)});
      const rStep=rpmMax>12000?2000:1000;
      this.xTicks=[];for(let r=0;r<=rpmMax;r+=rStep)this.xTicks.push({label:r/1000,x:x(r).toFixed(1)});
    };
  }
});
mod.run(['$compile','$rootScope',function($compile,$rootScope){
  // BJR creates its root after a UI reload. Wait for its real components so
  // its own initial root-clear cannot remove the add-on, and remount safely.
  let current,scope;
  const mount=()=>{
    if(current && !current.isConnected && scope){scope.$destroy();scope=null;current=null;}
    const host=document.querySelector('beamjoy');
    if(!host || !host.querySelector('bj-main')) return;
    if(current && current.isConnected) return;
    if(scope) scope.$destroy();
    scope=$rootScope.$new();current=document.createElement('bj-race-prep');current.id='raceprep-bjr-root';host.appendChild(current);$compile(current)(scope);
  };
  // Wait until Angular has linked its initial root; manual compilation during
  // bootstrap otherwise constructs two controllers/listeners for this element.
  const timer=setInterval(mount,750);$rootScope.$evalAsync(mount);
  $rootScope.$on('$destroy',()=>{clearInterval(timer);if(scope && !scope.$$destroyed) scope.$destroy();});
}]);
export default mod;
