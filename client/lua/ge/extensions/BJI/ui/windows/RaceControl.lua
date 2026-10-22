-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local Text, TooltipText = require("ge/extensions/raceprep/safeText").Text, require("ge/extensions/raceprep/safeText").TooltipText
local director=require('ge/extensions/raceprep/director')
local championshipName='Race Prep Championship'
local W={name='RaceControl',minSize=ImVec2(720,110),maxSize=ImVec2(1100,900),
 flags={BJI.Utils.Style.WINDOW_FLAGS.NO_COLLAPSE}}
-- opened from the Race Prep menu only (it used to pop up during races; the
-- yellow flag and start lights are in the race HUD)
W.getState=function() return director.show==true end
W.onClose=function() director.show=false end
W.body=function()
 local c=BJI.Utils.Style.TEXT_COLORS
 require('ge/extensions/raceprep/raceSignals').draw()
 if director.adminStatus then Text(director.adminStatus,{color=director.adminStatus:find('^Not saved') and c.ERROR or c.SUCCESS,wrap=true}) end
 local series=director.data and director.data.championship
 if series then
  Separator();Text(series.name or 'Championship',{color=c.HIGHLIGHT})
  Text(string.format('%s - round %d / %d',series.status or '',math.min(series.round or 1,series.totalRounds or 0),series.totalRounds or 0))
  local nextRound=series.rounds and series.rounds[series.round]
  if nextRound then Text('Next: '..tostring(nextRound.name)..' ('..tostring(nextRound.level)..')',{color=c.HIGHLIGHT}) end
  if BeginTable('rp-series-standings',{{label='Pos'},{label='Driver'},{label='Points'},{label='Wins'},{label='Races'}},
    {showHeader=true,flags={TABLE_FLAGS.ALTERNATE_ROW_BG,TABLE_FLAGS.SIZING_STRETCH_PROP}}) then
   for _,row in ipairs(series.rows or {}) do
    TableNewRow();Text(tostring(row.position));TableNextColumn();Text(row.name or '?')
    TableNextColumn();Text(tostring(row.points));TableNextColumn();Text(tostring(row.wins));TableNextColumn();Text(tostring(row.races))
   end
   EndTable()
  end
  Text(series.linkTournament and 'Rounds score only while BeamJoy tournament mode is enabled.' or 'Every listed round scores when it is raced, in any order.',{color=c.DISABLED,wrap=true})
 end
 local rubber=require("ge/extensions/raceprep/rubberLine").statusText()
 if rubber then Text(rubber,{color=c.DISABLED,wrap=true}) end
 local wind=require("ge/extensions/raceprep/raceEnvironment").status
 if wind then Text(wind,{color=c.DISABLED,wrap=true}) end
 local profiles=director.data and director.data.driverStats or {}
 if #profiles>0 and BeginTree('Driver statistics / safety rating') then
  if BeginTable('rp-driver-stats',{{label='Driver'},{label='Safety /5'},{label='Races'},{label='Wins'},
   {label='Laps'},{label='Contacts'},{label='Distance km'}},{showHeader=true,flags={TABLE_FLAGS.ALTERNATE_ROW_BG,TABLE_FLAGS.SIZING_STRETCH_PROP}}) then
   for _,p in ipairs(profiles) do
    TableNewRow();Text(p.name or '?');TableNextColumn();Text(string.format('%.2f%s',p.safety or 3,p.provisional and ' ?' or ''))
    TableNextColumn();Text(tostring(p.races or 0));TableNextColumn();Text(tostring(p.wins or 0))
    TableNextColumn();Text(tostring(p.laps or 0));TableNextColumn();Text(tostring(p.contacts or 0))
    TableNextColumn();Text(string.format('%.1f',p.kilometres or 0))
   end
   EndTable()
  end
  Text('Contact incidents count without assigning fault. ? = fewer than five races. Client-reported telemetry.',{color=c.DISABLED,wrap=true})
  EndTree()
 end
 if director.show and Button('rp-control-hide','Hide',{btnStyle=BJI.Utils.Style.BTN_PRESETS.WARNING}) then director.show=false end
 local prep=rawget(_G,'BJI_Win_RacePrep')
 if prep and prep.canEditRules and prep.canEditRules() then
  Separator();Text('Championship controls (admin)',{color=c.HIGHLIGHT})
  if InputText then local name=InputText('rp-series-name',championshipName,{width=300});if name then championshipName=name end end
  if Button('rp-series-create','New championship - BeamJoy tournament',{btnStyle=BJI.Utils.Style.BTN_PRESETS.INFO}) then
   director.championship('create',{name=championshipName,linkTournament=false})
  end
  SameLine()
  if Button('rp-series-start','Start scheduled championship',{btnStyle=BJI.Utils.Style.BTN_PRESETS.SUCCESS}) then director.championship('start') end
  if Button('rp-series-stop','Stop championship',{btnStyle=BJI.Utils.Style.BTN_PRESETS.WARNING}) then director.championship('stop') end
  if Button('rp-call-yellow','Call full-course yellow',{btnStyle=BJI.Utils.Style.BTN_PRESETS.WARNING}) then director.adminYellow(true) end
  SameLine()
  if Button('rp-clear-yellow','Clear yellow',{btnStyle=BJI.Utils.Style.BTN_PRESETS.SUCCESS}) then director.adminYellow(false) end
 end
end
return W
