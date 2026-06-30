# tmuxinator project template — macOS server (with a claude window)
# Usage: copy to ~/.config/tmuxinator/<project-name>.yml, then edit name/root
name: PROJECT_NAME
root: PROJECT_ROOT

windows:
  - shell:
  - claude: claude --version
