unit Argus.Common.Lsp.CodeLens.Tests;

interface

uses
  DUnitX.TestFramework,
  Argus.Common.Index.Contract,
  Argus.Common.Semantics.NameResolver,
  Argus.Common.Lsp.CodeLens;

type
  [TestFixture]
  TLspCodeLensTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function Describe(const AEntries: TArray<TCodeLensEntry>): string;
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
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Argus.Common.Documents.Contract,
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Pascal.Parser,
  Argus.Common.Index.SymbolIndex,
  Argus.Common.Index.Extractor,
  Argus.Common.Lsp.MessageHandlers;

const
  HauptFile = 'C:\P\Haupt.pas';
  BasisFile = 'C:\P\Basis.pas';

  UnitBasis =
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

  UnitHaupt =
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
  if SameText(AFileName, HauptFile) then
    AText := UnitHaupt
  else if SameText(AFileName, BasisFile) then
    AText := UnitBasis
  else
    Result := False;
end;

{ TLspCodeLensTests }

procedure TLspCodeLensTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitBasis, BasisFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitHaupt, HauptFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspCodeLensTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TLspCodeLensTests.Describe(const AEntries: TArray<TCodeLensEntry>): string;
var
  Entry: TCodeLensEntry;
begin
  Result := '';
  for Entry in AEntries do
    Result := Result + Format('%d %d %s %d|', [Entry.Range.StartPos.Line, Ord(Entry.Kind), Entry.Title,
      Length(Entry.Targets)]);
end;

procedure TLspCodeLensTests.FindsMessageHandlersAndInheritedOnes;
var
  Tree: TSyntaxTree;
  Overview: TMessageOverview;
begin
  Tree := TPascalParser.Parse(UnitHaupt);
  try
    Overview := TMessageHandlers.Overview(FResolver, FIndex, Tree, HauptFile, 'TFoo',
      function(const AName: string; out AText: string): Boolean
      begin
        Result := ReadFile(AName, AText);
      end);
    Assert.AreEqual(2, Integer(Length(Overview.Own)));
    Assert.AreEqual('WM_PAINT', Overview.Own[0].Message);
    Assert.AreEqual('WMSize', Overview.Own[1].MethodName);
    Assert.AreEqual(6, Overview.Own[1].SelectionRange.StartPos.Line);
    Assert.AreEqual('TBasis', Overview.Inherited_[0].TypeName);
    Assert.AreEqual('', Overview.Inherited_[1].TypeName);
    Assert.AreEqual('behandelt WM_PAINT, WM_SIZE (WM_PAINT auch in TBasis)', Overview.Title);
    Assert.AreEqual(0, Integer(Length(TMessageHandlers.InTree(Tree, HauptFile, 'TKind'))));
  finally
    Tree.Free;
  end;
end;

procedure TLspCodeLensTests.LensesForTypesAndMethods;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(UnitHaupt);
  try
    // Art: 0 Referenzen (offen), 1 überschreibt, 2 Nachfahren, 3 Nachrichten. Rümpfe ohne Linse.
    Assert.AreEqual(
      '4 0  0|4 2 1 Nachfahre 1|4 3 behandelt WM_PAINT, WM_SIZE (WM_PAINT auch in TBasis) 2|' +
      '5 0  0|5 1 überschreibt TBasis.WMPaint 1|6 0  0|7 0  0|7 1 überschreibt TBasis.Zeichne 1|9 0  0|',
      Describe(TLspCodeLens.Lenses(FResolver, FIndex, Tree, HauptFile, ReadFile)));
  finally
    Tree.Free;
  end;
end;

procedure TLspCodeLensTests.ResolvesReferenceCountWithoutHeaders;
var
  Tree: TSyntaxTree;
  Entries: TArray<TCodeLensEntry>;
  Resolved: TCodeLensEntry;
begin
  Tree := TPascalParser.Parse(UnitHaupt);
  try
    Entries := TLspCodeLens.Lenses(FResolver, FIndex, Tree, HauptFile, ReadFile);
    // Zeichne in TFoo (Zeile 7): zwei Aufrufe, der Kopf "procedure TFoo.Zeichne" zählt nicht.
    Resolved := TLspCodeLens.ResolveReferences(FResolver, FIndex, Tree, HauptFile, Entries[6],
      [HauptFile, BasisFile], ReadFile);
    Assert.AreEqual('2 Referenzen', Resolved.Title);
    Assert.AreEqual(14, Resolved.Targets[0].Range.StartPos.Line);
  finally
    Tree.Free;
  end;
end;

procedure TLspCodeLensTests.WritesCommandOrData;
var
  Entry: TCodeLensEntry;
  Json: TJSONObject;
begin
  Entry := Default(TCodeLensEntry);
  Entry.Range := TTextRange.Create(TTextPosition.Create(1, 2), TTextPosition.Create(1, 5));
  Json := TLspCodeLens.ToJson(Entry, HauptFile);
  try
    Assert.IsNotNull(Json.GetValue('data'));
    Assert.IsNull(Json.GetValue('command'));
  finally
    Json.Free;
  end;
  Entry.Title := '1 Referenz';
  Json := TLspCodeLens.ToJson(Entry, HauptFile);
  try
    Assert.AreEqual('1 Referenz', Json.GetValue<string>('command.title'));
    Assert.AreEqual(TLspCodeLens.ShowLocationsCommand, Json.GetValue<string>('command.command'));
    Assert.AreEqual(3, TJSONArray(Json.GetValue<TJSONValue>('command.arguments')).Count);
  finally
    Json.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspCodeLensTests);

end.
