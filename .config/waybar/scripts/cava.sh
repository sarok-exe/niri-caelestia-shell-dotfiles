#!/bin/bash
cava -p "$HOME/.config/cava/config-waybar" | while read -r line; do
    IFS=';' read -ra vals <<< "$line"
    bars=""
    for v in "${vals[@]}"; do
        v="${v//[!0-9]/}"
        if [ "$v" -gt 80 ]; then bars+="█"
        elif [ "$v" -gt 60 ]; then bars+="▓"
        elif [ "$v" -gt 40 ]; then bars+="▒"
        elif [ "$v" -gt 20 ]; then bars+="░"
        else bars+=" "
        fi
    done
    echo "{\"text\":\" $bars\"}"
done
