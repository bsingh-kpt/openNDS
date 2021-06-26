#!/bin/sh
#Copyright (C) The openNDS Contributors 2004-2021
#Copyright (C) BlueWave Projects and Services 2015-2021
#This software is released under the GNU GPL license.
#
# WARNING - shebang "sh" is for compatiblity with busybox ash (eg on OpenWrt)
# This is changed to "bash" automatically by Makefile for generic Linux
#

########################################################################
# WARNING - DO NOT edit this file unless you know what you are doing!	#
#									#
# WARNING - DO NOT delete or rename this file				#
########################################################################

# Customisation of the sequence of portal pages will normally be done in a corresponding themespec file.
# This script imports a themespec file for defining the dynamically generated portal sequence presented to the client
# The themespec file to be imported is defined in the openNDS config file

#
# Modes are selected in the openNDS config using the login_option_enabled parameter.
#
# Mode 0. login_option_enabled set to 0 - Default if FAS Disabled.
# Mode 1. login_option_enabled set to 1 - generate a simple "click to continue" portal sequence page (with Terms of Service).
# Mode 2. login_option_enabled set to 2 - generate a "username/email_address portal sequence page (with Terms of Service).
# Mode 3. login_option_enabled set to 3 - use themespec to generate a portal sequence page.
# Mode > 3. Reserved for customisation and future enhancement.

# functions:

# Download external file
webget() {
	fetch=$(type -t uclient-fetch)

	if [ -z "$fetch" ]; then
		wret="wget -t 1 -T 1"
	else
		wret="uclient-fetch -T 1"
	fi
}

# Get custom image files
get_image_file() {
	webget
	imagename=$1
	shelldetect=$(head -1 "/usr/lib/opennds/libopennds.sh")

	if [ "$shelldetect" = "#!/bin/sh" ]; then
		setcontents=$(set)
		imageurl=$(echo "$setcontents" | grep "$imagename='" | awk -F"'" '{print $2}')
	else
		set -o posix
		setcontents=$(set)
		set +o posix
		imageurl=$(echo "$setcontents" | grep "$imagename=" | awk -F"$imagename=" '{print $2}' | awk -F", " 'NR==1{print $1}')

	fi

	setcontents=""

	customimageroot="/ndsremote"
	customimagepath="/etc/opennds/htdocs$customimageroot"

	if [ ! -d "$mountpoint/ndsremote" ]; then
		mkdir -p "$mountpoint/ndsremote"
		ln -s "$mountpoint/ndsremote" "$customimagepath"
	fi

	# get image filename
	filename="${imagename%_*}.${imagename##*_}"
	forename="${imagename%_*}"
	evalimg=$(echo "$customimageroot/""$filename")
	eval $forename=$evalimg

	if [ ! -f "$mountpoint/ndsremote/$filename" ] || [ "$refresh" = "1" ]; then
		# get protocol
		protocol=$(echo "$imageurl" | awk -F'://' '{printf("%s", $1)}')

		if [ "$protocol" = "http" ]; then
			retrieve=$($wret -q -O "$mountpoint/ndsremote/$filename" "$imageurl")
		elif [ "$protocol" = "https" ]; then
			#test for https support
			result=$($wret -q -O - "https://detectportal.firefox.com/success.txt")
			if [ "$result" = "success" ];then
				retrieve=$($wret -q -O "$mountpoint/ndsremote/$filename" "$imageurl")
			else
				echo "wget - https support failed or not installed - skipping file download" | logger -p "daemon.err" -s -t "opennds[$ndspid]: "
			fi
		elif [ "$protocol" = "file" ]; then
			sourcefile=$(echo "$imageurl" | awk -F'://' '{printf("%s", $2)}')
			destinationfile="$mountpoint/ndsremote/$filename"
			cp "$sourcefile" "$destinationfile"
		else
			unsupported="Unsupported protocol [$protocol] for [$filename]in url [$imageurl] - skipping download"
			echo "$unsupported" | logger -p "daemon.err" -s -t "opennds[$ndspid]: "
		fi
	fi
}

