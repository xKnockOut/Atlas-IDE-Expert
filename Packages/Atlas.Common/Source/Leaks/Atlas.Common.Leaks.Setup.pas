unit Atlas.Common.Leaks.Setup;

// Leckprüfung für ein Projekt einrichten (#1880), ohne Dateisystem und ohne
// IDE: Was ist vorhanden, und welche Änderungen richten die Prüfung ein?
//
// Erkennen (Analyze):
// - FastMM4.pas bzw. FastMM5.pas in den Suchordnern (Suchpfade des Projekts,
//   Bibliothekspfade der Installation, dort landen auch GetIt-Pakete); Version
//   aus der Unit (FastMM4: Konstante FastMMVersion, FastMM5: Kopfkommentar
//   „FastMM 5.xx“), FastMM4Options.inc neben der Unit oder in einem Suchordner.
// - DLL für FullDebugMode je Plattform (FastMM_FullDebugMode.dll unter Win32,
//   FastMM_FullDebugMode64.dll unter Win64; FastMM4 und FastMM5 teilen sie) im
//   Ausgabeordner der Konfiguration Debug, sonst im PATH; als Vorlage zum
//   Kopieren neben der Unit oder in „FullDebugMode DLL\Precompiled“.
// - Im Hauptquelltext (.dpr): FastMM4/FastMM5 im uses (an erster Stelle? nur
//   in {$IFDEF DEBUG}?), Zuweisung an ReportMemoryLeaksOnShutdown (Zeile, nur
//   in Debug?), Bericht als Datei (FastMM5: FastMM_LogToFileEvents), DUnitX
//   (Testprojekt) und sein Leckmonitor DUnitX.MemoryLeakMonitor.*.
// - In den Symbolen der Konfiguration Debug: FullDebugMode (FastMM4) bzw.
//   FastMM_FullDebugMode (FastMM5), NoMessageBoxes (FastMM4, Bericht als
//   Datei).
//
// Einrichten (Plan): Einfügungen in den Hauptquelltext, immer in
// {$IFDEF DEBUG}, und Symbole für die Konfiguration Debug; was schon da ist,
// wird nicht noch einmal eingefügt.
//   Simple    ReportMemoryLeaksOnShutdown := DebugHook <> 0; am Anfang des
//             Hauptblocks
//   FastMM4/5 dazu die Unit als erste im uses und das Symbol für
//             FullDebugMode; mit AFileReport der Bericht als Datei statt
//             Meldungsfenster (FastMM4: Symbol NoMessageBoxes, FastMM5:
//             Ereignisse umstellen am Anfang des Hauptblocks)
// Die Einfügungen kommen von hinten nach vorn, so verschiebt keine die Stelle
// einer späteren.

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  /// <summary>Speichermanager mit Leckbericht: None = der der RTL.</summary>
  TLeakManager = (None, FastMM4, FastMM5);
{$SCOPEDENUMS OFF}

  /// <summary>Dateizugriffe von außen (Tests ohne Platte).</summary>
  ILeakSetupFiles = interface
    ['{62B7614D-5288-48D9-BA5E-A2FB3237CC5B}']
    function FileExists(const AFileName: string): Boolean;
    /// <summary>Liest eine Textdatei; False, wenn sie fehlt.</summary>
    function ReadText(const AFileName: string; out AText: string): Boolean;
  end;

  /// <summary>Was Analyze über das Projekt wissen muss.</summary>
  TLeakSetupInput = record
    /// <summary>Absoluter Pfad der .dproj.</summary>
    ProjectFile: string;
    /// <summary>Hauptquelltext (.dpr, .dpk) und sein Text, auch ungespeichert.</summary>
    MainSource: string;
    MainText: string;
    /// <summary>Plattform, z. B. Win32, Win64.</summary>
    Platform: string;
    /// <summary>Bedingte Symbole der Konfiguration Debug (DCC_Define mit Erbe).</summary>
    DebugDefines: TArray<string>;
    /// <summary>Ausgabeordner der Konfiguration Debug, absolut; '' = unbekannt.</summary>
    OutputFolder: string;
    /// <summary>Suchpfade des Projekts, dann Bibliothekspfade der Installation, absolut.</summary>
    SearchFolders: TArray<string>;
    /// <summary>Ordner aus der Umgebungsvariablen PATH.</summary>
    PathFolders: TArray<string>;
  end;

  /// <summary>Gefundene Quelle eines Speichermanagers.</summary>
  TLeakManagerSource = record
    /// <summary>Pfad der Unit; '' = nicht gefunden.</summary>
    FileName: string;
    /// <summary>Version aus der Unit, z. B. 4.993; '' = unbekannt.</summary>
    Version: string;
    /// <summary>FastMM4Options.inc (nur FastMM4); '' = nicht gefunden.</summary>
    OptionsFile: string;
    function Found: Boolean;
  end;

  /// <summary>Stand der Leckprüfung eines Projekts.</summary>
  TLeakSetupState = record
    Sources: array[TLeakManager] of TLeakManagerSource;
    /// <summary>Speichermanager im uses des Hauptquelltexts; None = keiner.</summary>
    UsesManager: TLeakManager;
    /// <summary>Er steht als erste Unit im uses (sonst gilt er nicht für alle Units).</summary>
    UsesFirst: Boolean;
    /// <summary>Er steht nur in {$IFDEF DEBUG}.</summary>
    UsesDebugOnly: Boolean;
    /// <summary>Zeile (ab 1) der Zuweisung an ReportMemoryLeaksOnShutdown; 0 = keine.</summary>
    ReportLine: Integer;
    /// <summary>Die Zuweisung steht nur in {$IFDEF DEBUG}.</summary>
    ReportDebugOnly: Boolean;
    /// <summary>Symbol für FullDebugMode in der Konfiguration Debug (zum Speichermanager im uses).</summary>
    DebugDefine: Boolean;
    /// <summary>Bericht als Datei statt Meldungsfenster ist eingerichtet.</summary>
    FileReport: Boolean;
    /// <summary>Name der DLL für FullDebugMode auf der Plattform.</summary>
    DllName: string;
    /// <summary>Gefundene DLL (Ausgabeordner oder PATH); '' = fehlt.</summary>
    DllFile: string;
    /// <summary>Vorlage zum Kopieren (neben der Unit); '' = keine.</summary>
    DllSource: string;
    /// <summary>Wohin die DLL gehört (Ausgabeordner der Konfiguration Debug); '' = unbekannt.</summary>
    DllTarget: string;
    /// <summary>Hauptquelltext ist ein Package (.dpk): keine Einrichtung.</summary>
    IsPackage: Boolean;
    /// <summary>Hauptquelltext verwendet DUnitX.</summary>
    IsTestProject: Boolean;
    /// <summary>Leckmonitor von DUnitX im uses (DUnitX.MemoryLeakMonitor.…); '' = keiner.</summary>
    LeakMonitor: string;
    /// <summary>Hauptquelltext hat ein uses (sonst keine Unit einzufügen).</summary>
    HasUses: Boolean;
    /// <summary>Hauptblock gefunden (begin … end.); sonst keine Zeile einzufügen.</summary>
    HasMainBlock: Boolean;
    /// <summary>Bedingte Symbole der Konfiguration Debug (aus der Eingabe).</summary>
    DebugDefines: TArray<string>;
  end;

  /// <summary>Einfügung in den Hauptquelltext; Zeile und Zeichen 0-basiert.</summary>
  TLeakSetupEdit = record
    Line: Integer;
    Character: Integer;
    Text: string;
  end;

  /// <summary>Was zum Einrichten zu tun ist.</summary>
  TLeakSetupPlan = record
    /// <summary>Einfügungen von hinten nach vorn.</summary>
    Edits: TArray<TLeakSetupEdit>;
    /// <summary>Symbole, die der Konfiguration Debug fehlen.</summary>
    Defines: TArray<string>;
    /// <summary>DLL aus DllSource nach DllTarget kopieren (nach Rückfrage).</summary>
    CopyDll: Boolean;
    function IsEmpty: Boolean;
  end;

  TLeakSetup = class
  public const
    cUnitNames: array[TLeakManager] of string = ('', 'FastMM4', 'FastMM5');
    /// <summary>Symbol für FullDebugMode je Speichermanager.</summary>
    cDebugDefines: array[TLeakManager] of string = ('', 'FullDebugMode', 'FastMM_FullDebugMode');
    /// <summary>FastMM4: keine Meldungsfenster, der Bericht steht in der Logdatei.</summary>
    cNoMessageBoxes = 'NoMessageBoxes';
    cOptionsFile = 'FastMM4Options.inc';
    cDll32 = 'FastMM_FullDebugMode.dll';
    cDll64 = 'FastMM_FullDebugMode64.dll';
    /// <summary>Unterordner der DLL in den Quellen von FastMM4.</summary>
    cDllSubFolder = 'FullDebugMode DLL' + PathDelim + 'Precompiled';
    cLeakMonitorPrefix = 'DUnitX.MemoryLeakMonitor.';
    cReportLine = 'ReportMemoryLeaksOnShutdown := DebugHook <> 0;';
  public
    /// <summary>Name der DLL für FullDebugMode auf APlatform (Win64 → …64.dll).</summary>
    class function DllNameOf(const APlatform: string): string; static;
    /// <summary>Version aus dem Text der Unit; '' = unbekannt.</summary>
    class function VersionOf(AManager: TLeakManager; const AText: string): string; static;
    /// <summary>Wertet nur den Hauptquelltext aus (uses, ReportMemoryLeaksOnShutdown, Bericht als Datei).
    /// </summary>
    class procedure ScanMain(const AText: string; var AState: TLeakSetupState); static;
    /// <summary>Stand der Leckprüfung des Projekts.</summary>
    class function Analyze(const AInput: TLeakSetupInput; const AFiles: ILeakSetupFiles): TLeakSetupState; static;
    /// <summary>Was AManager (None = Einfach) mit AFileReport einzurichten hat; leer, wenn alles da ist.</summary>
    class function Plan(const AState: TLeakSetupState; const AText: string; AManager: TLeakManager;
      AFileReport: Boolean): TLeakSetupPlan; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Common.Leaks.Internals.MainScan;

