unit Atlas.Common.Rules.ChangedFiles;

// Auswahl der zu prüfenden Dateien für --changed und --diff (#157). Die Unit
// wertet nur Text aus; Git bzw. SVN (#276) startet die Shell.
//   ParseNameStatus  Ausgabe von "git diff --name-status": umbenannte Dateien
//                    unter neuem Namen, gelöschte werden ignoriert.
//   ParseHunks       Ausgabe von "git diff -U0": geänderte Zeilen je Datei,
//                    dazu die Stellen, an denen nur Zeilen entfernt wurden
//                    (Gaps, für betroffene Tests #1353; ParseSvnDiff ebenso).
//   Select           geänderte Units, Units zu geänderten DFMs/FMXs und zu
//                    geänderten Include-Dateien; Projekt- und Konfigurations-
//                    dateien wählen alles.
//   ParseSvnStatus, ParseSvnSummarize, ParseSvnDiff  dasselbe für SVN: "svn status",
//                    "svn diff --summarize" und "svn diff" mit Kontextzeilen.
// Pfade aus Git sind relativ zur Wurzel des Repositorys und mit "/" getrennt.
// Pfade mit Sonderzeichen gibt Git in Anführungszeichen mit Oktalfolgen für
// die UTF-8-Bytes aus (core.quotepath); UnquotePath macht daraus wieder Text,
// damit die Ausgabe unabhängig von der Codepage der Konsole bleibt.

interface

uses
  System.SysUtils;

type
  /// <summary>Geänderte Zeilen einer Datei, 0-basiert und einschließlich.</summary>
  TLineSpan = record
    First: Integer;
    Last: Integer;
  end;

  TChangedLines = record
    /// <summary>Pfad relativ zur Wurzel des Repositorys, mit "/" getrennt.</summary>
    Path: string;
    Spans: TArray<TLineSpan>;
    /// <summary>Stellen, an denen nur Zeilen entfernt wurden (#1353): 0-basierte Zeile der neuen Fassung, vor der
    /// sie standen (am Dateiende die Zeilenzahl). Ersetzte Zeilen stehen in Spans, nicht hier.</summary>
    Gaps: TArray<Integer>;
    function Contains(ALine: Integer): Boolean;
  end;

  /// <summary>Liefert die in AFileName eingebundenen Include-Namen, wie sie in $I stehen.</summary>
  TIncludeNamesOf = reference to function(const AFileName: string): TArray<string>;

  TChangedFiles = class
  public
    /// <summary>Pfade aus "git diff --name-status": A, C, M, R (neuer Name), T; D wird ignoriert.</summary>
    class function ParseNameStatus(const ALines: TArray<string>): TArray<string>; static;
    /// <summary>Geänderte Zeilen je Datei aus "git diff -U0".</summary>
    class function ParseHunks(const ALines: TArray<string>): TArray<TChangedLines>; static;
    /// <summary>Pfade aus "svn status": A, M, R; mit AUnversioned auch "?" (neue Dateien).</summary>
    class function ParseSvnStatus(const ALines: TArray<string>; AUnversioned: Boolean): TArray<string>; static;
    /// <summary>Pfade aus "svn diff --summarize": A, M, R; D und reine Eigenschaftsänderungen nicht.</summary>
    class function ParseSvnSummarize(const ALines: TArray<string>): TArray<string>; static;
    /// <summary>Geänderte Zeilen aus "svn diff"; nur hinzugefügte Zeilen zählen, Kontextzeilen nicht.</summary>
    class function ParseSvnDiff(const ALines: TArray<string>): TArray<TChangedLines>; static;
    /// <summary>Include-Namen aus {$I name} und {$INCLUDE name}; {$I+} und {$I-} sind Schalter.</summary>
    class function IncludeNames(const AText: string): TArray<string>; static;
    /// <summary>Teilmenge von ACandidates (vollständige Pfade), die nach den geänderten Dateien
    /// AChanged (vollständige Pfade) zu prüfen ist.</summary>
    class function Select(const AChanged, ACandidates: TArray<string>;
      const AIncludeNamesOf: TIncludeNamesOf): TArray<string>; static;
    /// <summary>Geänderte Zeilen zu AFullPath; False, wenn die Datei keine Hunks hat.</summary>
    class function LinesOf(const AChanges: TArray<TChangedLines>; const ARepoRoot, AFullPath: string;
      out ALines: TChangedLines): Boolean; static;
    /// <summary>Pfad aus Git ohne Anführungszeichen; "\303\244" wird zu "ä".</summary>
    class function UnquotePath(const APath: string): string; static;
    /// <summary>Vollständiger Pfad zu einem Git-Pfad unterhalb von ARepoRoot.</summary>
    class function FullPath(const ARepoRoot, AGitPath: string): string; static;
  end;

