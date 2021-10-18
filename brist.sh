#!/bin/sh
# shellcheck disable=SC2154 disable=SC2034 disable=SC1090

root=$(dirname "$(readlink -f "$0")")
work=/tmp/brist-$(date +%F-%T | tr ' :' '--')

[ -f /etc/.brist-setup.sh ] && setup=/etc/.brist-setup.sh
[ -f ~/.brist-setup.sh ] && setup=~/.brist-setup.sh
[ ! "$setup" ] && setup=${root}/veth-setup.sh

. "$root"/lib.sh

waitlink()
{
	for i in $(seq 10); do
	    link="$(ip -br link show dev "$1" | awk '{ print($2); }')"

	    [ "$link" = "UP" ] && return 0;

	    sleep 0.5
	done

	return 1
}

origo()
{
    ip link del dev "$br0" type bridge >/dev/null 2>&1
    ip link del dev "$br1" type bridge >/dev/null 2>&1

    for port in $ports; do
	ip link set dev "$port" nomaster
	ip link set dev "$port" up
    done

    for port in $ports; do
	waitlink "$port" || die "No link on $port"
    done
}

mkdir -p "$work" || die "unable to create $work"

[ -f "$setup" ] || die "Missing setup $setup"
. "$setup"
br0=${br0:-brist0}
br1=${br1:-brist1}

bports="$b1 $b2 $b3 $b4"
hports="$h1 $h2 $h3 $h4"
ports="$bports $hports"

for suite in "$root"/suite/*.sh; do
    . "$suite"
done

results="$work/test-results.txt"
if [ -z "$BRIST_TEST" ]; then
    printf "\e[7mbrist: running suite, log at %s\e[0m\n" "$results"    | tee $results
else
    printf "\e[7mbrist: %s, log at %s\e[0m\n" "$BRIST_TEST" "$results" | tee $results
fi

sum_pass=0
sum_skip=0
sum_fail=0
sum_total=0

for t in $(echo "$alltests" | tr ' ' '\n' | grep -E "$BRIST_TEST"); do
    t_work=$work/$t
    t_outp=$t_work/output
    t_current=$t
    t_step=Setup
    t_status=2

    mkdir -p "$t_work"
    origo

    # silent output by default, unless running a single test
    if [ -z "$BRIST_TEST" ]; then
	printf "\e[1m%s:\e[0m started at %s\n" "$t" "$(date)" > "$t_outp"
	$t >> "$t_outp" 2>&1 || { step explicit return; t_status=2; }
    else
	printf "\e[1m%s:\e[0m started at %s\n" "$t" "$(date)"
	$t || { step explicit return; t_status=2; }
    fi
    case $t_status in
	0)
	    sum_pass=$((sum_pass + 1))
	    printf "\e[32mPASS\e[0m: %s\n" "$t"           | tee -a "$t_outp"
	    ;;
	1)
	    sum_skip=$((sum_skip + 1))
	    printf "\e[33mSKIP\e[0m: %s - $t_step\n" "$t" | tee -a "$t_outp"
	    ;;
	2)
	    sum_fail=$((sum_fail + 1))
	    printf "\e[31mFAIL\e[0m: %s - $t_step\n" "$t" | tee -a "$t_outp"
	    ;;
    esac

    sum_total=$((sum_total + 1))
    cat "$t_outp" >> "$results"
    echo >> "$results"
done

printf "============================================================================\n" | tee -a "$results"
printf "Test suite summary:\n"                  | tee -a "$results"
printf "  TOTAL: %d\n" $sum_total               | tee -a "$results"
if [ $sum_pass -ne 0 ]; then
    printf "  \e[32mPASS:  %d\e[0m\n" $sum_pass | tee -a "$results"
else
    printf "  PASS:  0\n"                       | tee -a "$results"
fi
if [ $sum_skip -ne 0 ]; then
    printf "  \e[33mSKIP:  %d\e[0m\n" $sum_skip | tee -a "$results"
else
    printf "  SKIP:  0\n"                       | tee -a "$results"
fi
if [ $sum_fail -ne 0 ]; then
    printf "  \e[31mFAIL:  %d\e[0m\n" $sum_fail | tee -a "$results"
else
    printf "  FAIL:  0\n"                       | tee -a "$results"
fi
printf "============================================================================\n" | tee -a "$results"

[ $sum_fail -eq 0 ] || exit 1
