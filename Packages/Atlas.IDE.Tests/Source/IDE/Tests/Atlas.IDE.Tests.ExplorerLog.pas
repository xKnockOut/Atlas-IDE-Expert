unit Atlas.IDE.Tests.ExplorerLog;

// Protokoll je Test im Fenster „Atlas-Tests“ (#2168, tests.log): merkt sich
// je Testprojekt das Protokoll der Läufe dieser Sitzung (Seitendatei des
// Atlas-Loggers und Konsolenausgabe, gelesen mit Atlas.Core.Tests.Log; ein
// neuer Lauf ersetzt die Einträge der Tests, die er enthält) und liefert die
// Zeilen zum gewählten Knoten mit Sprungzielen. Ein Verweis „Unit.Klasse.
// Methode“ ohne Zeile springt an den Methodenkopf (Puffer der IDE, sonst
// Platte). Nur im Hauptthread.

interface

uses
  System.Generics.Collections,
  Atlas.Text.TestResults,
  Atlas.Core.Tests.Explorer,
  Atlas.Core.Tests.Log;

type
  TAtlasIdeTestLogs = class
  private
    /// <summary>Protokoll je Testprojekt (Schlüssel klein).</summary>
    FRuns: TDictionary<string, TAtlasTestLogRun>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Protokoll aus ARun merken (Lauf aus dem Läufer mit Output bzw. LogFile); ohne beide nichts.
    /// </summary>
    procedure Remember(const AProject: string; const ARun: TTestRunResult);
    /// <summary>Zeilen zum Test bzw. zur Fixture AName im Testprojekt AProject mit Sprungzielen in AUnits; ACount
    /// für den Reiter. Ohne Lauf mit Protokoll leer.</summary>
    function Lines(const AProject, AName: string; const AUnits: TArray<TAtlasTestUnitRef>;
      out ACount: Integer): TArray<TAtlasTestStackLine>;
    /// <summary>Texte der Anzeige in der Sprache der IDE.</summary>
    class function Texts: TAtlasTestLogTexts; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.UI.Tests.Strings;

function KeyOf(const AFileName: string): string;
begin
  Result := AnsiLowerCase(AFileName);
end;

{ TAtlasIdeTestLogs }

constructor TAtlasIdeTestLogs.Create;
begin
  inherited Create;
  FRuns := TDictionary<string, TAtlasTestLogRun>.Create;
end;

destructor TAtlasIdeTestLogs.Destroy;
begin
  FRuns.Free;
  inherited;
end;

procedure TAtlasIdeTestLogs.Remember(const AProject: string; const ARun: TTestRunResult);
var
  mOld, mNew: TAtlasTestLogRun;
begin
  if (ARun.Output = '') and (ARun.LogFile = '') then
  begin
    Exit;
  end;
  mNew := TAtlasTestLog.Parse(ARun.LogFile, ARun.Output, TAtlasIdeSettings.Current.TestsLogMaxLines);
  if FRuns.TryGetValue(KeyOf(AProject), mOld) then
  begin
    mNew := TAtlasTestLog.Merged(mOld, mNew);
  end;
  FRuns.AddOrSetValue(KeyOf(AProject), mNew);
end;

class function TAtlasIdeTestLogs.Texts: TAtlasTestLogTexts;
begin
  Result.Start := TAtlasTestsStrings.Text(TAtlasTestsTextId.LogStart);
  Result.Finish := TAtlasTestsStrings.Text(TAtlasTestsTextId.LogFinish);
  Result.Warning := TAtlasTestsStrings.Text(TAtlasTestsTextId.LogWarning);
  Result.Error := TAtlasTestsStrings.Text(TAtlasTestsTextId.LogError);
  Result.Console := TAtlasTestsStrings.Text(TAtlasTestsTextId.LogConsole);
  Result.AfterEnd := TAtlasTestsStrings.Text(TAtlasTestsTextId.LogAfterEnd);
  Result.Dropped := TAtlasTestsStrings.Text(TAtlasTestsTextId.LogDropped);
  Result.Fixture := TAtlasTestsStrings.Text(TAtlasTestsTextId.LogFixture);
  Result.NoLogger := TAtlasTestsStrings.Text(TAtlasTestsTextId.LogNoLogger);
  Result.Output := TAtlasTestsStrings.Text(TAtlasTestsTextId.LogOutput);
  Result.Empty := TAtlasTestsStrings.Text(TAtlasTestsTextId.LogEmpty);
  Result.DecimalSeparator := FormatSettings.DecimalSeparator;
end;

/// <summary>Zeile des Methodenkopfs ARoutine in AFileName; 0 (Anfang der Unit) ohne.</summary>
function RoutineLineOf(const AFileName, ARoutine: string): Integer;
var
  mLines: TArray<string>;
begin
  Result := -1;
  if TAtlasIdeFiles.ReadLines(AFileName, mLines) then
  begin
    Result := TAtlasTestLog.RoutineLine(mLines, ARoutine);
  end;
  if Result < 0 then
  begin
    Result := 0;
  end;
end;

/// <summary>Zeile der Anzeige mit Sprungziel; Routinen ohne Zeile werden hier aufgelöst.</summary>
function StackLineOf(const ARow: TAtlasTestLogRow): TAtlasTestStackLine;
begin
  Result.Text := ARow.Text;
  Result.FileName := ARow.FileName;
  Result.Line := ARow.Line;
  if (Result.FileName <> '') and (Result.Line < 0) then
  begin
    Result.Line := RoutineLineOf(Result.FileName, ARow.Routine);
  end;
end;

function TAtlasIdeTestLogs.Lines(const AProject, AName: string; const AUnits: TArray<TAtlasTestUnitRef>;
  out ACount: Integer): TArray<TAtlasTestStackLine>;
var
  mRun: TAtlasTestLogRun;
  mUnits: TArray<TAtlasTestLogUnit>;
  mIndex: Integer;
  mRows: TArray<TAtlasTestLogRow>;
begin
  Result := nil;
  ACount := 0;
  if (AName = '') or not FRuns.TryGetValue(KeyOf(AProject), mRun) then
  begin
    Exit;
  end;
  SetLength(mUnits, Length(AUnits));
  for mIndex := 0 to High(AUnits) do
  begin
    mUnits[mIndex].UnitName := AUnits[mIndex].UnitName;
    mUnits[mIndex].FileName := AUnits[mIndex].FileName;
  end;
  ACount := TAtlasTestLog.CountOf(mRun, AName);
  mRows := TAtlasTestLog.Rows(mRun, AName, mUnits, Texts);
  SetLength(Result, Length(mRows));
  for mIndex := 0 to High(mRows) do
  begin
    Result[mIndex] := StackLineOf(mRows[mIndex]);
  end;
end;

end.
