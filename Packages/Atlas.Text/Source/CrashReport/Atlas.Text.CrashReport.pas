unit Atlas.Text.CrashReport;

// Liest Absturzberichte mit Aufrufstapeln (#74):
// - madExcept (bugreport.txt): Kopf „exception class : …“, je Thread ein
//   Abschnitt „main thread ($1A2C):“ mit Zeilen
//   „0045a1b2 +012 Project1.exe Unit1  42 +3 TForm1.Button1Click“, dazu die
//   Liste „modules:“ mit Basisadressen,
// - EurekaLog 6 und 7: Tabellen mit senkrechten Strichen; die Spalten erkennt
//   der Leser an der Kopfzeile (Address, Module, Unit, Class, Procedure,
//   Line), Threads an „|*Exception Thread: ID=…“, Module an der Tabelle mit
//   Handle und Name,
// - JclDebug: „[0045A1B2]{Project1.exe} Unit1.TForm1.Button1Click (Line 42,
//   "Unit1.pas" + 3) + $12“,
// - die Meldung einer Exception allein: „Access violation at address
//   0045A1B2 in module 'Project1.exe'“ (auch deutsch „bei Adresse … in Modul“).
// Leckberichte von FastMM liest Atlas.Text.LeakReport. In Atlas.Text, weil
// Plugin (Berichte einfügen, Stacktrace anklicken) und Server (MCP
// analyze_report, resolve_address) denselben Leser brauchen.

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  /// <summary>Herkunft eines Berichts; None, wenn der Text keinen Absturz beschreibt.</summary>
  TCrashReportKind = (None, MadExcept, EurekaLog, JclDebug, ExceptionText);
{$SCOPEDENUMS OFF}

  /// <summary>Eine Zeile des Aufrufstapels; ohne Debug-Informationen nur Adresse und Modul.</summary>
  TCrashFrame = record
    Address: UInt64;
    Module: string;
    FileName: string;
    UnitName: string;
    /// <summary>Routine mit Klasse, z. B. TForm1.Button1Click.</summary>
    Routine: string;
    /// <summary>Zeile ab 1; 0 ohne Zeilennummer.</summary>
    Line: Integer;
    function HasLocation: Boolean;
  end;

  TCrashThread = record
    Name: string;
    /// <summary>Thread, in dem die Exception auftrat.</summary>
    Crashed: Boolean;
    Frames: TArray<TCrashFrame>;
  end;

  /// <summary>Geladenes Modul (EXE, DLL, BPL) mit Basisadresse.</summary>
  TCrashModule = record
    Name: string;
    Base: UInt64;
  end;

  TCrashReport = record
    Kind: TCrashReportKind;
    ExceptionClass: string;
    ExceptionMessage: string;
    /// <summary>Absturzadresse; 0 ohne.</summary>
    Address: UInt64;
    /// <summary>Modul der Absturzadresse; '' ohne.</summary>
    Module: string;
    Threads: TArray<TCrashThread>;
    Modules: TArray<TCrashModule>;
    function IsEmpty: Boolean;
    /// <summary>Stapel des Threads mit der Exception (sonst des ersten Threads); nil ohne.</summary>
    function CrashFrames: TArray<TCrashFrame>;
    /// <summary>Basisadresse eines Moduls (ohne Groß-/Kleinschreibung, mit oder ohne Pfad); False ohne.</summary>
    function TryBaseOf(const AModule: string; out ABase: UInt64): Boolean;
  end;

  TCrashReports = class
  public
    /// <summary>Bericht aus einem eingefügten Text; Kind = None, wenn keiner darin steht.</summary>
    class function Parse(const AText: string): TCrashReport; static;
    /// <summary>Stapelzeile von madExcept; False bei anderem Text.</summary>
    class function ParseMadExceptFrame(const ALine: string; out AFrame: TCrashFrame): Boolean; static;
    /// <summary>Stapelzeile von JclDebug; False bei anderem Text.</summary>
    class function ParseJclFrame(const ALine: string; out AFrame: TCrashFrame): Boolean; static;
    /// <summary>Unit der RTL, VCL, FMX, Windows-API oder eines Werkzeugs zur Fehlersuche?</summary>
    class function IsLibraryUnit(const AUnitName: string): Boolean; static;
    /// <summary>Erste Zeile mit Zeilennummer außerhalb der Bibliotheken; -1 ohne.</summary>
    class function SiteOf(const AFrames: TArray<TCrashFrame>): Integer; static;
    /// <summary>Hexadezimalzahl ohne Präfix oder mit „$“/„0x“; False bei anderem Text.</summary>
    class function TryParseHex(const AText: string; out AValue: UInt64): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Text.Lines;

