#!/usr/bin/env bash

# identifier: Attaque Bruteforce
# description: Cracker le mot de passe WPA/WPA2 avec wordlist par patterns (Mode Smart pour ZTE)

# ============================================================ #
# ============= < Fichier Langue Bruteforce > ================ #
# ============================================================ #

# Sélection du mode
BruteforceModeQuery="Sélectionner le mode de bruteforce"
BruteforceSmartModeOption="Mode SMART - ZTE Orange Maroc (recommandé)"
BruteforceManualModeOption="Mode Manuel - Charset et longueur personnalisés"

# Options de jeu de caractères
BruteforceCharsetQuery="Sélectionner la composition du mot de passe"
BruteforceCharsetNumericOption="Chiffres uniquement (0-9)"
BruteforceCharsetUpperNumericOption="Majuscules + Chiffres (A-Z, 0-9) - Pattern ZTE"
BruteforceCharsetAlphanumMixedOption="Lettres + chiffres (a-z, A-Z, 0-9)"
BruteforceCharsetFullOption="Jeu complet (lettres, chiffres, symboles)"

# Options de longueur
BruteforceLengthQuery="Sélectionner la longueur du mot de passe"
BruteforceLength8Option="8 caractères (le plus commun pour ZTE)"
BruteforceLength10Option="10 caractères"
BruteforceLength12Option="12 caractères"
BruteforceLength18Option="18 caractères"
BruteforceLength24Option="24 caractères"
BruteforceLengthCustomOption="Longueur personnalisée"
BruteforceLengthCustomQuery="Entrer la longueur du mot de passe"
BruteforceLengthInvalidError="${CRed}Erreur: La longueur doit être entre 8 et 63${CClr}"

# Notices d'attaque
BruteforceStartingNotice="Démarrage de l'attaque bruteforce..."
BruteforceCompletedNotice="Attaque bruteforce terminée."
BruteforcePasswordFoundNotice="${CGrn}Mot de passe trouvé!${CClr}"
BruteforcePasswordNotFoundNotice="${CRed}Mot de passe non trouvé avec ces paramètres.${CClr}"
BruteforceCrunchMissingError="${CRed}Erreur: crunch n'est pas installé. Installer avec: apt install crunch${CClr}"

# Mode smart
BruteforceSmartModeStarting="Démarrage du mode SMART pour ZTE Orange Maroc..."
BruteforceSmartModePatterns="Test des patterns optimisés pour routeurs ZTE"
