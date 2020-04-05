--print(script_path)

obs           = obslua
source_name   = ""
group_name    = ""

activated     = false
ignore_names  = nil
ignore_expressions = nil

custom_properties = false
capture_method = 0
window_match_priority = 1
capture_cursor = true
compatibility = false
client_area = true

hotkey_id     = obs.OBS_INVALID_HOTKEY_ID

custom_window_capture_properties = {"method", "priority", "cursor", "compatibility", "client_area"}

function get_window_data(window)
	local window_reverse = string.reverse(window)
	local executable = nil
	local title = nil
	
	local exe_sep = string.find(window_reverse, ':', 1, true)
	if exe_sep ~= nil and exe_sep > 1 then
		local name_sep = string.find(window_reverse, ':', exe_sep+1, true)
		executable = string.reverse(string.sub(window_reverse, 1, exe_sep-1))
		
		if name_sep ~= nil then
			title = string.reverse(string.sub(window_reverse, name_sep+1))
			--print("Source Executable: " .. executable .. "  |  Source Title: " .. title)
		end
	end
	
	return executable, title
end

function capure_process_windows()
	local source = obs.obs_get_source_by_name(source_name)
	if source ~= nil then
		local settings = obs.obs_source_get_settings(source)
		--print(obs.obs_data_get_json(settings))
		local window = obs.obs_data_get_string(settings, "window")
		
		if window ~= nil then
			local executable, title = get_window_data(window)
			if executable ~= nil and title ~= nil then
				capture_process_windows_of(source, executable, title)
			end
		end
		
		obs.obs_data_release(settings)
		obs.obs_source_release(source)
	end
end

function is_title_ignored(title)
	if ignore_names ~= nil then
		local ignore_count = obs.obs_data_array_count(ignore_names)
		for idx = 0, ignore_count-1 do
			local ignore_item = obs.obs_data_array_item(ignore_names, idx)
			local ignore_name = obs.obs_data_get_string(ignore_item, "value")
			if ignore_name == title then
				return true
			end
		end
	end
	
	if ignore_expressions ~= nil then
		local ignore_exp_count = obs.obs_data_array_count(ignore_expressions)
		for idx = 0, ignore_exp_count-1 do
			local ignore_item = obs.obs_data_array_item(ignore_expressions, idx)
			local ignore_exp = obs.obs_data_get_string(ignore_item, "value")
			if string.find(title, ignore_exp) ~= nil then
				return true
			end
		end
	end
	
	return false
end

function is_window_captured(window)
	local sources = obs.obs_enum_sources()
	local found_match = false
	
	if sources ~= nil then
		for _, source in ipairs(sources) do
			local source_id = obs.obs_source_get_unversioned_id(source)
			if source_id == "window_capture" then
				local settings = obs.obs_source_get_settings(source)
				local source_window = obs.obs_data_get_string(settings, "window")
				
				if source_window == window then
					obs.obs_data_release(settings)
					found_match = true
					break
				end
				obs.obs_data_release(settings)
			end
		end
	end
	
	obs.source_list_release(sources)
	return found_match
end

function position_relative(scene_item, relative_to_source)
	relative_to_w = obs.obs_source_get_width(relative_to_source)
	relative_to_h = obs.obs_source_get_height(relative_to_source)

	local pos = obs.vec2()
	pos.x = relative_to_w / 2
	pos.y = relative_to_h / 2
	
	obs.obs_sceneitem_set_pos(scene_item, pos)
end

