unit Atlas.Common.Monitor.Commands.Tests;

// Tests für die Befehlsliste des Prüffensters von AtlasMonitor (#1900): Aufrufe je Befehl, Optionen, Aufruf für die
// CI ohne Ausgabedatei, Anführungszeichen, Art der Ausgabe, Rückfrage vor schreibenden Befehlen, Texte. Dass jeder
// Schalter des Servers vorkommt, prüft Shell.CommandLine.Tests.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMonitorCommandsTests = class
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure CheckWritesSarifIntoFile;
    [Test]
    procedure OptionsBecomeSwitches;
    [Test]
    procedure CopiedCallHasNoOutputFile;
    [Test]
    procedure ReportsUseTheirOwnFile;
    [Test]
    procedure ReplayNeedsNoTarget;
    [Test]
    procedure QuotesArguments;
    [Test]
    procedure WritingCommandsAsk;
    [Test]
    procedure TextsInBothLanguages;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Monitor.Commands;

function Joined(const AArgs: TArray<string>): string;
begin
  Result := string.Join(' ', AArgs);
end;

procedure TMonitorCommandsTests.Setup;
begin
  TAtlasLocale.Use(TTextLanguage.German);
end;

procedure TMonitorCommandsTests.TearDown;
begin
  TAtlasLocale.Use(TTextLanguage.German);
end;

procedure TMonitorCommandsTests.CheckWritesSarifIntoFile;
begin
  Assert.AreEqual('--check App.dproj --format sarif --fail-on never --output out.sarif --locale de',
    Joined(TMonitorCommands.Arguments(TMonitorCommand.Check, 'App.dproj', Default(TMonitorOptions), 'out.sarif',
    'de')));
  Assert.AreEqual<TMonitorOutputKind>(TMonitorOutputKind.Findings, TMonitorCommands.OutputKind(TMonitorCommand.Check));
  Assert.AreEqual('.sarif', TMonitorCommands.OutputExtension(TMonitorCommand.Check));
end;

procedure TMonitorCommandsTests.OptionsBecomeSwitches;
var
  mOptions: TMonitorOptions;
  mText: string;
begin
  mOptions := Default(TMonitorOptions);
  mOptions.MinSeverity := 'warning';
  mOptions.Rules := 'magic-number';
  mOptions.Profile := 'strict';
  mOptions.Units := 'Src/*';
  mOptions.Changed := True;
  mOptions.IncludeUncommitted := True;
  mOptions.ChangedLines := True;
  mOptions.Baseline := 'b.json';
  mOptions.NoIndex := True;
  mOptions.Timings := True;
  mText := Joined(TMonitorCommands.Arguments(TMonitorCommand.Check, 'Src', mOptions, 'o.sarif', ''));
  Assert.IsTrue(mText.Contains('--min-severity warning --rules magic-number --profile strict --baseline b.json ' +
    '--no-index --units Src/* --changed --include-uncommitted --changed-lines'), mText);
  Assert.IsTrue(mText.Contains('--timings o.timings.md'), mText);
  Assert.IsFalse(mText.Contains('--locale'), 'ohne Sprache');
  // --diff hat Vorrang, Basis mit "=".
  mOptions.DiffRef := 'HEAD~1';
  Assert.IsTrue(Joined(TMonitorCommands.Arguments(TMonitorCommand.Check, 'Src', mOptions, '', '')).Contains(
    '--diff HEAD~1'));
  mOptions.DiffRef := '';
  mOptions.ChangedBase := 'dev';
  Assert.IsTrue(Joined(TMonitorCommands.Arguments(TMonitorCommand.Metrics, 'Src', mOptions, 'm.md', '')).Contains(
    '--metrics --units Src/* --changed=dev'));
  mOptions := Default(TMonitorOptions);
end;

procedure TMonitorCommandsTests.CopiedCallHasNoOutputFile;
var
  mText: string;
begin
  mText := TMonitorCommands.CommandLine('AtlasServer.exe', TMonitorCommands.Arguments(TMonitorCommand.Check,
    'C:\Projekte\Mein App', Default(TMonitorOptions), '', ''));
  Assert.AreEqual('AtlasServer.exe --check "C:\Projekte\Mein App" --format sarif', mText);
end;

procedure TMonitorCommandsTests.ReportsUseTheirOwnFile;
var
  mOptions: TMonitorOptions;
