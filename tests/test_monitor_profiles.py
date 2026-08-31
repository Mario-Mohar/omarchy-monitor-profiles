"""Tests for the monitor-profiles helper.

The two pieces of real judgement in this script are which profile a set of
plugged-in outputs should select, and how a name somebody typed becomes an id
that `use`, the IPC target and monitors.lua can all address. Everything else is
sanitising a file that is expected to be hand-edited, where the contract is
that nothing raises and nothing bad reaches Hyprland.
"""

import json
import os

import pytest

# --------------------------------------------------------------------------
# sanitize: a hand-edited file is the normal case
# --------------------------------------------------------------------------

def test_sanitize_falls_back_to_defaults_for_nonsense(mp):
    default_ids = [p["id"] for p in mp.blank_config()["profiles"]]
    assert default_ids, "the fixture assumes there are shipped profiles"
    for junk in (None, [], "text", 42, {"profiles": "not a list"}):
        config = mp.sanitize(junk)
        assert [p["id"] for p in config["profiles"]] == default_ids
        assert config["active"] == mp.AUTO


def test_sanitize_keeps_a_good_profile(mp):
    config = mp.sanitize({"profiles": [
        {"id": "desk", "name": "Desk", "match": ["DP-1"], "monitors": []}
    ]})
    assert [p["id"] for p in config["profiles"]] == ["desk"]
    assert config["profiles"][0]["name"] == "Desk"


def test_sanitize_drops_a_profile_with_an_illegal_id(mp):
    config = mp.sanitize({"profiles": [
        {"id": "Desk Upstairs"},        # spaces and capitals
        {"id": ""},                     # empty
        {"id": "x" * 40},               # too long
        {"id": "ok"},
    ]})
    assert [p["id"] for p in config["profiles"]] == ["ok"]


def test_sanitize_drops_a_duplicate_id(mp):
    config = mp.sanitize({"profiles": [{"id": "desk"}, {"id": "desk"}]})
    assert len(config["profiles"]) == 1


def test_sanitize_refuses_auto_as_a_profile_id(mp):
    # "auto" is the reserved value of the `active` field, not a profile.
    config = mp.sanitize({"profiles": [{"id": mp.AUTO}, {"id": "desk"}]})
    assert [p["id"] for p in config["profiles"]] == ["desk"]


def test_sanitize_caps_the_number_of_profiles(mp):
    config = mp.sanitize({"profiles": [{"id": "p%d" % n} for n in range(50)]})
    assert len(config["profiles"]) == mp.MAX_PROFILES


def test_sanitize_names_an_unnamed_profile_after_its_id(mp):
    config = mp.sanitize({"profiles": [{"id": "desk", "name": "   "}]})
    assert config["profiles"][0]["name"] == "desk"


def test_sanitize_clips_a_long_name(mp):
    config = mp.sanitize({"profiles": [{"id": "desk", "name": "n" * 200}]})
    assert len(config["profiles"][0]["name"]) == mp.MAX_NAME


def test_sanitize_drops_illegal_output_names_from_match(mp):
    config = mp.sanitize({"profiles": [
        {"id": "desk", "match": ["DP-1", "not a name", 7, None, "HDMI-A-1"]}
    ]})
    assert config["profiles"][0]["match"] == ["DP-1", "HDMI-A-1"]


def test_an_empty_profile_list_is_respected(mp):
    """Deleting your last profile must not bring the shipped ones back.

    A list that merely held nothing usable still falls through to the defaults,
    which is what makes a mangled file recoverable. An explicitly empty one is
    a decision.
    """
    assert mp.sanitize({"profiles": []})["profiles"] == []
    assert mp.sanitize({"profiles": [{"id": "!!"}]})["profiles"] != []


def test_active_falls_back_to_auto_when_it_names_nothing(mp):
    config = mp.sanitize({"profiles": [{"id": "desk"}], "active": "gone"})
    assert config["active"] == mp.AUTO


