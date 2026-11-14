unit Atlas.Common.Lsp.CompletionSyntax.Tests;

// Hinweis bei unvollstaendigem Code (#457): Bereich der aktuellen Routine bzw. Klasse aus den Tokens, nur Fehler
// davor zaehlen, nicht die an der Tippstelle; eingeschraenkt bzw. unbekannt, JSON syntaxNotice, Schalter
// completion.syntaxNotice.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Lsp.CompletionSyntax;

type
  [TestFixture]
  TCompletionSyntaxTests = class
  private
    /// <summary>Schalter completion.syntaxNotice für DispatcherAnswersWithNotice.</summary>
    FSyntaxNotice: Boolean;
    function Assess(const AMarked: string; ACount: Integer): TCompletionSyntaxNotice; overload;
    function Assess(const AMarked: string): TCompletionSyntaxNotice; overload;
    function ScopeOf(const AMarked: string): TCompletionScope;
  public
    /// <summary>Erste Benutzung des Dispatcher-Wegs legt Dauerhaftes an; das gehört nicht in die Leckmessung.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure ScopeIsCurrentRoutine;
    [Test]
    procedure ScopeIsClassDeclaration;
    [Test]
    procedure NoScopeOutsideRoutines;
    [Test]
    procedure MissingEndInEarlierMethodIsNoNotice;
    [Test]
    procedure ErrorInCurrentMethodIsNotice;
    [Test]
    procedure TypingAtCursorIsNoNotice;
    [Test]
    procedure ErrorAfterCursorIsNoNotice;
    [Test]
    procedure ErrorInClassDeclaration;
    [Test]
    procedure UnknownWithoutItems;
    [Test]
    procedure WritesJson;
    [Test]
    procedure DispatcherAnswersWithNotice;
  end;

implementation

uses
  Atlas.Common.Documents.Contract,
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Lsp.Completion;

const
  cHead =
    'unit Haupt;'#10 +              // 0
    'interface'#10 +                // 1
    'type'#10 +                     // 2
    '  TF = class'#10 +             // 3
    '    procedure A;'#10 +         // 4
    '    procedure B;'#10 +         // 5
    '  end;'#10 +                   // 6
    'implementation'#10;            // 7

/// <summary>Text ohne "|" und die Position des "|".</summary>
function Split(const AMarked: string; out APosition: TTextPosition): string;
var
  mIndex, mLine, mCharacter: Integer;
begin
  mLine := 0;
  mCharacter := 0;
  for mIndex := 1 to Pos('|', AMarked) - 1 do
  begin
    if AMarked[mIndex] = #10 then
    begin
      Inc(mLine);
      mCharacter := 0;
    end
    else
    begin
      Inc(mCharacter);
    end;
  end;
  APosition := TTextPosition.Create(mLine, mCharacter);
  Result := StringReplace(AMarked, '|', '', []);
end;

{ TCompletionSyntaxTests }

function TCompletionSyntaxTests.Assess(const AMarked: string; ACount: Integer): TCompletionSyntaxNotice;
var
  mText: string;
  mPosition: TTextPosition;
  mTree: TSyntaxTree;
begin
  mText := Split(AMarked, mPosition);
  mTree := TPascalParser.Parse(mText);
  try
    Result := TCompletionSyntax.Assess(mTree, mText, mPosition, ACount);
  finally
    mTree.Free;
  end;
end;

function TCompletionSyntaxTests.Assess(const AMarked: string): TCompletionSyntaxNotice;
begin
  Result := Assess(AMarked, 5);
end;

function TCompletionSyntaxTests.ScopeOf(const AMarked: string): TCompletionScope;
var
  mText: string;
  mPosition: TTextPosition;
  mTree: TSyntaxTree;
begin
  mText := Split(AMarked, mPosition);
  mTree := TPascalParser.Parse(mText);
  try
    Result := TCompletionSyntax.ScopeAt(mTree.Tokens, mPosition);
  finally
    mTree.Free;
  end;
end;

procedure TCompletionSyntaxTests.ScopeIsCurrentRoutine;
var
  mScope: TCompletionScope;
begin
  mScope := ScopeOf(cHead +
    'procedure TF.A;'#10 +          // 8
    'begin'#10 +                    // 9
    'end;'#10 +                     // 10
    'procedure TF.B;'#10 +          // 11
    'var'#10 +                      // 12
    '  X: Integer;'#10 +            // 13
    'begin'#10 +                    // 14
    '  X|'#10 +                     // 15
    'end;'#10 +                     // 16
    'end.');                        // 17
  Assert.AreEqual(Ord(TCompletionScopeKind.Routine), Ord(mScope.Kind));
  Assert.AreEqual(11, mScope.FirstLine);
  Assert.AreEqual(16, mScope.LastLine);
