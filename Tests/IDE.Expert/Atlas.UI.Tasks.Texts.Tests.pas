unit Atlas.UI.Tasks.Texts.Tests;

// Tests für die Texte der Projektaufgaben (#900): Dauer, Kopfzeilen je
// Ausgang, Meldung beim Abbruch vor dem Build, letztes Ergebnis.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  TAtlasTaskTextsTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure DurationAndFindings;
    [Test]
    procedure HeaderPerOutcome;
    [Test]
    procedure BlockedNamesErrorsOrExitCode;
    [Test]
    procedure LastResultAndDescription;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Core.Tasks.Definitions,
  Atlas.Core.Tasks.Matchers,
  Atlas.Core.Tasks.Runs,
  Atlas.UI.Tasks.Texts;

function Run(AOutcome: TAtlasTaskOutcome; AExitCode, AErrors: Integer): TAtlasTaskRun;
var
  Index: Integer;
  Finding: TAtlasTaskFinding;
begin
  Result := Default(TAtlasTaskRun);
  Result.Name := 'Delphi-12-Prüfung';
  Result.Outcome := AOutcome;
  Result.ExitCode := AExitCode;
  Result.DurationMs := 2340;
  Result.Cwd := 'C:\Proj';
  for Index := 1 to AErrors do
  begin
    Finding := Default(TAtlasTaskFinding);
    Finding.FileName := 'C:\Proj\Kunde.pas';
    Finding.Line := Index;
    Result.Findings := Result.Findings + [Finding];
  end;
end;

{ TAtlasTaskTextsTests }

procedure TAtlasTaskTextsTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasTaskTextsTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasTaskTextsTests.DurationAndFindings;
begin
  Assert.AreEqual('0,4 s', TAtlasTaskTexts.Duration(420));
  Assert.AreEqual('59,9 s', TAtlasTaskTexts.Duration(59999));
  Assert.AreEqual('2:05 min', TAtlasTaskTexts.Duration(125000));
  Assert.AreEqual('0,0 s', TAtlasTaskTexts.Duration(-5));
  Assert.AreEqual('keine Befunde', TAtlasTaskTexts.Findings(0));
  Assert.AreEqual('1 Befund', TAtlasTaskTexts.Findings(1));
  Assert.AreEqual('3 Befunde', TAtlasTaskTexts.Findings(3));
  TAtlasStrings.Language := TAtlasLanguage.English;
  Assert.AreEqual('2.3 s', TAtlasTaskTexts.Duration(2340));
end;

procedure TAtlasTaskTextsTests.HeaderPerOutcome;
var
  Item: TAtlasTaskRun;
begin
  Assert.AreEqual('Delphi-12-Prüfung: Exit-Code 1, 2,3 s, 2 Befunde',
    TAtlasTaskTexts.Header(Run(TAtlasTaskOutcome.Finished, 1, 2), 600));
  Assert.AreEqual('Delphi-12-Prüfung: nach 600 s abgebrochen (Zeitlimit), keine Befunde',
    TAtlasTaskTexts.Header(Run(TAtlasTaskOutcome.TimedOut, -1, 0), 600));
  Assert.AreEqual('Delphi-12-Prüfung: abgebrochen, 1 Befund',
    TAtlasTaskTexts.Header(Run(TAtlasTaskOutcome.Cancelled, -1, 1), 600));
  Item := Run(TAtlasTaskOutcome.ProgramMissing, -1, 0);
  Item.Error := 'pwsh';
  Assert.AreEqual('Delphi-12-Prüfung: Programm „pwsh“ nicht gefunden (gesucht in C:\Proj und in PATH)',
    TAtlasTaskTexts.Header(Item, 600), 'klare Meldung mit Pfad');
  Item := Run(TAtlasTaskOutcome.StartFailed, -1, 0);
  Item.Error := 'Zugriff verweigert';
  Assert.AreEqual('Delphi-12-Prüfung: Start fehlgeschlagen: Zugriff verweigert', TAtlasTaskTexts.Header(Item, 600));
  Assert.AreEqual('▶ Delphi-12-Prüfung läuft: pwsh Tools/Check-Delphi12.ps1',
    TAtlasTaskTexts.Running('Delphi-12-Prüfung', 'pwsh Tools/Check-Delphi12.ps1'));
end;

procedure TAtlasTaskTextsTests.BlockedNamesErrorsOrExitCode;
begin
  Assert.AreEqual('Delphi-12-Prüfung: 2 Fehler, Build abgebrochen',
    TAtlasTaskTexts.Blocked(Run(TAtlasTaskOutcome.Finished, 1, 2)), 'Text aus dem Issue');
  Assert.AreEqual('Delphi-12-Prüfung: Exit-Code 3, Build abgebrochen',
    TAtlasTaskTexts.Blocked(Run(TAtlasTaskOutcome.Finished, 3, 0)));
  Assert.AreEqual('Delphi-12-Prüfung: nicht gelaufen, Build abgebrochen',
    TAtlasTaskTexts.Blocked(Run(TAtlasTaskOutcome.ProgramMissing, -1, 0)));
end;

procedure TAtlasTaskTextsTests.LastResultAndDescription;
var
  Last: TAtlasTaskLastRun;
  Task: TAtlasTaskDefinition;
begin
  Assert.AreEqual('noch nicht gelaufen', TAtlasTaskTexts.LastResult(Default(TAtlasTaskLastRun), False));
  Last := TAtlasTaskLastRun.From(Run(TAtlasTaskOutcome.Finished, 0, 0));
  Last.FinishedAt := EncodeDateTime(2026, 10, 23, 14, 3, 0, 0);
  Assert.AreEqual('bestanden 14:03', TAtlasTaskTexts.LastResult(Last, True));
  Last.ExitCode := 2;
  Assert.AreEqual('Exit-Code 2 14:03', TAtlasTaskTexts.LastResult(Last, True));
  Last.Counts.Errors := 4;
  Assert.AreEqual('4 Fehler 14:03', TAtlasTaskTexts.LastResult(Last, True), 'Fehler vor dem Exit-Code');
  Last.Outcome := TAtlasTaskOutcome.TimedOut;
  Assert.AreEqual('nicht gelaufen 14:03', TAtlasTaskTexts.LastResult(Last, True));
  Task := Default(TAtlasTaskDefinition);
  Task.Command := 'pwsh';
  Task.Args := TArray<string>.Create('Tools/Check-Delphi12.ps1');
  Task.Group := TAtlasTaskGroup.Check;
  Assert.AreEqual('Prüfung · pwsh Tools/Check-Delphi12.ps1 · bestanden 14:03',
    TAtlasTaskTexts.Description(Task, 'bestanden 14:03'));
  Assert.AreEqual('Sonstiges', TAtlasTaskTexts.GroupName(TAtlasTaskGroup.Other));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTaskTextsTests);

end.