function add_capture_source(source, scene_source, scene, window, title, grp_item)
	local sub_win = obs.obs_source_duplicate(source, title, false)
	local settings = obs.obs_source_get_settings(sub_win)
	
	-- set data
	obs.obs_data_set_string(settings, "window", window)
	if custom_properties then
		obs.obs_data_set_int(settings, "priority", window_match_priority)
		obs.obs_data_set_int(settings, "method", capture_method)
		obs.obs_data_set_bool(settings, "compatibility", compatibility)
		obs.obs_data_set_bool(settings, "cursor", capture_cursor)
		obs.obs_data_set_bool(settings, "client_area", client_area)
	end
	
	-- init scene item
	local scene_item = obs.obs_scene_add(scene, sub_win)
	
	obs.obs_source_update(sub_win, settings)
	obs.obs_data_release(settings)
	
	obs.obs_sceneitem_defer_update_begin(scene_item)
	obs.obs_sceneitem_set_alignment(scene_item, 0)
	
	if grp_item ~= nil then
		grp_source = obs.obs_sceneitem_get_source(grp_item)
		
		obs.obs_sceneitem_defer_group_resize_begin(scene_item)
		obs.obs_sceneitem_set_alignment(grp_item, 0)

		position_relative(scene_item, grp_source)
		position_relative(grp_item, scene_source)
		
		obs.obs_sceneitem_group_add_item(grp_item, scene_item)
		obs.obs_sceneitem_defer_group_resize_end(scene_item)
		
		obs.obs_sceneitem_set_order(scene_item, obs.OBS_ORDER_MOVE_TOP)
	else
		position_relative(scene_item, scene_source)
	end
	
	obs.obs_sceneitem_defer_update_end(scene_item)
	
	-- release
	--obs.obs_sceneitem_release(scene_item)
	obs.obs_source_release(sub_win)
end

function capture_process_windows_of(source, executable, title)
	local scene_source = obs.obs_frontend_get_current_scene()
	local scene = obs.obs_scene_from_source(scene_source)
	
	local source_props = obs.obs_source_properties(source)
	local window_prop = obs.obs_properties_get(source_props, "window")
	local window_count = obs.obs_property_list_item_count(window_prop)
	local grp_item = nil
	
	if group_name ~= nil and string.len(group_name) > 0 then
		grp_item = obs.obs_scene_get_group(scene, group_name)
	end
	
	for idx=0, window_count-1 do
		local window = obs.obs_property_list_item_string(window_prop, idx)
		if window ~= nil then
			local current_executable, current_title = get_window_data(window)
			if current_executable ~= nil and current_executable == executable 
			and current_title ~= nil and current_title ~= title 
			and not is_window_captured(window) and not is_title_ignored(current_title) then
				add_capture_source(source, scene_source, scene, window, current_title, grp_item)
			end
		end
	end
	
	-- release
	if grp_item ~= nil then
		--obs.obs_sceneitem_release(grp_item)
	end
	obs.obs_scene_release(scene)
	--obs.obs_source_release(scene_source)
end

function timer_callback()
	capure_process_windows()
end

function activate(activating)
	if activated == activating then
		return
	end

	activated = activating

	if activating then
		obs.timer_add(timer_callback, 500)
	else
		obs.timer_remove(timer_callback)
	end
end

-- Called when a source is activated/deactivated
function activate_signal(cd, activating)
	local source = obs.calldata_source(cd, "source")
	if source ~= nil then
		local name = obs.obs_source_get_name(source)
		if (name == source_name) then
			activate(activating)
		end
	end
end

function source_activated(cd)
	activate_signal(cd, true)
end

function source_deactivated(cd)
	activate_signal(cd, false)
end

function reset(pressed)
	if not pressed then
		return
	end

	activate(false)
	local source = obs.obs_get_source_by_name(source_name)
	if source ~= nil then
		local active = obs.obs_source_active(source)
		obs.obs_source_release(source)
		activate(active)
	end
end

function reset_button_clicked(props, p)
	reset(true)
	return false
end

----------------------------------------------------------

function redraw_properties(props, property, data)
	print("HII")
	init_script_properties(props)
end

