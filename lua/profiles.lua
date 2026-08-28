-- Applies the monitor arrangement of the active profile, and keeps it right
-- when screens come and go.
--
-- Load it from ~/.config/hypr/monitors.lua, after the generic fallback rule:
--
--   dofile(os.getenv("HOME")
--     .. "/.config/omarchy/plugins/themo.monitor-profiles/lua/profiles.lua")
--
-- The bar widget only records *which* profile is active and asks Hyprland to
-- reload; this file is what actually puts the screens where they belong. So a
-- profile survives a reload, a relogin and a reboot, and the Hyprland config
-- stays the one place that decides what is on screen.
--
-- Everything here fails quietly. A missing helper or an unreadable profile
-- means Hyprland falls through to its own rules, which is a working desktop --
-- an error thrown out of this file would be a black screen.

local ok = pcall(function()
  if type(hl) ~= "table" or type(hl.monitor) ~= "function" then return end

  -- Resolve the helper next to this file, so the plugin still works when it
  -- lives somewhere other than the default plugin directory.
  local source = debug.getinfo(1, "S").source
  local dir = source:sub(1, 1) == "@" and source:sub(2):match("^(.*)/lua/[^/]+$") or nil
  if not dir then return end

  local helper = "'" .. (dir .. "/bin/monitor-profiles"):gsub("'", "'\\''") .. "'"
  local pipe = io.popen(helper .. " emit 2>/dev/null")
  if not pipe then return end

  local numeric = { scale = true, transform = true }
  local hotplug = false

  for line in pipe:lines() do
    -- Directive lines carry settings rather than a monitor.
    local directive, value = line:match("^!([%w_]+)=(.*)$")
    if directive then
      if directive == "hotplug" then hotplug = value == "1" end
    else
      local spec = {}
      for field in line:gmatch("[^\t]+") do
        local key, raw = field:match("^([%w_]+)=(.*)$")
        if key then
          if key == "disabled" then
            spec.disabled = true
          elseif numeric[key] then
            spec[key] = tonumber(raw) or raw
          else
            spec[key] = raw
          end
        end
      end
      if spec.output then hl.monitor(spec) end
    end
  end

  pipe:close()

  -- ------------------------------------------------------------- hotplug
  -- Plugging a monitor in changes which profile "auto" should resolve to, but
  -- nothing re-reads the config on its own. These two events do.
  --
  -- This file runs again on every reload, and the reload is exactly what the
  -- hook triggers, so subscriptions would otherwise pile up and each hotplug
  -- would fire one more reload than the last. Old ones are removed first.
  if type(hl.on) ~= "function" then return end

  for _, subscription in ipairs(_G.__monitor_profiles_hooks or {}) do
    pcall(function() subscription:remove() end)
  end
  _G.__monitor_profiles_hooks = {}

  if not hotplug then return end

  -- The helper decides whether a reload is actually warranted and serialises
  -- the events a dock fires all at once, so the callback stays a fire and
  -- forget: blocking the compositor here would stall the whole desktop.
  local command = helper .. " sync"

  for _, event in ipairs({ "monitor.added", "monitor.removed" }) do
    local subscribed, subscription = pcall(hl.on, event, function()
      pcall(hl.exec_cmd, command)
    end)
    if subscribed and subscription then
      table.insert(_G.__monitor_profiles_hooks, subscription)
    end
  end
end)

-- Nothing to recover from, but leave a trace in the Hyprland log rather than
-- silently doing nothing at all.
if not ok then
  io.stderr:write("themo.monitor-profiles: could not apply the active profile\n")
end
