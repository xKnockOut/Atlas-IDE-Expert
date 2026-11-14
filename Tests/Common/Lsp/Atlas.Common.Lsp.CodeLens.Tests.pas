unit Atlas.Common.Lsp.CodeLens.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.CodeLens;

type
  [TestFixture]
  TLspCodeLensTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function Describe(const AEntries: TArray<TCodeLensEntry>): string;
    function SourceOf(ATree: TSyntaxTree): TCodeLensSource;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure FindsMessageHandlersAndInheritedOnes;
    [Test]
    procedure LensesForTypesAndMethods;
    [Test]
    procedure ResolvesReferenceCountWithoutHeaders;
    [Test]
    procedure WritesCommandOrData;
    [Test]
    procedure MetricLensesOverImplementedMethods;
    [Test]
    procedure MetricLensIsPlainText;
  end;

implementation

uses
  System.Generics.Collections,
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Metrics.Contract,
  Atlas.Common.Lsp.MessageHandlers;

const
  cHauptFile = 'C:\P\Haupt.pas';
  cBasisFile = 'C:\P\Basis.pas';

  cUnitBasis =
    'unit Basis;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TBasis = class'#10 +
    '    procedure WMPaint(var Message: TWMPaint); message WM_PAINT;'#10 +
    '    procedure Zeichne; virtual;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TBasis.WMPaint(var Message: TWMPaint);'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TBasis.Zeichne;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

  cUnitHaupt =
    'unit Haupt;'#10 +                                                    // 0
    'interface'#10 +                                                      // 1
    'uses Basis;'#10 +                                                    // 2
    'type'#10 +                                                           // 3
    '  TFoo = class(TBasis)'#10 +                                         // 4
    '    procedure WMPaint(var Message: TWMPaint); message WM_PAINT;'#10 + // 5
    '    procedure WMSize(var Message: TWMSize); message WM_SIZE;'#10 +   // 6
    '    procedure Zeichne; override;'#10 +                               // 7
    '  end;'#10 +                                                         // 8
    '  TKind = class(TFoo)'#10 +                                          // 9
    '  end;'#10 +                                                         // 10
    'implementation'#10 +                                                 // 11
    'procedure TFoo.WMPaint(var Message: TWMPaint);'#10 +                 // 12
    'begin'#10 +                                                          // 13
    '  Zeichne;'#10 +                                                     // 14
    'end;'#10 +                                                           // 15
    'procedure TFoo.WMSize(var Message: TWMSize);'#10 +                   // 16
    'begin'#10 +                                                          // 17
    '  Zeichne;'#10 +                                                     // 18
    'end;'#10 +                                                           // 19
    'procedure TFoo.Zeichne;'#10 +                                        // 20
    'begin'#10 +                                                          // 21
    'end;'#10 +                                                           // 22
    'end.';

function ReadFile(const AFileName: string; out AText: string): Boolean;
begin
  Result := True;
  if SameText(AFileName, cHauptFile) then
  begin
    AText := cUnitHaupt;
  end
  else if SameText(AFileName, cBasisFile) then
  begin
    AText := cUnitBasis;
  end
  else
  begin
    Result := False;
  end;
end;

{ TLspCodeLensTests }

procedure TLspCodeLensTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitBasis, cBasisFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitHaupt, cHauptFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspCodeLensTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TLspCodeLensTests.SourceOf(ATree: TSyntaxTree): TCodeLensSource;
begin
  Result.Resolver := FResolver;
  Result.Index := FIndex;
  Result.Tree := ATree;
  Result.FileName := cHauptFile;
  Result.ReadText := ReadFile;
end;

function TLspCodeLensTests.Describe(const AEntries: TArray<TCodeLensEntry>): string;
var
  mEntry: TCodeLensEntry;
begin
  Result := '';
  for mEntry in AEntries do
  begin
    Result := Result + Format('%d %d %s %d|', [mEntry.Range.StartPos.Line, Ord(mEntry.Kind), mEntry.Title,
      Length(mEntry.Targets)]);
  end;
end;

procedure TLspCodeLensTests.FindsMessageHandlersAndInheritedOnes;
var
  mTree: TSyntaxTree;
  mOverview: TMessageOverview;
