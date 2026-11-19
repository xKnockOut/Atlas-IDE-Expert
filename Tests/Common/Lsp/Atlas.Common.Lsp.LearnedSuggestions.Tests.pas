unit Atlas.Common.Lsp.LearnedSuggestions.Tests;

// Tests für atlas.server.suggestNext und atlas.server.learnedPatterns (#1890):
// Antwort mit Zeilen, Schreibmarke und Belegen, Schwellen aus den Argumenten,
// null ohne Muster, Ablehnung ohne Zeile und die Liste der Muster; für
// Vorschläge eines KI-Anbieters (#1922) atlas.server.checkSuggestion und
// atlas.server.suggestionContext.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract;

type
  [TestFixture]
  TLspLearnedSuggestionsTests = class
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    function Run(const AArguments: string): string;
    function Check(const ALines: string): string;
    function Context(const AArguments: string): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure SuggestsTryFinally;
    [Test]
    procedure ThresholdsFromArguments;
    [Test]
    procedure AdjustFromArguments;
    [Test]
    procedure NullWithoutDocument;
    [Test]
    procedure RejectsMissingLine;
    [Test]
    procedure ListsPatterns;
    [Test]
    procedure ReadOptionsClampsThresholds;
    [Test]
    procedure CheckAcceptsKnownNames;
    [Test]
    procedure CheckRejectsUnknownName;
    [Test]
    procedure CheckRejectsNewSyntaxError;
    [Test]
    procedure CheckRejectsMissingLines;
    [Test]
    procedure CheckIsInvalidWithoutDocument;
    [Test]
    procedure ContextListsMembersOfTheClass;
    [Test]
    procedure ContextIsEmptyOutsideMethods;
  end;

implementation

uses
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Editing.LearnedSuggestions,
  Atlas.Common.Lsp.LearnedSuggestions;

const
  cUri = 'file:///C:/P/Haupt.pas';
  cMethodUri = 'file:///C:/P/Ablauf.pas';
  cMethod =
    'unit Ablauf;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'procedure TKunde.Speichern;'#10 +
    'begin'#10 +
    #10 +
    'end;'#10 +
    'end.';
  cCustomer =
    'unit Kunden;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TKunde = class'#10 +
    '  private'#10 +
    '    FName: string;'#10 +
    '  public'#10 +
    '    procedure Speichern;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TKunde.Speichern;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';
  cMain =
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'procedure P;'#10 +
    'begin'#10 +
    '  Liste := TStringList.Create;'#10 +
    #10 +
    'end;'#10 +
    'end.';
  cFree =
    'unit System;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TObject = class'#10 +
    '    procedure Free;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TObject.Free;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

function Learned(const AName: string): string;
begin
  Result := 'unit ' + AName + ';'#10'interface'#10'implementation'#10'procedure Q;'#10'begin'#10 +
    '  X := TFoo.Create;'#10'  try'#10'  finally'#10'    X.Free;'#10'  end;'#10'end;'#10'end.';
end;

function OptionsFor(const AUri: string; const AEditorOptions: TJSONValue): TLearnedOptions;
begin
  Result := TLearnedOptions.Default;
end;

{ TLspLearnedSuggestionsTests }

function TLspLearnedSuggestionsTests.Run(const AArguments: string): string;
var
  mArguments: TJSONArray;
  mAnswer: TJSONValue;
begin
  mArguments := TJSONObject.ParseJSONValue(AArguments) as TJSONArray;
  try
    mAnswer := TLspLearnedSuggestions.ExecuteSuggest(FStore, FIndex, OptionsFor, mArguments);
    try
      Result := mAnswer.ToJSON;
    finally
      mAnswer.Free;
    end;
  finally
    mArguments.Free;
  end;
end;

function TLspLearnedSuggestionsTests.Check(const ALines: string): string;
var
  mArguments: TJSONArray;
  mAnswer: TJSONValue;
