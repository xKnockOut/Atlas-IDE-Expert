unit Atlas.Common.Lsp.CompletionSyntax.Tests;

// Hinweis bei unvollstaendigem Code (#457): Bereich der aktuellen Routine bzw. Klasse aus den Tokens, nur Fehler
// davor zaehlen, nicht die an der Tippstelle; eingeschraenkt bzw. unbekannt, JSON syntaxNotice, Schalter
// completion.syntaxNotice.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Documents.Contract,
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
  Head =
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
  Index, Line, Character: Integer;
begin
  Line := 0;
  Character := 0;
  for Index := 1 to Pos('|', AMarked) - 1 do
    if AMarked[Index] = #10 then
    begin
      Inc(Line);
      Character := 0;
    end
    else
      Inc(Character);
  APosition := TTextPosition.Create(Line, Character);
  Result := StringReplace(AMarked, '|', '', []);
end;

{ TCompletionSyntaxTests }

function TCompletionSyntaxTests.Assess(const AMarked: string; ACount: Integer): TCompletionSyntaxNotice;
var
  Text: string;
  Position: TTextPosition;
  Tree: TSyntaxTree;
begin
  Text := Split(AMarked, Position);
  Tree := TPascalParser.Parse(Text);
  try
    Result := TCompletionSyntax.Assess(Tree, Text, Position, ACount);
  finally
    Tree.Free;
  end;
end;

function TCompletionSyntaxTests.Assess(const AMarked: string): TCompletionSyntaxNotice;
begin
  Result := Assess(AMarked, 5);
end;

function TCompletionSyntaxTests.ScopeOf(const AMarked: string): TCompletionScope;
var
  Text: string;
  Position: TTextPosition;
  Tree: TSyntaxTree;
begin
  Text := Split(AMarked, Position);
  Tree := TPascalParser.Parse(Text);
  try
    Result := TCompletionSyntax.ScopeAt(Tree.Tokens, Position);
  finally
    Tree.Free;
  end;
end;

procedure TCompletionSyntaxTests.ScopeIsCurrentRoutine;
var
  Scope: TCompletionScope;
