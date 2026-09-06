#!/usr/bin/env bash
# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  tui_config_parser.sh — Declarative YAML/JSON Layout Loader              ║
# ╚════════════════════════════════════════════════════════════════════════════╝

# ── Style State Mappings ──
declare -gA _TUI_STYLE_FG=()
declare -gA _TUI_STYLE_BG=()
declare -gA _TUI_STYLE_MOD=()

tui.load_config() {
    local config_file="$1"
    
    if ! command -v yq &> /dev/null; then
        tui.log.error "Error: 'yq' is required to parse the configuration."
        return 1
    fi

    if [[ ! -f "$config_file" ]]; then
        tui.log.error "tcpError: Configuration file not found at '$config_file'."
        return 1
    fi
    
    tui.log.info "Loading TUI configuration from '$config_file'..."

    # 1. Load Imports (Business Logic & Callbacks)
    local num_imports
    num_imports=$(yq '.imports | length' "$config_file")
    
    local root_dir="${TUI_PROJECT_ROOT:-$(pwd)}"

    local i # <--- Scoped loop counter
    for (( i=0; i<num_imports; i++ )); do
        local import_path
        import_path=$(yq -r ".imports[$i]" "$config_file")
        
        local full_path="${root_dir}/${import_path#./}"
        
        if [[ -f "$full_path" ]]; then
            source "$full_path"
        else
            tui.log.warn "Warning: Import not found: $full_path"
        fi
    done

    # 2. Begin Layout Recursion
    _tui_parse_node "$config_file" ".layout" "root"
}

_tui_parse_style() {
    local file="$1" path="$2" widget_id="$3" state="$4"
    local style_key="${widget_id}_${state}"

    local fg
    fg=$(yq -r "${path}.fg // \"\"" "$file")
    local bg
    bg=$(yq -r "${path}.bg // \"\"" "$file")
    
    [[ -n "$fg" && "$fg" != "null" ]] && _TUI_STYLE_FG["$style_key"]="$fg"
    [[ -n "$bg" && "$bg" != "null" ]] && _TUI_STYLE_BG["$style_key"]="$bg"

    local num_mods
    num_mods=$(yq "${path}.modifiers | length" "$file" 2>/dev/null || echo 0)
    local mod_str=""
    
    local j # <--- Scoped loop counter
    for (( j=0; j<num_mods; j++ )); do
        local mod
        mod=$(yq -r "${path}.modifiers[$j]" "$file")
        mod_str+="${mod} "
    done
    [[ -n "$mod_str" ]] && _TUI_STYLE_MOD["$style_key"]="${mod_str% }"
}

_tui_parse_node() {
    local file="$1" path="$2" parent_id="$3"
    tui.log.debug "Parsing node at path '$path' with parent ID '$parent_id'..."
    
    local type
    type=$(yq -r "${path}.type" "$file")
    local id
    id=$(yq -r "${path}.id" "$file")

    local i # <--- Scoped loop counter for all loops in this function

    if [[ "$type" == "hsplit" || "$type" == "vsplit" ]]; then
        local num_children
        num_children=$(yq "${path}.children | length" "$file")
        local split_args=()
        
        for (( i=0; i<num_children; i++ )); do
            local cid
            cid=$(yq -r "${path}.children[$i].id" "$file")
            local cwt
            cwt=$(yq -r "${path}.children[$i].weight" "$file")
            split_args+=("${cid}:${cwt}")
        done
        
        "tui.${type}" "$id" "${split_args[@]}"

        for (( i=0; i<num_children; i++ )); do
            _tui_parse_node "$file" "${path}.children[$i]" "$id"
        done
        
    elif [[ "$type" == "pane" ]]; then
        local title
        title=$(yq -r "${path}.title // \"\"" "$file")
        local border
        border=$(yq -r "${path}.border // \"single\"" "$file")
        
        [[ -n "$title" && "$title" != "null" ]] && tui.pane_title "$id" "$title"
        tui.pane_border "$id" "$border"

        _tui_parse_style "$file" "${path}.title_style" "$id" "title"
        _tui_parse_style "$file" "${path}.border_style" "$id" "border"

        local num_widgets
        num_widgets=$(yq "${path}.widgets | length" "$file" 2>/dev/null || echo 0)
        
        for (( i=0; i<num_widgets; i++ )); do
            local wpath="${path}.widgets[$i]"
            local wtype
            wtype=$(yq -r "${wpath}.type" "$file")
            local wid
            wid=$(yq -r "${wpath}.id" "$file")
            local wrow
            wrow=$(yq -r "${wpath}.row" "$file")
            
            _tui_parse_style "$file" "${wpath}.style" "$wid" "normal"
            _tui_parse_style "$file" "${wpath}.focus_style" "$wid" "focus"

            if [[ "$wtype" == "label" ]]; then
                local text
                text=$(yq -r "${wpath}.text" "$file")
                tui.label "$wid" "$id" "$wrow" "$text"
                
            elif [[ "$wtype" == "button" ]]; then
                local text
                text=$(yq -r "${wpath}.text" "$file")
                local action
                action=$(yq -r "${wpath}.action" "$file")
                tui.button "$wid" "$id" "$wrow" "$text" "$action"
                
            elif [[ "$wtype" == "input" ]]; then
                local label
                label=$(yq -r "${wpath}.label // \"\"" "$file")
                local ph
                ph=$(yq -r "${wpath}.placeholder // \"\"" "$file")
                local action
                action=$(yq -r "${wpath}.action // \"\"" "$file")
                
                [[ "$label" == "null" ]] && label=""
                [[ "$ph" == "null" ]] && ph=""
                
                tui.input "$wid" "$id" "$wrow" "$ph" "$label"
                [[ -n "$action" && "$action" != "null" ]] && tui.on_action "$wid" "$action"
            fi
        done
        tui.log.debug "Pane '$id' parsed with $num_widgets widgets."
    fi
}