def test_active_is_kept_when_it_names_a_profile(mp):
    config = mp.sanitize({"profiles": [{"id": "desk"}], "active": "desk"})
    assert config["active"] == "desk"


def test_hotplug_defaults_to_on_and_only_false_turns_it_off(mp):
    assert mp.sanitize({})["hotplug"] is True
    assert mp.sanitize({"hotplug": False})["hotplug"] is False
    assert mp.sanitize({"hotplug": "no"})["hotplug"] is True


# --------------------------------------------------------------------------
# sanitize_monitors
# --------------------------------------------------------------------------

def test_monitors_need_a_legal_output_name(mp):
    monitors = mp.sanitize_monitors([{"output": "DP-1"}, {"output": "a b"}, {}, "x"])
    assert [m["output"] for m in monitors] == ["DP-1"]


def test_a_disabled_monitor_carries_nothing_else(mp):
    monitors = mp.sanitize_monitors([
        {"output": "DP-1", "disabled": True, "mode": "1920x1080", "scale": 2}
    ])
    assert monitors == [{"output": "DP-1", "disabled": True}]


def test_monitor_strings_are_kept_and_clipped(mp):
    monitors = mp.sanitize_monitors([
        {"output": "DP-1", "mode": "2560x1440@144", "position": "0x0", "mirror": "e" * 100}
    ])
    assert monitors[0]["mode"] == "2560x1440@144"
    assert monitors[0]["position"] == "0x0"
    assert len(monitors[0]["mirror"]) == 48


def test_scale_and_transform_must_be_numbers(mp):
    monitors = mp.sanitize_monitors([
        {"output": "DP-1", "scale": 1.5, "transform": 1},
        {"output": "DP-2", "scale": "big", "transform": True},
    ])
    assert monitors[0]["scale"] == 1.5 and monitors[0]["transform"] == 1
    # True is an int in Python, and would otherwise sail through as transform=1
    assert "scale" not in monitors[1] and "transform" not in monitors[1]


def test_monitor_count_is_capped(mp):
    monitors = mp.sanitize_monitors([{"output": "DP-%d" % n} for n in range(40)])
    assert len(monitors) == mp.MAX_MONITORS


# --------------------------------------------------------------------------
# auto_pick: the most specific profile that fits wins
# --------------------------------------------------------------------------

def config_with(mp, profiles):
    return mp.sanitize({"profiles": profiles})


def test_auto_pick_prefers_the_most_specific_match(mp):
    config = config_with(mp, [
        {"id": "laptop", "match": ["eDP-1"]},
        {"id": "desk", "match": ["eDP-1", "DP-1", "DP-2"]},
        {"id": "home", "match": ["eDP-1", "DP-1"]},
    ])
    picked = mp.auto_pick(config, ["eDP-1", "DP-1", "DP-2"])
    assert picked["id"] == "desk"


def test_auto_pick_ignores_a_profile_missing_an_output(mp):
    config = config_with(mp, [
        {"id": "laptop", "match": ["eDP-1"]},
        {"id": "desk", "match": ["eDP-1", "DP-1", "DP-2"]},
    ])
    assert mp.auto_pick(config, ["eDP-1", "DP-1"])["id"] == "laptop"


def test_auto_pick_does_not_depend_on_save_order(mp):
    profiles = [
        {"id": "desk", "match": ["eDP-1", "DP-1"]},
        {"id": "laptop", "match": ["eDP-1"]},
    ]
    forwards = mp.auto_pick(config_with(mp, profiles), ["eDP-1", "DP-1"])
    backwards = mp.auto_pick(config_with(mp, list(reversed(profiles))), ["eDP-1", "DP-1"])
    assert forwards["id"] == backwards["id"] == "desk"