const
  cBitsPerHexDigit = 4;
  cMaxHexDigits = 16;
  cMinAddressDigits = 6;
  cEurekaMark = 'eurekalog';
  cMadExceptMark = 'madexcept';
  cCrashedThreadMark = 'exception thread';
  // Unit-Namen der Bibliotheken: Präfix (mit Punkt) oder ganzer Name.
  cLibraryPrefixes: array[0..12] of string = ('system.', 'vcl.', 'winapi.', 'fmx.', 'data.', 'xml.', 'soap.', 'web.',
    'rest.', 'firedac.', 'datasnap.', 'ibx.', 'jcl');
  cLibraryUnits: array[0..18] of string = ('system', 'sysinit', 'sysutils', 'classes', 'forms', 'controls', 'windows',
    'messages', 'stdctrls', 'dialogs', 'graphics', 'madexcept', 'madbasic', 'madstacktrace', 'madmapfile',
    'ebase', 'eexception', 'estack', 'fastmm4');

type
  TCrashLines = TArray<string>;

{ TCrashFrame }

function TCrashFrame.HasLocation: Boolean;
begin
  Result := (UnitName <> '') or (FileName <> '') or (Routine <> '');
end;

{ TCrashReport }

function TCrashReport.IsEmpty: Boolean;
begin
  Result := Kind = TCrashReportKind.None;
end;

function TCrashReport.CrashFrames: TArray<TCrashFrame>;
var
  mThread: TCrashThread;
begin
  Result := nil;
  for mThread in Threads do
  begin
    if mThread.Crashed then
    begin
      Exit(mThread.Frames);
    end;
  end;
  if Length(Threads) > 0 then
  begin
    Result := Threads[0].Frames;
  end;
end;

function TCrashReport.TryBaseOf(const AModule: string; out ABase: UInt64): Boolean;
var
  mModule: TCrashModule;
begin
  ABase := 0;
  for mModule in Modules do
  begin
    if SameText(ExtractFileName(mModule.Name), ExtractFileName(AModule)) then
    begin
      ABase := mModule.Base;
      Exit(True);
    end;
  end;
  Result := False;
end;

{ Hilfen }

function IsHexDigit(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['0'..'9', 'A'..'F', 'a'..'f']);
end;

function IsDigits(const AText: string): Boolean;
var
  mChar: Char;
begin
  Result := AText <> '';
  for mChar in AText do
  begin
    if not CharInSet(mChar, ['0'..'9']) then
    begin
      Exit(False);
    end;
  end;
end;

/// <summary>Wörter einer Zeile, durch Leerzeichen und Tabulatoren getrennt.</summary>
function WordsOf(const ALine: string): TArray<string>;
var
  mPart: string;
