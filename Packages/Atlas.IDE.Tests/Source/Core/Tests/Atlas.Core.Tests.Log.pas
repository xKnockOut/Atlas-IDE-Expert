unit Atlas.Core.Tests.Log;

// Protokoll je Test (#2168), ohne VCL und Open Tools API, auch unter FPC
// prüfbar. Der NUnit-Bericht von DUnitX enthält keine Log-Zeilen; die liefert
// der Atlas-Logger im Testprojekt (Vorlage Setup/Vorlagen/Atlas.Testing.Log.pas):
// - Atlas legt vor dem Lauf die leere Seitendatei neben dem XML-Bericht an
//   (SideFileOf). Nur dann schreibt der Logger hinein, je Zeile
//   „Millisekunden<Tab>Art<Tab>Text“: A (Kopf, Formatversion), F+/F- (Fixture
//   beginnt bzw. endet, voller Name), S+/S- (Setup bzw. TearDown der Fixture),
//   T+/T- (Test beginnt bzw. endet, voller Name wie im Bericht), I/W/E
//   (Log-Meldung mit Stufe). Mehrzeilige Meldungen stehen als mehrere Zeilen.
// - In die Konsole schreibt der Logger dann Marken: cConsoleBegin + Name und
//   cConsoleEnd um jeden Test, cConsoleLog bei jeder Log-Meldung. Konsolenzeilen
//   (WriteLn außerhalb der Fixture) zwischen den Marken gehören zum Test und
//   stehen hinter der Log-Meldung, deren Marke ihnen vorausgeht. Eine Zeile,
//   die nur eine Log-Meldung wiederholt (Konsolen-Logger von DUnitX), entfällt.
// - Parse ordnet die Zeilen zu: in einem Test zum Test (Zeit ab Teststart);
//   im Setup bzw. TearDown der Fixture zu einem eigenen Eintrag der Fixture;
//   zwischen zwei Tests zum vorigen Test, markiert „nach Testende“ (Threads,
//   die den Test überdauern). Je Eintrag höchstens AMaxLines Zeilen, der Rest
//   wird gezählt.
// - Rows: Zeilen für die Anzeige mit Zeit, Stufe und Herkunft; Verweise
//   (Datei.pas:42, Datei.pas(42), Formate des Stacktraces, Unit.Klasse.Methode)
//   werden zu Sprungzielen in Units des Testprojekts.
// Zeilen sind 0-basiert.

interface