begin
  mTree := TPascalParser.Parse(cUnitHaupt);
  try
    mOverview := TMessageHandlers.Overview(FResolver, mTree, cHauptFile, 'TFoo',
      function(const AName: string; out AText: string): Boolean
      begin
        Result := ReadFile(AName, AText);
      end);
    Assert.AreEqual(2, Integer(Length(mOverview.Own)));
    Assert.AreEqual('WM_PAINT', mOverview.Own[0].Message);
    Assert.AreEqual('WMSize', mOverview.Own[1].MethodName);
    Assert.AreEqual(6, mOverview.Own[1].SelectionRange.StartPos.Line);
    Assert.AreEqual('TBasis', mOverview.Inherited_[0].TypeName);
    Assert.AreEqual('', mOverview.Inherited_[1].TypeName);
    Assert.AreEqual('behandelt WM_PAINT, WM_SIZE (WM_PAINT auch in TBasis)', mOverview.Title);
    Assert.AreEqual(0, Integer(Length(TMessageHandlers.InTree(mTree, cHauptFile, 'TKind'))));
  finally
    mTree.Free;
  end;
end;

procedure TLspCodeLensTests.LensesForTypesAndMethods;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cUnitHaupt);
  try
    // Art: 0 Referenzen (offen), 1 überschreibt, 2 Nachfahren, 3 Nachrichten. Rümpfe ohne Linse.
    Assert.AreEqual(
      '4 0  0|4 2 1 Nachfahre 1|4 3 behandelt WM_PAINT, WM_SIZE (WM_PAINT auch in TBasis) 2|' +
      '5 0  0|5 1 überschreibt TBasis.WMPaint 1|6 0  0|7 0  0|7 1 überschreibt TBasis.Zeichne 1|9 0  0|',
      Describe(TLspCodeLens.Lenses(SourceOf(mTree))));
  finally
    mTree.Free;
  end;
end;

procedure TLspCodeLensTests.ResolvesReferenceCountWithoutHeaders;
var
  mTree: TSyntaxTree;
  mEntries: TArray<TCodeLensEntry>;
  mResolved: TCodeLensEntry;
begin
  mTree := TPascalParser.Parse(cUnitHaupt);
  try
    mEntries := TLspCodeLens.Lenses(SourceOf(mTree));
    // Zeichne in TFoo (Zeile 7): zwei Aufrufe, der Kopf "procedure TFoo.Zeichne" zählt nicht.
    mResolved := TLspCodeLens.ResolveReferences(SourceOf(mTree), mEntries[6], [cHauptFile, cBasisFile]);
    Assert.AreEqual('2 Referenzen', mResolved.Title);
    Assert.AreEqual(14, mResolved.Targets[0].Range.StartPos.Line);
  finally
    mTree.Free;
  end;
end;

procedure TLspCodeLensTests.WritesCommandOrData;
var
  mEntry: TCodeLensEntry;
  mJson: TJSONObject;
begin
  mEntry := Default(TCodeLensEntry);
  mEntry.Range := TTextRange.Create(TTextPosition.Create(1, 2), TTextPosition.Create(1, 5));
  mJson := TLspCodeLens.ToJson(mEntry, cHauptFile);
  try
    Assert.IsNotNull(mJson.GetValue('data'));
    Assert.IsNull(mJson.GetValue('command'));
  finally
    mJson.Free;
  end;
  mEntry.Title := '1 Referenz';
  mJson := TLspCodeLens.ToJson(mEntry, cHauptFile);
  try
    Assert.AreEqual('1 Referenz', mJson.GetValue<string>('command.title'));
    Assert.AreEqual(TLspCodeLens.cShowLocationsCommand, mJson.GetValue<string>('command.command'));
    Assert.AreEqual(3, TJSONArray(mJson.GetValue<TJSONValue>('command.arguments')).Count);
  finally
    mJson.Free;
  end;
end;

procedure TLspCodeLensTests.MetricLensesOverImplementedMethods;
var
  mTree: TSyntaxTree;
  mEntries: TArray<TCodeLensEntry>;
  mLimits: TMetricLimits;