def test_a_profile_matching_nothing_in_particular_is_the_last_resort(mp):
    config = config_with(mp, [
        {"id": "fallback", "match": []},
        {"id": "desk", "match": ["DP-1"]},
    ])
    assert mp.auto_pick(config, ["eDP-1"])["id"] == "fallback"
    assert mp.auto_pick(config, ["DP-1"])["id"] == "desk"


def test_auto_pick_is_none_when_nothing_fits(mp):
    config = config_with(mp, [{"id": "desk", "match": ["DP-1"]}])
    assert mp.auto_pick(config, ["eDP-1"]) is None


def test_effective_honours_an_explicitly_chosen_profile(mp):
    config = mp.sanitize({
        "profiles": [{"id": "desk", "match": ["DP-1"]}, {"id": "laptop", "match": []}],
        "active": "desk",
    })
    # Chosen by hand, so it wins even though its output is not plugged in.
    assert mp.effective(config, connected=["eDP-1"])["id"] == "desk"


def test_effective_falls_back_to_auto_pick(mp):
    config = mp.sanitize({"profiles": [{"id": "laptop", "match": ["eDP-1"]}]})
    assert mp.effective(config, connected=["eDP-1"])["id"] == "laptop"


# --------------------------------------------------------------------------
# derive_id
# --------------------------------------------------------------------------

@pytest.mark.parametrize("name, expected", [
    ("Desk", "desk"),
    ("Office upstairs", "office-upstairs"),
    ("Büro", "buro"),
    ("Straße", "strasse"),
    ("   spaced   out   ", "spaced-out"),
    ("Two--dashes", "two-dashes"),
    ("---", "setup"),
    ("", "setup"),
    ("🖥️", "setup"),
])
def test_derive_id_makes_an_addressable_id(mp, name, expected):
    assert mp.derive_id(name, set()) == expected


def test_derive_id_is_always_legal(mp):
    for name in ["Desk", "Büro", "", "---", "x" * 200, "🖥️ 🖥️"]:
        assert mp.ID_RE.match(mp.derive_id(name, set()))


def test_derive_id_avoids_a_taken_id(mp):
    assert mp.derive_id("Desk", {"desk"}) == "desk-2"
    assert mp.derive_id("Desk", {"desk", "desk-2"}) == "desk-3"


def test_derive_id_keeps_a_suffixed_id_within_the_length_limit(mp):
    taken = {"a" * 32}
    candidate = mp.derive_id("a" * 200, taken)
    assert len(candidate) <= 32
    assert mp.ID_RE.match(candidate)


def test_derive_id_gives_up_rather_than_looping_forever(mp):
    taken = {"desk"} | {"desk-%d" % n for n in range(2, 100)}
    assert mp.derive_id("Desk", taken) == ""


# --------------------------------------------------------------------------
# load and save
# --------------------------------------------------------------------------

def test_load_returns_defaults_when_there_is_no_file(mp):
    assert mp.load()["profiles"] == mp.blank_config()["profiles"]


def test_load_survives_a_broken_file(mp):
    os.makedirs(mp.CONFIG_DIR, exist_ok=True)
    with open(mp.CONFIG_PATH, "w") as handle:
        handle.write("{ this is not json")
    assert mp.load()["profiles"] == mp.blank_config()["profiles"]


def test_save_then_load_round_trips(mp):
    config = mp.sanitize({"profiles": [{"id": "desk", "name": "Desk", "match": ["DP-1"]}],
                          "active": "desk"})
    mp.save(config)
    again = mp.load()
    assert again["active"] == "desk"
    assert [p["id"] for p in again["profiles"]] == ["desk"]


def test_save_leaves_no_temporary_behind(mp):
    mp.save(mp.blank_config())
    assert os.listdir(mp.CONFIG_DIR) == ["profiles.json"]


def test_save_writes_readable_json(mp):
    mp.save(mp.sanitize({"profiles": [{"id": "desk", "name": "Büro"}]}))
    with open(mp.CONFIG_PATH) as handle:
        assert json.load(handle)["profiles"][0]["name"] == "Büro"
