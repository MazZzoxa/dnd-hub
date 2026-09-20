# D&D Hub GM Server — Windows bootstrap

`server/run.py` intentionally does not rely on the first `python.exe` found on PATH.
On Windows it prefers the Python Launcher (`py -3`) and explicitly skips bundled
application Pythons such as the one shipped with Inkscape.

The server dependencies are installed into `server/.deps` so a venv is not required.