{ TLeakManagerSource }

function TLeakManagerSource.Found: Boolean;
begin
  Result := FileName <> '';
end;

{ TLeakSetupPlan }

function TLeakSetupPlan.IsEmpty: Boolean;
begin
  Result := (Length(Edits) = 0) and (Length(Defines) = 0) and not CopyDll;
end;

{ Dateien }

function JoinPath(const AFolder, AName: string): string;
begin
  Result := IncludeTrailingPathDelimiter(AFolder) + AName;
end;

function FindIn(const AFolders: TArray<string>; const AName: string; const AFiles: ILeakSetupFiles): string;
var
  mFolder: string;
begin
  Result := '';
  if AFiles = nil then
  begin
    Exit;
  end;
  for mFolder in AFolders do
  begin
    if (mFolder <> '') and AFiles.FileExists(JoinPath(mFolder, AName)) then
    begin
      Result := JoinPath(mFolder, AName);
      Exit;
    end;
  end;
end;

function ReadOrEmpty(const AFileName: string; const AFiles: ILeakSetupFiles): string;
begin
  if (AFiles = nil) or not AFiles.ReadText(AFileName, Result) then
  begin
    Result := '';
  end;
end;

function SourceOf(AManager: TLeakManager; const AInput: TLeakSetupInput;
  const AFiles: ILeakSetupFiles): TLeakManagerSource;
