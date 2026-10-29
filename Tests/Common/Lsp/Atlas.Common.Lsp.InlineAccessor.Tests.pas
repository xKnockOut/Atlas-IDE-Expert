unit Atlas.Common.Lsp.InlineAccessor.Tests;

// Tests für „Triviale Zugriffsmethode durch Feld ersetzen“ über das Protokoll
// (#717): Angebot der Code-Aktionen (einzeln, Unit, Projekt, abschaltbar),
// Ersetzen an der Property, Aufrufe in einer anderen Unit (Methode bleibt mit
// Hinweis bzw. Abbruch), Interfaces aus dem Index und die Sammelaktionen.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract;

type
  [TestFixture]
  TLspInlineAccessorTests = class
  private
    FIndex: ISymbolIndex;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure OffersActions;
    [Test]
    procedure ReplacesAtProperty;
    [Test]
    procedure KeepsCalledAccessor;
    [Test]
    procedure RefusesWhenAllCalled;
    [Test]
    procedure ReplacesWholeUnit;
    [Test]
    procedure ReplacesWholeProject;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.TextChanges,
  Atlas.Common.Editing.InlineAccessor,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.InlineAccessor;

const
  IntfFile = 'C:\P\Titles.pas';
  ModelFile = 'C:\P\Model.pas';
  UseFile = 'C:\P\Use.pas';
  OtherFile = 'C:\P\Other.pas';

  UnitIntf =
    'unit Titles;'#10'interface'#10'type'#10 +
    '  ITitled = interface'#10 +
    '    function GetTitle: string;'#10 +
    '  end;'#10 +
    'implementation'#10'end.'#10;
  UnitModel =
    'unit Model;'#10 +                                                    // 0
    'interface'#10 +                                                      // 1
    'uses'#10 +                                                           // 2
    '  Titles;'#10 +                                                      // 3
    'type'#10 +                                                           // 4
    '  TFoo = class'#10 +                                                 // 5
    '  private'#10 +                                                      // 6
    '    FName: string;'#10 +                                             // 7
    '    FCount: Integer;'#10 +                                           // 8
    '  public'#10 +                                                       // 9
    '    function GetName: string;'#10 +                                  // 10
    '    procedure SetName(const Value: string);'#10 +                    // 11
    '    function GetCount: Integer;'#10 +                                // 12
    '    procedure SetCount(const Value: Integer);'#10 +                  // 13
    '    property Name: string read GetName write SetName;'#10 +          // 14
    '    property Count: Integer read GetCount write SetCount;'#10 +      // 15
    '  end;'#10 +                                                         // 16
    '  TBar = class(TInterfacedObject, ITitled)'#10 +                     // 17
    '  private'#10 +                                                      // 18
    '    FTitle: string;'#10 +                                            // 19
    '    function GetTitle: string;'#10 +                                 // 20
    '  public'#10 +                                                       // 21
    '    property Title: string read GetTitle;'#10 +                      // 22
    '  end;'#10 +                                                         // 23
    'implementation'#10#10 +
    'function TFoo.GetName: string;'#10'begin'#10'  Result := FName;'#10'end;'#10#10 +
    'procedure TFoo.SetName(const Value: string);'#10'begin'#10'  FName := Value;'#10'end;'#10#10 +
    'function TFoo.GetCount: Integer;'#10'begin'#10'  Result := FCount;'#10'end;'#10#10 +
    'procedure TFoo.SetCount(const Value: Integer);'#10'begin'#10'  FCount := Value;'#10'end;'#10#10 +
    'function TBar.GetTitle: string;'#10'begin'#10'  Result := FTitle;'#10'end;'#10#10 +
    'end.'#10;
  UnitUse =
    'unit Use;'#10'interface'#10'uses'#10'  Model;'#10'implementation'#10#10 +
    'function Total(AFoo: TFoo): Integer;'#10'begin'#10'  Result := AFoo.GetCount + 1;'#10'end;'#10#10 +
    'end.'#10;
  UnitOther =
    'unit Other;'#10'interface'#10'type'#10 +
    '  TBaz = class'#10 +
    '  private'#10 +
    '    FSize: Integer;'#10 +
    '    function GetSize: Integer;'#10 +
    '  public'#10 +
    '    property Size: Integer read GetSize;'#10 +
    '  end;'#10 +
    'implementation'#10#10 +
    'function TBaz.GetSize: Integer;'#10'begin'#10'  Result := FSize;'#10'end;'#10#10 +
    'end.'#10;

