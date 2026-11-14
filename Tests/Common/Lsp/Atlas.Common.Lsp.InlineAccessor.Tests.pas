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
  cIntfFile = 'C:\P\Titles.pas';
  cModelFile = 'C:\P\Model.pas';
  cUseFile = 'C:\P\Use.pas';
  cOtherFile = 'C:\P\Other.pas';

  cUnitIntf =
    'unit Titles;'#10'interface'#10'type'#10 +
    '  ITitled = interface'#10 +
    '    function GetTitle: string;'#10 +
    '  end;'#10 +
    'implementation'#10'end.'#10;
  cUnitModel =
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
  cUnitUse =
    'unit Use;'#10'interface'#10'uses'#10'  Model;'#10'implementation'#10#10 +
    'function Total(AFoo: TFoo): Integer;'#10'begin'#10'  Result := AFoo.GetCount + 1;'#10'end;'#10#10 +
    'end.'#10;
  cUnitOther =
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
  if SameText(AFileName, cIntfFile) then
  begin
    Result := cUnitIntf;
  end
  else if SameText(AFileName, cModelFile) then
  begin
    Result := cUnitModel;
  end
  else if SameText(AFileName, cUseFile) then
  begin
    Result := cUnitUse;
  end
  else if SameText(AFileName, cOtherFile) then
  begin
    Result := cUnitOther;
  end
  else
  begin
    Result := '';
  end;
end;

function Context(const AIndex: ISymbolIndex): TInlineAccessorContext;
begin
  Result := Default(TInlineAccessorContext);
  Result.Index := AIndex;
  Result.Options := TInlineAccessorOptions.Default;
  Result.Files := [cIntfFile, cModelFile, cUseFile, cOtherFile];
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
  mItem, mEdit: TJSONValue;
  mDocument, mRange: TJSONObject;
  mEdits: TArray<TTextEdit>;
  mUri: string;
begin
  Result := TextOf(AFileName);
  for mItem in (AAnswer.GetValue('edit') as TJSONObject).GetValue('documentChanges') as TJSONArray do
  begin
    mDocument := TJSONObject(mItem);
    mUri := (mDocument.GetValue('textDocument') as TJSONObject).GetValue('uri').Value;
    if not SameText(TDocumentUris.ToPath(mUri), AFileName) then
    begin
      Continue;
    end;
    mEdits := nil;
    for mEdit in mDocument.GetValue('edits') as TJSONArray do
    begin
      mRange := TJSONObject(mEdit).GetValue('range') as TJSONObject;
      mEdits := mEdits + [TTextEdit.Create(TTextRange.Create(TLspPositions.ReadPosition(mRange.GetValue('start')),
        TLspPositions.ReadPosition(mRange.GetValue('end'))), TJSONObject(mEdit).GetValue('newText').Value)];
    end;
    Result := TTextChanges.Apply(Result, mEdits);
  end;
end;

function Run(const AIndex: ISymbolIndex; ALine: Integer; const AScope: string): TJSONObject;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mContext: TInlineAccessorContext;
begin
  mTree := TPascalParser.Parse(cUnitModel);
  mResolver := TNameResolver.Create(AIndex, nil);
  try
    mContext := Context(AIndex);
    mContext.Scope := AScope;
    Result := TLspInlineAccessor.Execute(mResolver, mTree, cModelFile, cUnitModel, TTextPosition.Create(ALine, 6),
      mContext);
  finally
    mResolver.Free;
    mTree.Free;
  end;
end;

function Titles(const AItems: TArray<TJSONObject>): string;
var
  mItem: TJSONObject;
begin
  Result := '';
  for mItem in AItems do
  begin
    Result := Result + mItem.GetValue('title').Value + '|';
    mItem.Free;
  end;
end;

function Warnings(AAnswer: TJSONObject): string;
var
  mItem: TJSONValue;
begin
  Result := '';
  for mItem in AAnswer.GetValue('warnings') as TJSONArray do
  begin
    Result := Result + mItem.Value + '|';
  end;
end;

procedure TLspInlineAccessorTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitIntf, cIntfFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitModel, cModelFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitUse, cUseFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitOther, cOtherFile, nil));
end;

procedure TLspInlineAccessorTests.TearDown;
begin
  FIndex := nil;
end;

