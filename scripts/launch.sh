#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/variables.sh"

if [[ -z $TMUX ]]; then
	exit 1
fi

if [[ $# -eq 1 ]]; then
	selected=$1
else
	project_paths="$(tmux show-option -gqv "@sessions-project-paths")"
	project_paths="${project_paths:-"~"}"
	IFS=';' read -r -a path_array <<<"$project_paths"

	for i in "${!path_array[@]}"; do
		if [[ ${path_array[i]} == ~* ]]; then
			path_array[i]="${path_array[i]/\~/$HOME}"
		fi
	done

	selected=$(find "${path_array[@]}" -mindepth 1 -maxdepth 1 \( -type d -o -xtype d \) | fzf)
fi

if [[ -z $selected ]]; then
	exit 0
fi

config_file="${selected:1}"
config_file="$CONFIG_DIR${config_file//\//.}.yaml"

if [[ -f "$config_file" ]]; then
	selected_name=$(yq -r '.name // ""' "$config_file")
fi

selected_name="${selected_name:-$(basename "$selected" | tr . _)}"

if ! tmux has-session -t="$selected_name" 2>/dev/null; then
	num_windows=0
	if [[ -f "$config_file" ]]; then
		num_windows=$(yq '.windows | length' "$config_file")
	fi

	if [[ $num_windows == 0 ]]; then
		tmux new-session -ds "${selected_name}" -c "${selected}"
	else
		for ((i = 0; i < num_windows; i++)); do
			name=$(yq -r ".windows[$i].name // \"\"" "$config_file")
			cmd=$(yq -r ".windows[$i].command // \"\"" "$config_file")
			path=$(yq -r ".windows[$i].path // \"\"" "$config_file")
			run_command=$(yq ".windows[$i].run" "$config_file")
			path="${path/\~/$HOME}"
			if [[ -n "$selected" && "${selected: -1}" != "/" ]]; then
				selected="${selected}/"
			fi
			if [[ "${path:0:1}" != "/" ]]; then
				path="${selected}${path}"
			fi

			window_path="$path"

			if [[ $i -eq 0 ]]; then
				if [[ -n "$name" ]]; then
					tmux new-session -ds "$selected_name" -c "${window_path}" -n "${name}"
				else
					tmux new-session -ds "$selected_name" -c "${window_path}"
				fi
			else
				if [[ -n "$name" ]]; then
					tmux new-window -t "$selected_name:" -c "${window_path}" -n "${name}"
				else
					tmux new-window -t "$selected_name:" -c "${window_path}"
				fi
			fi
			if [[ -n "${cmd}" ]]; then
				if [[ "$run_command" == "false" ]]; then
					tmux send-keys -t "${selected_name}" "${cmd}"
				else
					tmux send-keys -t "${selected_name}" "${cmd}" "C-m"
				fi
			fi
		done
		base_index=$(tmux show-option -gqv base-index)
		base_index=${base_index:-0}
		if [[ $num_windows != 1 ]]; then
			tmux select-window -t "${selected_name}:$((base_index + 1))"
		fi
		tmux select-window -t "${selected_name}:${base_index}"
	fi
fi
tmux switch-client -t "$selected_name"
