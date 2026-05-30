# Themes

A theme is a light/dark **pair** of palettes. The active theme is chosen with the
`NEUZ_THEME` environment variable (default: `default`). The existing
light / auto / dark toggle in the header switches between the active theme's two
modes — it is independent of which theme is selected.

## Built-in themes

`default`, `solarized`, `gruvbox`, `catppuccin`, `elflord`, `ayu`,
`tokyo-night`, `one-dark`.

Set one in `docker-compose.yml` (or your `.env`):

```yaml
NEUZ_THEME: gruvbox
```

then restart: `docker compose up -d`.

## The contract

Each theme is a plain CSS file defining 11 custom properties for light (`:root`)
and dark (`html.dark`). Values are space-separated RGB triples (so alpha
modifiers like `bg-paper/95` work):

| token | role |
|-------|------|
| `--paper` | page background |
| `--ink` | primary text |
| `--faint` | muted / secondary text |
| `--rule` | borders / dividers |
| `--tag` | subtle chip / fill background |
| `--accent` | links, brand, primary accent |
| `--good` | success (green) |
| `--bad` | error (red) |
| `--cell-1` `--cell-2` `--cell-3` | calendar heat scale, low → high |

```css
:root      { --paper: 251 241 199; --ink: 60 56 54; /* …all 11… */ }
html.dark  { --paper: 40 40 40;    --ink: 235 219 178; /* …all 11… */ }
```

## Custom themes (survive restarts & upgrades)

Custom themes live in `data/themes/` inside the container, which is on the
persistent `neuz-data` volume — so they survive `docker compose up --build`
and image upgrades.

1. Put `mytheme.css` in the volume — either bind-mount a host dir:

   ```yaml
   volumes:
     - neuz-data:/app/data
     - ./my-themes:/app/data/themes   # your *.css files
   ```

   or copy it in: `docker cp mytheme.css neuz:/app/data/themes/`.

2. Set `NEUZ_THEME: mytheme`.
3. Restart the container.

A custom file named the same as a built-in (e.g. `gruvbox.css`) overrides the
built-in. Theme files are cached at boot, so **restart to apply edits**.