type
{$SCOPEDENUMS ON}
  TAtlasTestLogLevel = (Info, Warning, Error);
  /// <summary>Herkunft einer Zeile: Start und Finish setzt Atlas, Log kommt vom Logger, Console aus der Ausgabe.
  /// </summary>
  TAtlasTestLogOrigin = (Start, Finish, Log, Console);
{$SCOPEDENUMS OFF}

  TAtlasTestLogLine = record
    /// <summary>Millisekunden ab Start des Tests bzw. der Fixture; -1 unbekannt (Konsole).</summary>
    Ms: Int64;
    Level: TAtlasTestLogLevel;
    Origin: TAtlasTestLogOrigin;
    /// <summary>Kam nach dem Ende des Tests (zwischen zwei Tests).</summary>
    AfterEnd: Boolean;
    Text: string;
  end;

  /// <summary>Protokoll eines Tests bzw. (IsFixture) von Setup und TearDown einer Fixture.</summary>
  TAtlasTestLogEntry = record
    /// <summary>Voller Name wie im Bericht (Unit.Fixture.Methode[.Fall]) bzw. der Fixture.</summary>
    Name: string;
    IsFixture: Boolean;
    Lines: TArray<TAtlasTestLogLine>;
    /// <summary>Wegen AMaxLines weggelassene Zeilen.</summary>
    Dropped: Integer;
    /// <summary>Zeilen ohne Start und Ende (Zahl im Reiter).</summary>
    function Count: Integer;
  end;

  /// <summary>Protokoll eines Laufs.</summary>
  TAtlasTestLogRun = record
    /// <summary>Der Logger hat die Seitendatei geschrieben.</summary>
    HasLogger: Boolean;
    Entries: TArray<TAtlasTestLogEntry>;
    /// <summary>Ohne Logger: die Konsolenausgabe des ganzen Laufs (höchstens AMaxLines Zeilen).</summary>
    Output: TArray<string>;
    /// <summary>Ohne Logger weggelassene Zeilen der Ausgabe.</summary>
    OutputDropped: Integer;
    /// <summary>Index des Eintrags AName (ohne Groß-/Kleinschreibung); -1 ohne.</summary>
    function IndexOf(const AName: string): Integer;
  end;

  /// <summary>Eine Unit des Testprojekts für Sprungziele.</summary>
  TAtlasTestLogUnit = record
    UnitName: string;
    FileName: string;
  end;

  /// <summary>Zeile der Anzeige mit Sprungziel: FileName '' ohne; Line -1 mit Routine = Methode suchen.</summary>
  TAtlasTestLogRow = record
    Text: string;
    FileName: string;
    Line: Integer;
    /// <summary>Klasse.Methode bzw. Routine aus „Unit.Klasse.Methode“ ohne Zeile; '' ohne.</summary>
    Routine: string;
  end;

  /// <summary>Texte der Anzeige: Start, Finish, Warning/Error/Console (%s Text), AfterEnd (%s Zeile), Dropped (%d),
  /// Fixture (Überschrift des Eintrags einer Fixture), NoLogger (Hinweis ohne Logger, Zeilen mit #10), Output
  /// (Überschrift der Gesamtausgabe), Empty (keine Zeilen).</summary>
  TAtlasTestLogTexts = record
    Start: string;
    Finish: string;
    Warning: string;
    Error: string;
    Console: string;
    AfterEnd: string;
    Dropped: string;
    Fixture: string;
    NoLogger: string;
    Output: string;
    Empty: string;
    DecimalSeparator: Char;
  end;

  TAtlasTestLog = class
  public const
    /// <summary>Endung der Seitendatei neben dem XML-Bericht.</summary>
    cSideExtension = '.atlas-log';
    /// <summary>Formatversion im Kopf der Seitendatei.</summary>
    cFormat = '1';
    cConsoleBegin = '##atlas-test+ ';
    cConsoleEnd = '##atlas-test-';
    cConsoleLog = '##atlas-log';
    cMinMaxLines = 100;
    cMaxMaxLines = 100000;
  public
    /// <summary>Seitendatei zum XML-Bericht AReportFile.</summary>
    class function SideFileOf(const AReportFile: string): string; static;
    /// <summary>Protokoll aus der Seitendatei ASide ('' = kein Logger) und der Konsolenausgabe AConsole; je
    /// Eintrag höchstens AMaxLines Zeilen.</summary>
    class function Parse(const ASide, AConsole: string; AMaxLines: Integer): TAtlasTestLogRun; static;
    /// <summary>AOld um ANew ergänzt: Einträge von ANew ersetzen gleichnamige; Logger und Ausgabe aus ANew.
    /// </summary>
    class function Merged(const AOld, ANew: TAtlasTestLogRun): TAtlasTestLogRun; static;
    /// <summary>Zeit relativ zum Start: „01,190“ (Sekunden, Millisekunden); Leerraum gleicher Breite ohne Zeit.
    /// </summary>
    class function TimeText(AMs: Int64; ADecimalSeparator: Char): string; static;
    /// <summary>Sprungziel in AText: Datei und Zeile (AFileName, ALine) bzw. Routine ohne Zeile (ARoutine,
    /// ALine = -1) in einer Unit aus AUnits; False ohne.</summary>
    class function Reference(const AText: string; const AUnits: TArray<TAtlasTestLogUnit>; out AFileName: string;
      out ALine: Integer; out ARoutine: string): Boolean; static;
    /// <summary>Zeile des Kopfs der Routine ARoutine (Klasse.Methode bzw. Routine) im implementation-Teil von
    /// ALines; -1 ohne.</summary>
    class function RoutineLine(const ALines: TArray<string>; const ARoutine: string): Integer; static;
    /// <summary>Anzeige zu AName (Test, Fall oder Fixture) aus ARun: die Zeilen seines Eintrags, ohne eigenen Eintrag
    /// die der Einträge darunter mit Überschrift; ohne Logger der Hinweis und die Gesamtausgabe.</summary>
    class function Rows(const ARun: TAtlasTestLogRun; const AName: string; const AUnits: TArray<TAtlasTestLogUnit>;
      const ATexts: TAtlasTestLogTexts): TArray<TAtlasTestLogRow>; static;
    /// <summary>Zahl für den Reiter „Protokoll (n)“: Zeilen zu AName (wie Rows) ohne Start und Ende; 0 ohne.</summary>
    class function CountOf(const ARun: TAtlasTestLogRun; const AName: string): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  Atlas.Text.Chars,
  Atlas.Text.Lines,
  Atlas.Core.Tests.AssertLine;