begin
  Scope := ScopeOf(Head +
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
  Assert.AreEqual(Ord(TCompletionScopeKind.Routine), Ord(Scope.Kind));
  Assert.AreEqual(11, Scope.FirstLine);
  Assert.AreEqual(16, Scope.LastLine);
end;

procedure TCompletionSyntaxTests.ScopeIsClassDeclaration;
var
  Scope: TCompletionScope;
begin
  Scope := ScopeOf('unit Haupt;'#10'interface'#10'type'#10'  TA = class'#10'    X: Integer;'#10'  end;'#10 +
    '  TF = class'#10'    |'#10'  end;'#10'var'#10'  G: Integer;'#10'implementation'#10'end.');
  Assert.AreEqual(Ord(TCompletionScopeKind.TypeDecl), Ord(Scope.Kind));
  Assert.AreEqual(6, Scope.FirstLine);
  Assert.AreEqual(8, Scope.LastLine);
end;

procedure TCompletionSyntaxTests.NoScopeOutsideRoutines;
begin
  Assert.AreEqual(Ord(TCompletionScopeKind.None), Ord(ScopeOf('unit Haupt;'#10'interface'#10'uses'#10 +
    '  Sys|'#10'implementation'#10'end.').Kind));
  // Globale Variable hinter einer Klasse.
  Assert.AreEqual(Ord(TCompletionScopeKind.None), Ord(ScopeOf(Head + 'var'#10'  G: |'#10'end.').Kind));
end;

procedure TCompletionSyntaxTests.MissingEndInEarlierMethodIsNoNotice;
begin
  // Akzeptanz: Ein fehlendes end; in einer frueheren Methode erzeugt keinen Hinweis.
  Assert.AreEqual(Ord(TCompletionTrust.Sure), Ord(Assess(Head +
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
  Notice: TCompletionSyntaxNotice;
begin
  // Akzeptanz: ein Fehler in der aktuellen Methode schon.
  Notice := Assess(Head +
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
  Assert.AreEqual(Ord(TCompletionTrust.Limited), Ord(Notice.Trust));
  Assert.AreEqual(13, Notice.Line);
  Assert.AreEqual(12, Notice.Character);
  Assert.IsTrue(Notice.Message <> '');
end;

procedure TCompletionSyntaxTests.TypingAtCursorIsNoNotice;
begin
  Assert.AreEqual(Ord(TCompletionTrust.Sure), Ord(Assess(Head + 'procedure TF.A;'#10'begin'#10 +
    '  X := Foo.|'#10'end;'#10'procedure TF.B;'#10'begin'#10'end;'#10'end.').Trust));
  Assert.AreEqual(Ord(TCompletionTrust.Sure), Ord(Assess(Head + 'procedure TF.A;'#10'begin'#10 +
    '  Foo(1, |'#10'end;'#10'end.').Trust));
  Assert.AreEqual(Ord(TCompletionTrust.Sure), Ord(Assess(Head + 'procedure TF.A;'#10'begin'#10 +
    '  if Ab|'#10'end;'#10'end.').Trust));
end;

procedure TCompletionSyntaxTests.ErrorAfterCursorIsNoNotice;
begin
  Assert.AreEqual(Ord(TCompletionTrust.Sure), Ord(Assess(Head + 'procedure TF.A;'#10'begin'#10 +
    '  Fo|;'#10'  X := (1 + ;'#10'end;'#10'end.').Trust));
end;

procedure TCompletionSyntaxTests.ErrorInClassDeclaration;
var
  Notice: TCompletionSyntaxNotice;
begin
  Notice := Assess('unit Haupt;'#10'interface'#10'type'#10'  TF = class'#10'    procedure A(;'#10 +
    '    procedure |'#10'  end;'#10'implementation'#10'end.');
  Assert.AreEqual(Ord(TCompletionTrust.Limited), Ord(Notice.Trust));
  Assert.AreEqual(4, Notice.Line);
  // Fehler in einer anderen Klasse zaehlt nicht.
  Notice := Assess('unit Haupt;'#10'interface'#10'type'#10'  TA = class'#10'    procedure A(;'#10'  end;'#10 +
    '  TF = class'#10'    procedure B;'#10'    |'#10'  end;'#10'implementation'#10'end.');
  Assert.AreEqual(Ord(TCompletionTrust.Sure), Ord(Notice.Trust));
end;

procedure TCompletionSyntaxTests.UnknownWithoutItems;
begin
  Assert.AreEqual(Ord(TCompletionTrust.Unknown), Ord(Assess(Head + 'procedure TF.A;'#10'begin'#10 +
    '  X := (1 + ;'#10'  |'#10'end;'#10'end.', 0).Trust));
end;

procedure TCompletionSyntaxTests.WritesJson;
var
  List: TJSONObject;
  Notice: TCompletionSyntaxNotice;
begin
  List := TJSONObject.Create;
  try
    Notice := Default(TCompletionSyntaxNotice);
    TCompletionSyntax.WriteJson(List, Notice);
    Assert.AreEqual('{}', List.ToJSON);
    Notice.Trust := TCompletionTrust.Limited;
    Notice.Line := 13;
    Notice.Character := 12;
    Notice.Message := 'Fehler';
    TCompletionSyntax.WriteJson(List, Notice);
    Assert.AreEqual('{"syntaxNotice":{"trust":"limited","line":13,"character":12,"message":"Fehler"}}',
      List.ToJSON);
  finally
    List.Free;
  end;
end;

procedure TCompletionSyntaxTests.DispatcherAnswersWithNotice;
var
  Text, Uri, Answer: string;
  Store: IDocumentStore;
  Completion: TLspCompletion;
  Dispatcher: TJsonRpcDispatcher;
  Position: TTextPosition;
  Index: ISymbolIndex;

  function Ask: string;
  var
    Request, Response: TJSONObject;
  begin
    Request := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":1,"method":"textDocument/completion",' +
      '"params":{"textDocument":{"uri":"' + Uri.Replace('\', '\\') + '"},"position":{"line":' +
      IntToStr(Position.Line) + ',"character":' + IntToStr(Position.Character) + '}}}') as TJSONObject;
    try
      Response := Dispatcher.DispatchMessage(Request);
      try
        Result := Response.ToJSON;
      finally
        Response.Free;
      end;
    finally
      Request.Free;
    end;
  end;

begin
  Text := Split(Head + 'procedure TF.A;'#10'var'#10'  Value: Integer;'#10'begin'#10'  X := (1 + ;'#10 +
    '  Va|'#10'end;'#10'end.', Position);
  Uri := TDocumentUris.FromPath('C:\P\Haupt.pas');
  Store := TDocumentStore.Create;
  Store.Open(Uri, 'delphi', 1, Text);
  Index := TSymbolIndex.Create;
  Completion := TLspCompletion.Create(Store, Index);
  Dispatcher := TJsonRpcDispatcher.Create;
  try
    Completion.Attach(Dispatcher);
    FSyntaxNotice := True;
    Completion.SettingsFor :=
      function(const AUri: string): TCompletionSettings
      begin
        Result := TCompletionSettings.Default;
        Result.SyntaxNotice := FSyntaxNotice;
      end;
    Answer := Ask;
    Assert.IsTrue(Answer.Contains('"syntaxNotice":{"trust":"limited","line":12,"character":12'), Answer);
    FSyntaxNotice := False;
    Answer := Ask;
    Assert.IsFalse(Answer.Contains('syntaxNotice'), Answer);
  finally
    Dispatcher.Free;
    Completion.Free;
  end;
end;

end.