begin
  mOptions := Default(TMonitorOptions);
  Assert.AreEqual('--check Src --architecture a.html', Joined(TMonitorCommands.Arguments(
    TMonitorCommand.Architecture, 'Src', mOptions, 'a.html', '')));
  Assert.AreEqual('--check Src --hotspots hotspots.html', Joined(TMonitorCommands.Arguments(
    TMonitorCommand.Hotspots, 'Src', mOptions, '', '')), 'ohne Datei ein Name für die CI');
  mOptions.ArchitectureFile := 'stand.json';
  Assert.AreEqual('--check Src --architecture stand.json', Joined(TMonitorCommands.Arguments(
    TMonitorCommand.ArchitectureSave, 'Src', mOptions, 'x.json', '')));
  Assert.AreEqual('--check Src --architecture a.html --compare stand.json', Joined(TMonitorCommands.Arguments(
    TMonitorCommand.ArchitectureCompare, 'Src', mOptions, 'a.html', '')));
  Assert.AreEqual('--check Src --fix all --fix-dry-run --output f.diff', Joined(TMonitorCommands.Arguments(
    TMonitorCommand.FixDryRun, 'Src', mOptions, 'f.diff', '')));
  Assert.AreEqual('--check Src --format-check --format diff --output f.diff', Joined(TMonitorCommands.Arguments(
    TMonitorCommand.FormatCheck, 'Src', mOptions, 'f.diff', '')));
  mOptions.AffectedBase := 'dev';
  Assert.AreEqual('--check T.dproj --affected-tests=dev --output t.txt', Joined(TMonitorCommands.Arguments(
    TMonitorCommand.AffectedTests, 'T.dproj', mOptions, 't.txt', '')));
  Assert.AreEqual<TMonitorOutputKind>(TMonitorOutputKind.Html, TMonitorCommands.OutputKind(TMonitorCommand.Hotspots));
  Assert.AreEqual<TMonitorOutputKind>(TMonitorOutputKind.Text, TMonitorCommands.OutputKind(TMonitorCommand.Todos));
  mOptions := Default(TMonitorOptions);
end;

procedure TMonitorCommandsTests.ReplayNeedsNoTarget;
var
  mOptions: TMonitorOptions;
begin
  mOptions := Default(TMonitorOptions);
  mOptions.ReplayFile := 'C:\crash\anfrage.json';
  Assert.IsFalse(TMonitorCommands.NeedsTarget(TMonitorCommand.Replay));
  Assert.IsTrue(TMonitorCommands.NeedsTarget(TMonitorCommand.Query));
  Assert.AreEqual('--replay C:\crash\anfrage.json --locale en', Joined(TMonitorCommands.Arguments(
    TMonitorCommand.Replay, 'Src', mOptions, 'r.txt', 'en')));
  mOptions := Default(TMonitorOptions);
end;

procedure TMonitorCommandsTests.QuotesArguments;
begin
  Assert.AreEqual('"C:\Program Files\Atlas\AtlasServer.exe" --query "classes where methods > 40"',
    TMonitorCommands.CommandLine('C:\Program Files\Atlas\AtlasServer.exe',
    TArray<string>.Create('--query', 'classes where methods > 40')));
end;

procedure TMonitorCommandsTests.WritingCommandsAsk;
var
  mOptions: TMonitorOptions;
begin
  mOptions := Default(TMonitorOptions);
  Assert.IsTrue(TMonitorCommands.Writes(TMonitorCommand.FormatWrite, mOptions));
  Assert.IsTrue(TMonitorCommands.Writes(TMonitorCommand.Fix, mOptions));
  Assert.IsFalse(TMonitorCommands.Writes(TMonitorCommand.FixDryRun, mOptions));
  Assert.IsFalse(TMonitorCommands.Writes(TMonitorCommand.Check, mOptions));
  mOptions.UpdateBaseline := True;
  Assert.IsTrue(TMonitorCommands.Writes(TMonitorCommand.Check, mOptions));
  mOptions := Default(TMonitorOptions);
end;

procedure TMonitorCommandsTests.TextsInBothLanguages;
begin
  Assert.AreEqual('Prüfen', TMonitorCommands.Text(TMonitorCommand.Check));
  TAtlasLocale.Use(TTextLanguage.English);
  Assert.AreEqual('Replay crash case', TMonitorCommands.Text(TMonitorCommand.Replay));
end;

initialization
  TDUnitX.RegisterTestFixture(TMonitorCommandsTests);

end.