const
  cFieldSeparator = #9;
  /// <summary>Felder je Zeile der Seitendatei: Millisekunden, Art, Text (mit Tabulatoren).</summary>
  cFieldCount = 3;
  cKindHead = 'A';
  cKindFixtureBegin = 'F+';
  cKindFixtureEnd = 'F-';
  cKindSetupBegin = 'S+';
  cKindSetupEnd = 'S-';
  cKindTestBegin = 'T+';
  cKindTestEnd = 'T-';
  cKindInfo = 'I';
  cKindWarning = 'W';
  cKindError = 'E';
  cMsPerSecond = 1000;
  /// <summary>Breite der Zeit „00,000“ samt Abstand dahinter.</summary>
  cTimeWidth = 6;
  cPasExtension = '.pas';

function TAtlasTestLogEntry.Count: Integer;
var
  mLine: TAtlasTestLogLine;
begin
  Result := Dropped;
  for mLine in Lines do
  begin
    if mLine.Origin in [TAtlasTestLogOrigin.Log, TAtlasTestLogOrigin.Console] then
    begin
      Inc(Result);
    end;
  end;
end;

function TAtlasTestLogRun.IndexOf(const AName: string): Integer;
begin
  for Result := 0 to High(Entries) do
  begin
    if SameText(Entries[Result].Name, AName) then
    begin
      Exit;
    end;
  end;
  Result := -1;
end;

type
  /// <summary>Zustand beim Lesen der Seitendatei.</summary>
  TLogReader = record
    Run: TAtlasTestLogRun;
    MaxLines: Integer;
    /// <summary>Laufender Test bzw. der zuletzt beendete (für „nach Testende“); -1 ohne.</summary>
    Test: Integer;
    Last: Integer;
    TestStart: Int64;
    /// <summary>Offene Fixtures (verschachtelt), die innerste zuletzt, mit ihrem Beginn.</summary>
    Fixtures: TArray<string>;
    FixtureStarts: TArray<Int64>;
    InSetup: Boolean;
    /// <summary>Eintrag AName (angelegt, wenn er fehlt).</summary>
    function EntryOf(const AName: string; AIsFixture: Boolean): Integer;
    /// <summary>Zeile an Eintrag AEntry anfügen, solange MaxLines nicht erreicht ist.</summary>
    procedure Add(AEntry: Integer; const ALine: TAtlasTestLogLine);
    /// <summary>Log-Meldung zum laufenden Test, zur Fixture oder zum vorigen Test.</summary>
    procedure Message(AMs: Int64; ALevel: TAtlasTestLogLevel; const AText: string);
    procedure Read(const ALine: string);
  end;

function NewLine(AMs: Int64; AOrigin: TAtlasTestLogOrigin; const AText: string): TAtlasTestLogLine;
begin
  Result := Default(TAtlasTestLogLine);
  Result.Ms := AMs;
  Result.Origin := AOrigin;
  Result.Text := AText;
end;

function TLogReader.EntryOf(const AName: string; AIsFixture: Boolean): Integer;
var
  mEntry: TAtlasTestLogEntry;
begin
  Result := Run.IndexOf(AName);
  if Result >= 0 then
  begin
    Exit;
  end;
  mEntry := Default(TAtlasTestLogEntry);
  mEntry.Name := AName;
  mEntry.IsFixture := AIsFixture;
  Result := Length(Run.Entries);
  SetLength(Run.Entries, Result + 1);
  Run.Entries[Result] := mEntry;
end;

