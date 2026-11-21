#!/usr/bin/env python3
"""Units umbenennen und verschieben, mit allem, was am Namen hängt.

Liest eine Tabelle (TSV, je Zeile ``alt<TAB>neu[<TAB>Zielordner]``, ``#`` leitet einen
Kommentar ein) und erledigt für jede Zeile:

- ``git mv`` der Unit (``alt.pas`` und gleichnamige ``.dfm``/``.fmx``) nach ``neu.pas``, im
  selben Ordner oder im Zielordner (relativ zum Wurzelordner des Repositorys);
- dazu jede Testunit ``alt.<Rest>`` unter ``Tests/`` (``alt.Tests`` → ``neu.Tests``), sofern
  ``alt.<Rest>`` keine Unit außerhalb von ``Tests/`` ist; sie bleibt in ihrem Ordner;
- den Namen in allen versionierten Textdateien: uses-Klauseln, Unit-Kopf, qualifizierte Bezeichner
  (``alt.TKlasse``), Kommentare, Doku, Skripte, ``atlas.json``, Baselines, ADR 0017;
- Pfade auf die verschobenen Dateien in ``.dpk``, ``.dpr``, ``.dproj``, Baselines, Skripten und
  Doku, egal ob relativ zur Datei, zum Wurzelordner oder zu einem Quellordner geschrieben
  (``..\\Packages\\…\\alt.pas``, ``Source/Core/…/alt.pas``, ``Core/Help/alt.pas``): Der geschriebene
  Pfad muss ein Ende des alten Pfads sein; er wird durch das entsprechende Ende des neuen ersetzt,
  mit demselben Trenner.

Ein Name wird nur als ganzer Bezeichner ersetzt (``alt`` nicht in ``altX`` oder ``X.alt``). Folgt ein
Punkt, bleibt die Stelle stehen, wenn ``alt.<Weiter>`` selbst eine Unit ist, die nicht in der Tabelle
steht (``Atlas.IDE.Help`` ist dann kein Treffer in ``Atlas.IDE.Help.Pages``). Groß- und Kleinschreibung
zählt nicht, geschrieben wird immer ``neu``.

Nicht angefasst werden ``CHANGELOG.md`` (Zusammenführen-Regel), Release-Notizen und ADRs außer der
Zuordnung 0017; ``Tools/UnitAssignment.tsv`` sortiert es danach wieder nach Package und Unit. ``--exclude`` nimmt weitere Pfadmuster aus. Kodierung, BOM und Zeilenenden bleiben,
wie sie sind.

Danach von Hand: Baselines mit Fingerabdrücken neu schreiben, wo ein Lauf das verlangt
(``AtlasServer --check Packages/<Package>/<Package>.dproj --update-baseline``,
``--check-duplicates --update-baseline``), und ``pwsh Tools/Check-PackageDependencies.ps1``.

Aufruf aus dem Wurzelordner:

    python3 Tools/Rename-Units.py umbenennungen.tsv            # umbenennen
    python3 Tools/Rename-Units.py umbenennungen.tsv --dry-run  # nur zeigen
    python3 Tools/Rename-Units.py --selbsttest

Ausgabe: je Zeile ``alt -> neu`` und die geänderten Dateien; Warnungen (Pfade, die sich keiner Datei
zuordnen lassen) auf stderr. Exit-Code 0 bei Erfolg, 1 bei Fehlern in der Tabelle.
"""

from __future__ import annotations

import argparse
import fnmatch
import os
import re
import shutil
import subprocess
import sys
import tempfile

cTextExtensions = {
    '.pas', '.dpr', '.dpk', '.dproj', '.groupproj', '.inc', '.json', '.jsonc', '.md', '.ps1', '.psm1', '.py',
    '.sh', '.txt', '.yml', '.yaml', '.tsv', '.xml', '.html', '.dfm', '.fmx', '.cfg',
}
cCompanions = ('.dfm', '.fmx')
cDefaultExcludes = ('CHANGELOG.md', 'docs/Release-Notizen/*', 'docs/adr/0[0-9][0-9][0-9]-*.md')
cKeptAdr = 'docs/adr/0017-unit-zuordnung.md'
cAssignment = 'Tools/UnitAssignment.tsv'
cIdent = r'[A-Za-z_][A-Za-z0-9_]*'


