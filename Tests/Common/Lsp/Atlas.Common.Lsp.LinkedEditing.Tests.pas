unit Atlas.Common.Lsp.LinkedEditing.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Lsp.LinkedEditing;

type
  [TestFixture]
  TLspLinkedEditingTests = class
  private
    FIndex: ISymbolIndex;
    FConflicts: TArray<TLinkedConflict>;
    function RangesAt(ALine, ACharacter: Integer): TArray<TTextRange>;
    /// <summary>Lokale Vorkommen an der Position als "Zeile:Spalte" mit Leerzeichen getrennt (#658).</summary>
    function LocalsAt(ALine, ACharacter: Integer): string;
    /// <summary>Antwort des Handlers als JSON-Text.</summary>
    function Answer(ALine, ACharacter: Integer; ALocalsOnly: Boolean): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure LinksMethodDeclarationAndImplementation;
    [Test]
    procedure LinksFromImplementation;
    [Test]
    procedure LinksForwardRoutines;
    [Test]
    procedure NothingForOverloads;
    [Test]
    procedure NothingForOtherNames;
    [Test]
    procedure WritesJson;
    [Test]
    procedure LinksLocalVariableInRoutine;
    [Test]
    procedure LinksParameterAndConstant;
    [Test]
    procedure LinksInlineAndLoopVariables;
    [Test]
    procedure NothingForFieldsMethodsAndGlobals;
    [Test]
    procedure ReportsVisibleNamesAsConflicts;
    [Test]
    procedure WritesConflictsAsJson;
    [Test]
    procedure HandlerKeepsMethodsOnlyWithoutLocalsFlag;
  end;

implementation

uses
  System.Generics.Collections,
  System.SysUtils,
  System.JSON,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.JsonRpc.Dispatcher;

const
  UnitText =
    'unit Muster;'#10 +                            // 0
    'interface'#10 +                               // 1
    'type'#10 +                                    // 2
    '  TFoo = class'#10 +                          // 3
    '    procedure Lauf;'#10 +                     // 4
    '    procedure Mehr(A: Integer); overload;'#10 + // 5
    '    procedure Mehr(A: string); overload;'#10 + // 6
    '  end;'#10 +                                  // 7
    'function Hilfe: Integer;'#10 +                // 8
    'implementation'#10 +                          // 9
    'procedure TFoo.Lauf;'#10 +                    // 10
    'begin'#10 +                                   // 11
    'end;'#10 +                                    // 12
    'procedure TFoo.Mehr(A: Integer);'#10 +        // 13
    'begin'#10 +                                   // 14
    'end;'#10 +                                    // 15
    'procedure TFoo.Mehr(A: string);'#10 +         // 16
    'begin'#10 +                                   // 17
    'end;'#10 +                                    // 18
    'function Hilfe: Integer;'#10 +                // 19
    'begin'#10 +                                   // 20
    '  Result := 0;'#10 +                          // 21
    'end;'#10 +                                    // 22
    'end.';

  LocalText =
    'unit Lokal;'#10 +                             // 0
    'interface'#10 +                               // 1
    'type'#10 +                                    // 2
    '  TGrid = class'#10 +                         // 3
    '    RowCount, Zeilen: Integer;'#10 +          // 4
    '    procedure Zeichne(Anzahl: Integer);'#10 + // 5
    '  end;'#10 +                                  // 6
    'implementation'#10 +                          // 7
    'var Global: Integer;'#10 +                    // 8
    'procedure TGrid.Zeichne(Anzahl: Integer);'#10 + // 9
    'const'#10 +                                   // 10
    '  Rand = 2;'#10 +                             // 11
    'var'#10 +                                     // 12
    '  Zeilen: Integer;'#10 +                      // 13
    '  Grid: TGrid;'#10 +                          // 14
    'begin'#10 +                                   // 15
    '  Zeilen := Anzahl + Rand; { Zeilen }'#10 +   // 16
    '  Grid := Self;'#10 +                         // 17
    '  Grid.Zeilen := Zeilen;'#10 +                // 18
    '  Writeln(''Zeilen'', Zeilen);'#10 +          // 19
    '  for var I := 0 to Zeilen do'#10 +           // 20
    '  begin'#10 +                                 // 21
    '    var Doppelt := I + I;'#10 +               // 22
    '    Writeln(Doppelt);'#10 +                   // 23
    '  end;'#10 +                                  // 24
    'end;'#10 +                                    // 25
    'procedure Andere;'#10 +                       // 26
    'var'#10 +                                     // 27
    '  Zeilen: Integer;'#10 +                      // 28
    'begin'#10 +                                   // 29
    '  Zeilen := Global;'#10 +                     // 30
    'end;'#10 +                                    // 31
    'end.';

  LocalFile = 'C:\P\Lokal.pas';