begin
  mArguments := TJSONObject.ParseJSONValue('["' + cUri + '", 6, ' + ALines + ']') as TJSONArray;
  try
    mAnswer := TLspLearnedSuggestions.ExecuteCheck(FStore, FIndex, mArguments);
    try
      Result := mAnswer.ToJSON;
    finally
      mAnswer.Free;
    end;
  finally
    mArguments.Free;
  end;
end;

function TLspLearnedSuggestionsTests.Context(const AArguments: string): string;
var
  mArguments: TJSONArray;
  mAnswer: TJSONValue;
begin
  mArguments := TJSONObject.ParseJSONValue(AArguments) as TJSONArray;
  try
    mAnswer := TLspLearnedSuggestions.ExecuteContext(FStore, FIndex, mArguments);
    try
      Result := mAnswer.ToJSON;
    finally
      mAnswer.Free;
    end;
  finally
    mArguments.Free;
  end;
end;

procedure TLspLearnedSuggestionsTests.Setup;
var
  mIndex: Integer;
  mLibrary: TUnitIndex;
begin
  FStore := TDocumentStore.Create;
  FStore.Open(cUri, 'delphi', 1, cMain);
  FStore.Open(cMethodUri, 'delphi', 1, cMethod);
  FIndex := TSymbolIndex.Create;
  for mIndex := 1 to 6 do
  begin
    FIndex.AddUnit(TIndexExtractor.ExtractText(Learned('U' + IntToStr(mIndex)), 'C:\P\U' + IntToStr(mIndex) + '.pas',
      nil, nil, False, True));
  end;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cCustomer, 'C:\P\Kunden.pas', nil, nil, False, True));
  mLibrary := TIndexExtractor.ExtractText(cFree, 'C:\RTL\System.pas', nil);
  mLibrary.Library_ := True;
  FIndex.AddUnit(mLibrary);
end;

procedure TLspLearnedSuggestionsTests.TearDown;
begin
  FStore := nil;
  FIndex := nil;
end;

procedure TLspLearnedSuggestionsTests.SuggestsTryFinally;
var
  mAnswer: string;
begin
  mAnswer := Run('["' + cUri + '", 6, null, {}]');
  Assert.IsTrue(Pos('"lines":["  try","    ","  finally","    Liste.Free;","  end;"]', mAnswer) > 0, mAnswer);
  Assert.IsTrue(Pos('"cursor":{"line":1,"character":4}', mAnswer) > 0, mAnswer);
  Assert.IsTrue(Pos('"count":6', mAnswer) > 0, mAnswer);
  Assert.IsTrue(Pos('"share":100', mAnswer) > 0, mAnswer);
  Assert.IsTrue(Pos('"team":false', mAnswer) > 0, mAnswer);
  Assert.IsTrue(Pos('"evidence":[{"uri":"', mAnswer) > 0, mAnswer);
end;

procedure TLspLearnedSuggestionsTests.ThresholdsFromArguments;
begin
  Assert.AreEqual('null', Run('["' + cUri + '", 6, null, {"minCount": 7}]'));
  Assert.AreNotEqual('null', Run('["' + cUri + '", 6, null, {"minCount": 6}]'));
end;

procedure TLspLearnedSuggestionsTests.AdjustFromArguments;
var
  mId: string;