function TextOf(const AFileName: string): string;
begin
  if SameText(AFileName, IntfFile) then
    Result := UnitIntf
  else if SameText(AFileName, ModelFile) then
    Result := UnitModel
  else if SameText(AFileName, UseFile) then
    Result := UnitUse
  else if SameText(AFileName, OtherFile) then
    Result := UnitOther
  else
    Result := '';
end;

function Context(const AIndex: ISymbolIndex): TInlineAccessorContext;
begin
  Result := Default(TInlineAccessorContext);
  Result.Index := AIndex;
  Result.Options := TInlineAccessorOptions.Default;
  Result.Files := [IntfFile, ModelFile, UseFile, OtherFile];
  Result.ReadText :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := TextOf(AFileName);
      Result := AText <> '';
    end;
end;

/// <summary>Text von AFileName nach dem WorkspaceEdit in AAnswer.</summary>
function After(AAnswer: TJSONObject; const AFileName: string): string;
var
  Item, Edit: TJSONValue;
  Document, Range: TJSONObject;
  Edits: TArray<TTextEdit>;
  Uri: string;
begin
  Result := TextOf(AFileName);
  for Item in (AAnswer.GetValue('edit') as TJSONObject).GetValue('documentChanges') as TJSONArray do
  begin
    Document := TJSONObject(Item);
    Uri := (Document.GetValue('textDocument') as TJSONObject).GetValue('uri').Value;
    if not SameText(TDocumentUris.ToPath(Uri), AFileName) then
      Continue;
    Edits := nil;
    for Edit in Document.GetValue('edits') as TJSONArray do
    begin
      Range := TJSONObject(Edit).GetValue('range') as TJSONObject;
      Edits := Edits + [TTextEdit.Create(TTextRange.Create(TLspPositions.ReadPosition(Range.GetValue('start')),
        TLspPositions.ReadPosition(Range.GetValue('end'))), TJSONObject(Edit).GetValue('newText').Value)];
    end;
    Result := TTextChanges.Apply(Result, Edits);
  end;
end;

function Run(const AIndex: ISymbolIndex; ALine: Integer; const AScope: string): TJSONObject;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
begin
  Tree := TPascalParser.Parse(UnitModel);
  Resolver := TNameResolver.Create(AIndex, nil);
  try
    Result := TLspInlineAccessor.Execute(Resolver, Tree, ModelFile, UnitModel, TTextPosition.Create(ALine, 6),
      AScope, Context(AIndex));
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

function Titles(const AItems: TArray<TJSONObject>): string;
var
  Item: TJSONObject;
begin
  Result := '';
  for Item in AItems do
  begin
    Result := Result + Item.GetValue('title').Value + '|';
    Item.Free;
  end;
end;

function Warnings(AAnswer: TJSONObject): string;
var
  Item: TJSONValue;
begin
  Result := '';
  for Item in AAnswer.GetValue('warnings') as TJSONArray do
    Result := Result + Item.Value + '|';
end;

procedure TLspInlineAccessorTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitIntf, IntfFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitModel, ModelFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitUse, UseFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitOther, OtherFile, nil));
end;

procedure TLspInlineAccessorTests.TearDown;
begin
  FIndex := nil;
end;

procedure TLspInlineAccessorTests.OffersActions;
var
  Tree: TSyntaxTree;

  function Offered(AEnabled, ABulk: Boolean; ALine: Integer): string;
  begin
    Result := Titles(TLspInlineAccessor.Actions(AEnabled, ABulk, Tree, UnitModel, 'file:///C:/P/Model.pas',
      TTextPosition.Create(ALine, 6), TInlineAccessorOptions.Default, FIndex));
  end;

begin
  Tree := TPascalParser.Parse(UnitModel);
  try
    // Vier triviale in TFoo; GetTitle gehört zu ITitled (Index) und zählt nicht.
    Assert.AreEqual('Zugriffsmethoden GetName und SetName durch Feld ersetzen|' +
      'Alle trivialen Zugriffsmethoden der Unit ersetzen (4)|' +
      'Alle trivialen Zugriffsmethoden des Projekts ersetzen …|', Offered(True, True, 14));
    Assert.AreEqual('Zugriffsmethode SetName durch Feld FName ersetzen|', Offered(True, False, 11));
    Assert.AreEqual('Zugriffsmethode GetName durch Feld FName ersetzen|', Offered(True, False, 27));
    Assert.AreEqual('Alle trivialen Zugriffsmethoden der Unit ersetzen (4)|' +
      'Alle trivialen Zugriffsmethoden des Projekts ersetzen …|', Offered(True, True, 5));
    Assert.AreEqual('', Offered(True, True, 7), 'Feld');
    Assert.AreEqual('', Offered(True, True, 22), 'Interface-Methode');
    Assert.AreEqual('', Offered(False, True, 14), 'abgeschaltet');
  finally
    Tree.Free;
  end;
