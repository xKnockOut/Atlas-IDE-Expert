#!/usr/bin/env node
// Synthetische große Unit für Messungen und Handtests mit großen Units (AA22 bis AA26):
// eine Klasse mit N Methoden, jede mit drei verschachtelten lokalen Routinen. Mit 600 Methoden
// (Vorgabe) entstehen etwa 26.000 Zeilen.
//
// Aufruf:  node Tools/Benchmark/big-unit.mjs [Ausgabedatei] [--routines N]
// Vorgabe: BigUnit.pas im aktuellen Ordner. Die Datei ist UTF-8 mit BOM und CRLF.

import { writeFileSync } from 'node:fs';

function parseArgs(argv) {
  const options = { output: 'BigUnit.pas', routines: 600 };
  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index];
    if (arg === '--routines') {
      options.routines = Number.parseInt(argv[++index], 10);
      if (!Number.isInteger(options.routines) || options.routines < 1) {
        throw new Error('--routines erwartet eine positive Zahl');
      }
    } else {
      options.output = arg;
    }
  }
  return options;
}

function routineBody(index) {
  return [
    `procedure TBig.Run${index}(AValue: Integer);`,
    'var',
    '  mTotal: Integer;',
    '  procedure Outer(AStep: Integer);',
    '  var',
    '    mLocal: Integer;',
    '    procedure Inner(ADepth: Integer);',
    '    var',
    '      mDeep: Integer;',
    '      procedure Deepest;',
    '      begin',
    '        mDeep := mDeep + 1;',
    '        if mDeep > 10 then',
    '        begin',
    '          mTotal := mTotal + mDeep;',
    '        end;',
    '      end;',
    '    begin',
    '      mDeep := ADepth;',
    '      while mDeep < 20 do',
    '      begin',
    '        Deepest;',
    '      end;',
    '      mLocal := mLocal + mDeep;',
    '    end;',
    '  begin',
    '    mLocal := AStep;',
    '    if AStep > 0 then',
    '    begin',
    '      Inner(AStep - 1);',
    '    end;',
    '    mTotal := mTotal + mLocal;',
    '  end;',
    'begin',
    '  mTotal := AValue;',
    '  Outer(AValue);',
    '  if mTotal > 100 then',
    '  begin',
    "    raise Exception.Create('zu groß');",
    '  end;',
    'end;',
    '',
  ];
}

export function bigUnit(routines) {
  const lines = ['unit BigUnit;', '', 'interface', '', 'uses', '  System.SysUtils, System.Classes;', '', 'type',
    '  TBig = class', '  public'];
  for (let index = 0; index < routines; index++) {
    lines.push(`    procedure Run${index}(AValue: Integer);`);
  }
  lines.push('  end;', '', 'implementation', '');
  for (let index = 0; index < routines; index++) {
    lines.push(...routineBody(index));
  }
  lines.push('end.', '');
  return lines.join('\r\n');
}

const options = parseArgs(process.argv.slice(2));
const text = bigUnit(options.routines);
writeFileSync(options.output, '﻿' + text, 'utf8');
console.error(`${options.output}: ${text.split('\r\n').length - 1} Zeilen, ${options.routines} Methoden`);
