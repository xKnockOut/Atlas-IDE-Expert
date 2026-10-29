unit Atlas.Common.Lsp.InlineValues.Tests;

// Werte beim Debuggen am Zeilenende (#508): nur die Routine mit dem Halt bis
// zu seiner Zeile, lokale Variablen, Parameter, Schleifenvariablen und Felder
// von Self; keine Aufrufe, Eigenschaften, Konstanten, Globalen, Mitglieder
// anderer Ausdrücke und Felder in with; JSON-Antwort des Handlers.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract;

type
  [TestFixture]
  TLspInlineValuesTests = class
  private
    FIndex: ISymbolIndex;
    /// <summary>Gefundene Werte als „Zeile:Name“ mit Leerzeichen getrennt.</summary>
    function ValuesFor(AFirstLine, ALastLine, AStoppedLine: Integer): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure LocalsParametersAndLoopVariable;
    [Test]
    procedure FieldsOfSelfButNotInWith;
    [Test]
    procedure NoCallsPropertiesConstantsOrGlobals;
    [Test]
    procedure OnlyUpToStoppedLineAndInRange;
    [Test]
    procedure KnowsDeclaredTypes;
    [Test]
    procedure NothingOutsideRoutine;
    [Test]
    procedure HandlerWritesInlineValues;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Lsp.InlineValues;

const
  UnitText =
    'unit Werte;'#10 +                                   // 0
    'interface'#10 +                                     // 1
    'type'#10 +                                          // 2
    '  TListe = class'#10 +                              // 3
    '    FCount: Integer;'#10 +                          // 4
    '    FName: string;'#10 +                            // 5
    '    function GetSize: Integer;'#10 +                // 6
    '    property Size: Integer read GetSize;'#10 +      // 7
    '    procedure Lauf(Anzahl: Integer);'#10 +          // 8
    '  end;'#10 +                                        // 9
    'implementation'#10 +                                // 10
    'var Global: Integer;'#10 +                          // 11
    'function TListe.GetSize: Integer;'#10 +             // 12
    'begin'#10 +                                         // 13
    '  Result := FCount;'#10 +                           // 14
    'end;'#10 +                                          // 15
    'procedure TListe.Lauf(Anzahl: Integer);'#10 +       // 16
    'const'#10 +                                         // 17
    '  Rand = 2;'#10 +                                   // 18
    'var'#10 +                                           // 19
    '  Summe: Integer;'#10 +                             // 20
    '  Andere: TListe;'#10 +                             // 21
    'begin'#10 +                                         // 22
    '  Summe := Anzahl + Rand + Global;'#10 +            // 23
    '  for var I := 0 to Anzahl do'#10 +                 // 24
    '    Summe := Summe + I + GetSize + Size;'#10 +      // 25
    '  FCount := Summe; FName := IntToStr(Summe);'#10 +  // 26
    '  Andere := Self;'#10 +                             // 27
    '  Andere.FCount := 1;'#10 +                         // 28
    '  with Andere do'#10 +                              // 29
    '    FCount := Summe;'#10 +                          // 30
    '  Summe := 0;'#10 +                                 // 31
    'end;'#10 +                                          // 32
    'end.';

  FileName = 'C:\P\Werte.pas';

{ TLspInlineValuesTests }

procedure TLspInlineValuesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
end;

procedure TLspInlineValuesTests.TearDown;
begin
  FIndex := nil;
end;

function TLspInlineValuesTests.ValuesFor(AFirstLine, ALastLine, AStoppedLine: Integer): string;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Value: TInlineValue;
begin
  Result := '';
  Tree := TPascalParser.Parse(UnitText);
  Resolver := TNameResolver.Create(FIndex);
  try
    for Value in TLspInlineValues.Collect(Resolver, Tree, FileName, TTextRange.Create(AFirstLine, 0, ALastLine, 0),
      AStoppedLine) do
    begin
      if Result <> '' then
        Result := Result + ' ';
      Result := Result + Format('%d:%s', [Value.Range.StartPos.Line, Value.Name]);
    end;
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

procedure TLspInlineValuesTests.LocalsParametersAndLoopVariable;
var
  Values: string;
begin
  Values := ValuesFor(0, 40, 25);
  Assert.IsTrue(Values.StartsWith('16:Anzahl 20:Summe 21:Andere 23:Summe 23:Anzahl 24:I 24:Anzahl 25:Summe 25:I'),
    Values);
end;

