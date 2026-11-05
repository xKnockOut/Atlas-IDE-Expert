#!/usr/bin/env node
// Synthetische große Unit für Messungen und Handtests mit großen Units (AA22 bis AA26):
// eine Klasse mit N Methoden, jede mit D ineinander verschachtelten lokalen Routinen.
//
// Aufruf:  node Tools/Benchmark/big-unit.mjs [Ausgabedatei] [--lines L | --routines N] [--depth D]
//   --lines L     etwa L Zeilen (die Zahl der Methoden ergibt sich daraus)
//   --routines N  genau N Methoden (Vorgabe 600)
//   --depth D     Tiefe der lokalen Routinen je Methode, 0 = keine (Vorgabe 3)
// Vorgabe: BigUnit.pas im aktuellen Ordner, 600 Methoden, Tiefe 3 (etwa 26.000 Zeilen).
// Die Datei ist UTF-8 mit BOM und CRLF.

import { writeFileSync } from 'node:fs';

function positiveInt(value, name, min) {
  const number = Number.parseInt(value, 10);
  if (!Number.isInteger(number) || number < min) {
    throw new Error(`${name} erwartet eine ganze Zahl ab ${min}`);
  }
  return number;
}

function parseArgs(argv) {
  const options = { output: 'BigUnit.pas', routines: 600, lines: 0, depth: 3 };
  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index];
    if (arg === '--routines') {
      options.routines = positiveInt(argv[++index], arg, 1);
    } else if (arg === '--lines') {
      options.lines = positiveInt(argv[++index], arg, 1);
    } else if (arg === '--depth') {
      options.depth = positiveInt(argv[++index], arg, 0);
    } else {
      options.output = arg;
    }
  }
  return options;
}

// Lokale Routine der Ebene ALevel (1 = äußerste) mit allen tieferen; AIndent = Einrückung ihres Kopfs.
function nestedRoutine(level, depth, indent) {
  const pad = ' '.repeat(indent);
  const local = `mLocal${level}`;
  const step = `AStep${level}`;
  const lines = [`${pad}procedure Level${level}(${step}: Integer);`, `${pad}var`, `${pad}  ${local}: Integer;`];
  if (level < depth) {
    lines.push(...nestedRoutine(level + 1, depth, indent + 2));
  }
  lines.push(`${pad}begin`, `${pad}  ${local} := ${step};`);
  if (level < depth) {
    lines.push(`${pad}  if ${step} > 0 then`, `${pad}  begin`, `${pad}    Level${level + 1}(${step} - 1);`, `${pad}  end;`);
  } else {
    lines.push(`${pad}  while ${local} < 20 do`, `${pad}  begin`, `${pad}    ${local} := ${local} + 1;`, `${pad}  end;`);
  }
  lines.push(`${pad}  mTotal := mTotal + ${local};`, `${pad}end;`);
  return lines;
}

function routineBody(index, depth) {
  const lines = [`procedure TBig.Run${index}(AValue: Integer);`, 'var', '  mTotal: Integer;'];
  if (depth > 0) {
    lines.push(...nestedRoutine(1, depth, 2));
  }
  lines.push('begin', '  mTotal := AValue;');
  if (depth > 0) {
    lines.push('  Level1(AValue);');
  }
  lines.push('  if mTotal > 100 then', '  begin', "    raise Exception.Create('zu groß');", '  end;', 'end;', '');
  return lines;
}

export function bigUnit(routines, depth) {
  const lines = ['unit BigUnit;', '', 'interface', '', 'uses', '  System.SysUtils, System.Classes;', '', 'type',
    '  TBig = class', '  public'];
  for (let index = 0; index < routines; index++) {
    lines.push(`    procedure Run${index}(AValue: Integer);`);
  }
  lines.push('  end;', '', 'implementation', '');
  for (let index = 0; index < routines; index++) {
    lines.push(...routineBody(index, depth));
  }
  lines.push('end.', '');
  return lines.join('\r\n');
}

// Methoden für etwa ALines Zeilen: feste Zeilen plus je Methode Rumpf und Deklaration.
export function routinesForLines(lines, depth) {
  const fixed = bigUnit(0, depth).split('\r\n').length - 1;
  const perRoutine = routineBody(0, depth).length + 1;
  return Math.max(1, Math.round((lines - fixed) / perRoutine));
}

const options = parseArgs(process.argv.slice(2));
const routines = options.lines > 0 ? routinesForLines(options.lines, options.depth) : options.routines;
const text = bigUnit(routines, options.depth);
writeFileSync(options.output, '﻿' + text, 'utf8');
console.error(`${options.output}: ${text.split('\r\n').length - 1} Zeilen, ${routines} Methoden, Tiefe ${options.depth}`);