begin
  Result := Default(TLeakManagerSource);
  Result.FileName := FindIn(AInput.SearchFolders, TLeakSetup.cUnitNames[AManager] + '.pas', AFiles);
  if not Result.Found then
  begin
    Exit;
  end;
  Result.Version := TLeakSetup.VersionOf(AManager, ReadOrEmpty(Result.FileName, AFiles));
  if AManager = TLeakManager.FastMM4 then
  begin
    Result.OptionsFile := FindIn([ExtractFileDir(Result.FileName)] + AInput.SearchFolders, TLeakSetup.cOptionsFile,
      AFiles);
  end;
end;

function HasDefine(const ADefines: TArray<string>; const AName: string): Boolean;
begin
  Result := (AName <> '') and (IndexText(AName, ADefines) >= 0);
end;

procedure FindDll(const AInput: TLeakSetupInput; const AFiles: ILeakSetupFiles; var AState: TLeakSetupState);
var
  mManager: TLeakManager;
  mFolder: string;
begin
  AState.DllName := TLeakSetup.DllNameOf(AInput.Platform);
  AState.DllTarget := AInput.OutputFolder;
  AState.DllFile := FindIn([AInput.OutputFolder] + AInput.PathFolders, AState.DllName, AFiles);
  for mManager := TLeakManager.FastMM4 to TLeakManager.FastMM5 do
  begin
    if AState.Sources[mManager].Found and (AState.DllSource = '') then
    begin
      mFolder := ExtractFileDir(AState.Sources[mManager].FileName);
      AState.DllSource := FindIn([mFolder, JoinPath(mFolder, TLeakSetup.cDllSubFolder)], AState.DllName, AFiles);
    end;
  end;
