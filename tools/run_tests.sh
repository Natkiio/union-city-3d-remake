#!/bin/sh
# Imports the project to catch parse errors, then runs every tests/test_*.gd
# headless. Prints one line per test file and exits non-zero if any fail.
cd "$(dirname "$0")/.." || exit 1
godot --headless --path . --import --quit >/tmp/uc_import.log 2>&1
if grep -q "SCRIPT ERROR\|Parse Error" /tmp/uc_import.log; then
	echo "IMPORT ERRORS:"; grep "SCRIPT ERROR\|Parse Error" -A2 /tmp/uc_import.log | head -30; exit 1
fi
failed=0
for t in tests/test_*.gd; do
	[ "$t" = "tests/test_base.gd" ] && continue
	out=$(godot --headless --path . -s "$t" 2>&1)
	summary=$(echo "$out" | grep "^=== ")
	if echo "$out" | grep -q "^\[FAIL\]\|SCRIPT ERROR\|Parse Error" || [ -z "$summary" ]; then
		echo "FAIL $t  ${summary:-no summary}"; echo "$out" | grep "^\[FAIL\]\|SCRIPT ERROR\|Parse Error" -A2 | head -12
		failed=1
	else
		echo "ok   $t  $summary"
	fi
done
exit $failed