procedure TLspInlineValuesTests.FieldsOfSelfButNotInWith;
var
  Values: string;
begin
  Values := ValuesFor(0, 40, 31);
  Assert.IsTrue(Values.Contains('26:FCount 26:Summe 26:FName'), Values);
  Assert.IsTrue(Values.Contains('27:Andere'), Values);
  Assert.IsTrue(Values.Contains('28:Andere 29:Andere 30:Summe 31:Summe'), 'Andere.FCount und with: ' + Values);
  Assert.IsFalse(Values.Contains('28:FCount'), 'Mitglied eines anderen Objekts');
  Assert.IsFalse(Values.Contains('30:FCount'), 'Feld in with gehört vielleicht Andere');
end;

procedure TLspInlineValuesTests.NoCallsPropertiesConstantsOrGlobals;
var
  Values: string;
begin
  Values := ValuesFor(0, 40, 31);
  Assert.IsFalse(Values.Contains('Rand'), 'Konstante: ' + Values);
  Assert.IsFalse(Values.Contains('Global'), 'globale Variable');
  Assert.IsFalse(Values.Contains('GetSize'), 'Aufruf');
  Assert.IsFalse(Values.Contains('Size'), 'Eigenschaft mit Getter');
  Assert.IsFalse(Values.Contains('IntToStr'), 'Routine');
  Assert.IsFalse(Values.Contains('TListe'), 'Typ');
end;

procedure TLspInlineValuesTests.OnlyUpToStoppedLineAndInRange;
var
  Values: string;
begin
  Values := ValuesFor(23, 40, 24);
  Assert.AreEqual('23:Summe 23:Anzahl 24:I 24:Anzahl', Values);
  Values := ValuesFor(0, 40, 14);
  Assert.AreEqual('14:Result 14:FCount', Values, 'andere Routine (GetSize)');
end;

procedure TLspInlineValuesTests.KnowsDeclaredTypes;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Value: TInlineValue;
  Types: string;
begin
  Types := '';
  Tree := TPascalParser.Parse(UnitText);
  Resolver := TNameResolver.Create(FIndex);
  try
    for Value in TLspInlineValues.Collect(Resolver, Tree, FileName, TTextRange.Create(26, 0, 27, 0), 31) do
      Types := Types + Value.Name + ':' + Value.TypeName + ' ';
  finally
    Resolver.Free;
    Tree.Free;
  end;
  Assert.AreEqual('FCount:Integer Summe:Integer FName:string Andere:TListe ', Types);
end;

procedure TLspInlineValuesTests.NothingOutsideRoutine;
begin
  Assert.AreEqual('', ValuesFor(0, 40, 4));
  Assert.AreEqual('', ValuesFor(0, 40, 11));
end;

procedure TLspInlineValuesTests.HandlerWritesInlineValues;
var
  Store: IDocumentStore;
  Values: TLspInlineValues;
  Dispatcher: TJsonRpcDispatcher;
  Request, Response: TJSONObject;
  Uri, Text: string;
begin
  Store := TDocumentStore.Create;
  Uri := TDocumentUris.FromPath(FileName);
  Store.Open(Uri, 'delphi', 1, UnitText);
  Values := TLspInlineValues.Create(Store, FIndex, nil);
  Dispatcher := TJsonRpcDispatcher.Create;
  try
    Values.Attach(Dispatcher);
    Request := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":1,"method":"' + TLspInlineValues.Method +
      '","params":{"textDocument":{"uri":"' + Uri.Replace('\', '\\') + '"},' +
      '"range":{"start":{"line":23,"character":0},"end":{"line":24,"character":0}},' +
      '"context":{"frameId":1,"stoppedLocation":{"start":{"line":23,"character":2},' +
      '"end":{"line":23,"character":2}}}}}') as TJSONObject;
    try
      Response := Dispatcher.DispatchMessage(Request);
    finally
      Request.Free;
    end;
    try
      Text := Response.GetValue('result').ToJSON;
    finally
      Response.Free;
    end;
  finally
    Dispatcher.Free;
    Values.Free;
  end;
  Assert.AreEqual('[{"range":{"start":{"line":23,"character":2},"end":{"line":23,"character":7}},' +
    '"variableName":"Summe","caseSensitiveLookup":false,"atlasType":"Integer"},{"range":{"start":{"line":23,' +
    '"character":11},"end":{"line":23,"character":17}},"variableName":"Anzahl","caseSensitiveLookup":false,' +
    '"atlasType":"Integer"}]', Text);
end;

end.