procedure TLogReader.Add(AEntry: Integer; const ALine: TAtlasTestLogLine);
begin
  if Length(Run.Entries[AEntry].Lines) >= MaxLines then
  begin
    Inc(Run.Entries[AEntry].Dropped);
    Exit;
  end;
  Run.Entries[AEntry].Lines := Run.Entries[AEntry].Lines + [ALine];
end;

procedure TLogReader.Message(AMs: Int64; ALevel: TAtlasTestLogLevel; const AText: string);
var
  mLine: TAtlasTestLogLine;
begin
  mLine := NewLine(AMs, TAtlasTestLogOrigin.Log, AText);
  mLine.Level := ALevel;
  if Test >= 0 then
  begin
    mLine.Ms := AMs - TestStart;
    Add(Test, mLine);
  end
  else if (Last >= 0) and not InSetup then
  begin
    mLine.Ms := AMs - TestStart;
    mLine.AfterEnd := True;
    Add(Last, mLine);
  end
  else if Length(Fixtures) > 0 then
  begin
    mLine.Ms := AMs - FixtureStarts[High(FixtureStarts)];
    Add(EntryOf(Fixtures[High(Fixtures)], True), mLine);
  end;
end;

procedure TLogReader.Read(const ALine: string);
var
  mParts: TArray<string>;
  mMs: Int64;
  mKind, mText: string;
begin
  mParts := ALine.Split([cFieldSeparator], cFieldCount);
  if Length(mParts) < 2 then
  begin
    Exit;
  end;
  mMs := StrToInt64Def(mParts[0], 0);
  mKind := mParts[1];
  mText := '';
  if Length(mParts) > 2 then
  begin
    mText := mParts[2];
  end;
  if mKind = cKindTestBegin then
  begin
    Test := EntryOf(mText, False);
    TestStart := mMs;
    Last := -1;
    Add(Test, NewLine(0, TAtlasTestLogOrigin.Start, ''));
  end
  else if (mKind = cKindTestEnd) and (Test >= 0) then
  begin
    Add(Test, NewLine(mMs - TestStart, TAtlasTestLogOrigin.Finish, ''));
    Last := Test;
    Test := -1;
  end
  else if mKind = cKindFixtureBegin then
  begin
    Fixtures := Fixtures + [mText];
    FixtureStarts := FixtureStarts + [mMs];
    Last := -1;
  end
  else if (mKind = cKindFixtureEnd) and (Length(Fixtures) > 0) then
  begin
    SetLength(Fixtures, Length(Fixtures) - 1);
    SetLength(FixtureStarts, Length(FixtureStarts) - 1);
    Last := -1;
  end
  else if (mKind = cKindSetupBegin) or (mKind = cKindSetupEnd) then
  begin
    InSetup := mKind = cKindSetupBegin;
  end
  else if mKind = cKindInfo then
  begin
    Message(mMs, TAtlasTestLogLevel.Info, mText);
  end
  else if mKind = cKindWarning then
  begin
    Message(mMs, TAtlasTestLogLevel.Warning, mText);
  end
  else if mKind = cKindError then
  begin
    Message(mMs, TAtlasTestLogLevel.Error, mText);
  end;
end;

/// <summary>Zeilen von AText ohne Zeilenende (CRLF, LF, CR).</summary>
function LinesOf(const AText: string): TArray<string>;
begin
  Result := TTextLines.SplitLines(AText);
  // Ein Zeilenende am Schluss ergibt keine leere letzte Zeile.
  if (Length(Result) > 0) and (Result[High(Result)] = '') then
  begin
    SetLength(Result, Length(Result) - 1);
  end;
end;

/// <summary>Wiederholt ATrimmed eine Log-Meldung von AEntry (Konsolen-Logger von DUnitX, ggf. mit Stufe davor)?
/// </summary>
function RepeatsLog(const AEntry: TAtlasTestLogEntry; const ATrimmed: string): Boolean;
var
  mLine: TAtlasTestLogLine;
  mText: string;
