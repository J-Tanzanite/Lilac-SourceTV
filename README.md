# Little Anti-Cheat - SourceTV
This plugin will automatically start recording SourceTV demos upon cheater detections by **Little Anti-Cheat**.
**
### Requirements:
- **Little Anti-Cheat:** https://github.com/J-Tanzanite/Little-Anti-Cheat

### Configuration:
This plugin will automatically generate a file when loaded, to **cfg/sourcemod/lilac_sourcetv.cfg**.

You can change settings there.

- **`lilac_stv_enable "1"`** - Enables and disables auto recording.
- **`lilac_stv_autojoin "1"`**- Automatically restart the map if SourceTV bot is missing.
- **`lilac_stv_record "1"`**- Automatically record demos (Disable this if you want to log-only).
- **`lilac_stv_log "1"`**- Log to **addons/sourcemod/logs/lilac_stv.log** when players are added & removed from a recording.
- **`lilac_stv_tickrate "1"`**- Set the SourceTV demo tickrate to the most optimal settings for best quality recordings.
