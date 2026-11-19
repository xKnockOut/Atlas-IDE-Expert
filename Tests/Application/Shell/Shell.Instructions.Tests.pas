unit Shell.Instructions.Tests;

// Anweisungsdateien für KI-Assistenten auf der Platte (#2615): TShellInstructions legt die Datei an und meldet
// danach „aktuell“; die Kommandozeile prüft mit --check-instructions (Exit-Code 1 bei veraltetem Abschnitt) und
// schreibt mit --write-instructions.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TShellInstructionsTests = class
  private
    FFolder: string;
    function Agents: string;
    function RunLinter(const AFlag: string): Integer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Erster Lauf legt AGENTS.md mit Abschnitt an, der zweite meldet ihn als aktuell.</summary>
    [Test]
    procedure WritesThenCurrent;
    /// <summary>Ohne Schreiben bleibt die Platte unberührt, der Stand ist „fehlt“.</summary>
    [Test]
    procedure ReadOnlyLeavesDisk;
    /// <summary>--check-instructions: 1 vor dem Schreiben, 0 danach; --write-instructions schreibt mit 0.</summary>
    [Test]
    procedure CommandLineExitCodes;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Instructions,
  Atlas.Common.Lsp.Instructions,
  Shell.CommandLine,
  Shell.Composition.Instructions,
  Shell.Linter.Instructions,
  Shell.Linter.Settings;

{ TShellInstructionsTests }

procedure TShellInstructionsTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'AtlasInstructions' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FFolder);
  TFile.WriteAllText(TPath.Combine(FFolder, 'atlas.json'), '{}');
end;

procedure TShellInstructionsTests.TearDown;
begin
  if TDirectory.Exists(FFolder) then
  begin
    TDirectory.Delete(FFolder, True);
  end;
  FFolder := '';
end;

function TShellInstructionsTests.Agents: string;
begin
  Result := TPath.Combine(FFolder, 'AGENTS.md');
end;

function TShellInstructionsTests.RunLinter(const AFlag: string): Integer;
begin
  Result := TLinterInstructions.Run(TCommandLineOptions.Parse(['--check', FFolder, AFlag]));
end;

procedure TShellInstructionsTests.WritesThenCurrent;
var
  mSettings: TServerSettings;
  mFiles: TArray<TInstructionsFile>;
begin
  mSettings := TLinterSettings.Load(FFolder);
  mFiles := TShellInstructions.Run(FFolder, mSettings, True);
  Assert.AreEqual(1, Integer(Length(mFiles)));
  Assert.IsTrue(mFiles[0].Written, 'geschrieben');
  Assert.AreEqual('', mFiles[0].Error);
  Assert.IsTrue(TFile.Exists(Agents), 'AGENTS.md angelegt');
  Assert.IsTrue(TFile.ReadAllText(Agents, TEncoding.UTF8).Contains(TRuleInstructions.cEndMarker), 'Endmarke');
  mFiles := TShellInstructions.Run(FFolder, mSettings, False);
  Assert.AreEqual(Ord(TInstructionsState.Current), Ord(mFiles[0].State), 'zweiter Lauf aktuell');
  Assert.AreEqual(0, TLspInstructions.StaleCount(mFiles));
end;

procedure TShellInstructionsTests.ReadOnlyLeavesDisk;
var
  mFiles: TArray<TInstructionsFile>;
begin
  mFiles := TShellInstructions.Run(FFolder, TLinterSettings.Load(FFolder), False);
  Assert.AreEqual(1, Integer(Length(mFiles)));
  Assert.AreEqual(Ord(TInstructionsState.Missing), Ord(mFiles[0].State), 'fehlt');
  Assert.IsFalse(mFiles[0].Written, 'nicht geschrieben');
  Assert.IsFalse(TFile.Exists(Agents), 'keine Datei angelegt');
end;

procedure TShellInstructionsTests.CommandLineExitCodes;
begin
  Assert.AreEqual(1, RunLinter('--check-instructions'), 'fehlt');
  Assert.IsFalse(TFile.Exists(Agents), 'Prüfen schreibt nicht');
  Assert.AreEqual(0, RunLinter('--write-instructions'), 'geschrieben');
  Assert.IsTrue(TFile.Exists(Agents), 'Datei da');
  Assert.AreEqual(0, RunLinter('--check-instructions'), 'aktuell');
end;

end.