begin
  Result := False;
  for mLine in AEntry.Lines do
  begin
    mText := Trim(mLine.Text);
    if (mLine.Origin = TAtlasTestLogOrigin.Log) and (mText <> '') and
      ((ATrimmed = mText) or ATrimmed.EndsWith(' ' + mText)) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Index hinter der AOrdinal-ten Log-Meldung (ab 1) von AEntry; vor dem Ende, wenn es sie nicht gibt.
/// </summary>
function InsertAt(const AEntry: TAtlasTestLogEntry; AOrdinal: Integer): Integer;
var
  mSeen: Integer;
begin
  mSeen := 0;
  for Result := 0 to High(AEntry.Lines) do
  begin
    if AEntry.Lines[Result].Origin = TAtlasTestLogOrigin.Log then
    begin
      Inc(mSeen);
    end;
    if (AEntry.Lines[Result].Origin = TAtlasTestLogOrigin.Finish) or
      ((mSeen > AOrdinal) and (AEntry.Lines[Result].Origin = TAtlasTestLogOrigin.Log)) then
    begin
      Exit;
    end;
  end;
  Result := Length(AEntry.Lines);
end;

/// <summary>Konsolenzeile AText in AEntry hinter der AOrdinal-ten Log-Meldung einfügen (Zeitpunkt unbekannt).
/// </summary>
procedure AddConsole(var AReader: TLogReader; AEntry, AOrdinal: Integer; const AText: string);
var
  mLines: TArray<TAtlasTestLogLine>;
  mAt: Integer;
begin
  if (Trim(AText) = '') or RepeatsLog(AReader.Run.Entries[AEntry], Trim(AText)) then
  begin
    Exit;
  end;
  mLines := AReader.Run.Entries[AEntry].Lines;
  if Length(mLines) >= AReader.MaxLines then
  begin
    Inc(AReader.Run.Entries[AEntry].Dropped);
    Exit;
  end;
  mAt := InsertAt(AReader.Run.Entries[AEntry], AOrdinal);
  Insert(NewLine(-1, TAtlasTestLogOrigin.Console, TrimRight(AText)), mLines, mAt);
  AReader.Run.Entries[AEntry].Lines := mLines;
end;

/// <summary>Konsolenzeilen zwischen den Marken der Tests zuordnen.</summary>
procedure ReadConsole(var AReader: TLogReader; const AConsole: string);
var
  mLine: string;
  mEntry, mOrdinal: Integer;
begin
  mEntry := -1;
  mOrdinal := 0;
  for mLine in LinesOf(AConsole) do
  begin
    if mLine.StartsWith(TAtlasTestLog.cConsoleBegin) then
    begin
      mEntry := AReader.EntryOf(Trim(Copy(mLine, Length(TAtlasTestLog.cConsoleBegin) + 1, MaxInt)), False);
      mOrdinal := 0;
    end
    else if mLine.StartsWith(TAtlasTestLog.cConsoleEnd) then
    begin
      mEntry := -1;
    end
    else if mLine.StartsWith(TAtlasTestLog.cConsoleLog) then
    begin
      Inc(mOrdinal);
    end
    else if mEntry >= 0 then
    begin
      AddConsole(AReader, mEntry, mOrdinal, mLine);
    end;
  end;
end;

/// <summary>Ohne Logger: die Ausgabe des Laufs, höchstens AMaxLines Zeilen.</summary>
procedure ReadOutput(var ARun: TAtlasTestLogRun; const AConsole: string; AMaxLines: Integer);
var
  mLines: TArray<string>;
begin
  mLines := LinesOf(AConsole);
  ARun.OutputDropped := Max(0, Length(mLines) - AMaxLines);
  ARun.Output := Copy(mLines, 0, AMaxLines);
end;

{ TAtlasTestLog }

class function TAtlasTestLog.SideFileOf(const AReportFile: string): string;
begin
  Result := ChangeFileExt(AReportFile, cSideExtension);
end;

class function TAtlasTestLog.Parse(const ASide, AConsole: string; AMaxLines: Integer): TAtlasTestLogRun;
var
  mReader: TLogReader;
  mLine: string;