{ TLspLinkedEditingTests }

procedure TLspLinkedEditingTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
end;

procedure TLspLinkedEditingTests.TearDown;
begin
  FIndex := nil;
  FConflicts := nil;
end;

function TLspLinkedEditingTests.LocalsAt(ALine, ACharacter: Integer): string;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Range: TTextRange;
begin
  Result := '';
  Tree := TPascalParser.Parse(LocalText);
  Resolver := TNameResolver.Create(FIndex);
  try
    for Range in TLspLinkedEditing.LocalRanges(Resolver, FIndex, Tree, LocalFile,
      TTextPosition.Create(ALine, ACharacter), FConflicts) do
    begin
      if Result <> '' then
        Result := Result + ' ';
      Result := Result + Format('%d:%d', [Range.StartPos.Line, Range.StartPos.Character]);
    end;
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

function TLspLinkedEditingTests.Answer(ALine, ACharacter: Integer; ALocalsOnly: Boolean): string;
var
  Store: IDocumentStore;
  Linked: TLspLinkedEditing;
  Dispatcher: TJsonRpcDispatcher;
  Request, Response: TJSONObject;
  Uri, Flag: string;
begin
  Store := TDocumentStore.Create;
  Uri := TDocumentUris.FromPath(LocalFile);
  Store.Open(Uri, 'delphi', 1, LocalText);
  Linked := TLspLinkedEditing.Create(Store, FIndex, nil);
  Dispatcher := TJsonRpcDispatcher.Create;
  try
    Linked.Attach(Dispatcher);
    Flag := '';
    if ALocalsOnly then
      Flag := ',"atlasLocals":true';
    Request := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":1,"method":"' + TLspLinkedEditing.Method +
      '","params":{"textDocument":{"uri":"' + Uri.Replace('\', '\\') + '"},"position":{"line":' +
      IntToStr(ALine) + ',"character":' + IntToStr(ACharacter) + '}' + Flag + '}}') as TJSONObject;
    try
      Response := Dispatcher.DispatchMessage(Request);
    finally
      Request.Free;
    end;
    try
      Result := Response.GetValue('result').ToJSON;
    finally
      Response.Free;
    end;
  finally
    Dispatcher.Free;
    Linked.Free;
  end;
end;

function TLspLinkedEditingTests.RangesAt(ALine, ACharacter: Integer): TArray<TTextRange>;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(UnitText);
  try
    Result := TLspLinkedEditing.Ranges(Tree, 'C:\P\Muster.pas', TTextPosition.Create(ALine, ACharacter));
  finally
    Tree.Free;
  end;
end;

procedure TLspLinkedEditingTests.LinksMethodDeclarationAndImplementation;
var
  Ranges: TArray<TTextRange>;
begin
  Ranges := RangesAt(4, 16);
  Assert.AreEqual(2, Integer(Length(Ranges)));
  Assert.AreEqual(4, Ranges[0].StartPos.Line);
  Assert.AreEqual(14, Ranges[0].StartPos.Character);
  Assert.AreEqual(18, Ranges[0].EndPos.Character);
  Assert.AreEqual(10, Ranges[1].StartPos.Line);
  Assert.AreEqual(15, Ranges[1].StartPos.Character);
end;

procedure TLspLinkedEditingTests.LinksFromImplementation;
begin
  Assert.AreEqual(2, Integer(Length(RangesAt(10, 17))));
end;

procedure TLspLinkedEditingTests.LinksForwardRoutines;
var
  Ranges: TArray<TTextRange>;
begin
  Ranges := RangesAt(19, 10);
  Assert.AreEqual(2, Integer(Length(Ranges)));
  Assert.AreEqual(8, Ranges[0].StartPos.Line);
  Assert.AreEqual(19, Ranges[1].StartPos.Line);
end;

procedure TLspLinkedEditingTests.NothingForOverloads;
begin
  Assert.AreEqual(0, Integer(Length(RangesAt(5, 16))));
end;

procedure TLspLinkedEditingTests.NothingForOtherNames;
begin
  // Typname und Anweisungen.
  Assert.AreEqual(0, Integer(Length(RangesAt(3, 3))));
  Assert.AreEqual(0, Integer(Length(RangesAt(21, 3))));
end;

procedure TLspLinkedEditingTests.WritesJson;
var
  Json: TJSONValue;
begin
  Json := TLspLinkedEditing.ToJson(RangesAt(4, 16));
  try
    Assert.AreEqual(2, (Json as TJSONObject).GetValue<TJSONArray>('ranges').Count);
    Assert.AreEqual(TLspLinkedEditing.WordPattern, (Json as TJSONObject).GetValue<string>('wordPattern'));
  finally
    Json.Free;
  end;
  Json := TLspLinkedEditing.ToJson(nil);
  try
    Assert.IsTrue(Json is TJSONNull);
  finally
    Json.Free;
  end;