class TRename:
    """Eine Zeile der Tabelle mit alter und neuer Datei."""

    def __init__(self, AOld: str, ANew: str, AOldPath: str, ANewPath: str):
        self.Old = AOld
        self.New = ANew
        self.OldPath = AOldPath
        self.NewPath = ANewPath


def Git(ARoot: str, AArgs: list[str]) -> str:
    return subprocess.run(['git', *AArgs], cwd=ARoot, check=True, capture_output=True, text=True).stdout


def ReadTable(APath: str) -> list[tuple[str, str, str]]:
    mRows = []
    with open(APath, encoding='utf-8-sig') as mFile:
        for mNumber, mLine in enumerate(mFile, 1):
            mLine = mLine.split('#', 1)[0].rstrip('\r\n')
            if not mLine.strip():
                continue
            mParts = [mPart.strip() for mPart in mLine.split('\t')]
            if mParts[0].lower() == 'alt' and len(mParts) > 1 and mParts[1].lower() == 'neu':
                continue
            if len(mParts) < 2 or not mParts[0] or not mParts[1]:
                raise ValueError(f'{APath}:{mNumber}: erwartet "alt<TAB>neu[<TAB>Zielordner]"')
            mRows.append((mParts[0], mParts[1], mParts[2] if len(mParts) > 2 else ''))
    return mRows


def UnitFiles(ARoot: str) -> dict[str, list[str]]:
    """Name (klein) -> versionierte .pas-Dateien (relativ, mit /)."""
    mResult: dict[str, list[str]] = {}
    for mPath in Git(ARoot, ['ls-files', '*.pas']).splitlines():
        mResult.setdefault(os.path.basename(mPath)[:-4].lower(), []).append(mPath)
    return mResult


def Plan(ARoot: str, ARows: list[tuple[str, str, str]]) -> list[TRename]:
    mUnits = UnitFiles(ARoot)
    mPlan: list[TRename] = []
    mSeen: set[str] = set()
    for mOld, mNew, mFolder in ARows:
        mPaths = [mPath for mPath in mUnits.get(mOld.lower(), []) if not mPath.startswith('Tests/')]
        if len(mPaths) != 1:
            raise ValueError(f'{mOld}: {len(mPaths)} Dateien außerhalb von Tests/ gefunden, erwartet genau eine')
        if mNew.lower() in mUnits and mNew.lower() != mOld.lower():
            raise ValueError(f'{mNew}: Unit gibt es schon ({mUnits[mNew.lower()][0]})')
        mDir = mFolder.strip('/').replace('\\', '/') if mFolder else os.path.dirname(mPaths[0])
        mPlan.append(TRename(mOld, mNew, mPaths[0], f'{mDir}/{mNew}.pas' if mDir else f'{mNew}.pas'))
        mSeen.add(mOld.lower())
    # Testunits: alt.<Rest> unter Tests/, solange alt.<Rest> keine eigene Unit außerhalb von Tests/ ist.
    mProduction = {mName for mName, mPaths in mUnits.items() if any(not mPath.startswith('Tests/') for mPath in mPaths)}
    for mEntry in list(mPlan):
        mPrefix = mEntry.Old.lower() + '.'
        for mName, mPaths in mUnits.items():
            if not mName.startswith(mPrefix) or mName in mProduction or mName in mSeen:
                continue
            for mPath in mPaths:
                if mPath.startswith('Tests/'):
                    mBase = os.path.basename(mPath)[:-4]
                    mNewName = mEntry.New + mBase[len(mEntry.Old):]
                    mPlan.append(TRename(mBase, mNewName, mPath, f'{os.path.dirname(mPath)}/{mNewName}.pas'))
                    mSeen.add(mName)
    return mPlan


def Excluded(APath: str, AExcludes: tuple[str, ...]) -> bool:
    if APath == cKeptAdr:
        return False
    return any(fnmatch.fnmatch(APath, mPattern) for mPattern in AExcludes)


def SplitPath(AText: str) -> tuple[str, list[str]]:
    """Trenner und Segmente ohne führende ./ und ../ (die bleiben als Vorsatz stehen)."""
    mSep = '\\' if '\\' in AText else '/'
    return mSep, re.split(r'[\\/]', AText)