end;

procedure TCompletionSyntaxTests.ScopeIsClassDeclaration;
var
  mScope: TCompletionScope;
begin
  mScope := ScopeOf('unit Haupt;'#10'interface'#10'type'#10'  TA = class'#10'    X: Integer;'#10'  end;'#10 +
    '  TF = class'#10'    |'#10'  end;'#10'var'#10'  G: Integer;'#10'implementation'#10'end.');
  Assert.AreEqual(Ord(TCompletionScopeKind.TypeDecl), Ord(mScope.Kind));
  Assert.AreEqual(6, mScope.FirstLine);
  Assert.AreEqual(8, mScope.LastLine);
end;

procedure TCompletionSyntaxTests.NoScopeOutsideRoutines;
begin
  Assert.AreEqual(Ord(TCompletionScopeKind.None), Ord(ScopeOf('unit Haupt;'#10'interface'#10'uses'#10 +
    '  Sys|'#10'implementation'#10'end.').Kind));
  // Globale Variable hinter einer Klasse.
  Assert.AreEqual(Ord(TCompletionScopeKind.None), Ord(ScopeOf(cHead + 'var'#10'  G: |'#10'end.').Kind));
end;

procedure TCompletionSyntaxTests.MissingEndInEarlierMethodIsNoNotice;
begin
  // Akzeptanz: Ein fehlendes end; in einer frueheren Methode erzeugt keinen Hinweis.
  Assert.AreEqual(Ord(TCompletionTrust.Sure), Ord(Assess(cHead +
    'procedure TF.A;'#10 +
    'begin'#10 +
    '  if True then'#10 +
    '  begin'#10 +
    '    A;'#10 +
    'end;'#10 +
    'procedure TF.B;'#10 +
    'begin'#10 +
    '  B.|'#10 +
    'end;'#10 +
    'end.').Trust));
end;

procedure TCompletionSyntaxTests.ErrorInCurrentMethodIsNotice;
var
  mNotice: TCompletionSyntaxNotice;
begin
  // Akzeptanz: ein Fehler in der aktuellen Methode schon.
  mNotice := Assess(cHead +
    'procedure TF.A;'#10 +          // 8
    'begin'#10 +                    // 9
    'end;'#10 +                     // 10
    'procedure TF.B;'#10 +          // 11
    'begin'#10 +                    // 12
    '  X := (1 + ;'#10 +            // 13
    '  Y := 2;'#10 +                // 14
    '  Z|'#10 +                     // 15
    'end;'#10 +
    'end.');
  Assert.AreEqual(Ord(TCompletionTrust.Limited), Ord(mNotice.Trust));
  Assert.AreEqual(13, mNotice.Line);
  Assert.AreEqual(12, mNotice.Character);
  Assert.AreNotEqual('', mNotice.Message);
end;

procedure TCompletionSyntaxTests.TypingAtCursorIsNoNotice;
begin
  Assert.AreEqual(Ord(TCompletionTrust.Sure), Ord(Assess(cHead + 'procedure TF.A;'#10'begin'#10 +
    '  X := Foo.|'#10'end;'#10'procedure TF.B;'#10'begin'#10'end;'#10'end.').Trust));
  Assert.AreEqual(Ord(TCompletionTrust.Sure), Ord(Assess(cHead + 'procedure TF.A;'#10'begin'#10 +
    '  Foo(1, |'#10'end;'#10'end.').Trust));
  Assert.AreEqual(Ord(TCompletionTrust.Sure), Ord(Assess(cHead + 'procedure TF.A;'#10'begin'#10 +
    '  if Ab|'#10'end;'#10'end.').Trust));
end;

procedure TCompletionSyntaxTests.ErrorAfterCursorIsNoNotice;
begin
  Assert.AreEqual(Ord(TCompletionTrust.Sure), Ord(Assess(cHead + 'procedure TF.A;'#10'begin'#10 +
    '  Fo|;'#10'  X := (1 + ;'#10'end;'#10'end.').Trust));
end;

procedure TCompletionSyntaxTests.ErrorInClassDeclaration;
var
  mNotice: TCompletionSyntaxNotice;
begin
  mNotice := Assess('unit Haupt;'#10'interface'#10'type'#10'  TF = class'#10'    procedure A(;'#10 +
    '    procedure |'#10'  end;'#10'implementation'#10'end.');
  Assert.AreEqual(Ord(TCompletionTrust.Limited), Ord(mNotice.Trust));
  Assert.AreEqual(4, mNotice.Line);
  // Fehler in einer anderen Klasse zaehlt nicht.
  mNotice := Assess('unit Haupt;'#10'interface'#10'type'#10'  TA = class'#10'    procedure A(;'#10'  end;'#10 +
    '  TF = class'#10'    procedure B;'#10'    |'#10'  end;'#10'implementation'#10'end.');
  Assert.AreEqual(Ord(TCompletionTrust.Sure), Ord(mNotice.Trust));
end;

procedure TCompletionSyntaxTests.UnknownWithoutItems;
begin
  Assert.AreEqual(Ord(TCompletionTrust.Unknown), Ord(Assess(cHead + 'procedure TF.A;'#10'begin'#10 +
    '  X := (1 + ;'#10'  |'#10'end;'#10'end.', 0).Trust));
end;

procedure TCompletionSyntaxTests.WritesJson;
var
  mList: TJSONObject;
  mNotice: TCompletionSyntaxNotice;
begin
  mList := TJSONObject.Create;
  try
    mNotice := Default(TCompletionSyntaxNotice);
    TCompletionSyntax.WriteJson(mList, mNotice);
    Assert.AreEqual('{}', mList.ToJSON);
    mNotice.Trust := TCompletionTrust.Limited;
    mNotice.Line := 13;
    mNotice.Character := 12;
    mNotice.Message := 'Fehler';
    TCompletionSyntax.WriteJson(mList, mNotice);
    Assert.AreEqual('{"syntaxNotice":{"trust":"limited","line":13,"character":12,"message":"Fehler"}}',
      mList.ToJSON);
  finally
    mList.Free;
  end;
end;

procedure TCompletionSyntaxTests.WarmUpFirstUse;
begin
  DispatcherAnswersWithNotice;
end;

procedure TCompletionSyntaxTests.DispatcherAnswersWithNotice;
var
  mText, mUri, mAnswer: string;
  mStore: IDocumentStore;
  mCompletion: TLspCompletion;
  mDispatcher: TJsonRpcDispatcher;
  mPosition: TTextPosition;
  mIndex: ISymbolIndex;

  function Ask: string;
  var
    mRequest, mResponse: TJSONObject;
  begin
    mRequest := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":1,"method":"textDocument/completion",' +
      '"params":{"textDocument":{"uri":"' + mUri.Replace('\', '\\') + '"},"position":{"line":' +
      IntToStr(mPosition.Line) + ',"character":' + IntToStr(mPosition.Character) + '}}}') as TJSONObject;
    try
      mResponse := mDispatcher.DispatchMessage(mRequest);
      try
        Result := mResponse.ToJSON;
      finally
        mResponse.Free;
      end;
    finally
      mRequest.Free;
    end;
  end;

begin
  mText := Split(cHead + 'procedure TF.A;'#10'var'#10'  Value: Integer;'#10'begin'#10'  X := (1 + ;'#10 +
    '  Va|'#10'end;'#10'end.', mPosition);
  mUri := TDocumentUris.FromPath('C:\P\Haupt.pas');
  mStore := TDocumentStore.Create;
  mStore.Open(mUri, 'delphi', 1, mText);
  mIndex := TSymbolIndex.Create;
  mCompletion := TLspCompletion.Create(mStore, mIndex);
  mDispatcher := TJsonRpcDispatcher.Create;
  try
    mCompletion.Attach(mDispatcher);
    FSyntaxNotice := True;
    mCompletion.Hooks.SettingsFor :=
      function(const AUri: string): TCompletionSettings
      begin
        Result := TCompletionSettings.Default;
        Result.SyntaxNotice := FSyntaxNotice;
      end;
    mAnswer := Ask;
    Assert.IsTrue(mAnswer.Contains('"syntaxNotice":{"trust":"limited","line":12,"character":12'), mAnswer);
    FSyntaxNotice := False;
    mAnswer := Ask;
    Assert.IsFalse(mAnswer.Contains('syntaxNotice'), mAnswer);
  finally
    mDispatcher.Free;
    mCompletion.Free;
  end;
end;

end.
