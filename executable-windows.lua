script_path = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
dofile(script_path .. "executable-windows-lib/executable-windows-main.lua")
