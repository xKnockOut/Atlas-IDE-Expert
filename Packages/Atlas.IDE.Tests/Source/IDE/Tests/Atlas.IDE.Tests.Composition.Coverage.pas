unit Atlas.IDE.Tests.Composition.Coverage;

// Testabdeckung (#275) und Mutationslauf (#1460), aus Atlas.IDE.Tests.Composition gelöst:
// - Teil „TestCoverage“ der Feature-Tabelle (liest nur einen Bericht, baut und startet nichts; unabhängig von
//   tests.run) mit den Befehlen „Testabdeckung laden …“ und „Testabdeckung ausblenden“;
// - Mutationslauf (tests.mutation): Die Composition legt ihn mit dem Läufer an und gibt ihn vor ihm frei; Befehle
//   für Methode, Unit, geänderte Methoden und Abbruch;
// - Balken der Testabdeckung und Ergebnisse des Mutationslaufs in der Rinne.

interface

uses
  Atlas.Core.Modules.Contract,
  Atlas.IDE.Tests.Output,
  Atlas.IDE.Tests.Runner;

/// <summary>Teil „TestCoverage“ der Feature-Tabelle: nur im normalen Start und mit tests.coverage.</summary>
function CoveragePart: IAtlasFeaturePart;
/// <summary>Balken der Testabdeckung und Ergebnisse des Mutationslaufs in der Rinne von AScope.</summary>
procedure ProvideGutterMarks(const AScope: IAtlasModuleScope);
/// <summary>„Testabdeckung laden …“ sichtbar: tests.coverage und Teil gestartet.</summary>
function CoverageVisible: Boolean;
/// <summary>„Testabdeckung ausblenden“ sichtbar: zusätzlich ein geladener Bericht.</summary>
function CoverageClearVisible: Boolean;
procedure LoadCoverage;
procedure ClearCoverage;
/// <summary>Mutationslauf anlegen: Projektwahl und Ausgabe von ATests und AOutput (leben länger), eigener
/// Prozessläufer aus ANewRunner, Build des Schattenprojekts über die Build-Pipeline.</summary>
procedure StartMutation(const AScope: IAtlasModuleScope; ATests: TAtlasIdeTests; AOutput: TAtlasIdeTestsOutput;
  const ANewRunner: TAtlasTestsRunnerFactory);
/// <summary>Mutationslauf freigeben; schließt sein Schattenprojekt.</summary>
procedure StopMutation;
/// <summary>Läuft gerade ein Mutationslauf?</summary>
function MutationBusy: Boolean;
/// <summary>Befehle zum Starten sichtbar: tests.mutation, tests.run und kein Lauf.</summary>
function MutationIdle: Boolean;
/// <summary>„Mutationslauf abbrechen“ sichtbar: tests.mutation, tests.run und ein Lauf.</summary>
function MutationRunning: Boolean;
procedure MutateMethod;
procedure MutateUnit;
procedure MutateChanged;
procedure CancelMutation;

implementation

uses
  System.SysUtils,
  Atlas.Core.Modules.FeatureParts,
  Atlas.Core.Tests.MutationPlan,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Tests.Composition.Hooks,
  Atlas.IDE.Tests.Coverage,
  Atlas.IDE.Tests.Mutation,
  Atlas.IDE.Tests.MutationMarks;

var
  GMutation: TAtlasIdeMutationRun;

{ Testabdeckung (#275) }

function CoveragePart: IAtlasFeaturePart;
begin
  Result := TAtlasFeaturePart.When('TestCoverage',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel = TAtlasSafeLevel.Normal) and TAtlasIdeSettings.Current.TestCoverage;
    end, TAtlasIdeTestCoverage.Started, TAtlasIdeTestCoverage.Start, TAtlasIdeTestCoverage.Stop);
end;

procedure ProvideGutterMarks(const AScope: IAtlasModuleScope);
begin
  TAtlasIdeTestCoverage.ProvideIn(AScope);
  TAtlasIdeMutationMarks.ProvideIn(AScope);
end;

function CoverageVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.TestCoverage and TAtlasIdeTestCoverage.Started;
end;

function CoverageClearVisible: Boolean;
begin
  Result := CoverageVisible and TAtlasIdeTestCoverage.Loaded;
end;

procedure LoadCoverage;
begin
  TAtlasIdeTestCoverage.Choose;
end;

procedure ClearCoverage;
begin
  TAtlasIdeTestCoverage.Clear;
end;

{ Mutationslauf (#1460) }

procedure StartMutation(const AScope: IAtlasModuleScope; ATests: TAtlasIdeTests; AOutput: TAtlasIdeTestsOutput;
  const ANewRunner: TAtlasTestsRunnerFactory);
begin
  GMutation := TAtlasIdeMutationRun.Create(AScope, ATests, AOutput, ANewRunner, BuildForMutation);
end;

procedure StopMutation;
begin
  FreeAndNil(GMutation);
end;

function MutationBusy: Boolean;
begin
  Result := (GMutation <> nil) and GMutation.Running;
end;

/// <summary>Mutationslauf gewünscht: tests.mutation, tests.run und ein Lauf angelegt (mit dem Läufer).</summary>
function MutationVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.TestRun and TAtlasIdeSettings.Current.TestsMutation and (GMutation <> nil);
end;

function MutationIdle: Boolean;
begin
  Result := MutationVisible and not GMutation.Running;
end;

function MutationRunning: Boolean;
begin
  Result := MutationVisible and GMutation.Running;
end;

procedure MutateMethod;
begin
  if GMutation <> nil then
  begin
    GMutation.Start(TAtlasMutationScope.Routine);
  end;
end;

procedure MutateUnit;
begin
  if GMutation <> nil then
  begin
    GMutation.Start(TAtlasMutationScope.WholeUnit);
  end;
end;

procedure MutateChanged;
begin
  if GMutation <> nil then
  begin
    GMutation.Start(TAtlasMutationScope.Changed);
  end;
end;

procedure CancelMutation;
begin
  if GMutation <> nil then
  begin
    GMutation.Cancel;
  end;
end;

end.