begin
  mReader := Default(TLogReader);
  mReader.MaxLines := EnsureRange(AMaxLines, cMinMaxLines, cMaxMaxLines);
  mReader.Test := -1;
  mReader.Last := -1;
  mReader.Run.HasLogger := ASide.StartsWith('0' + cFieldSeparator + cKindHead) or
    (Pos(cFieldSeparator + cKindHead + cFieldSeparator, ASide) > 0);
  if not mReader.Run.HasLogger then
  begin
    ReadOutput(mReader.Run, AConsole, mReader.MaxLines);
    Exit(mReader.Run);
  end;
  for mLine in LinesOf(ASide) do
  begin
    mReader.Read(mLine);
  end;
  ReadConsole(mReader, AConsole);
  Result := mReader.Run;
end;

class function TAtlasTestLog.Merged(const AOld, ANew: TAtlasTestLogRun): TAtlasTestLogRun;
var
  mEntry: TAtlasTestLogEntry;
  mAt: Integer;
begin
  Result := ANew;
  Result.Entries := Copy(AOld.Entries);
  for mEntry in ANew.Entries do
  begin
    mAt := Result.IndexOf(mEntry.Name);
    if mAt >= 0 then
    begin
      Result.Entries[mAt] := mEntry;
    end
    else
    begin
      Result.Entries := Result.Entries + [mEntry];
    end;
  end;
end;

class function TAtlasTestLog.TimeText(AMs: Int64; ADecimalSeparator: Char): string;
begin
  if AMs < 0 then
  begin
    Exit(StringOfChar(' ', cTimeWidth));
  end;
  Result := Format('%.2d%s%.3d', [AMs div cMsPerSecond, ADecimalSeparator, AMs mod cMsPerSecond]);
end;

/// <summary>Bezeichnerkette (A.B.C) ab APos (1-basiert) in AText; '' ohne.</summary>
function IdentChainAt(const AText: string; APos: Integer): string;
var
  mEnd: Integer;
begin
  mEnd := APos;
  while (mEnd <= Length(AText)) and (TTextChars.IsIdentChar(AText[mEnd]) or
    ((AText[mEnd] = '.') and (mEnd < Length(AText)) and TTextChars.IsIdentStart(AText[mEnd + 1]))) do
  begin
    Inc(mEnd);
  end;
  Result := Copy(AText, APos, mEnd - APos);
  if (Result <> '') and not TTextChars.IsIdentStart(Result[1]) then
  begin
    Result := '';
  end;
end;

/// <summary>Routine hinter „AUnitName.“ als ganzem Wort in AText; '' ohne.</summary>
function RoutineAfter(const AText, AUnitName: string): string;
var
  mLower, mPrefix: string;
  mFrom, mAt: Integer;
  mParts: TArray<string>;
begin
  Result := '';
  mLower := AnsiLowerCase(AText);
  mPrefix := AnsiLowerCase(AUnitName) + '.';
  mFrom := 1;
  repeat
    mAt := Pos(mPrefix, mLower, mFrom);
    if mAt = 0 then
    begin
      Exit;
    end;
    mFrom := mAt + 1;
    if (mAt > 1) and (TTextChars.IsIdentChar(AText[mAt - 1]) or (AText[mAt - 1] = '.')) then
    begin
      Continue;
    end;
    mParts := IdentChainAt(AText, mAt + Length(mPrefix)).Split(['.']);
    // „Unit.pas“ ist eine Datei, keine Routine.
    if (Length(mParts) > 0) and not SameText(mParts[0], Copy(cPasExtension, 2, MaxInt)) then
    begin
      Result := mParts[0];
      if Length(mParts) > 1 then
      begin
        Result := Result + '.' + mParts[1];
      end;
      Exit;
    end;
  until False;
end;

/// <summary>Nennt AText die Unit AUnit mit Zeile (Formate des Stacktraces)? Nur mit „.pas“ oder einem Unitnamen
/// mit Punkt, damit ein Wort im Fließtext keine Zeile wird.</summary>
function LineOf(const AText: string; const AUnit: TAtlasTestLogUnit): Integer;
begin
  Result := -1;
  if (Pos(cPasExtension, AnsiLowerCase(AText)) > 0) or (Pos('.', AUnit.UnitName) > 0) then
  begin
    Result := TAtlasAssertLine.FromStackTrace(AText, AUnit.UnitName, AUnit.FileName, MaxInt);
  end;
