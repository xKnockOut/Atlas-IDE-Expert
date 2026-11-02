unit Shell.Composition.Analysis.Tests;

// Analysen des Servers: Befehle der Metriken und TODOs werden angemeldet, die Namensräume des Projekts kommen bei
// den Analysen an.

interface

uses
  DUnitX.TestFramework,
  Shell.Composition.Analysis;

type
  [TestFixture]
  TShellAnalysisTests = class
  public
    /// <summary>Metriken und TODO-Übersicht stehen in executeCommandProvider.</summary>
    [Test]
    procedure RegistersReportCommands;
    /// <summary>Gesetzte Namensräume liest die Analyse unverändert zurück.</summary>
    [Test]
    procedure SetNamespacesReachesAnalyses;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.Metrics,
  Atlas.Common.Lsp.Todos;

procedure TShellAnalysisTests.RegistersReportCommands;
var
  mAnalysis: TShellAnalysis;
  mCommands: TLspCommands;
  mCapability: TJSONObject;
  mText: string;
begin
  mAnalysis := TShellAnalysis.Create(Default(TShellAnalysisServices));
  mCommands := TLspCommands.Create;
  try
    mAnalysis.RegisterReportCommands(mCommands);
    mCapability := mCommands.Capability;
    try
      mText := mCapability.ToJSON;
    finally
      mCapability.Free;
    end;
    Assert.IsTrue(Pos('"' + TLspMetrics.Command + '"', mText) > 0, TLspMetrics.Command);
    Assert.IsTrue(Pos('"' + TLspTodos.Command + '"', mText) > 0, TLspTodos.Command);
  finally
    mCommands.Free;
    mAnalysis.Free;
  end;
end;

procedure TShellAnalysisTests.SetNamespacesReachesAnalyses;
var
  mAnalysis: TShellAnalysis;
  mNamespaces: TArray<string>;
begin
  mAnalysis := TShellAnalysis.Create(Default(TShellAnalysisServices));
  try
    mAnalysis.SetNamespaces(TArray<string>.Create('System', 'Vcl'));
    mNamespaces := mAnalysis.Namespaces;
    Assert.AreEqual(2, Integer(Length(mNamespaces)));
    Assert.AreEqual('System', mNamespaces[0]);
    Assert.AreEqual('Vcl', mNamespaces[1]);
  finally
    mAnalysis.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TShellAnalysisTests);

end.