end;

procedure TLspLinkedEditingTests.LinksLocalVariableInRoutine;
begin
  // Deklaration und Verwendungen; nicht das Feld Grid.Zeilen, nicht String und Kommentar, nicht Andere.
  Assert.AreEqual('13:2 16:2 18:17 19:20 20:20', LocalsAt(16, 3));
  Assert.AreEqual('13:2 16:2 18:17 19:20 20:20', LocalsAt(13, 2));
  // Cursor direkt hinter dem Namen.
  Assert.AreEqual('13:2 16:2 18:17 19:20 20:20', LocalsAt(18, 23));
  Assert.AreEqual('28:2 30:2', LocalsAt(30, 4));
end;

procedure TLspLinkedEditingTests.LinksParameterAndConstant;
begin
  Assert.AreEqual('9:24 16:12', LocalsAt(16, 12));
  Assert.AreEqual('11:2 16:21', LocalsAt(16, 22));
end;

procedure TLspLinkedEditingTests.LinksInlineAndLoopVariables;
begin
  Assert.AreEqual('22:8 23:12', LocalsAt(23, 12));
  Assert.AreEqual('20:10 22:19 22:23', LocalsAt(22, 19));
end;

procedure TLspLinkedEditingTests.NothingForFieldsMethodsAndGlobals;
begin
  Assert.AreEqual('', LocalsAt(4, 4));
  Assert.AreEqual('', LocalsAt(18, 8));
  Assert.AreEqual('', LocalsAt(9, 18));
  Assert.AreEqual('', LocalsAt(30, 13));
  Assert.AreEqual('', LocalsAt(17, 10));
  Assert.AreEqual(0, Integer(Length(FConflicts)));
end;

procedure TLspLinkedEditingTests.ReportsVisibleNamesAsConflicts;
var
  Conflict: TLinkedConflict;
  Names: string;
  RowCount: string;
begin
  LocalsAt(16, 3);
  Names := '';
  RowCount := '';
  for Conflict in FConflicts do
  begin
    Names := Names + '|' + Conflict.Name;
    if Conflict.Name = 'RowCount' then
      RowCount := Conflict.Detail;
  end;
  Names := Names + '|';
  Assert.IsTrue(Pos('|Anzahl|', Names) > 0, Names);
  Assert.IsTrue(Pos('|Rand|', Names) > 0, Names);
  Assert.IsTrue(Pos('|Grid|', Names) > 0, Names);
  Assert.IsTrue(Pos('|Global|', Names) > 0, Names);
  Assert.IsTrue(Pos('|RowCount|', Names) > 0, Names);
  Assert.IsFalse(Pos('|Zeilen|', Names) > 0, Names);
  Assert.AreEqual('Feld TGrid.RowCount', RowCount);
end;

procedure TLspLinkedEditingTests.WritesConflictsAsJson;
var
  Conflict: TLinkedConflict;
  Json: TJSONValue;
  Items: TJSONArray;
begin
  Conflict.Name := 'Rand';
  Conflict.Detail := 'lokale Variable Rand';
  Json := TLspLinkedEditing.ToJson([TTextRange.Create(TTextPosition.Create(1, 2), TTextPosition.Create(1, 4))],
    [Conflict]);
  try
    Items := (Json as TJSONObject).GetValue<TJSONArray>('atlasConflicts');
    Assert.AreEqual(1, Items.Count);
    Assert.AreEqual('Rand', (Items.Items[0] as TJSONObject).GetValue<string>('name'));
    Assert.AreEqual('lokale Variable Rand', (Items.Items[0] as TJSONObject).GetValue<string>('detail'));
  finally
    Json.Free;
  end;
  Json := TLspLinkedEditing.ToJson(nil, [Conflict]);
  try
    Assert.IsTrue(Json is TJSONNull);
  finally
    Json.Free;
  end;
end;

procedure TLspLinkedEditingTests.HandlerKeepsMethodsOnlyWithoutLocalsFlag;
begin
  // Methode: ohne Kennzeichen Deklaration und Rumpf (#39), mit atlasLocals nichts (#658).
  Assert.IsTrue(Pos('"ranges"', Answer(9, 18, False)) > 0);
  Assert.AreEqual('null', Answer(9, 18, True));
  // Lokale Variable in beiden Fällen, samt Konflikten.
  Assert.IsTrue(Pos('"atlasConflicts"', Answer(16, 3, True)) > 0);
  Assert.IsTrue(Pos('"atlasConflicts"', Answer(16, 3, False)) > 0);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspLinkedEditingTests);

end.
