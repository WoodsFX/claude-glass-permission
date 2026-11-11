# Claude Glass Permission

Une notification qui s'affiche dès que **Claude Code** a besoin de ton autorisation (lancer une commande, modifier un fichier, ouvrir une page web, utiliser un outil MCP…). Tu acceptes ou refuses directement depuis la notification, sans revenir dans le terminal.

- **Entrée** : autoriser
- **Effacer**, **Suppr** ou **Échap** : refuser
- Sans réponse au bout de 90 s : Claude pose la question dans le terminal, comme d'habitude

La notification est sombre, apparaît en bas à droite de l'écran et glisse vers le haut. Sur Mac, une variante en verre (« Liquid Glass ») est aussi disponible.

> Ça ne marche qu'avec **Claude Code lancé sur ton ordinateur** : dans le terminal, ou dans l'app Claude en mode Code avec un dossier de ton ordinateur. Ça ne marche pas avec les sessions cloud ni avec les conversations classiques de Claude.

---

## 🍎 Mac

Il faut les outils Apple en ligne de commande (`xcode-select --install`).

```bash
git clone <URL-de-ce-dépôt>
cd claude-glass-permission/mac
chmod +x install.sh demo.sh
./install.sh
```

Pour tester :

```bash
./demo.sh
```

Pour passer à la pop-up en verre (puis revenir à la notification) :

```bash
echo glass > ~/.claude/glass-permission/style
echo toast > ~/.claude/glass-permission/style
```

Pour désinstaller :

```bash
./install.sh --uninstall
```

## 🪟 Windows

Rien à installer en plus : PowerShell et WPF sont déjà inclus dans Windows.

1. Télécharge le dépôt (bouton **Code → Download ZIP**), puis clic droit → **Extraire tout**.
2. Dans le dossier `windows`, double-clique sur **install.cmd**.
   Si Windows bloque : « Informations complémentaires » → « Exécuter quand même ».
3. Double-clique sur **demo.cmd** pour tester.
4. Redémarre Claude Code.

Pour désinstaller : double-clique sur **uninstall.cmd**.

---

## Comment ça marche

Les scripts d'installation ajoutent un hook `PermissionRequest` dans `~/.claude/settings.json` (une sauvegarde `settings.json.bak` est créée). À chaque demande d'autorisation, Claude Code lance la notification, qui lui renvoie ta réponse.

## Dépannage

La notification n'apparaît pas ?
- Vérifie que tu n'es pas dans une **session cloud**.
- Vérifie que le mode d'autorisation est sur **Manuel** (en mode Auto, Claude ne demande rien).
- Les **questions à choix** de Claude ne sont pas des autorisations : elles ne déclenchent pas la notification.
- Lance `demo.sh` (Mac) ou `demo.cmd` (Windows) : si la notification s'affiche, l'installation est bonne.
