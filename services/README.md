# rclone — configuração

Este serviço monta o Google Drive automaticamente no boot.

## Setup (uma vez)

1. Criar o remote no rclone (interativo):
   ```bash
   rclone config
   # Escolher: n (new remote)
   # Nome: drive001
   # Tipo: drive (Google Drive)
   # Seguir o fluxo OAuth no navegador
   ```

2. Criar o ponto de montagem:
   ```bash
   mkdir -p ~/Gdrive/drive001
   ```

3. Instalar o serviço:
   ```bash
   ./install.sh services   # cria o symlink
   systemctl --user daemon-reload
   systemctl --user enable --now rclone-drive001.service
   ```

4. Testar:
   ```bash
   ls ~/Gdrive/drive001/
   ```