begin
  Result := nil;
  for mPart in ALine.Replace(#9, ' ').Split([' ']) do
  begin
    if mPart <> '' then
    begin
      Result := Result + [mPart];
    end;
  end;
end;

/// <summary>Adresse aus 6 bis 16 Hexziffern ohne Präfix; False bei anderem Text.</summary>
function TryAddress(const AText: string; out AValue: UInt64): Boolean;
begin
  Result := (Length(AText) >= cMinAddressDigits) and TCrashReports.TryParseHex(AText, AValue);
end;

/// <summary>„Schlüssel : Wert“; der Schlüssel ohne vorangestellte Nummer („2.5 Type“ → „Type“).</summary>
function TryKeyValue(const ALine: string; out AKey, AValue: string): Boolean;
var
  mColon: Integer;
  mWords: TArray<string>;
begin
  mColon := Pos(':', ALine);
  Result := (mColon > 1) and (Pos('|', ALine) = 0);
  if not Result then
  begin
    Exit;
  end;
  AValue := Trim(Copy(ALine, mColon + 1, MaxInt));
  mWords := WordsOf(Copy(ALine, 1, mColon - 1));
  if (Length(mWords) > 1) and CharInSet(mWords[0][1], ['0'..'9']) then
  begin
    mWords := Copy(mWords, 1, MaxInt);
  end;
  AKey := LowerCase(string.Join(' ', mWords));
  Result := AKey <> '';
end;

/// <summary>Zeile „42[3]“ oder „42“; 0 ohne Zahl.</summary>
function LineNumberOf(const AText: string): Integer;
var
  mText: string;
begin
  mText := Trim(AText);
  if Pos('[', mText) > 0 then
  begin
    mText := Copy(mText, 1, Pos('[', mText) - 1);
  end;
  if not TryStrToInt(mText, Result) or (Result < 0) then
  begin
    Result := 0;
  end;
end;

procedure AddFrame(var AReport: TCrashReport; const AFrame: TCrashFrame);
var
  mThread: TCrashThread;
begin
  if Length(AReport.Threads) = 0 then
  begin
    mThread := Default(TCrashThread);
    mThread.Crashed := True;
    AReport.Threads := AReport.Threads + [mThread];
  end;
  AReport.Threads[High(AReport.Threads)].Frames := AReport.Threads[High(AReport.Threads)].Frames + [AFrame];
end;

procedure AddThread(var AReport: TCrashReport; const AName: string; ACrashed: Boolean);
var
  mThread: TCrashThread;
begin
  mThread := Default(TCrashThread);
  mThread.Name := AName;
  mThread.Crashed := ACrashed;
  AReport.Threads := AReport.Threads + [mThread];
end;

procedure AddModule(var AReport: TCrashReport; const AName: string; ABase: UInt64);
var
  mModule: TCrashModule;
begin
  mModule.Name := AName;
  mModule.Base := ABase;
  AReport.Modules := AReport.Modules + [mModule];
end;

/// <summary>Threads ohne Zeilen fallen weg; ohne Kennzeichnung gilt der erste als Thread der Exception.</summary>
procedure TidyThreads(var AReport: TCrashReport);
var
  mThreads: TArray<TCrashThread>;
  mThread: TCrashThread;
  mAnyCrashed: Boolean;
begin
  mThreads := nil;
  mAnyCrashed := False;
  for mThread in AReport.Threads do
  begin
    if Length(mThread.Frames) > 0 then
    begin
      mThreads := mThreads + [mThread];
      mAnyCrashed := mAnyCrashed or mThread.Crashed;
    end;
  end;
  if not mAnyCrashed and (Length(mThreads) > 0) then
  begin
    mThreads[0].Crashed := True;
  end;
  AReport.Threads := mThreads;
end;

{ Meldung einer Exception }

/// <summary>Hexzahl hinter dem ersten Wort „address“/„Adresse“; False ohne.</summary>
function TryMessageAddress(const AText: string; out AAddress: UInt64): Boolean;
var
  mWords: TArray<string>;
  mIndex: Integer;
begin
  mWords := WordsOf(AText);
  for mIndex := 0 to High(mWords) - 1 do
  begin
    if (SameText(mWords[mIndex], 'address') or SameText(mWords[mIndex], 'adresse')) and
      TryAddress(mWords[mIndex + 1].TrimRight(['.', ',']), AAddress) then
    begin
      Exit(True);
    end;
  end;
  AAddress := 0;
  Result := False;
end;

/// <summary>Erster Name in einfachen Anführungszeichen mit Punkt (Modul); '' ohne.</summary>
function QuotedModule(const AText: string): string;
var
  mParts: TArray<string>;
  mIndex: Integer;
begin
  mParts := AText.Split(['''']);
  mIndex := 1;
  while mIndex <= High(mParts) - 1 do
  begin
    if (Pos('.', mParts[mIndex]) > 1) and (Pos(' ', mParts[mIndex]) = 0) then
    begin
      Exit(mParts[mIndex]);
    end;
    Inc(mIndex, 2);
  end;
  Result := '';
end;

/// <summary>Absturzadresse und Modul aus der Meldung übernehmen, wenn noch keine bekannt sind.</summary>
procedure TakeMessage(var AReport: TCrashReport; const AMessage: string);
var
  mAddress: UInt64;
begin
  if (AReport.Address = 0) and TryMessageAddress(AMessage, mAddress) then
  begin
    AReport.Address := mAddress;
    if AReport.Module = '' then
    begin
      AReport.Module := QuotedModule(AMessage);
    end;
  end;
end;

{ madExcept }

/// <summary>Kopfzeile eines Threads: „main thread ($1a2c):“, „thread $2b3c (TWorker):“.</summary>
function IsMadThreadHeader(const ALine: string): Boolean;
var
  mTrimmed: string;
begin
  mTrimmed := Trim(ALine);
  Result := mTrimmed.EndsWith(':') and (Pos('|', mTrimmed) = 0) and
    (StartsText('main thread', mTrimmed) or StartsText('thread $', mTrimmed));
end;

/// <summary>Zeile der Modulliste „00400000 Project1.exe 1.0.0.0 C:\…“.</summary>
function TryMadModule(const ALine: string; out AName: string; out ABase: UInt64): Boolean;
var
  mWords: TArray<string>;
begin
  mWords := WordsOf(ALine);
  Result := (Length(mWords) >= 2) and TryAddress(mWords[0], ABase) and (Pos('.', mWords[1]) > 1);
  if Result then
  begin
    AName := mWords[1];
  end;
end;

/// <summary>Unit, Zeile und Routine aus den Wörtern zwischen Modul und Ende.</summary>
procedure TakeMadMiddle(const AWords: TArray<string>; var AFrame: TCrashFrame);
var
  mIndex: Integer;
begin
  // Wörter 3 .. High-1: [Unit] [Zeile] [+Versatz]
  for mIndex := 3 to High(AWords) - 1 do
  begin
    if IsDigits(AWords[mIndex]) then
    begin
      AFrame.Line := StrToInt(AWords[mIndex]);
    end
    else if not AWords[mIndex].StartsWith('+') and (AFrame.UnitName = '') then
    begin
      AFrame.UnitName := AWords[mIndex];
    end;
  end;
end;

class function TCrashReports.ParseMadExceptFrame(const ALine: string; out AFrame: TCrashFrame): Boolean;
var
  mWords: TArray<string>;
begin
  AFrame := Default(TCrashFrame);
  // 0045a1b2 +012 Project1.exe Unit1  42  +3 TForm1.Button1Click
  mWords := WordsOf(ALine);
  Result := (Length(mWords) >= 3) and TryAddress(mWords[0], AFrame.Address) and mWords[1].StartsWith('+') and
    (Pos('.', mWords[2]) > 1);
  if not Result then
  begin
    Exit;
  end;
  AFrame.Module := mWords[2];
  if Length(mWords) >= 4 then
  begin
    AFrame.Routine := mWords[High(mWords)];
    TakeMadMiddle(mWords, AFrame);
  end;
end;

type
{$SCOPEDENUMS ON}
  TMadSection = (Head, Thread, Modules);
{$SCOPEDENUMS OFF}

procedure TakeMadHead(var AReport: TCrashReport; const ALine: string);
var
  mKey, mValue: string;
begin
  if not TryKeyValue(ALine, mKey, mValue) then
  begin
    Exit;
  end;
  if mKey = 'exception class' then
  begin
    AReport.ExceptionClass := mValue;
  end
  else if mKey = 'exception message' then
  begin
    AReport.ExceptionMessage := mValue;
  end
  else if (mKey = 'exception address') and TryAddress(mValue, AReport.Address) then
  begin
    AReport.Module := '';
  end;
end;

procedure TakeMadLine(var AReport: TCrashReport; const ALine: string; var ASection: TMadSection);
var
  mFrame: TCrashFrame;
  mName: string;
  mBase: UInt64;
begin
  if IsMadThreadHeader(ALine) then
  begin
    // madExcept schreibt den Thread der Exception zuerst.
    AddThread(AReport, Trim(ALine).TrimRight([':']), Length(AReport.Threads) = 0);
    ASection := TMadSection.Thread;
  end
  else if SameText(Trim(ALine), 'modules:') then
  begin
    ASection := TMadSection.Modules;
  end
  else if (ASection = TMadSection.Modules) and TryMadModule(ALine, mName, mBase) then
  begin
    AddModule(AReport, mName, mBase);
  end
  else if (ASection <> TMadSection.Modules) and TCrashReports.ParseMadExceptFrame(ALine, mFrame) then
  begin
    AddFrame(AReport, mFrame);
  end
  else if ASection = TMadSection.Head then
  begin
    TakeMadHead(AReport, ALine);
  end;
end;

function ReadMadExcept(const ALines: TCrashLines; out AReport: TCrashReport): Boolean;
var
  mLine: string;
  mSection: TMadSection;
begin
  AReport := Default(TCrashReport);
  mSection := TMadSection.Head;
  for mLine in ALines do
  begin
    TakeMadLine(AReport, mLine, mSection);
  end;
  TidyThreads(AReport);
  Result := Length(AReport.CrashFrames) > 0;
  if Result then
  begin
    AReport.Kind := TCrashReportKind.MadExcept;
  end;
end;

{ EurekaLog }

type
  /// <summary>Spalten der zuletzt gelesenen Kopfzeile einer Tabelle; -1 = fehlt.</summary>
  TEurekaColumns = record
    Count: Integer;
    Address, Module, UnitName, ClassName, Routine, Line, Handle, Name: Integer;
    function IsStack: Boolean;
    function IsModules: Boolean;
  end;

function TEurekaColumns.IsStack: Boolean;
begin
  Result := (Address >= 0) and (Module >= 0) and (Routine >= 0);
end;

function TEurekaColumns.IsModules: Boolean;
begin
  Result := (Handle >= 0) and (Name >= 0);
end;

/// <summary>Zellen einer Tabellenzeile „|a |b |“; nil, wenn die Zeile keine Tabellenzeile ist.</summary>
function CellsOf(const ALine: string): TArray<string>;
var
  mTrimmed: string;
  mIndex: Integer;
begin
  Result := nil;
  mTrimmed := Trim(ALine);
  if (Length(mTrimmed) < 2) or (mTrimmed[1] <> '|') or (mTrimmed[Length(mTrimmed)] <> '|') then
  begin
    Exit;
  end;
  Result := Copy(mTrimmed, 2, Length(mTrimmed) - 2).Split(['|']);
  for mIndex := 0 to High(Result) do
  begin
    Result[mIndex] := Trim(Result[mIndex]);
  end;
end;

const
  // Spaltennamen der Kopfzeile in der Reihenfolge von TEurekaColumn; „Procedure“ als Anfang („Procedure/Method“).
  cEurekaColumnNames: array[0..7] of string = ('address', 'module', 'unit', 'class', 'procedure', 'line', 'handle',
    'name');

function ColumnSlot(var AColumns: TEurekaColumns; ASlot: Integer): PInteger;
begin
  case ASlot of
    0:
      Result := @AColumns.Address;
    1:
      Result := @AColumns.Module;
    2:
      Result := @AColumns.UnitName;
    3:
      Result := @AColumns.ClassName;
    4:
      Result := @AColumns.Routine;
    5:
      Result := @AColumns.Line;
    6:
      Result := @AColumns.Handle;
  else
    Result := @AColumns.Name;
  end;
end;

procedure SetColumn(var AColumns: TEurekaColumns; const ACell: string; AIndex: Integer);
var
  mSlot: Integer;
begin
  for mSlot := 0 to High(cEurekaColumnNames) do
  begin
    if SameText(ACell, cEurekaColumnNames[mSlot]) or
      ((cEurekaColumnNames[mSlot] = 'procedure') and StartsText('procedure', ACell)) then
    begin
      ColumnSlot(AColumns, mSlot)^ := AIndex;
      Exit;
    end;
  end;
end;

/// <summary>Kopfzeile einer Tabelle; False, wenn die Zellen keine Stapel- oder Modultabelle beschreiben.</summary>
function TryEurekaHeader(const ACells: TArray<string>; out AColumns: TEurekaColumns): Boolean;
var
  mIndex: Integer;
begin
  AColumns := Default(TEurekaColumns);
  for mIndex := 0 to High(cEurekaColumnNames) do
  begin
    ColumnSlot(AColumns, mIndex)^ := -1;
  end;
  AColumns.Count := Length(ACells);
  for mIndex := 0 to High(ACells) do
  begin
    SetColumn(AColumns, ACells[mIndex], mIndex);
  end;
  Result := AColumns.IsStack or AColumns.IsModules;
end;

function CellAt(const ACells: TArray<string>; AIndex: Integer): string;
begin
  Result := '';
  if (AIndex >= 0) and (AIndex <= High(ACells)) then
  begin
    Result := ACells[AIndex];
  end;
end;

/// <summary>Unit-Spalte: EurekaLog 6 nennt die Datei („Unit1.pas“), EurekaLog 7 die Unit.</summary>
procedure TakeEurekaUnit(const AText: string; var AFrame: TCrashFrame);
begin
  if EndsText('.pas', AText) or EndsText('.dpr', AText) or EndsText('.inc', AText) then
  begin
    AFrame.FileName := AText;
    AFrame.UnitName := ChangeFileExt(AText, '');
  end
  else
  begin
    AFrame.UnitName := AText;
  end;
end;

function TryEurekaFrame(const ACells: TArray<string>; const AColumns: TEurekaColumns;
  out AFrame: TCrashFrame): Boolean;
var
  mClass: string;
begin
  AFrame := Default(TCrashFrame);
  Result := (Length(ACells) = AColumns.Count) and TryAddress(CellAt(ACells, AColumns.Address), AFrame.Address);
  if not Result then
  begin
    Exit;
  end;
  AFrame.Module := CellAt(ACells, AColumns.Module);
  TakeEurekaUnit(CellAt(ACells, AColumns.UnitName), AFrame);
  AFrame.Routine := CellAt(ACells, AColumns.Routine);
  mClass := CellAt(ACells, AColumns.ClassName);
  if (mClass <> '') and (AFrame.Routine <> '') then
  begin
    AFrame.Routine := mClass + '.' + AFrame.Routine;
  end;
  AFrame.Line := LineNumberOf(CellAt(ACells, AColumns.Line));
end;

/// <summary>Zeile „|*Exception Thread: ID=6708; …“ oder „|Running Thread: ID=…“.</summary>
function TryEurekaThread(const ACells: TArray<string>; out AName: string; out ACrashed: Boolean): Boolean;
var
  mCell: string;
begin
  Result := Length(ACells) = 1;
  if not Result then
  begin
    Exit;
  end;
  mCell := ACells[0];
  Result := ContainsText(mCell, 'thread:') and ContainsText(mCell, 'id=');
  AName := mCell.TrimLeft(['*']);
  ACrashed := ContainsText(mCell, cCrashedThreadMark);
end;

procedure TakeEurekaHead(var AReport: TCrashReport; const ALine: string);
var
  mKey, mValue: string;
begin
  if not TryKeyValue(ALine, mKey, mValue) then
  begin
    Exit;
  end;
  if (mKey = 'type') or (mKey = 'exception class') then
  begin
    AReport.ExceptionClass := mValue;
  end
  else if (mKey = 'message') or (mKey = 'exception message') then
  begin
    AReport.ExceptionMessage := mValue;
  end
  else if (mKey = 'address') and TryAddress(mValue, AReport.Address) then
  begin
    AReport.Module := '';
  end;
end;

procedure TakeEurekaRow(var AReport: TCrashReport; const ACells: TArray<string>; const AColumns: TEurekaColumns);
var
  mFrame: TCrashFrame;
  mName: string;
  mCrashed: Boolean;
  mBase: UInt64;
begin
  if TryEurekaThread(ACells, mName, mCrashed) then
  begin
    AddThread(AReport, mName, mCrashed);
  end
  else if AColumns.IsStack and TryEurekaFrame(ACells, AColumns, mFrame) then
  begin
    AddFrame(AReport, mFrame);
  end
  else if AColumns.IsModules and (Length(ACells) = AColumns.Count) and
    TryAddress(CellAt(ACells, AColumns.Handle), mBase) then
  begin
    AddModule(AReport, CellAt(ACells, AColumns.Name), mBase);
  end;
end;

procedure TakeEurekaLine(var AReport: TCrashReport; const ALine: string; var AColumns: TEurekaColumns);
var
  mCells: TArray<string>;
  mHeader: TEurekaColumns;
begin
  mCells := CellsOf(ALine);
  if mCells = nil then
  begin
    TakeEurekaHead(AReport, ALine);
  end
  else if TryEurekaHeader(mCells, mHeader) then
  begin
    AColumns := mHeader;
  end
  else
  begin
    TakeEurekaRow(AReport, mCells, AColumns);
  end;
end;

function ReadEurekaLog(const ALines: TCrashLines; out AReport: TCrashReport): Boolean;
var
  mLine: string;
  mColumns: TEurekaColumns;
begin
  AReport := Default(TCrashReport);
  TryEurekaHeader(nil, mColumns);
  for mLine in ALines do
  begin
    TakeEurekaLine(AReport, mLine, mColumns);
  end;
  TidyThreads(AReport);
  Result := Length(AReport.CrashFrames) > 0;
  if Result then
  begin
    AReport.Kind := TCrashReportKind.EurekaLog;
  end;
end;

{ JclDebug }

/// <summary>„Unit1.TForm1.Button1Click (Line 42, "Unit1.pas" + 3) + $12“ in Routine, Zeile und Datei.</summary>
procedure TakeJclRest(const ARest: string; var AFrame: TCrashFrame);
var
  mOpen: Integer;
  mInside, mUnit: string;
  mQuoted: TArray<string>;
begin
  mOpen := Pos(' (', ARest);
  AFrame.Routine := Trim(ARest);
  if mOpen > 0 then
  begin
    AFrame.Routine := Trim(Copy(ARest, 1, mOpen - 1));
    mInside := Copy(ARest, mOpen + 2, MaxInt);
    if StartsText('line ', mInside) then
    begin
      AFrame.Line := LineNumberOf(Copy(mInside, Length('line ') + 1, Pos(',', mInside + ',') - Length('line ') - 1));
    end;
    mQuoted := mInside.Split(['"']);
    if Length(mQuoted) >= 3 then
    begin
      AFrame.FileName := mQuoted[1];
    end;
  end;
  if Pos(' + $', AFrame.Routine) > 0 then
  begin
    AFrame.Routine := Trim(Copy(AFrame.Routine, 1, Pos(' + $', AFrame.Routine) - 1));
  end;
  // Die Routine beginnt mit der Unit der Datei („Unit1.TForm1.Click“ zu „Unit1.pas“).
  mUnit := ChangeFileExt(AFrame.FileName, '');
  if (mUnit <> '') and StartsText(mUnit + '.', AFrame.Routine) then
  begin
    AFrame.UnitName := Copy(AFrame.Routine, 1, Length(mUnit));
    AFrame.Routine := Copy(AFrame.Routine, Length(mUnit) + 2, MaxInt);
  end;
end;

class function TCrashReports.ParseJclFrame(const ALine: string; out AFrame: TCrashFrame): Boolean;
var
  mText: string;
  mClose, mBraceClose: Integer;
begin
  AFrame := Default(TCrashFrame);
  // [0045A1B2]{Project1.exe} Unit1.TForm1.Button1Click (Line 42, "Unit1.pas" + 3) + $12
  mText := Trim(ALine);
  mClose := Pos(']', mText);
  Result := (Length(mText) > 2) and (mText[1] = '[') and (mClose > 2) and
    TryAddress(Copy(mText, 2, mClose - 2), AFrame.Address) and (Copy(mText, mClose + 1, 1) = '{');
  if not Result then
  begin
    Exit;
  end;
  mBraceClose := PosEx('}', mText, mClose);
  Result := mBraceClose > 0;
  if Result then
  begin
    AFrame.Module := Trim(Copy(mText, mClose + 2, mBraceClose - mClose - 2));
    TakeJclRest(Copy(mText, mBraceClose + 1, MaxInt), AFrame);
  end;
end;

function ReadJcl(const ALines: TCrashLines; out AReport: TCrashReport): Boolean;
var
  mLine: string;
  mFrame: TCrashFrame;
begin
  AReport := Default(TCrashReport);
  for mLine in ALines do
  begin
    if TCrashReports.ParseJclFrame(mLine, mFrame) then
    begin
      AddFrame(AReport, mFrame);
    end
    else if (AReport.ExceptionMessage = '') and (Trim(mLine) <> '') and (Length(AReport.Threads) = 0) then
    begin
      AReport.ExceptionMessage := Trim(mLine);
    end;
  end;
  Result := Length(AReport.CrashFrames) > 0;
  if Result then
  begin
    AReport.Kind := TCrashReportKind.JclDebug;
  end;
end;

{ Nur die Meldung }

function ReadExceptionText(const ALines: TCrashLines; out AReport: TCrashReport): Boolean;
var
  mLine: string;
begin
  AReport := Default(TCrashReport);
  for mLine in ALines do
  begin
    TakeMessage(AReport, mLine);
    if AReport.Address <> 0 then
    begin
      AReport.ExceptionMessage := Trim(mLine);
      AReport.Kind := TCrashReportKind.ExceptionText;
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TCrashReports }

class function TCrashReports.TryParseHex(const AText: string; out AValue: UInt64): Boolean;
var
  mText: string;
  mChar: Char;
begin
  AValue := 0;
  mText := AText;
  if StartsText('0x', mText) then
  begin
    mText := Copy(mText, 3, MaxInt);
  end
  else if mText.StartsWith('$') then
  begin
    mText := Copy(mText, 2, MaxInt);
  end;
  Result := (mText <> '') and (Length(mText) <= cMaxHexDigits);
  if not Result then
  begin
    Exit;
  end;
  for mChar in mText do
  begin
    if not IsHexDigit(mChar) then
    begin
      AValue := 0;
      Exit(False);
    end;
    AValue := (AValue shl cBitsPerHexDigit) or UInt64(Pos(UpCase(mChar), '0123456789ABCDEF') - 1);
  end;
end;

class function TCrashReports.IsLibraryUnit(const AUnitName: string): Boolean;
var
  mLower, mName: string;
begin
  mLower := LowerCase(AUnitName);
  for mName in cLibraryUnits do
  begin
    if mLower = mName then
    begin
      Exit(True);
    end;
  end;
  for mName in cLibraryPrefixes do
  begin
    if StartsStr(mName, mLower) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TCrashReports.SiteOf(const AFrames: TArray<TCrashFrame>): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AFrames) do
  begin
    if (AFrames[mIndex].Line > 0) and not IsLibraryUnit(AFrames[mIndex].UnitName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Adresse und Modul ergänzen: aus der Meldung, sonst aus der ersten Stapelzeile.</summary>
procedure CompleteCrashSite(var AReport: TCrashReport);
var
  mFrames: TArray<TCrashFrame>;
begin
  TakeMessage(AReport, AReport.ExceptionMessage);
  mFrames := AReport.CrashFrames;
  if (AReport.Address = 0) and (Length(mFrames) > 0) then
  begin
    AReport.Address := mFrames[0].Address;
  end;
  if (AReport.Module = '') and (Length(mFrames) > 0) and (mFrames[0].Address = AReport.Address) then
  begin
    AReport.Module := mFrames[0].Module;
  end;
end;

type
  TCrashReader = function(const ALines: TCrashLines; out AReport: TCrashReport): Boolean;

const
  // Ohne Kennzeichen im Text entscheidet der Aufbau in dieser Reihenfolge.
  cReaders: array[0..3] of TCrashReader = (ReadMadExcept, ReadEurekaLog, ReadJcl, ReadExceptionText);

/// <summary>Leser, den ein Kennzeichen im Text („EurekaLog“, „madExcept“) zuerst fragt; nil ohne.</summary>
function MarkedReader(const AText: string): TCrashReader;
begin
  Result := nil;
  if ContainsText(AText, cEurekaMark) then
  begin
    Result := ReadEurekaLog;
  end
  else if ContainsText(AText, cMadExceptMark) then
  begin
    Result := ReadMadExcept;
  end;
end;

class function TCrashReports.Parse(const AText: string): TCrashReport;
var
  mLines: TCrashLines;
  mFirst, mReader: TCrashReader;
begin
  mLines := TTextLines.SplitLines(AText);
  mFirst := MarkedReader(AText);
  if Assigned(mFirst) and mFirst(mLines, Result) then
  begin
    CompleteCrashSite(Result);
    Exit;
  end;
  for mReader in cReaders do
  begin
    if mReader(mLines, Result) then
    begin
      CompleteCrashSite(Result);
      Exit;
    end;
  end;
  Result := Default(TCrashReport);
end;

end.