def MapPath(AWritten: str, AEntries: dict[str, TRename], AFile: str, AWarnings: list[str]) -> str:
    """Ersetzt einen geschriebenen Pfad auf eine verschobene Datei; sonst unverändert."""
    mSep, mParts = SplitPath(AWritten)
    mLead = []
    while mParts and mParts[0] in ('.', '..'):
        mLead.append(mParts.pop(0))
    if not mParts:
        return AWritten
    mStem, mExt = os.path.splitext(mParts[-1])
    mEntry = AEntries.get(mStem.lower())
    if mEntry is None:
        return AWritten
    if len(mParts) == 1:
        return mEntry.New + mExt
    mOldParts = (os.path.splitext(mEntry.OldPath)[0] + mExt).split('/')
    mNewParts = (os.path.splitext(mEntry.NewPath)[0] + mExt).split('/')
    mTail = [mPart.lower() for mPart in mParts]
    if len(mTail) > len(mOldParts) or [mPart.lower() for mPart in mOldParts[-len(mTail):]] != mTail:
        AWarnings.append(f'{AFile}: Pfad {AWritten} passt nicht zu {mEntry.OldPath}, nur der Name wird ersetzt')
        return AWritten
    mBase = mOldParts[:len(mOldParts) - len(mTail)]
    if [mPart.lower() for mPart in mNewParts[:len(mBase)]] != [mPart.lower() for mPart in mBase]:
        AWarnings.append(f'{AFile}: Pfad {AWritten} reicht nicht bis zum neuen Ordner von {mEntry.NewPath}')
        return AWritten
    return mSep.join(mLead + mNewParts[len(mBase):])


def BuildPatterns(APlan: list[TRename]):
    mNames = sorted({mEntry.Old for mEntry in APlan}, key=len, reverse=True)
    mAlternatives = '|'.join(re.escape(mName) for mName in mNames)
    mPathPattern = re.compile(
        r'(?<![A-Za-z0-9_.\-])((?:[A-Za-z0-9_.\-]+[\\/])*(?:' + mAlternatives + r')\.(?:pas|dfm|fmx))(?![A-Za-z0-9_])',
        re.IGNORECASE)
    mNamePattern = re.compile(r'(?<![A-Za-z0-9_.])(' + mAlternatives + r')((?:\.' + cIdent + r')*)(?![A-Za-z0-9_])',
                              re.IGNORECASE)
    return mPathPattern, mNamePattern


def RewriteText(AText: str, APlan: list[TRename], AKnownUnits: set[str], AFile: str,
                AWarnings: list[str]) -> str:
    mEntries = {mEntry.Old.lower(): mEntry for mEntry in APlan}
    mPathPattern, mNamePattern = BuildPatterns(APlan)
    mText = mPathPattern.sub(lambda AMatch: MapPath(AMatch.group(1), mEntries, AFile, AWarnings), AText)

    def ReplaceName(AMatch: re.Match) -> str:
        mOld = AMatch.group(1)
        mRest = AMatch.group(2)
        # alt.<Weiter> ist selbst eine Unit, die nicht umbenannt wird: kein Treffer.
        mSegments = mRest.split('.')[1:]
        for mCount in range(len(mSegments), 0, -1):
            mLonger = (mOld + '.' + '.'.join(mSegments[:mCount])).lower()
            if mLonger in AKnownUnits and mLonger not in mEntries:
                return AMatch.group(0)
        return mEntries[mOld.lower()].New + mRest

    return mNamePattern.sub(ReplaceName, mText)


def Decode(AData: bytes) -> tuple[str, bytes] | None:
    mBom = b'\xef\xbb\xbf' if AData.startswith(b'\xef\xbb\xbf') else b''
    try:
        return AData[len(mBom):].decode('utf-8'), mBom
    except UnicodeDecodeError:
        return None


