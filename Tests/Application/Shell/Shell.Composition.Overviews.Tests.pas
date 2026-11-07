unit Shell.Composition.Overviews.Tests;

// Übersichten des Servers: Befehle werden angemeldet (lesende nebenläufig), Quelltext kommt über die Dienste der
// Komposition, die Abfragen stehen für die Regeln query:<name> bereit.

interface

uses
  DUnitX.TestFramework,
  Shell.Composition.Overviews;

type
  [TestFixture]
  TShellOverviewsTests = class
  private
    FReads: Integer;
    function NewServices: TShellOverviewServices;
    function CountRead(const AFileName: string; out AText: string): Boolean;
  public
    [Setup]
    procedure Setup;
    /// <summary>Alle Befehle der Übersichten stehen in executeCommandProvider.</summary>
    [Test]
    procedure RegistersAllCommands;
    /// <summary>Lesende Befehle laufen nebenläufig (Diagnose 06.11.2026), Berichte speichern und uses ändern in der
    /// Reihenfolge der Nachrichten.</summary>
    [Test]
    procedure ReadingCommandsRunConcurrently;
    /// <summary>Die Rekursionssymbole lesen den Quelltext über den Dienst der Komposition.</summary>
    [Test]
    procedure RecursionReadsThroughServices;
    /// <summary>Die Abfragen bestehen ab dem Anlegen.</summary>
    [Test]
    procedure QueriesExist;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.Architecture,
  Atlas.Common.Lsp.Query,
  Atlas.Common.Lsp.Hotspots,
  Atlas.Common.Lsp.UnitRelations,
  Atlas.Common.Lsp.SymbolPath,
  Atlas.Common.Lsp.DebugDisplay,
  Atlas.Common.Lsp.EventHandlers,
  Atlas.Common.Lsp.Recursion;

const
  cRecursiveUnit = 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'  P;'#10'end;'#10'end.'#10;

procedure TShellOverviewsTests.Setup;
begin
  FReads := 0;
end;

function TShellOverviewsTests.CountRead(const AFileName: string; out AText: string): Boolean;
begin
  Inc(FReads);
  AText := cRecursiveUnit;
  Result := True;
end;

function TShellOverviewsTests.NewServices: TShellOverviewServices;
begin
  Result := Default(TShellOverviewServices);
  Result.ReadText := CountRead;
end;

procedure TShellOverviewsTests.RegistersAllCommands;
var
  mOverviews: TShellOverviews;
  mCommands: TLspCommands;
  mCapability: TJSONObject;
  mText: string;
  mName: string;
begin
  mOverviews := TShellOverviews.Create(NewServices);
  mCommands := TLspCommands.Create;
  try
    mOverviews.RegisterReportCommands(mCommands);
    mOverviews.RegisterUnitCommands(mCommands);
    mCapability := mCommands.Capability;
    try
      mText := mCapability.ToJSON;
    finally
      mCapability.Free;
    end;
    for mName in TArray<string>.Create(TLspArchitecture.cCommand, TLspArchitecture.cSaveCommand, TLspQuery.cCommand,
      TLspHotspots.cCommand, TLspHotspots.cSaveCommand, TLspUnitRelations.cCommand, TLspUnitRelations.cMoveCommand,
      TLspUnitRelations.cRemoveCommand, TLspUnitRelations.cCostCommand, TLspUnitRelations.cUseUnitCommand,
      TLspSymbolPath.cCommand, TLspDebugDisplay.cCommand, TLspEventHandlers.cCommand, TLspRecursion.cCommand) do
    begin
      Assert.IsTrue(Pos('"' + mName + '"', mText) > 0, mName);
    end;
  finally
    mCommands.Free;
    mOverviews.Free;
  end;
end;

procedure TShellOverviewsTests.ReadingCommandsRunConcurrently;
var
  mOverviews: TShellOverviews;
  mCommands: TLspCommands;
  mName: string;
begin
  mOverviews := TShellOverviews.Create(NewServices);
  mCommands := TLspCommands.Create;
  try
    mOverviews.RegisterReportCommands(mCommands);
    mOverviews.RegisterUnitCommands(mCommands);
    for mName in TArray<string>.Create(TLspArchitecture.cCommand, TLspQuery.cCommand, TLspHotspots.cCommand,
      TLspHotspots.cSaveCommand, TLspUnitRelations.cCommand, TLspUnitRelations.cCostCommand,
      TLspUnitRelations.cUseUnitCommand, TLspSymbolPath.cCommand, TLspRecursion.cCommand) do
    begin
      Assert.IsTrue(mCommands.IsConcurrentCommand(mName), mName);
    end;
    for mName in TArray<string>.Create(TLspArchitecture.cSaveCommand, TLspUnitRelations.cMoveCommand,
      TLspUnitRelations.cRemoveCommand, TLspDebugDisplay.cCommand, TLspEventHandlers.cCommand) do
    begin
      Assert.IsFalse(mCommands.IsConcurrentCommand(mName), mName);
    end;
  finally
    mCommands.Free;
    mOverviews.Free;
  end;
end;

procedure TShellOverviewsTests.RecursionReadsThroughServices;
var
  mOverviews: TShellOverviews;
  mCommands: TLspCommands;
  mArguments: TJSONArray;
  mResult: TJSONValue;
begin
  mOverviews := TShellOverviews.Create(NewServices);
  mCommands := TLspCommands.Create;
  mArguments := TJSONArray.Create;
  try
    mOverviews.RegisterUnitCommands(mCommands);
    mArguments.Add('file:///tmp/u.pas');
    mResult := mCommands.Execute(TLspRecursion.cCommand, mArguments);
    try
      Assert.AreEqual(1, FReads);
      Assert.IsTrue(mResult is TJSONObject);
    finally
      mResult.Free;
    end;
  finally
    mArguments.Free;
    mCommands.Free;
    mOverviews.Free;
  end;
end;

procedure TShellOverviewsTests.QueriesExist;
var
  mOverviews: TShellOverviews;
begin
  mOverviews := TShellOverviews.Create(NewServices);
  try
    Assert.IsNotNull(mOverviews.Queries);
  finally
    mOverviews.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TShellOverviewsTests);

end.