begin
  mId := TLearnedSuggestions.IdOf('$S := $T.Create', 'try'#10'>$|'#10'finally'#10'>$S.Free;'#10'end;');
  Assert.AreEqual('null', Run('["' + cUri + '", 6, null, {"adjust": {"' + mId + '": -40}}]'));
end;

procedure TLspLearnedSuggestionsTests.NullWithoutDocument;
begin
  Assert.AreEqual('null', Run('["file:///C:/P/Fehlt.pas", 6]'));
  Assert.AreEqual('null', Run('["' + cUri + '", 2]'), 'keine leere Zeile nach einem Auslöser');
end;

procedure TLspLearnedSuggestionsTests.RejectsMissingLine;
begin
  Assert.WillRaise(
    procedure
    begin
      Run('["' + cUri + '"]');
    end, EArgumentException);
end;

procedure TLspLearnedSuggestionsTests.ListsPatterns;
var
  mArguments: TJSONArray;
  mAnswer: TJSONValue;
  mText: string;
begin
  mArguments := TJSONObject.ParseJSONValue('["' + cUri + '"]') as TJSONArray;
  try
    mAnswer := TLspLearnedSuggestions.ExecuteList(FIndex, OptionsFor, mArguments);
    try
      mText := mAnswer.ToJSON;
    finally
      mAnswer.Free;
    end;
  finally
    mArguments.Free;
  end;
  Assert.IsTrue(Pos('"text":"try \u2026 finally $S.Free; end;"', mText) + Pos('"text":"try … finally $S.Free; end;"',
    mText) > 0, mText);
  Assert.IsTrue(Pos('"trigger":"$S := $T.Create"', mText) > 0, mText);
end;

procedure TLspLearnedSuggestionsTests.ReadOptionsClampsThresholds;
var
  mOptions: TLearnedOptions;
  mValue: TJSONValue;
begin
  mOptions := TLearnedOptions.Default;
  mValue := TJSONObject.ParseJSONValue('{"minCount": 1, "minShare": 300, "adjust": {"a": 5, "b": "x"}}');
  try
    TLspLearnedSuggestions.ReadOptions(mValue, mOptions);
  finally
    mValue.Free;
  end;
  Assert.AreEqual(2, mOptions.MinCount);
  Assert.AreEqual(100, mOptions.MinShare);
  Assert.AreEqual(1, Integer(Length(mOptions.AdjustIds)));
  Assert.AreEqual(5, mOptions.AdjustOf('A'));
end;

procedure TLspLearnedSuggestionsTests.CheckAcceptsKnownNames;
begin
  // Liste steht in der Datei, Free im Index.
  Assert.AreEqual('{"valid":true}', Check('["  Liste.Free;"]'));
end;

procedure TLspLearnedSuggestionsTests.CheckRejectsUnknownName;
begin
  Assert.AreEqual('{"valid":false}', Check('["  Zauberwort.Free;"]'));
end;

procedure TLspLearnedSuggestionsTests.CheckRejectsNewSyntaxError;
begin
  Assert.AreEqual('{"valid":false}', Check('["  Liste.Free(;"]'));
end;

procedure TLspLearnedSuggestionsTests.CheckRejectsMissingLines;
begin
  Assert.WillRaise(
    procedure
    begin
      Check('{}');
    end, EArgumentException);
end;

procedure TLspLearnedSuggestionsTests.CheckIsInvalidWithoutDocument;
var
  mArguments: TJSONArray;
  mAnswer: TJSONValue;
begin
  mArguments := TJSONObject.ParseJSONValue('["file:///C:/P/Fehlt.pas", 1, ["  X;"]]') as TJSONArray;
  try
    mAnswer := TLspLearnedSuggestions.ExecuteCheck(FStore, FIndex, mArguments);
    try
      Assert.AreEqual('{"valid":false}', mAnswer.ToJSON);
    finally
      mAnswer.Free;
    end;
  finally
    mArguments.Free;
  end;
end;

procedure TLspLearnedSuggestionsTests.ContextListsMembersOfTheClass;
var
  mText: string;
begin
  mText := Context('["' + cMethodUri + '", 5]');
  Assert.IsTrue(Pos('TKunde = class', mText) > 0, mText);
  Assert.IsTrue(Pos('FName: string', mText) > 0, mText);
  Assert.IsTrue(Pos('procedure Speichern', mText) > 0, mText);
end;

procedure TLspLearnedSuggestionsTests.ContextIsEmptyOutsideMethods;
begin
  Assert.AreEqual('{"declarations":[]}', Context('["' + cMethodUri + '", 1]'));
  Assert.AreEqual('{"declarations":[]}', Context('["' + cUri + '", 6]'), 'Routine ohne Klasse');
end;

initialization
  TDUnitX.RegisterTestFixture(TLspLearnedSuggestionsTests);

end.