def Apply(ARoot: str, APlan: list[TRename], ADryRun: bool, AExcludes: tuple[str, ...], ATable: str = '') -> list[str]:
    mWarnings: list[str] = []
    mKnown = set(UnitFiles(ARoot))
    mChanged = []
    for mPath in Git(ARoot, ['ls-files']).splitlines():
        if os.path.splitext(mPath)[1].lower() not in cTextExtensions or Excluded(mPath, AExcludes):
            continue
        mFull = os.path.join(ARoot, mPath)
        if not os.path.isfile(mFull) or (ATable and os.path.abspath(mFull) == os.path.abspath(ATable)):
            continue
        with open(mFull, 'rb') as mFile:
            mData = mFile.read()
        mDecoded = Decode(mData)
        if mDecoded is None:
            if any(mEntry.Old.lower().encode() in mData.lower() for mEntry in APlan):
                mWarnings.append(f'{mPath}: nicht UTF-8, nicht geändert')
            continue
        mText, mBom = mDecoded
        mNew = RewriteText(mText, APlan, mKnown, mPath, mWarnings)
        if mNew != mText:
            mChanged.append(mPath)
            if not ADryRun:
                with open(mFull, 'wb') as mFile:
                    mFile.write(mBom + mNew.encode('utf-8'))
    for mEntry in APlan:
        mMoves = [(mEntry.OldPath, mEntry.NewPath)]
        for mExt in cCompanions:
            mCompanion = mEntry.OldPath[:-4] + mExt
            if os.path.isfile(os.path.join(ARoot, mCompanion)):
                mMoves.append((mCompanion, mEntry.NewPath[:-4] + mExt))
        for mFrom, mTo in mMoves:
            print(f'{mFrom} -> {mTo}')
            if not ADryRun:
                os.makedirs(os.path.dirname(os.path.join(ARoot, mTo)) or ARoot, exist_ok=True)
                Git(ARoot, ['mv', mFrom, mTo])
    if cAssignment in mChanged and not ADryRun:
        SortAssignment(os.path.join(ARoot, cAssignment))
    for mPath in mChanged:
        print(f'  geändert: {mPath}')
    return mWarnings


def SortAssignment(APath: str) -> None:
    """Zeilen der Unit-Zuordnung nach Package und Unit ordnen, wie Check-PackageDependencies es verlangt."""
    with open(APath, 'rb') as mFile:
        mData = mFile.read()
    mBom = b'\xef\xbb\xbf' if mData.startswith(b'\xef\xbb\xbf') else b''
    mText = mData[len(mBom):].decode('utf-8')
    mBreak = '\r\n' if '\r\n' in mText else '\n'
    mLines = mText.split(mBreak)
    mTrailing = mLines[-1] == ''
    if mTrailing:
        mLines.pop()
    mHead = [mLine for mLine in mLines[:1]]
    mRows = [mLine for mLine in mLines[1:] if mLine.strip() and not mLine.startswith('#')]
    mOther = [mLine for mLine in mLines[1:] if not (mLine.strip() and not mLine.startswith('#'))]
    mRows.sort(key=lambda ALine: '\t'.join(ALine.split('\t')[:2]).upper())
    mResult = mBreak.join(mHead + mOther + mRows) + (mBreak if mTrailing else '')
    with open(APath, 'wb') as mFile:
        mFile.write(mBom + mResult.encode('utf-8'))