end;

class function TAtlasTestLog.Reference(const AText: string; const AUnits: TArray<TAtlasTestLogUnit>;
  out AFileName: string; out ALine: Integer; out ARoutine: string): Boolean;
var
  mUnit: TAtlasTestLogUnit;
  mLine, mLongest: Integer;
  mRoutine: string;
begin
  AFileName := '';
  ALine := -1;
  ARoutine := '';
  mLongest := -1;
  // „Rechner“ steht auch in „Rechner.Tests 42“: der längste passende Unitname gilt, eine Zeile vor der Routine.
  for mUnit in AUnits do
  begin
    mLine := LineOf(AText, mUnit);
    mRoutine := '';
    if mLine < 0 then
    begin
      mRoutine := RoutineAfter(AText, mUnit.UnitName);
    end;
    if ((mLine >= 0) or (mRoutine <> '')) and (Length(mUnit.UnitName) > mLongest) and
      ((mLine >= 0) or (ALine < 0)) then
    begin
      mLongest := Length(mUnit.UnitName);
      AFileName := mUnit.FileName;
      ALine := mLine;
      ARoutine := mRoutine;
    end;
  end;
  Result := AFileName <> '';
end;

/// <summary>Beginnt ATrimmed (klein) mit dem Kopf einer Routine ARoutine (klein)?</summary>
function IsRoutineHead(const ATrimmed, ARoutine: string): Boolean;
const
  cHeads: array[0..4] of string = ('procedure ', 'function ', 'constructor ', 'destructor ', 'operator ');
var
  mHead, mRest: string;
begin
  Result := False;
  mRest := ATrimmed;
  if mRest.StartsWith('class ') then
  begin
    mRest := TrimLeft(Copy(mRest, Length('class ') + 1, MaxInt));
  end;
  for mHead in cHeads do
  begin
    if mRest.StartsWith(mHead + ARoutine) then
    begin
      mRest := Copy(mRest, Length(mHead + ARoutine) + 1, MaxInt);
      Exit((mRest = '') or not TTextChars.IsIdentChar(mRest[1]));
    end;
  end;
end;

class function TAtlasTestLog.RoutineLine(const ALines: TArray<string>; const ARoutine: string): Integer;
var
  mRoutine: string;
  mInImplementation: Boolean;
begin
  mRoutine := AnsiLowerCase(ARoutine);
  mInImplementation := False;
  for Result := 0 to High(ALines) do
  begin
    if SameText(Trim(ALines[Result]), 'implementation') then
    begin
      mInImplementation := True;
    end
    else if mInImplementation and IsRoutineHead(AnsiLowerCase(Trim(ALines[Result])), mRoutine) then
    begin
      Exit;
    end;
  end;
  Result := -1;
end;

/// <summary>Zeile der Anzeige mit Sprungziel aus AText.</summary>
function NewRow(const AText, ASource: string; const AUnits: TArray<TAtlasTestLogUnit>): TAtlasTestLogRow;
begin
  Result := Default(TAtlasTestLogRow);
  Result.Text := AText;
  Result.Line := -1;
  if ASource <> '' then
  begin
    TAtlasTestLog.Reference(ASource, AUnits, Result.FileName, Result.Line, Result.Routine);
  end;
end;

/// <summary>Text einer Zeile: Zeit, dann Start, Ende oder die Meldung mit Stufe bzw. Herkunft.</summary>
function LineText(const ALine: TAtlasTestLogLine; const ATexts: TAtlasTestLogTexts): string;
begin
  case ALine.Origin of
    TAtlasTestLogOrigin.Start:
      Result := ATexts.Start;
    TAtlasTestLogOrigin.Finish:
      Result := ATexts.Finish;
    TAtlasTestLogOrigin.Console:
      Result := Format(ATexts.Console, [ALine.Text]);
  else
    case ALine.Level of
      TAtlasTestLogLevel.Warning:
        Result := Format(ATexts.Warning, [ALine.Text]);
      TAtlasTestLogLevel.Error:
        Result := Format(ATexts.Error, [ALine.Text]);
    else
      Result := ALine.Text;
    end;
  end;
  if ALine.AfterEnd then
  begin
    Result := Format(ATexts.AfterEnd, [Result]);
  end;
  Result := TAtlasTestLog.TimeText(ALine.Ms, ATexts.DecimalSeparator) + '  ' + Result;
