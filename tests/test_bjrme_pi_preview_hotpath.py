from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_workshop_snapshot_never_compiles_preview_ratings():
    source = (ROOT / "client/lua/ge/extensions/raceprepBJR.lua").read_text()
    snapshot = source.split("M.snapshot=function()", 1)[1].split("actions.draft=function", 1)[0]
    for forbidden in ("previewRating", "previewTree", "loadJbeam", "previewTick"):
        assert forbidden not in snapshot


def test_saved_preview_setting_remains_explicitly_opt_in():
    source = (ROOT / "client/ui/modModules/raceprepBJR/raceprepBJR.js").read_text()
    assert "vm.piPreview=false;try{vm.piPreview=localStorage.getItem('raceprep.piPreview')==='true';" in source
    assert "state.piPreviewGate?.passed" not in source



def test_preview_compiler_has_no_ui_or_update_loop_entry_point():
    backend = (ROOT / "client/lua/ge/extensions/raceprepBJR.lua").read_text()
    ratings = (ROOT / "client/lua/ge/extensions/raceprepRatings.lua").read_text()
    assert "previewRating" not in backend and "previewTree" not in backend
    update = ratings.split("function M.onUpdate(dt)", 1)[1].split("function M.onClientEndMission", 1)[0]
    assert "previewTick" not in update
    assert "function M.previewRating" not in ratings
    assert "actions.quickClass=function()" in backend
    assert "Rating upgrades are not available yet." in backend