end;

{ TLeakSetup }

class function TLeakSetup.DllNameOf(const APlatform: string): string;
begin
  if SameText(APlatform, 'Win64') or SameText(APlatform, 'Win64x') then
  begin
    Result := cDll64;
  end
  else
  begin
    Result := cDll32;
  end;
end;

/// <summary>Text zwischen den ersten Hochkommas ab APos; '' ohne.</summary>
function QuotedAfter(const AText: string; APos: Integer): string;
var
  mStart, mStop: Integer;
begin
  Result := '';
  mStart := PosEx('''', AText, APos);
  if mStart = 0 then
  begin
    Exit;
  end;
  mStop := PosEx('''', AText, mStart + 1);
  if mStop > mStart then
  begin
    Result := Copy(AText, mStart + 1, mStop - mStart - 1);
  end;
end;

/// <summary>Versionsnummer (Ziffern und Punkte) ab APos; '' ohne.</summary>
function NumberAt(const AText: string; APos: Integer): string;
var
  mStop: Integer;
begin
  mStop := APos;
  while (mStop <= Length(AText)) and CharInSet(AText[mStop], ['0'..'9', '.']) do
  begin
    Inc(mStop);
  end;
  Result := Copy(AText, APos, mStop - APos);
  while EndsStr('.', Result) do
  begin
    Delete(Result, Length(Result), 1);
  end;
end;

class function TLeakSetup.VersionOf(AManager: TLeakManager; const AText: string): string;
var
  mPos: Integer;
begin
  Result := '';
  case AManager of
    TLeakManager.FastMM4:
      begin
        // FastMMVersion = '4.993';
        mPos := Pos('FASTMMVERSION', UpperCase(AText));
        if mPos > 0 then
        begin
          Result := QuotedAfter(AText, mPos);
        end;
      end;
    TLeakManager.FastMM5:
      begin
        // Kopfkommentar: "FastMM 5.04" bzw. "FastMM 5.04 -"
        mPos := Pos('FASTMM 5', UpperCase(AText));
        if mPos > 0 then
        begin
          Result := NumberAt(AText, mPos + Length('FastMM '));
        end;
      end;
  end;
end;

class procedure TLeakSetup.ScanMain(const AText: string; var AState: TLeakSetupState);
var
  mScan: TLeakMainScan;
begin
  mScan := TLeakMainScan.Run(AText);
  AState.HasUses := mScan.UsesFound;
  AState.HasMainBlock := mScan.MainBegin >= 0;
  AState.UsesManager := TLeakManager.None;
  if mScan.ManagerIndex >= 0 then
  begin
    AState.UsesManager := TLeakManager(mScan.ManagerKind);
    AState.UsesFirst := mScan.ManagerIndex = 0;
    AState.UsesDebugOnly := mScan.ManagerDebugOnly;
  end;
  AState.ReportLine := mScan.ReportLine;
  AState.ReportDebugOnly := mScan.ReportDebugOnly;
  AState.FileReport := mScan.LogToFile;
  AState.IsTestProject := mScan.UsesDUnitX;
  AState.LeakMonitor := mScan.LeakMonitor;
end;

class function TLeakSetup.Analyze(const AInput: TLeakSetupInput; const AFiles: ILeakSetupFiles): TLeakSetupState;
var
  mManager: TLeakManager;
begin
  Result := Default(TLeakSetupState);
  Result.IsPackage := SameText(ExtractFileExt(AInput.MainSource), '.dpk');
  for mManager := TLeakManager.FastMM4 to TLeakManager.FastMM5 do
  begin
    Result.Sources[mManager] := SourceOf(mManager, AInput, AFiles);
  end;
  ScanMain(AInput.MainText, Result);
  Result.DebugDefines := AInput.DebugDefines;
  Result.DebugDefine := HasDefine(AInput.DebugDefines, cDebugDefines[Result.UsesManager]);
  if Result.UsesManager = TLeakManager.FastMM4 then
  begin
    Result.FileReport := HasDefine(AInput.DebugDefines, cNoMessageBoxes);
  end;
  FindDll(AInput, AFiles, Result);
end;

{ Plan }

/// <summary>Zeilen in {$IFDEF DEBUG} mit AIndent eingerückt, jede mit Zeilenumbruch.</summary>
function DebugBlock(const ALines: TArray<string>; const AIndent, ABreak: string): string;
var
  mLine: string;
begin
  Result := AIndent + '{$IFDEF DEBUG}' + ABreak;
  for mLine in ALines do
  begin
    Result := Result + AIndent + mLine + ABreak;
  end;
  Result := Result + AIndent + '{$ENDIF}' + ABreak;
end;

function Edit(ALine, ACharacter: Integer; const AText: string): TLeakSetupEdit;
begin
  Result.Line := ALine;
  Result.Character := ACharacter;
  Result.Text := AText;
end;

/// <summary>Zeilen am Anfang des Hauptblocks.</summary>
function MainLines(const AState: TLeakSetupState; AManager: TLeakManager; AFileReport: Boolean): TArray<string>;
begin
  Result := nil;
  if AState.ReportLine = 0 then
  begin
    Result := Result + [TLeakSetup.cReportLine];
  end;
  if AFileReport and (AManager = TLeakManager.FastMM5) and not AState.FileReport then
  begin
    Result := Result + [
      'FastMM_MessageBoxEvents := FastMM_MessageBoxEvents - [mmetUnexpectedMemoryLeakDetail, ' +
        'mmetUnexpectedMemoryLeakSummary];',
      'FastMM_LogToFileEvents := FastMM_LogToFileEvents + [mmetUnexpectedMemoryLeakDetail, ' +
        'mmetUnexpectedMemoryLeakSummary];'];
  end;
end;

/// <summary>Einfügung der Unit vor dem ersten Eintrag im uses.</summary>
function UsesEdit(const AScan: TLeakMainScan; const AName, ABreak: string): TLeakSetupEdit;
var
  mIndent: string;
begin
  if AScan.FirstEntryStartsLine then
  begin
    mIndent := StringOfChar(' ', AScan.FirstEntry.Character);
    Result := Edit(AScan.FirstEntry.Line, 0, DebugBlock([AName + ','], mIndent, ABreak));
  end
  else
  begin
    Result := Edit(AScan.FirstEntry.Line, AScan.FirstEntry.Character, '{$IFDEF DEBUG}' + AName + ',{$ENDIF} ');
  end;
end;

function PlanDefines(const AState: TLeakSetupState; AManager: TLeakManager; AFileReport: Boolean): TArray<string>;
begin
  Result := nil;
  if (AManager = TLeakManager.None) or (AState.UsesManager <> TLeakManager.None) and
    (AState.UsesManager <> AManager) then
  begin
    Exit;
  end;
  if not HasDefine(AState.DebugDefines, TLeakSetup.cDebugDefines[AManager]) then
  begin
    Result := Result + [TLeakSetup.cDebugDefines[AManager]];
  end;
  if AFileReport and (AManager = TLeakManager.FastMM4) and not HasDefine(AState.DebugDefines,
    TLeakSetup.cNoMessageBoxes) then
  begin
    Result := Result + [TLeakSetup.cNoMessageBoxes];
  end;
end;

class function TLeakSetup.Plan(const AState: TLeakSetupState; const AText: string; AManager: TLeakManager;
  AFileReport: Boolean): TLeakSetupPlan;
var
  mScan: TLeakMainScan;
  mBreak: string;
  mLines: TArray<string>;
begin
  Result := Default(TLeakSetupPlan);
  if AState.IsPackage then
  begin
    Exit;
  end;
  mScan := TLeakMainScan.Run(AText);
  mBreak := TTextLines.LineBreakOf(AText);
  mLines := MainLines(AState, AManager, AFileReport);
  if (Length(mLines) > 0) and (mScan.MainBegin >= 0) then
  begin
    Result.Edits := Result.Edits + [Edit(mScan.MainBegin + 1, 0, DebugBlock(mLines, '  ', mBreak))];
  end;
  if (AManager <> TLeakManager.None) and (AState.UsesManager = TLeakManager.None) and mScan.UsesFound and
    (mScan.EntryCount > 0) then
  begin
    Result.Edits := Result.Edits + [UsesEdit(mScan, cUnitNames[AManager], mBreak)];
  end;
  Result.Defines := PlanDefines(AState, AManager, AFileReport);
  Result.CopyDll := (AManager <> TLeakManager.None) and (AState.DllFile = '') and (AState.DllSource <> '') and
    (AState.DllTarget <> '');
end;

end.
