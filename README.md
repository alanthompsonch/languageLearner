# languageLearner

Minimaler Player zum Sprachenlernen mit fremdsprachigen Serien, direkt im Kitty-Terminal.

Basiert vollständig auf [mpv](https://mpv.io) mit der Videoausgabe `kitty` (Kitty Graphics Protocol)
und einem kleinen Lua-Skript. mpv spielt alle gängigen Video-, Audio- und Untertitelformate ab
(mkv, mp4, webm, mp3, flac, srt, ass, vtt, eingebettete Untertitel usw.).

## Voraussetzungen

- `mpv` (ab 0.36, mit `--vo=kitty`)
- `ffmpeg` (für die erweiterte Untertitel-Ansicht)
- Kitty-Terminal

## Start

```sh
./langlearn serie-s01e01.mkv
./langlearn serie-s01e01.mkv --sub-file=de.srt --sub-file=en.srt
```

Externe Untertitel mit ähnlichem Dateinamen (z. B. `serie-s01e01.de.srt`) werden automatisch geladen.
Weitere mpv-Optionen können einfach angehängt werden.

## Tasten

| Taste           | Funktion                                                   |
|-----------------|------------------------------------------------------------|
| `1` … `9`       | N Sekunden zurückspringen                                  |
| `0`             | 10 Sekunden zurückspringen                                 |
| `Shift` + Ziffer | N Sekunden vorwärtsspringen                               |
| `Alt` + Ziffer  | ebenfalls vorwärtsspringen, unabhängig vom Tastaturlayout (z. B. für Tastaturen, die Shift bei Ziffern ignorieren) |
| `l`             | Untertitelspur wechseln (inkl. «aus»)                      |
| `t`             | zwischen den letzten zwei Untertitelspuren hin- und herschalten |
| `L`             | zweite Untertitelspur (oben angezeigt) wechseln            |
| `e`             | erweiterte Ansicht: vorherige und nächste Zeilen anzeigen  |
| `v`             | Untertitel ein-/ausblenden                                 |
| `h`             | Legende der Tasten ein-/ausblenden                         |
| `↑` / `↓`       | Lautstärke                                                 |
| `Leertaste`     | Pause                                                      |
| `q`             | Beenden                                                    |

Alle übrigen mpv-Standardtasten funktionieren weiterhin.

## Einstellungen

Zuoberst in `langlearn`:

```sh
LAYOUT=ch          # Tastaturlayout für Shift+Ziffer: ch (Schweizerdeutsch) oder us
CONTEXT_LINES=2    # Zeilen vor und nach der aktuellen Zeile in der erweiterten Ansicht
```

Der Ordner ist in sich geschlossen: Er kann an einen beliebigen Ort kopiert oder `langlearn` per Symlink in den
`PATH` gelegt werden. Eine allfällige mpv-Konfiguration unter `~/.config/mpv` wird bewusst ignoriert
(`--no-config`), damit sich der Player auf jedem Rechner gleich verhält.

## Einschränkungen

- Die erweiterte Ansicht funktioniert nur mit Text-Untertiteln, nicht mit Bild-Untertiteln
  (PGS/DVD von Blu-rays und DVDs).
- Die Videoausgabe im Terminal ist softwarebasiert; bei hohen Auflösungen kann sie ruckeln.
  Ein kleineres Kitty-Fenster hilft.
- Die Bilder werden als Escape-Sequenzen übertragen (`--vo-kitty-use-shm=no`). Die schnellere Übertragung
  über Shared Memory hat in Kitty kein Bild angezeigt (nur Ton).
