"""Schreibt die Ressourcendateien des Atlas-Symbols (#751) ohne Ressourcencompiler.

Atlas.Symbol.res (Plugin): ATLAS_ICON_HELL und ATLAS_ICON_DUNKEL als Symbol,
ATLAS_<VARIANTE>_<px> als RCDATA mit den PNG-Dateien. Atlas.Icon.res (Server
und Installer): MAINICON aus atlas-hell.ico. Inhalt wie Atlas.Symbol.rc und
Atlas.Icon.rc; die .res liegen im Repository, damit cc.ps1 und dcc ohne
Ressourcencompiler bauen (BRCC32 kann keine PNG-komprimierten 256-px-Symbole).

Aufruf im Ordner Resources/Symbol:  python3 Quellen/Erzeuge-Res.py .
"""
import os
import struct
import sys

RT_ICON, RT_RCDATA, RT_GROUP_ICON = 3, 10, 14
SIZES = [16, 20, 24, 32, 40, 48, 64, 128, 256]


def ident(value):
    if isinstance(value, int):
        return struct.pack('<HH', 0xFFFF, value)
    return (value.upper() + '\0').encode('utf-16-le')


def pad4(data):
    return data + b'\0' * (-len(data) % 4)


def entry(res_type, name, data, flags):
    names = pad4(ident(res_type) + ident(name))
    header = struct.pack('<II', len(data), 8 + len(names) + 16) + names
    header += struct.pack('<IHHII', 0, flags, 0, 0, 0)
    return header + pad4(data)


def icon_entries(path, group, first_id):
    data = open(path, 'rb').read()
    _, kind, count = struct.unpack_from('<HHH', data, 0)
    assert kind == 1, path
    result, directory = [], struct.pack('<HHH', 0, 1, count)
    for index in range(count):
        width, height, colors, reserved, planes, bits, size, offset = struct.unpack_from(
            '<BBBBHHII', data, 6 + 16 * index)
        result.append(entry(RT_ICON, first_id + index, data[offset:offset + size], 0x1010))
        directory += struct.pack('<BBBBHHIH', width, height, colors, reserved, planes, bits, size,
                                 first_id + index)
    result.append(entry(RT_GROUP_ICON, group, directory, 0x1030))
    return result, first_id + count


def write(path, entries):
    with open(path, 'wb') as target:
        target.write(entry(0, 0, b'', 0))
        for item in entries:
            target.write(item)


def main(folder):
    entries, next_id = [], 1
    for variant in ('hell', 'dunkel'):
        icons, next_id = icon_entries(os.path.join(folder, f'atlas-{variant}.ico'),
                                      f'ATLAS_ICON_{variant.upper()}', next_id)
        entries += icons
    for variant in ('hell', 'dunkel'):
        for size in SIZES:
            png = open(os.path.join(folder, f'atlas-{variant}-{size}.png'), 'rb').read()
            entries.append(entry(RT_RCDATA, f'ATLAS_{variant.upper()}_{size}', png, 0x0030))
    write(os.path.join(folder, 'Atlas.Symbol.res'), entries)
    icons, _ = icon_entries(os.path.join(folder, 'atlas-hell.ico'), 'MAINICON', 1)
    write(os.path.join(folder, 'Atlas.Icon.res'), icons)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else '.')
