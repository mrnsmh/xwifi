# xWifi by AIFlowHub

**xWifi** est un outil avancé d'audit WiFi avec des fonctionnalités intelligentes pour le Maroc.

## 🚀 Fonctionnalités

- **TEST LIVE** - Test de mots de passe en temps réel SANS handshake
- **AUTO CAPTURE** - Capture automatique de tous les réseaux
- **PATTERNS MAROC** - Mots de passe optimisés pour les FAI marocains (Orange ZTE, Inwi, IAM)
- **SMART MODE** - Mode 100% automatique
- **Background Cracking** - Bruteforce en arrière-plan avec screen/tmux

## 📦 Installation

```bash
git clone https://github.com/mrnsmh/xwifi.git
cd xwifi
sudo ./xwifi.sh
```

## 🔧 Dépendances

- aircrack-ng
- screen (recommandé)
- hashcat (optionnel, pour GPU)
- hcxtools (optionnel)

## 📱 Patterns FAI Marocains

| FAI | Format | Exemple |
|-----|--------|---------|
| Orange ZTE Fibre | 18 chars MAJ+CHIFFRES | 9NF4GP5S37KP529SNR |
| Inwi | 12 chars HEX | D842F7067E29 |
| IAM | 10 chars | ABCD123456 |
| Commun | 8 chiffres | 20252026 |

## ⚡ Utilisation Rapide

```bash
# Mode interactif
sudo ./xwifi.sh

# Mode smart automatique
sudo ./xwifi.sh --smart
```

## 📝 License

Open Source - Usage éducatif uniquement.

## 👨‍💻 Crédits

**xWifi by AIFlowHub** - Fork optimisé pour le Maroc