begin
  mTree := TPascalParser.Parse(cUnitHaupt);
  try
    mEntries := TLspCodeLens.MetricLenses(mTree, TMetricLimits.Default);
    // Aufbau (#939) zuerst: Unit-Name, uses, je Klasse; dann nur die Rümpfe, keine Deklarationen.
    Assert.AreEqual(7, Integer(Length(mEntries)));
    Assert.AreEqual<TCodeLensKind>(TCodeLensKind.Metrics, mEntries[0].Kind);
    Assert.AreEqual('24 Zeilen', mEntries[0].Title);
    Assert.AreEqual(0, mEntries[0].Range.StartPos.Line);
    Assert.AreEqual('1 Units im uses', mEntries[1].Title);
    Assert.AreEqual(2, mEntries[1].Range.StartPos.Line);
    Assert.AreEqual('3 Member', mEntries[2].Title);
    Assert.AreEqual(4, mEntries[2].Range.StartPos.Line);
    Assert.AreEqual(2, mEntries[2].Range.StartPos.Character);
    Assert.AreEqual('0 Member', mEntries[3].Title);
    Assert.AreEqual(12, mEntries[4].Range.StartPos.Line);
    Assert.AreEqual(10, mEntries[4].Range.StartPos.Character);
    Assert.AreEqual('4 Zeilen · Tiefe 0 · zyklomatisch 1 · kognitiv 0 · 1 Parameter · Operanden 0 · 0 lokale · ' +
      '0 Ausstiege', mEntries[4].Title);
    Assert.AreEqual(20, mEntries[6].Range.StartPos.Line);
    mLimits := TMetricLimits.Default;
    mLimits.Values[TMetricKind.MethodLength] := 3;
    mLimits.Structure[TStructureKind.ClassSize] := 2;
    mEntries := TLspCodeLens.MetricLenses(mTree, mLimits);
    Assert.AreEqual('3 Member (> 2)', mEntries[2].Title);
    Assert.AreEqual('4 Zeilen (> 3) · Tiefe 0 · zyklomatisch 1 · kognitiv 0 · 1 Parameter · Operanden 0 · ' +
      '0 lokale · 0 Ausstiege', mEntries[4].Title);
    // Mit Index die Vererbungstiefe (#980): TFoo erbt von TBasis aus der Unit Basis, TKind von TFoo.
    mEntries := TLspCodeLens.MetricLenses(mTree, TMetricLimits.Default, FIndex, 'C:\P\Haupt.pas');
    Assert.AreEqual(9, Integer(Length(mEntries)));
    Assert.AreEqual('Vererbungstiefe 1', mEntries[7].Title);
    Assert.AreEqual(4, mEntries[7].Range.StartPos.Line);
    Assert.AreEqual('Vererbungstiefe 2', mEntries[8].Title);
    Assert.AreEqual(9, mEntries[8].Range.StartPos.Line);
    // Ohne Basis im Index bricht die Kette ab: Untergrenze, TFoo ohne bekannte eigene Vorfahren fehlt.
    mEntries := TLspCodeLens.MetricLenses(mTree, TMetricLimits.Default, nil, 'C:\P\Haupt.pas');
    Assert.AreEqual(8, Integer(Length(mEntries)));
    Assert.AreEqual('Vererbungstiefe mindestens 1', mEntries[7].Title);
  finally
    mTree.Free;
  end;
end;

procedure TLspCodeLensTests.MetricLensIsPlainText;
var
  mEntry: TCodeLensEntry;
  mJson: TJSONObject;
  mTitle, mCommand: string;
begin
  mEntry := Default(TCodeLensEntry);
  mEntry.Kind := TCodeLensKind.Metrics;
  mEntry.Range := TTextRange.Create(TTextPosition.Create(12, 10), TTextPosition.Create(12, 22));
  mEntry.Title := '4 Zeilen';
  mJson := TLspCodeLens.ToJson(mEntry, cHauptFile);
  try
    mTitle := mJson.GetValue<string>('command.title');
    mCommand := mJson.GetValue<string>('command.command');
    Assert.AreEqual('4 Zeilen', mTitle);
    Assert.AreEqual('', mCommand, 'ohne Klickziel');
    Assert.IsNull(mJson.GetValue('data'));
  finally
    mJson.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspCodeLensTests);

end.