function toggle_custom_source_properties(props, property, data)
	local use_custom_prop = obs.obs_properties_get(props, "custom_properties")
	local use_custom = custom_properties
	local sn_prop = obs.obs_properties_get(props, "source")
	local sn = source_name
	local source_set = false
	local source_props = nil
	local source = nil

	if sn ~= nil and string.len(sn) > 0 then
		source = obs.obs_get_source_by_name(sn)
		if source ~= nil then
			source_id = obs.obs_source_get_unversioned_id(source)
			if source_id == "window_capture" then
				source_props = obs.obs_source_properties(source)
				source_set = true
			end
		end
	end
	
	obs.obs_property_set_enabled(use_custom_prop, source_set)
	
	local source_props_count = table.getn(custom_window_capture_properties)
	for idx=1, source_props_count do
		local prop_name = custom_window_capture_properties[idx]
		local p = obs.obs_properties_get(props, prop_name)
		if p == nil and source_set then
			print("AAAAH")
			p = copy_property(prop_name, source_props, props)
		end
		
		obs.obs_property_set_enabled(p, use_custom)
		obs.obs_property_set_visible(p, source_set)
	end
	
	obs.obs_source_release(source)
	
	return true
end

function init_script_properties(props)
	local capture = obs.obs_properties_add_list(props, "source", "Window Capture", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
	local grp = obs.obs_properties_add_list(props, "sub_group", "Sub Window Group", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
	local sources = obs.obs_enum_sources()
	
	if sources ~= nil then
		for _, source in ipairs(sources) do
			source_id = obs.obs_source_get_unversioned_id(source)
			if source_id == "window_capture" then
				local name = obs.obs_source_get_name(source)
				obs.obs_property_list_add_string(capture, name, name)
			elseif source_id == "group" then
				local name = obs.obs_source_get_name(source)
				obs.obs_property_list_add_string(grp, name, name)
			end
		end
	end
	obs.source_list_release(sources)
	
	
	
	obs.obs_properties_add_editable_list(props, "ignore_names", "Ignore Window Titles", obs.OBS_EDITABLE_LIST_TYPE_STRINGS, "", "")
	obs.obs_properties_add_editable_list(props, "ignore_expressions", "Ignore Window Title Expressions", obs.OBS_EDITABLE_LIST_TYPE_STRINGS, "", "")
	
	local custom_props = obs.obs_properties_add_bool(props, "custom_properties", "Use Custom Window Capture Properties")
	
	obs.obs_property_set_modified_callback(custom_props, toggle_custom_source_properties)
	obs.obs_property_set_modified_callback(capture, toggle_custom_source_properties)
	
	--local cap_cursor = obs.obs_properties_add_bool(props, "capture_cursor", "Capture Cursor")
	--local comapat = obs.obs_properties_add_bool(props, "compatibility", "Multi-adapter Compatibility")
	--local cap_method = obs.obs_properties_add_list(props, "capture_method", "Capture Method", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
	--local match_prior = obs.obs_properties_add_list(props, "match_priority", "Window Match Priority", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
	--local cl_area = obs.obs_properties_add_bool(props, "client_area", "Client Area")
	--local source_props = obs.obs_get_source_properties("window_capture") -- CRASHES FOR SOME REASON
	-- THIS IS THE WORKAROUND FOR IT
	if source_name ~= nil and string.len(source_name) > 0 then
		local source = obs.obs_get_source_by_name(source_name)
		if source ~= nil then
			local source_props = obs.obs_source_properties(source)
			local source_props_count = table.getn(custom_window_capture_properties)
			
			--copy_property("window", source_props, props)
			for idx=1, source_props_count do
				local prop_name = custom_window_capture_properties[idx]
				local p = copy_property(prop_name, source_props, props)
			end
			
			--method_prop = copy_property("method", source_props, props)
			--priority_prop = copy_property("priority", source_props, props)
			--cursor_prop = copy_property("cursor", source_props, props)
			--compatibility_prop = copy_property("compatibility", source_props, props)
			--client_area_prop = copy_property("client_area", source_props, props)
			
			obs.obs_source_release(source)
		end
	end
	
	
end

function copy_property(property_name, from_properties, to_properties)
	local from_property = obs.obs_properties_get(from_properties, property_name)
	local prop_type = obs.obs_property_get_type(from_property)
	local prop_description = obs.obs_property_description(from_property)
	
	local to_property = nil	

    if prop_type == obs.OBS_PROPERTY_INVALID then
		return nil
    elseif prop_type == obs.OBS_PROPERTY_BOOL then
		to_property = obs.obs_properties_add_bool(to_properties, property_name, prop_description)
		
    elseif prop_type == obs.OBS_PROPERTY_INT then
		local int_min = obs.obs_property_int_min(from_property)
		local int_max = obs.obs_property_int_max(from_property)
		local int_step = obs.obs_property_int_step(from_property)
		local int_type = obs.obs_property_int_type(from_property)
		
		if int_type == obs.OBS_NUMBER_SLIDER then
			to_property = obs.obs_properties_add_int_slider(to_properties, property_name, prop_description, int_min, int_max, int_step)
		else -- elseif int_type == obs.OBS_NUMBER_SCROLLER then
			to_property = obs.obs_properties_add_int(to_properties, property_name, prop_description, int_min, int_max, int_step)
		end
		
    elseif prop_type == obs.OBS_PROPERTY_FLOAT then
		local float_min = obs.obs_property_float_min(from_property)
		local float_max = obs.obs_property_float_max(from_property)
		local float_step = obs.obs_property_float_step(from_property)
		local float_type = obs.obs_property_float_type(from_property)
		
		if float_type == obs.OBS_NUMBER_SLIDER then
			to_property = obs.obs_properties_add_float_slider(to_properties, property_name, prop_description, float_min, float_max, float_step)
		else -- elseif float_type == obs.OBS_NUMBER_SCROLLER then
			to_property = obs.obs_properties_add_float(to_properties, property_name, prop_description, float_min, float_max, float_step)
		end
		
    elseif prop_type == obs.OBS_PROPERTY_TEXT then
		local text_type = obs.obs_property_text_type(from_property)
		to_property = obs.obs_properties_add_text(to_properties, property_name, prop_description, text_type)
		
    elseif prop_type == obs.OBS_PROPERTY_PATH then
		local path_type = obs.obs_property_path_type(from_property)
		local path_filter = obs.obs_property_path_filter(from_property)
		local default_path = obs.obs_property_path_default_path(from_property)
		to_property = obs.obs_properties_add_path(to_properties, property_name, prop_description, path_type, path_filter, default_path)
		
    elseif prop_type == obs.OBS_PROPERTY_LIST then --or prop_type == obs.OBS_PROPERTY_EDITABLE_LIST then
		local list_type = obs.obs_property_list_type(from_property)
		local list_format = obs.obs_property_list_format(from_property)
		to_property = obs.obs_properties_add_list(to_properties, property_name, prop_description, list_type, list_format)
		
		if to_property ~= nil then
			local list_count = obs.obs_property_list_item_count(from_property)
			for idx=0, list_count-1 do
				local list_item_name = obs.obs_property_list_item_name(from_property, idx)
				local list_item_disabled = obs.obs_property_list_item_disabled(from_property, idx)
				
				if list_format == obs.OBS_COMBO_FORMAT_INT then
					local int_item = obs.obs_property_list_item_int(from_property, idx)
					obs.obs_property_list_add_int(to_property, list_item_name, int_item)
				elseif list_format == obs.OBS_COMBO_FORMAT_FLOAT then
					local float_item = obs.obs_property_list_item_float(from_property, idx)
					obs.obs_property_list_add_float(to_property, list_item_name, float_item)
				elseif list_format == obs.OBS_COMBO_FORMAT_STRING then
					local string_item = obs.obs_property_list_item_string(from_property, idx)
					obs.obs_property_list_add_string(to_property, list_item_name, string_item)
				end
				
				if list_item_disabled then
					obs.obs_property_list_item_disable(to_property, idx)
				end
			end
		end
		
    elseif prop_type == obs.OBS_PROPERTY_COLOR then
		to_property = obs.obs_properties_add_color(to_properties, property_name, prop_description)
		
    elseif prop_type == obs.OBS_PROPERTY_BUTTON then
		-- maybe ignore buttons as they probably make no sense in this context
		--to_property = obs.obs_properties_add_button(to_properties, property_name, prop_description)
		
    elseif prop_type == obs.OBS_PROPERTY_FONT then
		to_property = obs.obs_properties_add_font(to_properties, property_name, prop_description)
		
    elseif prop_type == obs.OBS_PROPERTY_FRAME_RATE then
		to_property = obs.obs_properties_add_frame_rate(to_properties, property_name, prop_description)
		
	end
	
	if to_property ~= nil then
		local visible = obs.obs_property_visible(from_property)
		local enabled = obs.obs_property_enabled(from_property)
		
		--obs.obs_property_set_visible(to_property, visible)
		obs.obs_property_set_enabled(to_property, custom_properties)
	end
	
	return to_property
end

----------------------------------------------------------

-- A function named script_properties defines the properties that the user
-- can change for the entire script module itself
function script_properties()
	local props = obs.obs_properties_create()
	init_script_properties(props)
	return props
end

function redraw_properties(props, property, data)
	print("HII")
	init_script_properties(props)
end

-- A function named script_description returns the description shown to
-- the user
function script_description()
	return "Automatically generates sources for subwindows of a window capture source."
end

-- A function named script_update will be called when settings are changed
function script_update(settings)
	activate(false)
	source_name = obs.obs_data_get_string(settings, "source")
	group_name = obs.obs_data_get_string(settings, "sub_group")
	ignore_names = obs.obs_data_get_array(settings, "ignore_names")
	ignore_expressions = obs.obs_data_get_array(settings, "ignore_expressions")
	custom_properties = obs.obs_data_get_bool(settings, "custom_properties")
	
	capture_method = obs.obs_data_get_int(settings, "method")
	window_match_priority = obs.obs_data_get_int(settings, "priority")
	capture_cursor = obs.obs_data_get_bool(settings, "cursor")
	compatibility = obs.obs_data_get_bool(settings, "compatibility")
	client_area = obs.obs_data_get_bool(settings, "client_area")
	
	reset(true)
end

-- A function named script_defaults will be called to set the default settings
function script_defaults(settings)
	--obs.obs_data_set_default_int(settings, "duration", 5)
	--obs.obs_data_set_default_string(settings, "stop_text", "Starting soon (tm)")
end

-- A function named script_save will be called when the script is saved
--
-- NOTE: This function is usually used for saving extra data (such as in this
-- case, a hotkey's save data).  Settings set via the properties are saved
-- automatically.
function script_save(settings)
	--local hotkey_save_array = obs.obs_hotkey_save(hotkey_id)
	--obs.obs_data_set_array(settings, "reset_hotkey", hotkey_save_array)
	--obs.obs_data_array_release(hotkey_save_array)
end

-- a function named script_load will be called on startup
function script_load(settings)
	-- Connect hotkey and activation/deactivation signal callbacks
	--
	-- NOTE: These particular script callbacks do not necessarily have to
	-- be disconnected, as callbacks will automatically destroy themselves
	-- if the script is unloaded.  So there's no real need to manually
	-- disconnect callbacks that are intended to last until the script is
	-- unloaded.
	local sh = obs.obs_get_signal_handler()
	obs.signal_handler_connect(sh, "source_activate", source_activated)
	obs.signal_handler_connect(sh, "source_deactivate", source_deactivated)

	-- hotkey_id = obs.obs_hotkey_register_frontend("reset_timer_thingy", "Reset Timer", reset)
	-- local hotkey_save_array = obs.obs_data_get_array(settings, "reset_hotkey")
	-- obs.obs_hotkey_load(hotkey_id, hotkey_save_array)
	-- obs.obs_data_array_release(hotkey_save_array)
end