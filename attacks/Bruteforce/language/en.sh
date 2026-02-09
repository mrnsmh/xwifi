#!/usr/bin/env bash

# identifier: Bruteforce Attack
# description: Crack WPA/WPA2 password using pattern-based wordlists (Smart mode for ZTE)

# ============================================================ #
# =============== < Bruteforce Language File > =============== #
# ============================================================ #

# Mode selection
BruteforceModeQuery="Select bruteforce mode"
BruteforceSmartModeOption="SMART Mode - ZTE Orange Maroc (recommended)"
BruteforceManualModeOption="Manual Mode - Custom charset and length"

# Charset options
BruteforceCharsetQuery="Select password character composition"
BruteforceCharsetNumericOption="Numeric only (0-9)"
BruteforceCharsetUpperNumericOption="Uppercase + Numeric (A-Z, 0-9) - ZTE pattern"
BruteforceCharsetAlphanumMixedOption="All letters + numbers (a-z, A-Z, 0-9)"
BruteforceCharsetFullOption="Full charset (letters, numbers, symbols)"

# Length options
BruteforceLengthQuery="Select password length"
BruteforceLength8Option="8 characters (most common for ZTE)"
BruteforceLength10Option="10 characters"
BruteforceLength12Option="12 characters"
BruteforceLength18Option="18 characters"
BruteforceLength24Option="24 characters"
BruteforceLengthCustomOption="Custom length"
BruteforceLengthCustomQuery="Enter password length"
BruteforceLengthInvalidError="${CRed}Error: Length must be between 8 and 63${CClr}"

# Attack notices
BruteforceStartingNotice="Starting bruteforce attack..."
BruteforceCompletedNotice="Bruteforce attack completed."
BruteforcePasswordFoundNotice="${CGrn}Password found!${CClr}"
BruteforcePasswordNotFoundNotice="${CRed}Password not found with current settings.${CClr}"
BruteforceCrunchMissingError="${CRed}Error: crunch is not installed. Install with: apt install crunch${CClr}"

# Smart mode
BruteforceSmartModeStarting="Starting SMART mode for ZTE Orange Morocco..."
BruteforceSmartModePatterns="Testing optimized patterns for ZTE routers"
