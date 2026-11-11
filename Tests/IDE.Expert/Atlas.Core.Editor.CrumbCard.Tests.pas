unit Atlas.Core.Editor.CrumbCard.Tests;

// Kennzahlen-Karte an Brotkrumengliedern (#1787): Methode mit Werten und
// Grenzen, Typ mit Mitgliedern und Vererbungstiefe, ohne Kennzahlen nur die
// Kopfzeile.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasCrumbCardsTests = class
  public
    [Test]
    procedure MethodShowsBodyMetrics;
    [Test]
    procedure TypeShowsStructure;
    [Test]
    procedure WithoutMetricsOnlyTitle;
    [Test]
    procedure RowTexts;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Lsp.DocumentSymbols,
  Atlas.Core.Editor.Metrics,
  Atlas.Core.Outline.Model,
  Atlas.Core.Editor.CrumbCard;

const
  cCode =
    'unit Kunden;'#13#10 +                                          // 0
    'interface'#13#10 +                                             // 1
    'type'#13#10 +                                                  // 2
    '  TKunde = class(TObject)'#13#10 +                             // 3
    '    procedure Speichern(A, B: Integer);'#13#10 +               // 4
    '  end;'#13#10 +                                                // 5
    'implementation'#13#10 +                                        // 6
    'procedure TKunde.Speichern(A, B: Integer);'#13#10 +            // 7
    'begin'#13#10 +                                                 // 8
    'end;'#13#10 +                                                  // 9
    'end.';

  // Zeilen 1-basiert wie vom Server.
  cAnswer =
    '{"enabled": true, "limits": {"length": 60, "nesting": 4, "cyclomatic": 15, "parameters": 5},' +
    ' "methods": [{"name": "TKunde.Speichern", "line": 8, "values": {"length": 86, "nesting": 2,' +
    ' "cyclomatic": 3, "parameters": 2}}],' +
    ' "structure": [{"kind": "classSize", "line": 4, "value": 1, "limit": 30},' +
    ' {"kind": "inheritanceDepth", "line": 4, "value": 2, "limit": 5, "atLeast": true}]}';

function Nodes: TAtlasOutlineNodes;
var
  mTree: TSyntaxTree;
  mSymbols: TJSONArray;
begin
  mTree := TPascalParser.Parse(cCode);
  try
    mSymbols := TLspDocumentSymbols.BuildSymbols(mTree, cCode);
  finally
    mTree.Free;
  end;
  try
    Result := TAtlasOutline.FromJson(mSymbols);
  finally
    mSymbols.Free;
  end;
end;

function Lines: TArray<string>;
begin
  Result := cCode.Split([#13#10]);
end;

function Metrics: TAtlasFileMetrics;
var
  mJson: TJSONValue;
begin
  mJson := TJSONObject.ParseJSONValue(cAnswer);
  try
    Result := TAtlasFileMetrics.FromJson(mJson);
  finally
    mJson.Free;
  end;
end;

function NodeAt(const ANodes: TAtlasOutlineNodes; const AName: string; ALine: Integer): Integer;
begin
  for Result := 0 to High(ANodes) do
  begin
    if (ANodes[Result].Name = AName) and (ANodes[Result].NameLine = ALine) then
    begin
      Exit;
    end;
  end;
  Result := -1;
end;

procedure TAtlasCrumbCardsTests.MethodShowsBodyMetrics;
var
  mNodes: TAtlasOutlineNodes;
  mCard: TAtlasCrumbCard;
begin
  mNodes := Nodes;
  // Vom Deklarationsglied aus zählen die Werte des Rumpfs.
  mCard := TAtlasCrumbCards.Build(mNodes, Lines, NodeAt(mNodes, 'Speichern', 4), True, Metrics);
  Assert.IsTrue(mCard.Available);
  Assert.IsTrue(mCard.Title.Contains('Speichern(A, B: Integer)'), mCard.Title);
  Assert.AreEqual(4, Integer(Length(mCard.Rows)));
  Assert.IsTrue(mCard.Rows[0].Metric = TAtlasCardMetric.Lines);
  Assert.AreEqual(86, mCard.Rows[0].Value);
  Assert.AreEqual(60, mCard.Rows[0].Limit);
  Assert.IsTrue(mCard.Rows[0].Over);
  Assert.IsTrue(mCard.Rows[1].Metric = TAtlasCardMetric.Cyclomatic);
  Assert.AreEqual(3, mCard.Rows[1].Value);
  Assert.IsFalse(mCard.Rows[1].Over);
end;

procedure TAtlasCrumbCardsTests.TypeShowsStructure;
var
  mNodes: TAtlasOutlineNodes;
  mCard: TAtlasCrumbCard;
begin
  mNodes := Nodes;
  mCard := TAtlasCrumbCards.Build(mNodes, Lines, NodeAt(mNodes, 'TKunde', 3), True, Metrics);
  Assert.IsTrue(mCard.Available);
  Assert.AreEqual('TKunde = class(TObject)', mCard.Title);
  Assert.AreEqual(3, Integer(Length(mCard.Rows)));
  Assert.IsTrue(mCard.Rows[0].Metric = TAtlasCardMetric.Lines);
  Assert.AreEqual(MaxInt, mCard.Rows[0].Limit);
  Assert.IsTrue(mCard.Rows[1].Metric = TAtlasCardMetric.Members);
  Assert.IsTrue(mCard.Rows[2].Metric = TAtlasCardMetric.InheritanceDepth);
  Assert.IsTrue(mCard.Rows[2].AtLeast);
end;

procedure TAtlasCrumbCardsTests.WithoutMetricsOnlyTitle;
var
  mNodes: TAtlasOutlineNodes;
  mCard: TAtlasCrumbCard;
begin
  mNodes := Nodes;
  mCard := TAtlasCrumbCards.Build(mNodes, Lines, NodeAt(mNodes, 'Speichern', 4), False, Default(TAtlasFileMetrics));
  Assert.IsFalse(mCard.Available);
  Assert.IsTrue(mCard.Title <> '');
  Assert.AreEqual(0, Integer(Length(mCard.Rows)));
  Assert.IsFalse(TAtlasCrumbCards.HasCard(mNodes, -1));
  Assert.IsFalse(TAtlasCrumbCards.HasCard(mNodes, NodeAt(mNodes, 'Kunden', 0)));
end;

procedure TAtlasCrumbCardsTests.RowTexts;
var
  mRow: TAtlasCardRow;
begin
  mRow := Default(TAtlasCardRow);
  mRow.Value := 5;
  mRow.Limit := MaxInt;
  Assert.AreEqual('5', mRow.ValueText);
  Assert.IsFalse(mRow.Over);
  mRow.AtLeast := True;
  Assert.AreEqual('≥ 5', mRow.ValueText);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCrumbCardsTests);

end.