implementation

uses
  System.StrUtils;

{ TChangedLines }

function TChangedLines.Contains(ALine: Integer): Boolean;
var
  mSpan: TLineSpan;
begin
  for mSpan in Spans do
  begin
    if (ALine >= mSpan.First) and (ALine <= mSpan.Last) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TChangedFiles }

class function TChangedFiles.FullPath(const ARepoRoot, AGitPath: string): string;
begin
  Result := IncludeTrailingPathDelimiter(ARepoRoot) + StringReplace(AGitPath, '/', PathDelim, [rfReplaceAll]);
  if PathDelim = '/' then
  begin
    Result := StringReplace(Result, '\', '/', [rfReplaceAll]);
  end;
end;

/// <summary>Byte einer Escape-Folge ab AIndex (Zeichen nach dem Backslash): drei Oktalziffern, \t, \n, \r oder
/// das Zeichen selbst. AIndex steht danach auf dem letzten Zeichen der Folge.</summary>
function EscapedByte(const APath: string; var AIndex: Integer): Byte;
begin
  if CharInSet(APath[AIndex], ['0'..'7']) and (AIndex + 2 < Length(APath)) then
  begin
    Result := (Ord(APath[AIndex]) - Ord('0')) * 64 + (Ord(APath[AIndex + 1]) - Ord('0')) * 8 +
      Ord(APath[AIndex + 2]) - Ord('0');
    Inc(AIndex, 2);
    Exit;
  end;
  case APath[AIndex] of
    't':
      Result := 9;
    'n':
      Result := 10;
    'r':
      Result := 13;
  else
    Result := Byte(Ord(APath[AIndex]));
  end;
end;

class function TChangedFiles.UnquotePath(const APath: string): string;
var
  mBytes: TBytes;
  mIndex: Integer;
begin
  if (Length(APath) < 2) or (APath[1] <> '"') or (APath[Length(APath)] <> '"') then
  begin
    Exit(APath);
  end;
  mBytes := nil;
  mIndex := 2;
  while mIndex < Length(APath) do
  begin
    if (APath[mIndex] = '\') and (mIndex + 1 < Length(APath)) then
    begin
      Inc(mIndex);
      mBytes := mBytes + [EscapedByte(APath, mIndex)];
    end
    else if Ord(APath[mIndex]) < 128 then
    begin
      mBytes := mBytes + [Byte(Ord(APath[mIndex]))];
    end
    else
    begin
      // Zeichen außerhalb von ASCII ohne Oktalfolge: als UTF-8 übernehmen.
      mBytes := mBytes + TEncoding.UTF8.GetBytes(string(APath[mIndex]));
    end;
    Inc(mIndex);
  end;
  Result := TEncoding.UTF8.GetString(mBytes);
end;


class function TChangedFiles.ParseNameStatus(const ALines: TArray<string>): TArray<string>;
var
  mLine, mStatus, mRest: string;
  mTab: Integer;
begin
  Result := nil;
  for mLine in ALines do
  begin
    // "M<Tab>Pfad", "R087<Tab>Alt<Tab>Neu"
    mTab := Pos(#9, mLine);
    if mTab < 2 then
    begin
      Continue;
    end;
    mStatus := UpperCase(Copy(mLine, 1, 1));
    mRest := Copy(mLine, mTab + 1, MaxInt);
    if (mStatus = 'R') or (mStatus = 'C') then
    begin
      mTab := Pos(#9, mRest);
      if mTab > 0 then
      begin
        Result := Result + [UnquotePath(Copy(mRest, mTab + 1, MaxInt))];
      end;
    end
    else if ((mStatus = 'A') or (mStatus = 'M') or (mStatus = 'T')) and (mRest <> '') then
    begin
      Result := Result + [UnquotePath(mRest)];
    end;
  end;
end;

/// <summary>Neue Zeilen aus "@@ -a[,b] +c[,d] @@": AStart = c, ACount = d (fehlt = 1); False ohne "+c".</summary>
function HunkRange(const ALine: string; out AStart, ACount: Integer): Boolean;
var
  mPlus, mSpace, mComma: Integer;
  mHeader: string;
begin
  AStart := 0;
  ACount := 0;
  mPlus := Pos(' +', ALine);
  mSpace := PosEx(' ', ALine, mPlus + 2);
  Result := (mPlus > 0) and (mSpace > 0);
  if not Result then
  begin
    Exit;
  end;
  mHeader := Copy(ALine, mPlus + 2, mSpace - mPlus - 2);
  mComma := Pos(',', mHeader);
  if mComma > 0 then
  begin
    AStart := StrToIntDef(Copy(mHeader, 1, mComma - 1), 0);
    ACount := StrToIntDef(Copy(mHeader, mComma + 1, MaxInt), 0);
  end
  else
  begin
    AStart := StrToIntDef(mHeader, 0);
    ACount := 1;
  end;
end;

/// <summary>Neue Zeilen AStart .. AStart+ACount-1 (1-basiert) als Bereich; ACount = 0 nennt die Zeile AStart, hinter
/// der Zeilen nur entfernt wurden (0 am Dateianfang).</summary>
procedure AddHunk(var AItem: TChangedLines; AStart, ACount: Integer);
var
  mSpan: TLineSpan;
begin
  if (ACount = 0) and (AStart >= 0) then
  begin
    AItem.Gaps := AItem.Gaps + [AStart];
  end
  else if (ACount > 0) and (AStart > 0) then
  begin
    mSpan.First := AStart - 1;
    mSpan.Last := AStart + ACount - 2;
    AItem.Spans := AItem.Spans + [mSpan];
  end;
end;

class function TChangedFiles.ParseHunks(const ALines: TArray<string>): TArray<TChangedLines>;
var
  mLine, mHeader: string;
  mCurrent, mStart, mCount: Integer;
  mItem: TChangedLines;
begin
  Result := nil;
  mCurrent := -1;
  for mLine in ALines do
  begin
    if StartsStr('+++ ', mLine) then
    begin
      mCurrent := -1;
      // "+++ b/Pfad", "+++ "b/Pfad"" bzw. "+++ /dev/null" bei gelöschten Dateien
      mHeader := UnquotePath(Copy(mLine, Length('+++ ') + 1, MaxInt));
      if StartsStr('b/', mHeader) then
      begin
        mItem := Default(TChangedLines);
        mItem.Path := Copy(mHeader, Length('b/') + 1, MaxInt);
        Result := Result + [mItem];
        mCurrent := High(Result);
      end;
    end
    else if StartsStr('@@ ', mLine) and (mCurrent >= 0) and HunkRange(mLine, mStart, mCount) then
    begin
      AddHunk(Result[mCurrent], mStart, mCount);
    end;
  end;
end;


/// <summary>Pfad ab Spalte 9 bei Status in Spalte 1 aus AStates; '' sonst.</summary>
function SvnPath(const ALine: string; const AStates: string): string;
begin
  Result := '';
  if (Length(ALine) < 9) or (Pos(ALine[1], AStates) = 0) then
  begin
    Exit;
  end;
  Result := Trim(Copy(ALine, 9, MaxInt));
end;

class function TChangedFiles.ParseSvnStatus(const ALines: TArray<string>; AUnversioned: Boolean): TArray<string>;
var
  mLine, mStates, mPath: string;
begin
  Result := nil;
  mStates := 'AMR';
  if AUnversioned then
  begin
    mStates := mStates + '?';
  end;
  for mLine in ALines do
  begin
    mPath := SvnPath(mLine, mStates);
    if mPath <> '' then
    begin
      Result := Result + [mPath];
    end;
  end;
end;

class function TChangedFiles.ParseSvnSummarize(const ALines: TArray<string>): TArray<string>;
var
  mLine, mPath: string;
begin
  Result := nil;
  for mLine in ALines do
  begin
    mPath := SvnPath(mLine, 'AMR');
    if mPath <> '' then
    begin
      Result := Result + [mPath];
    end;
  end;
end;

type
  /// <summary>Zustand beim Lesen von "svn diff": aktuelle Datei, nächste neue Zeile (0-basiert, -1 außerhalb eines
  /// Hunks) und Anfang entfernter Zeilen ohne "+" dahinter.</summary>
  TSvnDiffReader = record
    FItems: TArray<TChangedLines>;
    FCurrent: Integer;
    FNewLine: Integer;
    FRemovedAt: Integer;
    procedure Init;
    procedure FlushRemoved;
    procedure StartFile(const ALine: string);
    procedure StartHunk(const ALine: string);
    procedure AddLine;
    procedure ReadBody(const ALine: string);
    procedure ReadLine(const ALine: string);
  end;

/// <summary>Erste neue Zeile (0-basiert) aus "@@ -a,b +c,d @@"; -1 ohne "+c", 0 bei leerer neuer Fassung.</summary>
function SvnHunkStart(const ALine: string): Integer;
var
  mPlus, mSpace, mComma: Integer;
  mHeader: string;
begin
  Result := -1;
  mPlus := Pos(' +', ALine);
  mSpace := PosEx(' ', ALine, mPlus + 2);
  if (mPlus = 0) or (mSpace = 0) then
  begin
    Exit;
  end;
  mHeader := Copy(ALine, mPlus + 2, mSpace - mPlus - 2);
  mComma := Pos(',', mHeader);
  if mComma > 0 then
  begin
    mHeader := Copy(mHeader, 1, mComma - 1);
  end;
  Result := StrToIntDef(mHeader, -1) - 1;
  // "+0,0": Die neue Fassung ist leer.
  if Result = -1 then
  begin
    Result := 0;
  end;
end;

{ TSvnDiffReader }

procedure TSvnDiffReader.Init;
begin
  FItems := nil;
  FCurrent := -1;
  FNewLine := -1;
  FRemovedAt := -1;
end;

// Nur entfernte Zeilen (ohne "+" dahinter) als Lücke vor FNewLine, wie "+c,0" bei Git (#1353).
procedure TSvnDiffReader.FlushRemoved;
begin
  if (FRemovedAt >= 0) and (FCurrent >= 0) then
  begin
    FItems[FCurrent].Gaps := FItems[FCurrent].Gaps + [FRemovedAt];
  end;
  FRemovedAt := -1;
end;

procedure TSvnDiffReader.StartFile(const ALine: string);
var
  mHeader: string;
  mItem: TChangedLines;
begin
  FlushRemoved;
  // "+++ Src/Kunde.pas	(working copy)"
  mHeader := Copy(ALine, Length('+++ ') + 1, MaxInt);
  if Pos(#9, mHeader) > 0 then
  begin
    mHeader := Copy(mHeader, 1, Pos(#9, mHeader) - 1);
  end;
  mItem := Default(TChangedLines);
  mItem.Path := Trim(mHeader);
  FItems := FItems + [mItem];
  FCurrent := High(FItems);
  FNewLine := -1;
end;

procedure TSvnDiffReader.StartHunk(const ALine: string);
begin
  FlushRemoved;
  FNewLine := SvnHunkStart(ALine);
end;

procedure TSvnDiffReader.AddLine;
var
  mSpan: TLineSpan;
  mLast: Integer;
begin
  FRemovedAt := -1;
  mLast := High(FItems[FCurrent].Spans);
  // Benachbarte Zeilen zu einem Bereich zusammenfassen.
  if (mLast >= 0) and (FItems[FCurrent].Spans[mLast].Last = FNewLine - 1) then
  begin
    FItems[FCurrent].Spans[mLast].Last := FNewLine;
  end
  else
  begin
    mSpan.First := FNewLine;
    mSpan.Last := FNewLine;
    FItems[FCurrent].Spans := FItems[FCurrent].Spans + [mSpan];
  end;
  Inc(FNewLine);
end;

procedure TSvnDiffReader.ReadBody(const ALine: string);
begin
  case ALine[1] of
    ' ':
      begin
        FlushRemoved;
        Inc(FNewLine);
      end;
    '+':
      begin
        AddLine;
      end;
    '-':
      begin
        if FRemovedAt < 0 then
        begin
          FRemovedAt := FNewLine;
        end;
      end;
    '\':
      begin
      end;
  else
    begin
      FlushRemoved;
      FNewLine := -1;
    end;
  end;
end;

procedure TSvnDiffReader.ReadLine(const ALine: string);
begin
  if StartsStr('+++ ', ALine) then
  begin
    StartFile(ALine);
  end
  else if StartsStr('@@ ', ALine) and (FCurrent >= 0) then
  begin
    StartHunk(ALine);
  end
  else if (FCurrent >= 0) and (FNewLine >= 0) and (ALine <> '') then
  begin
    ReadBody(ALine);
  end;
end;

class function TChangedFiles.ParseSvnDiff(const ALines: TArray<string>): TArray<TChangedLines>;
var
  mReader: TSvnDiffReader;
  mLine: string;
begin
  mReader.Init;
  for mLine in ALines do
  begin
    mReader.ReadLine(mLine);
  end;
  mReader.FlushRemoved;
  Result := mReader.FItems;
end;

/// <summary>Position hinter "{$" bzw. "(*$" an AIndex; 0, wenn dort keine Direktive beginnt.</summary>
function DirectiveBody(const AUpper: string; AIndex: Integer): Integer;
begin
  Result := 0;
  if (AUpper[AIndex] = '{') and (Copy(AUpper, AIndex + 1, 1) = '$') then
  begin
    Result := AIndex + 2;
  end
  else if Copy(AUpper, AIndex, 3) = '(*$' then
  begin
    Result := AIndex + 3;
  end;
end;

/// <summary>Steht an AIndex ein Leerzeichen oder Tabulator?</summary>
function IsBlank(const AText: string; AIndex: Integer): Boolean;
begin
  Result := (AIndex <= Length(AText)) and CharInSet(AText[AIndex], [' ', #9]);
end;

/// <summary>Anfang des Arguments von $I bzw. $INCLUDE ab ABody; 0 bei anderen Direktiven und bei den Schaltern
/// $I+ und $I-.</summary>
function IncludeArgument(const AUpper: string; ABody: Integer): Integer;
var
  mAt: Integer;
begin
  Result := 0;
  mAt := ABody;
  if Copy(AUpper, mAt, 7) = 'INCLUDE' then
  begin
    Inc(mAt, 7);
  end
  else if (Copy(AUpper, mAt, 1) = 'I') and IsBlank(AUpper, mAt + 1) then
  begin
    Inc(mAt);
  end
  else
  begin
    Exit;
  end;
  if not IsBlank(AUpper, mAt) then
  begin
    Exit;
  end;
  while IsBlank(AUpper, mAt) do
  begin
    Inc(mAt);
  end;
  if (mAt <= Length(AUpper)) and not CharInSet(AUpper[mAt], ['+', '-']) then
  begin
    Result := mAt;
  end;
end;

/// <summary>Ende (ausschließlich) des Include-Namens ab AStart; bei einem Namen in Hochkommas steht AStart danach
/// hinter dem öffnenden.</summary>
function IncludeNameEnd(const AText: string; var AStart: Integer): Integer;
begin
  if AText[AStart] = '''' then
  begin
    Inc(AStart);
    Exit(PosEx('''', AText, AStart));
  end;
  Result := AStart;
  while (Result <= Length(AText)) and not CharInSet(AText[Result], [' ', #9, '}', '*', #10, #13]) do
  begin
    Inc(Result);
  end;
end;

class function TChangedFiles.IncludeNames(const AText: string): TArray<string>;
var
  mUpper: string;
  mIndex, mStart, mStop: Integer;
begin
  Result := nil;
  mUpper := UpperCase(AText);
  mIndex := 1;
  while mIndex <= Length(mUpper) do
  begin
    mStart := DirectiveBody(mUpper, mIndex);
    if mStart = 0 then
    begin
      Inc(mIndex);
      Continue;
    end;
    mIndex := mStart;
    mStart := IncludeArgument(mUpper, mStart);
    if mStart = 0 then
    begin
      Continue;
    end;
    mStop := IncludeNameEnd(AText, mStart);
    if mStop > mStart then
    begin
      Result := Result + [Copy(AText, mStart, mStop - mStart)];
      mIndex := mStop;
    end;
  end;
end;

function Normalize(const APath: string): string;
begin
  Result := LowerCase(StringReplace(APath, '\', '/', [rfReplaceAll]));
end;

function WithoutExt(const APath: string): string;
begin
  Result := Normalize(ChangeFileExt(APath, ''));
end;

function BaseName(const APath: string): string;
var
  mPath: string;
begin
  mPath := StringReplace(APath, '\', '/', [rfReplaceAll]);
  Result := Copy(mPath, LastDelimiter('/', mPath) + 1, MaxInt);
end;

function IncludeMatches(const AIncludeName, AIncludeFile: string): Boolean;
var
  mName: string;
begin
  // Abgleich über den Dateinamen; Suchpfade sind hier nicht bekannt.
  mName := BaseName(AIncludeName);
  if Pos('.', mName) = 0 then
  begin
    mName := mName + '.inc';
  end;
  Result := SameText(mName, BaseName(AIncludeFile));
end;

/// <summary>Wählt eine Änderung an AChanged alle Dateien? Projekt- und Konfigurationsdateien.</summary>
function ChangesAll(const AChanged: string): Boolean;
begin
  Result := MatchText(ExtractFileExt(AChanged), ['.dproj', '.dpk', '.dpr']) or
    SameText(ExtractFileName(AChanged), 'atlas.json');
end;

/// <summary>Betrifft die Änderung an AChanged ACandidate direkt: dieselbe Datei oder ihr Formular?</summary>
function DirectlyAffected(const ACandidate, AChanged: string): Boolean;
begin
  Result := (Normalize(ACandidate) = Normalize(AChanged)) or
    (MatchText(ExtractFileExt(AChanged), ['.dfm', '.fmx']) and (WithoutExt(ACandidate) = WithoutExt(AChanged)));
end;

/// <summary>Bindet ACandidate eine der geänderten Include-Dateien AIncludes ein?</summary>
function IncludesAny(const ACandidate: string; const AIncludes: TArray<string>;
  const AIncludeNamesOf: TIncludeNamesOf): Boolean;
var
  mName, mInclude: string;
begin
  for mName in AIncludeNamesOf(ACandidate) do
  begin
    for mInclude in AIncludes do
    begin
      if IncludeMatches(mName, mInclude) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

/// <summary>Markiert in AWanted die Kandidaten, die die Änderung an AChanged direkt betrifft.</summary>
procedure MarkAffected(const ACandidates: TArray<string>; const AChanged: string; var AWanted: TArray<Boolean>);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ACandidates) do
  begin
    if DirectlyAffected(ACandidates[mIndex], AChanged) then
    begin
      AWanted[mIndex] := True;
    end;
  end;
end;

class function TChangedFiles.Select(const AChanged, ACandidates: TArray<string>;
  const AIncludeNamesOf: TIncludeNamesOf): TArray<string>;
var
  mChanged: string;
  mIncludes: TArray<string>;
  mWanted: TArray<Boolean>;
  mIndex: Integer;
begin
  SetLength(mWanted, Length(ACandidates));
  mIncludes := nil;
  for mChanged in AChanged do
  begin
    if ChangesAll(mChanged) then
    begin
      Exit(Copy(ACandidates));
    end;
    if SameText(ExtractFileExt(mChanged), '.inc') then
    begin
      mIncludes := mIncludes + [mChanged];
    end;
    MarkAffected(ACandidates, mChanged, mWanted);
  end;
  Result := nil;
  for mIndex := 0 to High(ACandidates) do
  begin
    if not mWanted[mIndex] and (mIncludes <> nil) and Assigned(AIncludeNamesOf) then
    begin
      mWanted[mIndex] := IncludesAny(ACandidates[mIndex], mIncludes, AIncludeNamesOf);
    end;
    if mWanted[mIndex] then
    begin
      Result := Result + [ACandidates[mIndex]];
    end;
  end;
end;

class function TChangedFiles.LinesOf(const AChanges: TArray<TChangedLines>; const ARepoRoot, AFullPath: string;
  out ALines: TChangedLines): Boolean;
var
  mItem: TChangedLines;
begin
  for mItem in AChanges do
  begin
    if Normalize(FullPath(ARepoRoot, mItem.Path)) = Normalize(AFullPath) then
    begin
      ALines := mItem;
      Exit(True);
    end;
  end;
  ALines := Default(TChangedLines);
  Result := False;
end;

end.