end;

procedure TLspInlineAccessorTests.ReplacesAtProperty;
var
  Answer: TJSONObject;
  Text: string;
begin
  Answer := Run(FIndex, 14, TLspInlineAccessor.ScopeHere);
  try
    Assert.AreEqual(2, (Answer.GetValue('accessors') as TJSONNumber).AsInt);
    Assert.AreEqual('', Warnings(Answer));
    Text := After(Answer, ModelFile);
    Assert.IsTrue(ContainsStr(Text, '    property Name: string read FName write FName;'), Text);
    Assert.IsFalse(ContainsStr(Text, 'GetName'), Text);
    Assert.IsFalse(ContainsStr(Text, 'SetName'), Text);
    Assert.IsTrue(ContainsStr(Text, 'function TFoo.GetCount'), Text);
  finally
    Answer.Free;
  end;
end;

procedure TLspInlineAccessorTests.KeepsCalledAccessor;
var
  Answer: TJSONObject;
  Text: string;
begin
  Answer := Run(FIndex, 15, TLspInlineAccessor.ScopeHere);
  try
    Assert.AreEqual(1, (Answer.GetValue('accessors') as TJSONNumber).AsInt);
    Assert.AreEqual('TFoo.GetCount bleibt: Es wird noch aufgerufen (Use.pas:9).|', Warnings(Answer));
    Text := After(Answer, ModelFile);
    Assert.IsTrue(ContainsStr(Text, '    property Count: Integer read GetCount write FCount;'), Text);
    Assert.IsFalse(ContainsStr(Text, 'SetCount'), Text);
  finally
    Answer.Free;
  end;
end;

procedure TLspInlineAccessorTests.RefusesWhenAllCalled;
begin
  Assert.WillRaiseWithMessage(
    procedure
    begin
      Run(FIndex, 12, TLspInlineAccessor.ScopeHere).Free;
    end, EJsonRpcError, 'TFoo.GetCount bleibt: Es wird noch aufgerufen (Use.pas:9).');
  Assert.WillRaiseWithMessage(
    procedure
    begin
      Run(FIndex, 20, TLspInlineAccessor.ScopeHere).Free;
    end, EJsonRpcError, 'GetTitle implementiert eine Methode von ITitled.');
end;

procedure TLspInlineAccessorTests.ReplacesWholeUnit;
var
  Answer: TJSONObject;
  Text: string;
begin
  Answer := Run(FIndex, 5, TLspInlineAccessor.ScopeUnit);
  try
    Assert.AreEqual(3, (Answer.GetValue('accessors') as TJSONNumber).AsInt);
    Assert.AreEqual(1, (Answer.GetValue('files') as TJSONNumber).AsInt);
    Text := After(Answer, ModelFile);
    Assert.IsTrue(ContainsStr(Text, 'read FName write FName;'), Text);
    Assert.IsTrue(ContainsStr(Text, 'read GetCount write FCount;'), Text);
    Assert.IsTrue(ContainsStr(Text, 'read GetTitle;'), Text);
  finally
    Answer.Free;
  end;
end;

procedure TLspInlineAccessorTests.ReplacesWholeProject;
var
  Answer: TJSONObject;
  Text: string;
begin
  Answer := Run(FIndex, 5, TLspInlineAccessor.ScopeProject);
  try
    Assert.AreEqual(4, (Answer.GetValue('accessors') as TJSONNumber).AsInt);
    Assert.AreEqual(2, (Answer.GetValue('files') as TJSONNumber).AsInt);
    Text := After(Answer, OtherFile);
    Assert.IsTrue(ContainsStr(Text, '    property Size: Integer read FSize;'), Text);
    Assert.IsFalse(ContainsStr(Text, 'GetSize'), Text);
  finally
    Answer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspInlineAccessorTests);

end.
