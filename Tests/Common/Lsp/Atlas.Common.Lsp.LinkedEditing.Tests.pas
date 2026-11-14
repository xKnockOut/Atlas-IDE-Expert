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
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
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
  cUnitText =
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

  cLocalText =
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

  cLocalFile = 'C:\P\Lokal.pas';

{ TLspLinkedEditingTests }

procedure TLspLinkedEditingTests.WarmUpFirstUse;
begin
  Setup;
  try
    HandlerKeepsMethodsOnlyWithoutLocalsFlag;
  finally
    TearDown;
  end;
end;

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
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mRange: TTextRange;
begin
  Result := '';
  mTree := TPascalParser.Parse(cLocalText);
  mResolver := TNameResolver.Create(FIndex);
  try
    for mRange in TLspLinkedEditing.LocalRanges(mResolver, FIndex, mTree, cLocalFile,
      TTextPosition.Create(ALine, ACharacter), FConflicts) do
    begin
      if Result <> '' then
      begin
        Result := Result + ' ';
      end;
      Result := Result + Format('%d:%d', [mRange.StartPos.Line, mRange.StartPos.Character]);
    end;
  finally
    mResolver.Free;
    mTree.Free;
  end;
end;

function TLspLinkedEditingTests.Answer(ALine, ACharacter: Integer; ALocalsOnly: Boolean): string;
var
  mStore: IDocumentStore;
  mLinked: TLspLinkedEditing;
  mDispatcher: TJsonRpcDispatcher;
  mRequest, mResponse: TJSONObject;
  mUri, mFlag: string;
begin
  mStore := TDocumentStore.Create;
  mUri := TDocumentUris.FromPath(cLocalFile);
  mStore.Open(mUri, 'delphi', 1, cLocalText);
  mLinked := TLspLinkedEditing.Create(mStore, FIndex, nil);
  mDispatcher := TJsonRpcDispatcher.Create;
  try
    mLinked.Attach(mDispatcher);
    mFlag := '';
    if ALocalsOnly then
    begin
      mFlag := ',"atlasLocals":true';
    end;
    mRequest := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":1,"method":"' + TLspLinkedEditing.cMethod +
      '","params":{"textDocument":{"uri":"' + mUri.Replace('\', '\\') + '"},"position":{"line":' +
      IntToStr(ALine) + ',"character":' + IntToStr(ACharacter) + '}' + mFlag + '}}') as TJSONObject;
    try
      mResponse := mDispatcher.DispatchMessage(mRequest);
    finally
      mRequest.Free;
    end;
    try
      Result := mResponse.GetValue('result').ToJSON;
    finally
      mResponse.Free;
    end;
  finally
    mDispatcher.Free;
    mLinked.Free;
  end;
end;

function TLspLinkedEditingTests.RangesAt(ALine, ACharacter: Integer): TArray<TTextRange>;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cUnitText);
  try
    Result := TLspLinkedEditing.Ranges(mTree, 'C:\P\Muster.pas', TTextPosition.Create(ALine, ACharacter));
  finally
    mTree.Free;
  end;
end;

procedure TLspLinkedEditingTests.LinksMethodDeclarationAndImplementation;
var
  mRanges: TArray<TTextRange>;
begin
  mRanges := RangesAt(4, 16);
  Assert.AreEqual(2, Integer(Length(mRanges)));
  Assert.AreEqual(4, mRanges[0].StartPos.Line);
  Assert.AreEqual(14, mRanges[0].StartPos.Character);
  Assert.AreEqual(18, mRanges[0].EndPos.Character);
  Assert.AreEqual(10, mRanges[1].StartPos.Line);
  Assert.AreEqual(15, mRanges[1].StartPos.Character);
end;

procedure TLspLinkedEditingTests.LinksFromImplementation;
begin
  Assert.AreEqual(2, Integer(Length(RangesAt(10, 17))));
end;

procedure TLspLinkedEditingTests.LinksForwardRoutines;
var
  mRanges: TArray<TTextRange>;
begin
  mRanges := RangesAt(19, 10);
  Assert.AreEqual(2, Integer(Length(mRanges)));
  Assert.AreEqual(8, mRanges[0].StartPos.Line);
  Assert.AreEqual(19, mRanges[1].StartPos.Line);
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
  mJson: TJSONValue;
begin
  mJson := TLspLinkedEditing.ToJson(RangesAt(4, 16));
  try
    Assert.AreEqual(2, (mJson as TJSONObject).GetValue<TJSONArray>('ranges').Count);
    Assert.AreEqual(TLspLinkedEditing.cWordPattern, (mJson as TJSONObject).GetValue<string>('wordPattern'));
  finally
    mJson.Free;
  end;
  mJson := TLspLinkedEditing.ToJson(nil);
  try
    Assert.IsTrue(mJson is TJSONNull);
  finally
    mJson.Free;
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
  mConflict: TLinkedConflict;
  mNames: string;
  mRowCount: string;
begin
  LocalsAt(16, 3);
  mNames := '';
  mRowCount := '';
  for mConflict in FConflicts do
  begin
    mNames := mNames + '|' + mConflict.Name;
    if mConflict.Name = 'RowCount' then
    begin
      mRowCount := mConflict.Detail;
    end;
  end;
  mNames := mNames + '|';
  Assert.IsTrue(Pos('|Anzahl|', mNames) > 0, mNames);
  Assert.IsTrue(Pos('|Rand|', mNames) > 0, mNames);
  Assert.IsTrue(Pos('|Grid|', mNames) > 0, mNames);
  Assert.IsTrue(Pos('|Global|', mNames) > 0, mNames);
  Assert.IsTrue(Pos('|RowCount|', mNames) > 0, mNames);
  Assert.IsFalse(Pos('|Zeilen|', mNames) > 0, mNames);
  Assert.AreEqual('Feld TGrid.RowCount', mRowCount);
end;

procedure TLspLinkedEditingTests.WritesConflictsAsJson;
var
  mConflict: TLinkedConflict;
  mJson: TJSONValue;
  mItems: TJSONArray;
begin
  mConflict.Name := 'Rand';
  mConflict.Detail := 'lokale Variable Rand';
  mJson := TLspLinkedEditing.ToJson([TTextRange.Create(TTextPosition.Create(1, 2), TTextPosition.Create(1, 4))],
    [mConflict]);
  try
    mItems := (mJson as TJSONObject).GetValue<TJSONArray>('atlasConflicts');
    Assert.AreEqual(1, Integer(mItems.Count));
    Assert.AreEqual('Rand', (mItems.Items[0] as TJSONObject).GetValue<string>('name'));
    Assert.AreEqual('lokale Variable Rand', (mItems.Items[0] as TJSONObject).GetValue<string>('detail'));
  finally
    mJson.Free;
  end;
  mJson := TLspLinkedEditing.ToJson(nil, [mConflict]);
  try
    Assert.IsTrue(mJson is TJSONNull);
  finally
    mJson.Free;
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
