# AeroTech globe map texture

`aerotech_mapa_mundi.png` is a 2048 × 1024 equirectangular PNG generated from Natural Earth **Admin 0 – Countries, 1:50m**, dataset version 5.1.1 (the version listed for this theme on the source page; archive retrieved 2026-11-12).

- Source data: [Natural Earth 1:50m Cultural Vectors](https://www.naturalearthdata.com/downloads/50m-cultural-vectors/)
- Archive: `https://naturalearth.s3.amazonaws.com/50m_cultural/ne_50m_admin_0_countries.zip`
- License: Natural Earth data is public domain; see [Terms of Use](https://www.naturalearthdata.com/about/terms-of-use/).
- Bundled source archive: `tool/data/ne_50m_admin_0_countries.zip` (SHA-256 `5fed433373581fa648920435f937d95f2d3c0200e067409c6478dcdf1b853139`).
- Generator: `tool/generar_textura_mapa.py`; render dependency is isolated to this asset-generation tool and is not an application/runtime dependency.

To regenerate the texture and embedded GLB from the bundled archive:

```powershell
python -m pip install -r tool/requirements-map-texture.txt
python tool/generar_textura_mapa.py
python tool/generar_globo_aerotech.py
```

The GLB embeds the PNG and carries the equirectangular UVs, so app builds do not need the archive, Python, Pillow, or network access. The sphere's looping aircraft animation and app asset paths are unchanged.