# Get custom data files
get_data_file() {
	webget
	dataname=$1
	shelldetect=$(head -1 "/usr/lib/opennds/libopennds.sh")

	if [ "$shelldetect" = "#!/bin/sh" ]; then
		setcontents=$(set)

		dataurl=$(echo "$setcontents" | grep "$dataname='" | awk -F"'" '{print $2}')
	else
		set -o posix
		setcontents=$(set)
		set +o posix
		dataurl=$(echo "$setcontents" | grep "$dataname=" | awk -F"$dataname=" '{print $2}' | awk -F", " 'NR==1{print $1}')
	fi

	setcontents=""

	if [ ! -d "$mountpoint/ndsdata" ]; then
		mkdir -p "$mountpoint/ndsdata"
	fi

	# get data filename
	filename="${dataname%_*}.${dataname##*_}"
	forename="${dataname%_*}"
	evaldata=$(echo "$mountpoint/ndsdata/""$filename")
	eval $forename=$evaldata

	if [ ! -f "$mountpoint/ndsdata/$filename" ] || [ "$refresh" = "1" ]; then
		# get protocol
		protocol=$(echo "$dataurl" | awk -F'://' '{printf("%s", $1)}')

		if [ "$protocol" = "http" ]; then
			retrieve=$($wret -q -O "$mountpoint/ndsdata/$filename" "$dataurl")
		elif [ "$protocol" = "https" ]; then
			#test for https support
			result=$($wret -q -O - "https://detectportal.firefox.com/success.txt")
			if [ "$result" = "success" ];then
				retrieve=$($wret -q -O "$mountpoint/ndsdata/$filename" "$dataurl")
			else
				echo "wget - https support failed or not installed - skipping file download" | logger -p "daemon.err" -s -t "opennds[$ndspid]: "
			fi
		elif [ "$protocol" = "file" ]; then
			sourcefile=$(echo "$dataurl" | awk -F'://' '{printf("%s", $2)}')
			destinationfile="$mountpoint/ndsdata/$filename"
			cp "$sourcefile" "$destinationfile"
		else
			unsupported="Unsupported protocol [$protocol] for [$filename]in url [$imageurl] - skipping download"
			echo "$unsupported" | logger -p "daemon.err" -s -t "opennds[$ndspid]: "
		fi
	fi
}

# Function to send commands to openNDS:
do_ndsctl () {
	local timeout=4

	for tic in $(seq $timeout); do
		ndsstatus="ready"
		ndsctlout=$(ndsctl $ndsctlcmd)

		for keyword in $ndsctlout; do

			if [ $keyword = "locked" ]; then
				ndsstatus="busy"
				sleep 1
				break
			fi

			if [ $keyword = "Failed" ]; then
				ndsstatus="failed"
				break
			fi

			if [ $keyword = "authenticated." ]; then
				ndsstatus="authenticated"
				break
			fi

		done

		keyword=""

		if [ $tic = $timeout ] ; then
			busy_page
		fi

		if [ "$ndsstatus" = "authenticated" ]; then
			break
		fi

		if [ "$ndsstatus" = "failed" ]; then
			break
		fi

		if [ "$ndsstatus" = "ready" ]; then
			break
		fi
	done
}

