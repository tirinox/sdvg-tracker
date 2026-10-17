#!/bin/zsh
# Daily install on the iPhone: a free Personal Team build stops opening after 7 days.
# launchd runs this every hour (and on wake); the first try of the day that finds the
# phone installs the app, later tries that day do nothing. The app isn't launched.
#
#   scripts/ios-daily.sh on | off | status    (run with no argument = one try)

label=com.tirinox.sdvgtracker.daily-install
plist=~/Library/LaunchAgents/$label.plist
# The main checkout, even when called from a worktree that may be gone tomorrow
repo=${$(git -C "${0:A:h}" rev-parse --path-format=absolute --git-common-dir):h}
log=$repo/ios/build/daily-install.log
stamp=$repo/ios/build/daily-install.stamp

case $1 in
on)
	mkdir -p $repo/ios/build
	cat > $plist <<-EOF
	<?xml version="1.0" encoding="UTF-8"?>
	<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
	<plist version="1.0">
	<dict>
		<key>Label</key><string>$label</string>
		<key>ProgramArguments</key>
		<array><string>/bin/zsh</string><string>$repo/scripts/ios-daily.sh</string></array>
		<key>StartInterval</key><integer>3600</integer>
		<key>RunAtLoad</key><true/>
		<key>StandardOutPath</key><string>$log</string>
		<key>StandardErrorPath</key><string>$log</string>
	</dict>
	</plist>
	EOF
	launchctl bootout gui/$UID/$label 2>/dev/null
	launchctl bootstrap gui/$UID $plist && echo "On: hourly tries, one install a day. Log: $log"
	;;
off)
	launchctl bootout gui/$UID/$label 2>/dev/null
	rm -f $plist && echo "Off"
	;;
status)
	launchctl print gui/$UID/$label >/dev/null 2>&1 && echo "On" || echo "Off"
	echo "Last install: $(cat $stamp 2>/dev/null || echo never)"
	;;
*)
	today=$(date +%F)
	[[ "$(cat $stamp 2>/dev/null)" == $today ]] && exit 0
	echo "== $(date '+%F %T')"
	# Xcode reuses a cached profile until it expires, so a daily install alone still runs out
	# on day 7. Drop the app's profiles two days early and the build fetches fresh ones.
	for f in ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision(N); do
		p=$(security cms -D -i $f 2>/dev/null) || continue
		[[ $(plutil -extract Name raw - <<< $p) == *com.tirinox.sdvgtracker* ]] || continue
		exp=$(date -ju -f %Y-%m-%dT%H:%M:%SZ $(plutil -extract ExpirationDate raw - <<< $p) +%s)
		(( exp - $(date +%s) < 2 * 86400 )) && rm -f $f && echo "Profile expires soon, renewing: ${f:t}"
	done
	make -C $repo --no-print-directory ios-install IOS_LAUNCH=0 && echo $today > $stamp
	;;
esac
