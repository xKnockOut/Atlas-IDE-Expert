unit Shell.Composition.Refactorings.Parts.Tests;

// Teile der Refactorings des Servers einzeln: Jeder Teil meldet nur seine eigenen Befehle an.

interface

uses
  DUnitX.TestFramework,
  Shell.Composition.Refactorings.Services;

type
  [TestFixture]
  TShellRefactoringPartsTests = class
  private
    FServices: TShellRefactoringServices;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Jeder Teil meldet nur seine eigenen Befehle an.</summary>
    [Test]
    procedure EachPartRegistersItsCommands;
  end;

implementation

uses
  System.JSON,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.ChangeSignature,
  Atlas.Common.Lsp.SafeDelete,
  Atlas.Common.Lsp.TypeAlias,
  Atlas.Common.Lsp.DisableWarning,
  Atlas.Common.Lsp.StepFilter,
  Atlas.Common.Lsp.MethodBreakpoints,
  Atlas.Common.Lsp.UnitRename,
  Atlas.Common.Lsp.RaiseVisibility,
  Shell.Composition.Refactorings.Structure,
  Shell.Composition.Refactorings.Visibility,
  Shell.Composition.Refactorings.Conversions,
  Shell.Composition.Refactorings.Types,
  Shell.Composition.Refactorings.Fixes,
  Shell.Composition.Refactorings.Editing,
  Shell.Composition.Stepping,
  Shell.Composition.MethodBreakpoints,
  Shell.Composition.Refactorings.TestSupport;

/// <summary>Einstellungen der Refactorings: alles aus.</summary>
function NoSettings(const AUri: string): TRefactoringSettings;
begin
  Result := Default(TRefactoringSettings);
end;

/// <summary>Befehle, die APart anmeldet, als JSON; gibt APart frei.</summary>
function CommandsOf(APart: TShellRefactoringPart): string;
var
  mCommands: TLspCommands;
  mCapability: TJSONObject;
begin
  mCommands := TLspCommands.Create;
  try
    APart.Register(mCommands);
    mCapability := mCommands.Capability;
    try
      Result := mCapability.ToJSON;
    finally
      mCapability.Free;
    end;
  finally
    mCommands.Free;
    APart.Free;
  end;
end;

procedure TShellRefactoringPartsTests.Setup;
var
  mDocuments: IDocumentStore;
begin
  mDocuments := TDocumentStore.Create;
  FServices := NewRefactoringServices(mDocuments, NoSettings);
end;

procedure TShellRefactoringPartsTests.TearDown;
begin
  FServices := Default(TShellRefactoringServices);
end;

procedure TShellRefactoringPartsTests.EachPartRegistersItsCommands;
var
  mText: string;
begin
  mText := CommandsOf(TShellStructureRefactorings.Create(FServices));
  Assert.IsTrue(Pos(TLspChangeSignature.cApplyCommand, mText) > 0, 'Aufbau');
  Assert.IsFalse(Pos(TLspStepFilter.cCommand, mText) > 0, 'Aufbau ohne Debugger');
  mText := CommandsOf(TShellConversionRefactorings.Create(FServices));
  Assert.IsFalse(Pos(TLspSafeDelete.cApplyCommand, mText) > 0, 'Umwandlungen ohne Sicher löschen');
  Assert.IsTrue(Pos(TLspTypeAlias.cApplyCommand, CommandsOf(TShellTypeRefactorings.Create(FServices))) > 0, 'Typen');
  Assert.IsTrue(Pos(TLspDisableWarning.cApplyCommand, CommandsOf(TShellFixRefactorings.Create(FServices))) > 0,
    'Korrekturen');
  Assert.IsTrue(Pos(TLspUnitRename.cCommand, CommandsOf(TShellEditingRefactorings.Create(FServices))) > 0,
    'Bearbeiten');
  Assert.IsTrue(Pos(TLspStepFilter.cCountsCommand, CommandsOf(TShellStepping.Create(FServices))) > 0, 'Debugger');
  Assert.IsTrue(Pos(TLspMethodBreakpoints.cCommand, CommandsOf(TShellMethodBreakpoints.Create(FServices))) > 0,
    'Methodenhaltepunkte');
  Assert.IsTrue(Pos(TLspRaiseVisibility.cCommand, CommandsOf(TShellVisibilityRefactorings.Create(FServices))) > 0,
    'Sichtbarkeit');
end;

initialization
  TDUnitX.RegisterTestFixture(TShellRefactoringPartsTests);

end.