end;

/// <summary>Zeilen des Hinweises ohne Logger und der Gesamtausgabe.</summary>
function NoLoggerRows(const ARun: TAtlasTestLogRun; const AUnits: TArray<TAtlasTestLogUnit>;
  const ATexts: TAtlasTestLogTexts): TArray<TAtlasTestLogRow>;
var
  mText: string;
begin
  Result := nil;
  for mText in ATexts.NoLogger.Split([#10]) do
  begin
    Result := Result + [NewRow(mText, '', AUnits)];
  end;
  if Length(ARun.Output) = 0 then
  begin
    Exit;
  end;
  Result := Result + [NewRow(ATexts.Output, '', AUnits)];
  for mText in ARun.Output do
  begin
    Result := Result + [NewRow(mText, mText, AUnits)];
  end;
  if ARun.OutputDropped > 0 then
  begin
    Result := Result + [NewRow(Format(ATexts.Dropped, [ARun.OutputDropped]), '', AUnits)];
  end;
end;

/// <summary>Einträge zu AName: der Eintrag selbst, sonst die darunter (Fälle eines Tests, Tests einer Fixture).
/// </summary>
function Matching(const ARun: TAtlasTestLogRun; const AName: string): TArray<Integer>;
var
  mIndex: Integer;
begin
  mIndex := ARun.IndexOf(AName);
  if mIndex >= 0 then
  begin
    Result := [mIndex];
    Exit;
  end;
  Result := nil;
  for mIndex := 0 to High(ARun.Entries) do
  begin
    // Fälle heißen „Methode.Fall“ bzw. „Methode(1,2)“ (AutoNameTestCase).
    if not ARun.Entries[mIndex].IsFixture and (StartsText(AName + '.', ARun.Entries[mIndex].Name) or
      StartsText(AName + '(', ARun.Entries[mIndex].Name)) then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

/// <summary>Zeilen eines Eintrags; AHeader: Name als Überschrift (mehrere Einträge).</summary>
function EntryRows(const AEntry: TAtlasTestLogEntry; AHeader: Boolean; const AUnits: TArray<TAtlasTestLogUnit>;
  const ATexts: TAtlasTestLogTexts): TArray<TAtlasTestLogRow>;
var
  mLine: TAtlasTestLogLine;
begin
  Result := nil;
  if AEntry.IsFixture then
  begin
    Result := [NewRow(ATexts.Fixture, '', AUnits)];
  end
  else if AHeader then
  begin
    Result := [NewRow(AEntry.Name, '', AUnits)];
  end;
  for mLine in AEntry.Lines do
  begin
    Result := Result + [NewRow(LineText(mLine, ATexts), mLine.Text, AUnits)];
  end;
  if AEntry.Dropped > 0 then
  begin
    Result := Result + [NewRow(Format(ATexts.Dropped, [AEntry.Dropped]), '', AUnits)];
  end;
end;

class function TAtlasTestLog.Rows(const ARun: TAtlasTestLogRun; const AName: string;
  const AUnits: TArray<TAtlasTestLogUnit>; const ATexts: TAtlasTestLogTexts): TArray<TAtlasTestLogRow>;
var
  mMatching: TArray<Integer>;
  mIndex: Integer;
begin
  if not ARun.HasLogger then
  begin
    Exit(NoLoggerRows(ARun, AUnits, ATexts));
  end;
  mMatching := Matching(ARun, AName);
  if Length(mMatching) = 0 then
  begin
    Result := [NewRow(ATexts.Empty, '', AUnits)];
    Exit;
  end;
  Result := nil;
  for mIndex in mMatching do
  begin
    Result := Result + EntryRows(ARun.Entries[mIndex], Length(mMatching) > 1, AUnits, ATexts);
  end;
end;

class function TAtlasTestLog.CountOf(const ARun: TAtlasTestLogRun; const AName: string): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex in Matching(ARun, AName) do
  begin
    Inc(Result, ARun.Entries[mIndex].Count);
  end;
end;

end.
