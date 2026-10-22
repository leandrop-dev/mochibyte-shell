VERBOSE=0
if [[ "${1:-}" == "--verbose" ]]; then
    VERBOSE=1
fi

if command -v hyprctl &>/dev/null; then
    if [ "$VERBOSE" -eq 1 ]; then
        out=$(hyprctl monitors 2>/dev/null | awk '/^Monitor /{name=$2; got_mode=0} !got_mode && /^[[:space:]]+[0-9]+x[0-9]+@[0-9.]+/{split($1,a,"@"); printf "%s|%s|%.2f\n", name, a[1], a[2]; got_mode=1}')
    else
        out=$(hyprctl monitors 2>/dev/null | awk '/^Monitor /{print $2}')
    fi
    if [ -n "$out" ]; then
        echo "$out"
        exit 0
    fi
fi

if command -v wlr-randr &>/dev/null; then
    if [ "$VERBOSE" -eq 1 ]; then
        out=$(wlr-randr 2>/dev/null | awk '/^[a-zA-Z0-9-]+ /{name=$1} /current/{dim=""; fps="60.00"; for(i=1;i<=NF;i++){if($i~/^[0-9]+x[0-9]+$/) dim=$i; if($(i+1)=="Hz") fps=$i}; if(name!="" && dim!=""){printf "%s|%s|%.2f\n", name, dim, fps; name=""}}')
    else
        out=$(wlr-randr 2>/dev/null | awk '/^[a-zA-Z0-9-]+ /{print $1}')
    fi
    if [ -n "$out" ]; then
        echo "$out"
        exit 0
    fi
fi

if command -v xrandr &>/dev/null; then
    if [ "$VERBOSE" -eq 1 ]; then
        out=$(xrandr --query 2>/dev/null | awk '/ connected/{name=$1; dim=""; for(i=1;i<=NF;i++){if($i~/^[0-9]+x[0-9]+\+[0-9]+\+[0-9]+$/){split($i,p,"+"); dim=p[1]}}} /^\s+[0-9]+x[0-9]+/ && /\*/{if(dim=="") dim=$1; fps="60.00"; for(i=1;i<=NF;i++){if($i~/\*/){v=$i; gsub(/[\*+]/,"",v); fps=v}}; if(name!=""){printf "%s|%s|%.2f\n", name, dim, fps; name=""}}')
    else
        out=$(xrandr --query 2>/dev/null | awk '/ connected/{print $1}')
    fi
    if [ -n "$out" ]; then
        echo "$out"
        exit 0
    fi
fi

for status in /sys/class/drm/card*-*/status; do
    if [ -f "$status" ] && [ "$(cat "$status")" = "connected" ]; then
        dev=$(dirname "$status")
        name=$(basename "$dev")
        name="${name#card*-}"
        if [ "$VERBOSE" -eq 1 ]; then
            if [ -f "$dev/modes" ]; then
                mode=$(head -n 1 "$dev/modes")
                echo "$name|$mode|60.00"
            else
                echo "$name|Unknown|60.00"
            fi
        else
            echo "$name"
        fi
    fi
done