get_theme_environment() {
	# Get the query-string, user_agent and mode
	# The query string is urlencoded AND base64 encoded
	query_enc=$1

	# url decode and strip off variables that are added by this script into $fasvars
	querystr=$(printf "${query_enc//%/\\x}")

	# Check if the query string in $fas is valid:
	i=5
	query_type=${querystr:0:$i}

	if [ "$query_type" != "?fas=" ]; then
		exit 1
	fi

	querysplitremainder=$querystr

	while true; do
		querysplit="${querysplitremainder##*', '}"
		querysplitremainder="${querysplitremainder%', '*}"

		query_split_type=${querysplit:0:$i}

		if [ "$query_split_type" = "?fas=" ]; then
			break
		else
			# MAY be user entered so we must sanitize by html entity encoding
			htmlentityencode "$querysplit"
			querysplit=$entityencoded
			fasvars="$fasvars, $querysplit"
		fi
	done

	# $fas will be the urlDECODED but still b64ENCODED query string containing parameters passed from openNDS to this FAS script
	fas=$querysplitremainder

	# Get the other stuff we need:
	user_agent_enc="$2"
	mode="$3"
	cid=${query_enc:$i+9:86}
	ciddir="$mountpoint/ndscids"

	if [ "$mode" = "0" ]; then
		themespecpath="/usr/lib/opennds/theme_click-to-continue-basic.sh"
	elif [ "$mode" = "1" ]; then
		themespecpath="/usr/lib/opennds/theme_click-to-continue-basic.sh"
	elif [ "$mode" = "2" ]; then
		themespecpath="/usr/lib/opennds/theme_user-email-login-basic.sh"
	elif [ "$mode" = "3" ]; then
		themespecpath="$4"
	else
		type header &>/dev/null && header || default_header
		echo "<b>Invalid login mode #:[$mode]</b>"
		type footer &>/dev/null && footer || default_footer
		exit 0
	fi

	if [ ! -f "$themespecpath" ]; then
		imagepath="/images/splash.jpg"
		type header &>/dev/null && header || default_header
		echo "<b>Bad or Missing ThemeSpec for mode #:[$mode]</b>"
		type footer &>/dev/null && footer || default_footer
		exit 0
	fi

	# Include the Theme: 
	. $themespecpath

	# The base64 encoded query string can be very long and exceed the maximum length for a script argument
	# This is true in OpenWrt and is likely to be the case in many other operating systems, particularly those that use Busybox ASH shell
	# To be safe we will fragment the querystring for b64 decoding

	# The b64encoded data begins at the 10th character, ie character number 9 (numbering starts at zero).
	#

	# some variables we need:
	fullfrag="="
	query=""

	faslen=$((${#fas}))

	# Test if we have already decoded the query string and parsed it, or openNDS parsed it for us
	if [ -e "$ciddir/$cid" ]; then
		# We have it already so include the data
		. $ciddir/$cid

	else

		# Fragment and decode:
		# fragsize must not exceed the maximum shell argument size, typically 1024
		# fragsize and overlap MUST both be divisible by 4
		# overlap is the MAXIMUM size of a parameter to be parsed
		fragsize=1024
		overlap=256

		while true; do
			# get a fragment
			b64frag=${fas:$i:$fragsize}

			if [ -z "$b64frag" ]; then
				break
			fi

			#base64 decode the current fragment
			ndsctlcmd="b64decode $b64frag"
			do_ndsctl
			frag=$ndsctlout
			ndsctlcmd=""
			ndsctlout=""

			# parse variables in this fragment (each time round this loop we will add more parsed variables)
			query="$frag"
			frag=""
			queryvarlist=$ndsparamlist

			parse_variables

			# Increment the pointer
			i=$((i+$fragsize-$overlap))
		done

		# Save the variables we parsed from the query string
		mkdir -p $ciddir

		if [ ! -e "$ciddir/$cid" ]; then
			for var in $queryvarlist; do
				val=$(eval 'echo $'$var)
				echo "$var=\"$val\"" >> "$ciddir/$cid"
			done
		fi
	fi
}

get_arguments () {
	# Arguments may be sent to us from NDS in a urlencoded form,
	# we can decode an argument as follows:
	# arg[N]=$(printf "${arg[N]_enc//%/\\x}")

	# The User Agent argument is sent urlencoded, so:
	user_agent=$(printf "${user_agent_enc//%/\\x}")

	# Now we need to parse any fas variables this script may have added. These are in the string $fasvars:
	queryvarlist=$fasvarlist
	query="$fasvars"

	if [ ! -z "$query" ]; then
		parse_variables
	fi

	# Strip the name so we can send it back in forms
	fas=${fas##*'fas='}

	#Check if we parsed the client zone, if not, get it
	get_client_zone

}

parse_variables() {
	# Parse for variables in $query from the list in $queryvarlist:

	for var in $queryvarlist; do
		evalstr=$(echo "$query" | awk -F"$var=" '{print $2}' | awk -F', ' '{print $1}')
		evalstr=$(printf "${evalstr//%/\\x}")

		# sanitise $evalstr to prevent code injection
		htmlentityencode "$evalstr"
		evalstr=$entityencoded

		if [ -z "$evalstr" ]; then
			continue
		fi

		eval $var=$(echo "\"$evalstr\"")
		evalstr=""
	done
	query=""
}

configure_log_location() {
	# Generate the Logfile location; use the tmpfs "temporary" directory to prevent flash wear.
	# Alternately you may choose to manually override the settings generated here.
	# For example mount a USB storage device and manually set logdir and logname instead of this code
	#
	# DEFAULT Location depends upon OS distro in use:
	tempdir="/tmp /run /var"

	# set default values
	mountpoint="/tmp"
	logdir="/tmp/ndslog/"
	logname="ndslog.log"

	for var in $tempdir; do
		_mountpoint=$(df | awk -F ' ' '$1=="tmpfs" && $6=="'$var'" {print $6}')
		if [ "$_mountpoint" = "$var" ]; then
			mountpoint="$var"
			logdir="$mountpoint/ndslog/"
			break
		fi
	done

	#For syslog
	ndspid=$(pgrep '/usr/bin/opennds')
}

check_authenticated() {
	if [ "$status" = "authenticated" ]; then
		echo "
			<p>
				<big-red>
					You are already logged in and have access to the Internet.
				</big-red>
			</p>
			<hr>
			<p>
				<italic-black>
					You can use your Browser, Email and other network Apps as you normally would.
				</italic-black>
			</p>
		"

		read_terms
		footer
	fi
}


htmlentityencode() {
	entitylist="
		s/\"/\&quot;/g
		s/>/\&gt;/g
		s/</\&lt;/g
		s/%/\&#37;/g
		s/'/\&#39;/g
		s/\`/\&#96;/g
	"
	local buffer="$1"

	for entity in $entitylist; do
		entityencoded=$(echo "$buffer" | sed "$entity")
		buffer=$entityencoded
	done

	entityencoded=$(echo "$buffer" | awk '{ gsub(/\$/, "\\&#36;"); print }')
}


htmlentitydecode() {
	entitylist="
		s/\&quot;/\"/g
		s/\&gt;/>/g
		s/\&lt;/</g
		s/\&#37;/%/g
		s/\&#39;/'/g
		s/\&#96;/\`/g
	"
	local buffer="$1"

	for entity in $entitylist; do
		entitydecoded=$(echo "$buffer" | sed "$entity")
		buffer=$entitydecoded
	done

	entitydecoded=$(echo "$buffer" | awk '{ gsub(/\\&#36;/, "\$"); print }')
}

get_client_zone () {
	# Gets the client zone, (if we don't already have it) ie the connection the client is using, such as:
	# local interface (br-lan, wlan0, wlan0-1 etc.,
	# or remote mesh node mac address
	# This zone name is only displayed here but could be used to customise the login form for each zone

	if [ -z "$client_zone" ]; then
		client_mac=$(ip -4 neigh |grep "$clientip" | awk '{print $5}')
		client_if_string=$(/usr/lib/opennds/get_client_interface.sh $client_mac)
		failcheck=$(echo "$client_if_string" | grep "get_client_interface")

		if [ -z $failcheck ]; then
			client_if=$(echo "$client_if_string" | awk '{printf $1}')
			client_meshnode=$(echo "$client_if_string" | awk '{printf $2}' | awk -F ':' '{print $1$2$3$4$5$6}')
			local_mesh_if=$(echo "$client_if_string" | awk '{printf $3}')

			if [ ! -z "$client_meshnode" ]; then
				client_zone="MeshZone:$client_meshnode"
			else
				client_zone="LocalZone:$client_if"
			fi
		else
			client_zone=""
		fi
	else
		client_zone=$(printf "${client_zone//%/\\x}")
	fi
}

auth_log () {
	# We are ready to authenticate the client

	rhid=$(printf "$hid$key" | sha256sum | awk -F' ' '{printf $1}')
	ndsctlcmd="auth $rhid $quotas $binauth_custom"

	do_ndsctl
	authstat=$ndsctlout
	# $authstat contains the response from do_ndsctl

	mountcheck=$(df | grep "$mountpoint")
	clientinfo="status=$authstat, mac=$clientmac, ip=$clientip, zone=$client_zone, ua=$user_agent"

	if [ ! -z "$logname" ]; then

		if [ ! -d "$logdir" ]; then
			mkdir -p "$logdir"
		fi

		logfile="$logdir""$logname"
		awkcmd="awk ""'\$6==""\"$mountpoint\"""{print \$4}'"
		min_freespace_to_log_ratio=10
		datetime=$(date)

		if [ ! -f "$logfile" ]; then
			echo "$datetime, New log file created" > $logfile
		fi

		if [ ! -z "$mountcheck" ]; then
			filesize=$(ls -s -1 $logfile | awk -F' ' '{print $1}')
			available=$(df | grep "$mountpoint" | eval "$awkcmd")
			sizeratio=$(($available/$filesize))

			if [ $sizeratio -ge $min_freespace_to_log_ratio ]; then
				echo "$datetime, $userinfo, $clientinfo" >> $logfile
			else
				echo "PreAuth - log file too big, please archive contents" | logger -p "daemon.err" -s -t "opennds[$ndspid]: "
			fi
		else
			echo "Log location is NOT a mountpoint - logs would fill storage space - logging disabled" | logger -p "daemon.err" -s -t "opennds[$ndspid]: "
		fi
	fi

	# We will not remove the client id file, rather we will let openNDS delete it on deauth/timeout
}

default_header() {
# Define a common header html for every page served
	echo "<!DOCTYPE html>
		<html>
		<head>
		<meta http-equiv=\"Cache-Control\" content=\"no-cache, no-store, must-revalidate\">
		<meta http-equiv=\"Pragma\" content=\"no-cache\">
		<meta http-equiv=\"Expires\" content=\"0\">
		<meta charset=\"utf-8\">
		<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
		<link rel=\"shortcut icon\" href=\"/images/splash.jpg\" type=\"image/x-icon\">
		<link rel=\"stylesheet\" type=\"text/css\" href=\"/splash.css\">
		<title>$gatewayname</title>
		</head>
		<body>
		<div class=\"offset\">
		<med-blue>
			$gatewayname <br>
		</med-blue>
		<div class=\"insert\" style=\"max-width:100%;\">
	"
}

default_footer() {
	# Define a common footer html for every page served (with openNDS version on the thankyou page)
	year=$(date +'%Y')
	echo "
		<hr>
		<div style=\"font-size:0.5em;\">
			<img style=\"height:30px; width:60px; float:left;\" src=\"$imagepath\" alt=\"Splash Page: For access to the Internet.\">
			&copy; The openNDS Project 2015 - $year<br>
			openNDS $version
			<br><br>
		</div>
		</div>
		</div>
		</body>
		</html>
	"

	exit 0
}

busy_page() {
	type header &>/dev/null && header || default_header
	echo "
		<p>
			<big-red>
				Sorry: The Portal is Busy
			</big-red>
		</p>
		<hr>
		<p>
			<italic-black>
				Please Try Again Later
			</italic-black>
		</p>
	"

	type footer &>/dev/null && footer || default_footer
	exit 0
}

serve_error_message () {
	echo "<br><b style=\"color:red;\">Error: $1 </b><br>"
	default_footer
	exit 0
}

# Configure custom input fields
config_input_fields () {
	if [ ! -z "$input" ]; then
		if [ "$1" = "input" ]; then
			#custom variable for form input is configured
			inputremainder=$input

			# Parse for each input field. Format is name:description:type, fields separated by ";" character
			while true; do
				inputtail="${inputremainder##*';'}"
				inputremainder="${inputremainder%';'*}"

				fieldremainder=$inputtail

				#inputlist must list in the reverse order to that defined in the custom var (input=....)
				inputlist="type description name"

				# For each field, get the values of name:description:type
				for var in $inputlist; do
					fieldtail="${fieldremainder##*':'}"
					fieldremainder="${fieldremainder%':'*}"
					htmlentityencode "$fieldtail"
					fieldtail=$entityencoded

					eval $var=$(echo "\"$fieldtail\"")

					if [ "$fieldtail" = "$fieldremainder" ]; then
						break
					fi
				done

				# Make a list of field names
				inputnames="$inputnames $name"


				val=$(echo "$fasvars" | awk -F"$name=" '{print $2}' | awk -F', ' '{print $1}')

				eval $name=$(echo "\"$val\"")

				custom_inputs="
					$custom_inputs
					<input type=\"$type\" name=\"$name\" value=\"$val\" required autocomplete=\"on\" ><br><b>$description</b><br><br>
				"

				if [ "$inputtail" = "$inputremainder" ]; then
					break
				fi
			done

		elif [ "$1" = "hidden" ]; then

			for var in $inputnames; do
				val=$(echo "$fasvars" | awk -F"$var=" '{print $2}' | awk -F', ' '{print $1}')

				eval $var=$(echo "\"$val\"")

				userinfo="$userinfo, $var=$val"
				custom_passthrough="
					$custom_passthrough
					<input type=\"hidden\" name=\"$var\" value=\"$val\" >
				"
			done
		fi
	fi
}

check_mhd() {
	fetch=$(type -t uclient-fetch)
	mhdstatus="2"
	local timeout=4

	for tic in $(seq $timeout); do
		mhd_get_status

		if [ "$mhdstatus" = "2" ]; then
			# MHD response fail - wait then try again:
			sleep 1
		elif [ "$mhdstatus" = "1" ]; then
			break
		fi
	done
}

mhd_get_status() {

	if [ -z "$fetch" ]; then
		mhdtest=$(wget -t 1 -T 1 -O - "http://$gw_address/mhdstatus" 2>&1 | awk -F'ERROR 511: ' '{printf("%s", $2)}')

		if [ "$mhdtest" = "Network Authentication Required." ]; then
			mhdstatus="1"
		fi
	else
		mhdtest=$(uclient-fetch -T 1 -O - "http://$gw_address/mhdstatus" 2>&1 | awk -F'error ' '{printf("%s", $2)}')

		if [ "$mhdtest" = "511" ]; then
			mhdstatus="1"
		fi
	fi
}

get_key_from_config() {
	faskey=""

	if [ -e "/etc/config/opennds" ]; then
		faskey=$(uci -q get opennds.@opennds[0].faskey | awk '{printf("%s", $0)}')

	elif [ -e "/etc/opennds/opennds.conf" ]; then
		faskey=$(cat "/etc/opennds/opennds.conf" | awk -F'faskey ' '{printf("%s", $2)}')
	fi

	if [ -z "$faskey" ]; then
		faskey="1234567890"
	fi

	key=$faskey
}

check_gw_mac() {
	mac_sys=$(cat "/sys/class/net/$ifname/address")
	mac_sys=${mac_sys:0:17}

	if [ "$gw_mac" = "00:00:00:00:00:00" ] || [ -z "$gw_mac" ]; then
		gw_mac=$mac_sys
	elif [ "$mac_sys" != "$gw_mac" ]; then
		ndspid=$(pgrep '/usr/bin/opennds')
		echo "Warning, gateway mac changed from [$gw_mac] to [$mac_sys]" | logger -p "daemon.warn" -s -t "opennds[$ndspid]"
		gw_mac=$mac_sys
	fi
}

#### end of functions ####


#########################################
#					#
#  Start - Main entry point		#
#					#
#  This script starts executing here	#
#					#
#					#
#########################################

if [ "$1" = "clean" ]; then
	# Do a cleanup if asked and reply with tmpfs mountpoint
	configure_log_location

	if [ -d "$mountpoint/ndsremote" ]; then
		rm -R "$mountpoint/ndsremote"
	fi

	if [ -d "$mountpoint/ndsdata" ]; then
		rm -R "$mountpoint/ndsdata"
	fi

	if [ -d "$mountpoint/ndscids" ]; then
		rm -R "$mountpoint/ndscids"
	fi

	mkdir "$mountpoint/ndsremote"
	mkdir "$mountpoint/ndsdata"
	mkdir "$mountpoint/ndscids"

	printf "$mountpoint"
	exit 0

elif [ "$1" = "tmpfs" ]; then
	# Reply with tmpfs mountpoint
	configure_log_location
	printf "$mountpoint"
	exit 0

elif [ "$1" = "mhdcheck" ]; then
	# Check if MHD is healthy
	gw_address=$2

	if [ -z "$gw_address" ]; then
		exit 1
	fi

	check_mhd
	printf "$mhdstatus"
	exit 0

elif [ "$1" = "gatewaymac" ]; then
	# Check gatewaymac and return value
	ifname=$2
	gw_mac=$3

	check_gw_mac
	printf "$gw_mac"
	exit 0

elif [ "$1" = "gatewayroute" ]; then
	# Check for valid gatewayroute
	ifname=$2
	defaultif=$(ip route | grep "default" | awk '{printf("%s %s", $3, $5)}')

	if [ -z "$defaultif" ]; then
		defaultif="offline"
	else
		for var in $defaultif; do
			if [ "$var" = "$ifname" ]; then
				defaultif="-"
				break
			fi
		done
	fi

	printf "$defaultif"
	exit 0

elif [ "$1" = "clientaddress" ]; then
	# Find and return client ip and mac
	# $2 contains either client mac or client ip
	addrs=$(ip neigh | grep "$2" | awk 'NR==1, length($1)<16 {printf("%s %s", $1, $5)}')

	if [ -z "$addrs" ]; then
		addrs="-"
	fi
	printf "$addrs"
	exit 0

elif [ "$1" = "rmcid" ]; then
	# Remove an existing cidfile
	# $2 contains the cid
	# $3 contains the mountpoint
	rm "$3/ndscids/$2"
	echo "done"
	exit 0

elif [ "$1" = "write" ]; then
	# Write client info element to cidfile
	# $2 contains the cid
	# $3 contains the mountpoint
	# $4 contains the info element
	echo "$4" >> "$3/ndscids/$2"
	echo "done"
	exit 0

elif [ "$1" = "parse" ]; then
	# Parse for sub elements and write to cidfile
	# $2 contains the cid
	# $3 contains the mountpoint
	# $4 contains the info elements
	list="$4"
	list=${list//', '/'"; '}
	list=${list//'='/'="'}
	list=$(printf "${list//%/\\x}")

	echo "$list" >> "$3/ndscids/$2"
	echo "done"
	exit 0

elif [ "$1" = "download" ]; then
	# Download files required for themespec
	# $2 contains the themespec path
	# $3 contains the image list
	# $4 contains the file list
	# $5 contains the refresh flag, set to 1 to refresh downloads

	refresh=$5
	configure_log_location

	list="$3"
	if [ ! -z "$list" ]; then
		list=${list//', '/'"; '}
		list=${list//'='/'="'}
		eval $list
	fi

	list="$4"
	if [ ! -z "$list" ]; then
		list=${list//', '/'"; '}
		list=${list//'='/'="'}
		eval $list
	fi

	# Include the Theme:
	themespecpath=$2
	. $themespecpath

	type download_image_files &>/dev/null && download_image_files
	type download_data_files &>/dev/null && download_data_files

	echo "done"

	exit 0

else
	#Display a splash page sequence using a Themespec

	#################################
	# Any parameters set here	#
	# will be overridden if set	#
	# in the themespec file	#
	#################################

	#  setup required parameters:	#

	# Preshared key
	#########################################
	# Default value is 1234567890 when faskey is not set in config
	get_key_from_config

	# Quotas and Data Rates
	#########################################
	# Set length of session in minutes (eg 24 hours is 1440 minutes - if set to 0 then defaults to global sessiontimeout value):
	# eg for 100 mins:
	# session_length="100"
	#
	# eg for 20 hours:
	# session_length=$((20*60))
	#
	# eg for 20 hours and 30 minutes:
	# session_length=$((20*60+30))
	session_length="0"

	# Set Rate and Quota values for the client
	# The session length, rate and quota values could be determined by this script, on a per client basis.
	# rates are in kb/s, quotas are in kB. - if set to 0 then defaults to global value).
	upload_rate="0"
	download_rate="0"
	upload_quota="0"
	download_quota="0"

	quotas="$session_length $upload_rate $download_rate $upload_quota $download_quota"
	#########################################

	# The list of Parameters sent from openNDS:
	# Note you can add custom parameters to the config file and to read them you must also add them here.
	# Custom parameters are "Portal" information and are the same for all clients eg "admin_email" and "location"
	ndsparamlist="clientip clientmac gatewayname version hid gatewayaddress gatewaymac originurl clientif"

	# The list of FAS Variables used in the Login Dialogue generated by this script.
	# These FAS variables received from the login form presented to the client.
	# The following are the defaults for all themes. Theme specific variables are appended by the ThemeSpec script.
	fasvarlist="terms landing status continue binauth_custom"

	# You can choose to send a custom data string to BinAuth. Set the variable $binauth_custom to the desired value.
	# Note1: As this script runs on the openNDS router and creates its own log file, there is little point also enabling Binauth.
	#	BinAuth is intended more for use with EXTERNAL FAS servers that don't have direct access to the local router.
	#	Nevertheless it can be enabled at the same time as this script if so desired.
	# Note2: Spaces will be translated to underscore characters.
	# Note3: You must escape any quotes.
	#
	#The following value will, if uncommented, be overidden by any value set in a themespec file.
	#
	#binauth_custom="This is sample text with the intention of sending it to \"BinAuth\" for post authentication processing."

	# Set the Logfile location, using the tmpfs "temporary" directory to prevent flash wear.
	# or override to a custom location in the ThemeSpec file (eg USB stick)
	configure_log_location

	############################################################################
	### We are now ready to generate the html for the Portal "Splash" pages: ###
	############################################################################

	# Get the arguments sent from openNDS and parse/decode them, setting portal ThemeSpec as required
	get_theme_environment $1 $2 $3 $4

	type download_image_files &>/dev/null && download_image_files
	type download_data_files &>/dev/null && download_data_files

	# Note: $mountpoint is now set to point to a safe storage area, so we have loaded custom images there

	config_input_fields "input"

	# Add inputnames to fasvarlist
	fasvarlist="$fasvarlist $inputnames"

	get_arguments

	config_input_fields "hidden"

	# Set the default image to be displayed
	if [ -z "$imagepath" ]; then
		imagepath="http://$gatewayaddress/images/splash.jpg"
	fi

	# Output the page common header
	type header &>/dev/null && header || default_header

	# Check if Terms of Service is requested
	if [ "$terms" = "yes" ]; then
		display_terms
	fi

	# Check if landing page is requested
	if [ "$landing" = "yes" ]; then
		landing_page
	fi

	# Check if the client is already logged in (have probably tapped "back" on their browser)
	# Make this a friendly message explaining they are good to go
	check_authenticated

	# Generate the dynamic portal splash page sequence
	type generate_splash_sequence &>/dev/null && generate_splash_sequence || serve_error_message "Invalid ThemeSpec"

	# Customisation of the sequence of portal pages will normally be done in a corresponding themespec file.
	# This script imports a themespec file for defining the dynamically generated portal sequence presented to the client
	# The themespec file to be imported is defined in the openNDS config file
	# Hints:
	# The output of this script will be served by openNDS built in web server (MHD) and
	# ultimately displayed on the client device screen via the CPD process on that device.
	#
	# It should be noted when designing a custom splash page that for security reasons
	# most client device CPD implementations MAY do one or all of the following:
	#
	#	1.Immediately close the browser when the client has authenticated.
	#	2.Prohibit the use of href links.
	#	3.Prohibit downloading of external files (including .css and .js, even if they are allowed in NDS firewall settings).
	#	4.Prohibit the execution of javascript.
	#
fi

########################################################################
# WARNING - DO NOT edit this file unless you know what you are doing!	#
#									#
# WARNING - DO NOT delete or rename this file				#
########################################################################

