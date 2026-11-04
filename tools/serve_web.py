#!/usr/bin/env python3
"""Preview an exported ECHO Web build on this computer."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class WebHandler(SimpleHTTPRequestHandler):
    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        '.wasm': 'application/wasm',
        '.pck': 'application/octet-stream',
        '.js': 'text/javascript',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=8787)
    args = parser.parse_args()
    directory = ROOT / 'builds/web'
    if not (directory / 'index.html').is_file():
        parser.error('Export the Web preset before starting the preview.')
    try:
        server = ThreadingHTTPServer(('127.0.0.1', args.port),
                                    partial(WebHandler, directory=str(directory)))
    except OSError as error:
        parser.error(f'Could not start the preview: {error}. Try --port 8788.')
    print(f'ECHO preview: http://127.0.0.1:{server.server_port}/', flush=True)
    print('Local preview only. Press Ctrl+C to stop.', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
