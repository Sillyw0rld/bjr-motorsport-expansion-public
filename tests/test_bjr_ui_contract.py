from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return (ROOT / path).read_text()


def test_challenge_buttons_have_text_labels_and_rotation_action():
    js = read("client/ui/modModules/raceprepBJR/raceprepBJR.js")
    html = read("client/ui/modModules/raceprepBJR/raceprep.html")
    assert "Start daily challenge" in js
    assert "Start weekly challenge" in js
    assert "vm.send('rivalsStart',{rotation:p.id})" in js
    assert "{{$ctrl.challengeStartLabel(p)}}" in html
    assert "Start {{p.kind}}" not in html


def test_shared_tune_round_trip_does_not_replace_installed_parts():
    ge = read("client/lua/ge/extensions/raceprepBJR.lua")
    html = read("client/ui/modModules/raceprepBJR/raceprep.html")
    start = ge.index("actions.libraryLoad=function(p)")
    end = ge.index("actions.enginePackage=function(p)", start)
    load = ge[start:end]
    assert "actions.sharedTunes=function(p)" in ge
    assert "action:'publish'" in html and "action:'download'" in html
    assert "payload.entry=e" in ge
    assert "sharedTunePending=='publish'" in ge
    assert "core_vehicle_partmgmt.setConfigVars" in load
    assert "setPartsConfig" not in load
    assert "installed upgrades stay fitted" in html


def test_crew_create_validates_and_shows_server_feedback():
    js = read("client/ui/modModules/raceprepBJR/raceprepBJR.js")
    html = read("client/ui/modModules/raceprepBJR/raceprep.html")
    assert "vm.createCrew=()=>" in js
    assert "vm.crewAction('create')" in js
    assert "Use a crew tag with 2–4 letters or numbers." in js
    assert "$ctrl.createCrew()" in html
    assert "{{$ctrl.state.rulesStatus}}" in html
    assert "vm.localMessage=''" in js


def test_preset_restrictions_are_shown_and_lobby_name_uses_bjr_public_api():
    js = read("client/ui/modModules/raceprepBJR/raceprepBJR.js")
    html = read("client/ui/modModules/raceprepBJR/raceprep.html")
    server = read("server/RacePrep/RacePrep.lua")
    assert "vm.rulesSummary=r=>" in js
    assert "Vehicle: '+r.specModel" in js
    assert "PI: '+(lo??'no minimum')" in js
    assert "Enforced entry rules:" in html
    assert "Enforced when drivers press Ready:" in html
    assert "name=presetLobbyLabel(selected)" in server
    assert "bjrApi.call('race.open'" in server