def SelfTest() -> int:
    mRoot = tempfile.mkdtemp(prefix='rename-units-')
    try:
        def Write(APath: str, AText: str, ABom: bool = True) -> None:
            mFull = os.path.join(mRoot, APath)
            os.makedirs(os.path.dirname(mFull), exist_ok=True)
            with open(mFull, 'wb') as mFile:
                mFile.write((b'\xef\xbb\xbf' if ABom else b'') + AText.encode('utf-8'))

        def Read(APath: str) -> str:
            with open(os.path.join(mRoot, APath), encoding='utf-8-sig', newline='') as mFile:
                return mFile.read()

        Write('Packages/P/Source/Core/Help/Atlas.Core.Help.Links.pas',
              'unit Atlas.Core.Help.Links;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\nend.\r\n')
        Write('Packages/P/Source/Core/Help/Atlas.Core.Help.Links.dfm', 'object X: TX\r\nend\r\n')
        Write('Packages/P/Source/IDE/Help/Atlas.IDE.Help.pas', 'unit Atlas.IDE.Help;\r\nend.\r\n')
        Write('Packages/P/Source/IDE/Help/Atlas.IDE.Help.Pages.pas',
              'unit Atlas.IDE.Help.Pages;\r\n\r\ninterface\r\n\r\nuses\r\n  Atlas.Core.Help.Links, Atlas.IDE.Help;\r\n\r\n'
              'implementation\r\n\r\n// Ziele aus Atlas.Core.Help.Links; nicht Atlas.Core.Help.LinksX\r\n'
              'begin\r\n  Atlas.Core.Help.Links.TLinks.Open; atlas.core.help.links.X;\r\nend.\r\n')
        Write('Packages/P/P.dpk', "package P;\r\ncontains\r\n"
              "  Atlas.Core.Help.Links in 'Source\\Core\\Help\\Atlas.Core.Help.Links.pas',\r\n"
              "  Atlas.IDE.Help in 'Source\\IDE\\Help\\Atlas.IDE.Help.pas';\r\nend.\r\n")
        Write('Packages/P/P.dproj', '<DCCReference Include="Source\\Core\\Help\\Atlas.Core.Help.Links.pas">\r\n'
              '  <Form>Atlas.Core.Help.Links.dfm</Form>\r\n</DCCReference>\r\n', ABom=False)
        Write('Packages/P/atlas-baseline.json', '{"path": "Source/Core/Help/Atlas.Core.Help.Links.pas"}\n', ABom=False)
        Write('Tests/IDE/Atlas.Core.Help.Links.Tests.pas', 'unit Atlas.Core.Help.Links.Tests;\r\nuses Atlas.Core.Help.Links;\r\nend.\r\n')
        Write('Tests/T.dpr', "uses\r\n  Atlas.Core.Help.Links in '..\\Packages\\P\\Source\\Core\\Help\\Atlas.Core.Help.Links.pas',\r\n"
              "  Atlas.Core.Help.Links.Tests in 'IDE\\Atlas.Core.Help.Links.Tests.pas';\r\n")
        Write('docs/adr/0017-unit-zuordnung.md', '| `Atlas.Core.Help.Links` | `Core/Help/Atlas.Core.Help.Links.pas` |\n', ABom=False)
        Write('Tools/UnitAssignment.tsv', 'Package\tUnit\tDatei\tGrund\n'
              'P\tAtlas.Core.Help.Links\tCore/Help/Atlas.Core.Help.Links.pas\tLinks\n'
              'P\tAtlas.Core.Zeta\tCore/Zeta.pas\tZ\n', ABom=False)
        Write('docs/adr/0002-alt.md', 'Atlas.Core.Help.Links\n', ABom=False)
        Write('CHANGELOG.md', 'Atlas.Core.Help.Links\n', ABom=False)
        Write('Tools/X.ps1', "$X = Join-Path $Root 'Packages/P/Source/Core/Help/Atlas.Core.Help.Links.pas'\n", ABom=False)
        Write('Rename.tsv', 'alt\tneu\tZielordner\n'
              'Atlas.Core.Help.Links\tAtlas.IDE.P.Topics.Links\tPackages/P/Source/Topics  # Kommentar\n', ABom=False)
        Git(mRoot, ['init', '-q'])
        Git(mRoot, ['add', '-A'])
        mPlan = Plan(mRoot, ReadTable(os.path.join(mRoot, 'Rename.tsv')))
        mWarnings = Apply(mRoot, mPlan, False, cDefaultExcludes, os.path.join(mRoot, 'Rename.tsv'))
        mExpect = {
            'Packages/P/Source/Topics/Atlas.IDE.P.Topics.Links.pas': 'unit Atlas.IDE.P.Topics.Links;',
            'Packages/P/Source/Topics/Atlas.IDE.P.Topics.Links.dfm': 'object X',
            'Packages/P/Source/IDE/Help/Atlas.IDE.Help.Pages.pas': 'Atlas.IDE.P.Topics.Links, Atlas.IDE.Help;',
            'Packages/P/P.dpk': "Atlas.IDE.P.Topics.Links in 'Source\\Topics\\Atlas.IDE.P.Topics.Links.pas'",
            'Packages/P/P.dproj': 'Include="Source\\Topics\\Atlas.IDE.P.Topics.Links.pas"',
            'Packages/P/atlas-baseline.json': '"Source/Topics/Atlas.IDE.P.Topics.Links.pas"',
            'Tests/IDE/Atlas.IDE.P.Topics.Links.Tests.pas': 'unit Atlas.IDE.P.Topics.Links.Tests;\r\nuses Atlas.IDE.P.Topics.Links;',
            'Tests/T.dpr': "Atlas.IDE.P.Topics.Links.Tests in 'IDE\\Atlas.IDE.P.Topics.Links.Tests.pas'",
            'docs/adr/0017-unit-zuordnung.md': '`Topics/Atlas.IDE.P.Topics.Links.pas`',
            'Tools/X.ps1': "'Packages/P/Source/Topics/Atlas.IDE.P.Topics.Links.pas'",
        }
        mErrors = []
        for mPath, mPart in mExpect.items():
            if not os.path.isfile(os.path.join(mRoot, mPath)) or mPart not in Read(mPath):
                mErrors.append(f'{mPath}: erwartet {mPart!r}')
        mPages = Read('Packages/P/Source/IDE/Help/Atlas.IDE.Help.Pages.pas')
        for mPart in ('Atlas.IDE.P.Topics.Links.TLinks.Open', 'Atlas.IDE.P.Topics.Links.X', 'Atlas.Core.Help.LinksX',
                      'unit Atlas.IDE.Help.Pages;', '\r\n'):
            if mPart not in mPages:
                mErrors.append(f'Pages: erwartet {mPart!r}')
        if Read('Tools/UnitAssignment.tsv') != ('Package\tUnit\tDatei\tGrund\nP\tAtlas.Core.Zeta\tCore/Zeta.pas\tZ\n'
                                                'P\tAtlas.IDE.P.Topics.Links\tTopics/Atlas.IDE.P.Topics.Links.pas\tLinks\n'):
            mErrors.append('UnitAssignment.tsv: nicht ersetzt oder nicht sortiert')
        if Read('Tests/T.dpr').count("'..\\Packages\\P\\Source\\Topics\\Atlas.IDE.P.Topics.Links.pas'") != 1:
            mErrors.append('T.dpr: Pfad auf die Unit nicht ersetzt')
        if 'Atlas.Core.Help.Links' not in Read('CHANGELOG.md') or 'Atlas.Core.Help.Links' not in Read('docs/adr/0002-alt.md'):
            mErrors.append('CHANGELOG.md bzw. ADR 0002 wurden geändert')
        if not Read('Packages/P/Source/Topics/Atlas.IDE.P.Topics.Links.pas').endswith('end.\r\n'):
            mErrors.append('Zeilenenden geändert')
        with open(os.path.join(mRoot, 'Packages/P/Source/Topics/Atlas.IDE.P.Topics.Links.pas'), 'rb') as mFile:
            if not mFile.read().startswith(b'\xef\xbb\xbf'):
                mErrors.append('BOM verloren')
        if mWarnings:
            mErrors.append('unerwartete Warnungen: ' + '; '.join(mWarnings))
        for mError in mErrors:
            print(f'Selbsttest: {mError}', file=sys.stderr)
        if not mErrors:
            print('Selbsttest bestanden.')
        return 1 if mErrors else 0
    finally:
        shutil.rmtree(mRoot, ignore_errors=True)


def Main() -> int:
    mParser = argparse.ArgumentParser(description='Units umbenennen und verschieben (siehe Kopf der Datei).')
    mParser.add_argument('table', nargs='?', help='TSV: alt<TAB>neu[<TAB>Zielordner]')
    mParser.add_argument('--root', default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    mParser.add_argument('--dry-run', action='store_true', help='nur zeigen, nichts schreiben')
    mParser.add_argument('--exclude', action='append', default=[], help='weiteres Pfadmuster (fnmatch)')
    mParser.add_argument('--selbsttest', action='store_true')
    mArgs = mParser.parse_args()
    if mArgs.selbsttest:
        return SelfTest()
    if not mArgs.table:
        mParser.error('Tabelle fehlt')
    try:
        mPlan = Plan(mArgs.root, ReadTable(mArgs.table))
    except ValueError as mError:
        print(mError, file=sys.stderr)
        return 1
    for mEntry in mPlan:
        print(f'{mEntry.Old} -> {mEntry.New}')
    for mWarning in Apply(mArgs.root, mPlan, mArgs.dry_run, cDefaultExcludes + tuple(mArgs.exclude), mArgs.table):
        print(f'Warnung: {mWarning}', file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(Main())
