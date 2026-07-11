# Fastfetch — imagens aleatórias

Coloque aqui as imagens (PNG/JPG/WEBP) que o `run-random.sh` vai sortear no
greeting do Fish. Suporta qualquer proporção.

```
img/
├── random/          # imagens para o run-random.sh (uma pasta)
│   ├── anime1.png
│   ├── wallpaper.jpg
│   └── ...
└── ascii_art_anime.txt  # logo ASCII usado pelo config.jsonc estático
```

## Notas

- O script detecta o backend automaticamente: **kitty** (Kitty), **sixel**
  (Konsole), **chafa** (fallback para qualquer terminal).
- `imagemagick` é necessário (`identify` para ler dimensões).
- As imagens NÃO são versionadas no git (ver `.gitignore`) — adicione manualmente.