procedure TLspInlineAccessorTests.OffersActions;
var
  mTree: TSyntaxTree;

  function Offered(AEnabled, ABulk: Boolean; ALine: Integer): string;
  var
    mOffer: TInlineAccessorOffer;
  begin
    mOffer := Default(TInlineAccessorOffer);
    mOffer.Enabled := AEnabled;
    mOffer.Bulk := ABulk;
    mOffer.Options := TInlineAccessorOptions.Default;
    mOffer.Index := FIndex;
    Result := Titles(TLspInlineAccessor.Actions(mOffer, mTree, cUnitModel, 'file:///C:/P/Model.pas',
      TTextPosition.Create(ALine, 6)));
  end;

begin
  mTree := TPascalParser.Parse(cUnitModel);
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
    mTree.Free;
  end;
end;

procedure TLspInlineAccessorTests.ReplacesAtProperty;
var
  mAnswer: TJSONObject;
  mText: string;
begin
  mAnswer := Run(FIndex, 14, TLspInlineAccessor.cScopeHere);
  try
    Assert.AreEqual(2, (mAnswer.GetValue('accessors') as TJSONNumber).AsInt);
    Assert.AreEqual('', Warnings(mAnswer));
    mText := After(mAnswer, cModelFile);
    Assert.IsTrue(ContainsStr(mText, '    property Name: string read FName write FName;'), mText);
    Assert.IsFalse(ContainsStr(mText, 'GetName'), mText);
    Assert.IsFalse(ContainsStr(mText, 'SetName'), mText);
    Assert.IsTrue(ContainsStr(mText, 'function TFoo.GetCount'), mText);
  finally
    mAnswer.Free;
  end;
end;

procedure TLspInlineAccessorTests.KeepsCalledAccessor;
var
  mAnswer: TJSONObject;
  mText: string;
begin
  mAnswer := Run(FIndex, 15, TLspInlineAccessor.cScopeHere);
  try
    Assert.AreEqual(1, (mAnswer.GetValue('accessors') as TJSONNumber).AsInt);
    Assert.AreEqual('TFoo.GetCount bleibt: Es wird noch aufgerufen (Use.pas:9).|', Warnings(mAnswer));
    mText := After(mAnswer, cModelFile);
    Assert.IsTrue(ContainsStr(mText, '    property Count: Integer read GetCount write FCount;'), mText);
    Assert.IsFalse(ContainsStr(mText, 'SetCount'), mText);
  finally
    mAnswer.Free;
  end;
end;

procedure TLspInlineAccessorTests.RefusesWhenAllCalled;
begin
  Assert.WillRaiseWithMessage(
    procedure
    begin
      Run(FIndex, 12, TLspInlineAccessor.cScopeHere).Free;
    end, EJsonRpcError, 'TFoo.GetCount bleibt: Es wird noch aufgerufen (Use.pas:9).');
  Assert.WillRaiseWithMessage(
    procedure
    begin
      Run(FIndex, 20, TLspInlineAccessor.cScopeHere).Free;
    end, EJsonRpcError, 'GetTitle implementiert eine Methode von ITitled.');
end;

procedure TLspInlineAccessorTests.ReplacesWholeUnit;
var
  mAnswer: TJSONObject;
  mText: string;
begin
  mAnswer := Run(FIndex, 5, TLspInlineAccessor.cScopeUnit);
  try
    Assert.AreEqual(3, (mAnswer.GetValue('accessors') as TJSONNumber).AsInt);
    Assert.AreEqual(1, (mAnswer.GetValue('files') as TJSONNumber).AsInt);
    mText := After(mAnswer, cModelFile);
    Assert.IsTrue(ContainsStr(mText, 'read FName write FName;'), mText);
    Assert.IsTrue(ContainsStr(mText, 'read GetCount write FCount;'), mText);
    Assert.IsTrue(ContainsStr(mText, 'read GetTitle;'), mText);
  finally
    mAnswer.Free;
  end;
end;

procedure TLspInlineAccessorTests.ReplacesWholeProject;
var
  mAnswer: TJSONObject;
  mText: string;
begin
  mAnswer := Run(FIndex, 5, TLspInlineAccessor.cScopeProject);
  try
    Assert.AreEqual(4, (mAnswer.GetValue('accessors') as TJSONNumber).AsInt);
    Assert.AreEqual(2, (mAnswer.GetValue('files') as TJSONNumber).AsInt);
    mText := After(mAnswer, cOtherFile);
    Assert.IsTrue(ContainsStr(mText, '    property Size: Integer read FSize;'), mText);
    Assert.IsFalse(ContainsStr(mText, 'GetSize'), mText);
  finally
    mAnswer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspInlineAccessorTests);

end.
