unit Atlas.Common.Lsp.Refactorings.Tests;

// Tests für die Code-Aktionen aus #50 mit Namensauflösung: „case
// vervollständigen“, „with auflösen“, Typabfrage und Schalter.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Lsp.Refactorings;

type
  [TestFixture]
  TLspRefactoringsTests = class
  private
    FIndex: ISymbolIndex;
    function Context: TRefactoringContext;
    function Titles(const AText: string; ALine, ACharacter: Integer; const AContext: TRefactoringContext): string;
    function Applied(const AText, ATitle: string; ALine, ACharacter: Integer): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure CompletesCaseOfEnumeration;
    [Test]
    procedure ResolvesWithOverTheIndex;
    [Test]
    procedure NoWithActionForUnknownNames;
    [Test]
    procedure ProbeFindsTypeAndKind;
    [Test]
    procedure SettingsSwitchActionsOff;
    /// <summary>Strg+Leertaste auf dem Wort with bietet „with auflösen“ an.</summary>
    [Test]
    procedure CompletionOffersWithItem;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.Extract,
  Atlas.Common.Lsp.CompletionRequest,
  Atlas.Common.Lsp.Completion;

const
  HauptFile = 'C:\P\Haupt.pas';

  UnitHaupt =
    'unit Haupt;'#10 +                                                               // 0
    'interface'#10 +                                                                 // 1
    'type'#10 +                                                                      // 2
    '  TAlign = (alNone, alTop, alBottom, alLeft, alRight, alClient, alCustom);'#10 + // 3
    '  TKunde = class'#10 +                                                          // 4
    '  public'#10 +                                                                  // 5
    '    Name: string;'#10 +                                                         // 6
    '  end;'#10 +                                                                    // 7
    '  TAdresse = class'#10 +                                                        // 8
    '  public'#10 +                                                                  // 9
    '    Ort: string;'#10 +                                                          // 10
    '  end;'#10 +                                                                    // 11
    'procedure Zeige(A: TAlign);'#10 +                                               // 12
    'procedure Setze(K: TKunde; D: TAdresse);'#10 +                                  // 13
    'implementation'#10 +                                                            // 14
    'procedure Zeige(A: TAlign);'#10 +                                               // 15
    'begin'#10 +                                                                     // 16
    '  case A of'#10 +                                                               // 17
    '    alNone: ;'#10 +                                                             // 18
    '    alTop: ;'#10 +                                                              // 19
    '    alBottom: ;'#10 +                                                           // 20
    '  end;'#10 +                                                                    // 21
    'end;'#10 +                                                                      // 22
    'procedure Setze(K: TKunde; D: TAdresse);'#10 +                                  // 23
    'begin'#10 +                                                                     // 24
    '  with K, D do'#10 +                                                            // 25
    '    Name := Ort;'#10 +                                                          // 26
    'end;'#10 +                                                                      // 27
    'procedure Fremd(K: TFremd);'#10 +                                               // 28
    'begin'#10 +                                                                     // 29
    '  with K do'#10 +                                                               // 30
    '    Name := ''x'';'#10 +                                                         // 31
    'end;'#10 +                                                                      // 32
    'end.'#10;

function ReadFile(const AFileName: string; out AText: string): Boolean;
begin
  AText := UnitHaupt;
  Result := SameText(AFileName, HauptFile);
end;

{ TLspRefactoringsTests }

procedure TLspRefactoringsTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitHaupt, HauptFile, nil));
end;

procedure TLspRefactoringsTests.TearDown;
begin
  FIndex := nil;
end;

function TLspRefactoringsTests.Context: TRefactoringContext;
begin
  Result := Default(TRefactoringContext);
  Result.Index := FIndex;
  Result.FileName := HauptFile;
  Result.ReadText := ReadFile;
  Result.Settings := TRefactoringSettings.Default;
  Result.InlineVar := True;
  Result.Style := TFormatStyle.Default;
end;

function TLspRefactoringsTests.Titles(const AText: string; ALine, ACharacter: Integer;
  const AContext: TRefactoringContext): string;
var
  Tree: TSyntaxTree;
  Action: TCodeAction;
begin
  Result := '';
  Tree := TPascalParser.Parse(AText);
  try
    for Action in TLspRefactorings.Actions(Tree, AText, TTextRange.Create(TTextPosition.Create(ALine, ACharacter),
      TTextPosition.Create(ALine, ACharacter)), AContext) do
      Result := Result + Action.Title + '|';
  finally
    Tree.Free;
  end;
end;

function TLspRefactoringsTests.Applied(const AText, ATitle: string; ALine, ACharacter: Integer): string;
var
  Tree: TSyntaxTree;
  Action: TCodeAction;
begin
  Result := '-';
  Tree := TPascalParser.Parse(AText);
  try
    for Action in TLspRefactorings.Actions(Tree, AText, TTextRange.Create(TTextPosition.Create(ALine, ACharacter),
      TTextPosition.Create(ALine, ACharacter)), Context) do
      if Action.Title = ATitle then
        Exit(TChangeSignature.ApplyEdits(AText, Action.Edits));
  finally
    Tree.Free;
  end;
end;

procedure TLspRefactoringsTests.CompletesCaseOfEnumeration;
var
  Expected: string;
begin
  // Abnahmefall: case über TAlign mit drei vorhandenen Werten ergänzt die vier fehlenden.
  Expected := StringReplace(UnitHaupt, '    alBottom: ;'#10,
    '    alBottom: ;'#10'    alLeft: ;'#10'    alRight: ;'#10'    alClient: ;'#10'    alCustom: ;'#10, []);
  Assert.AreEqual(Expected, Applied(UnitHaupt, 'case vervollständigen (4 fehlende Werte)', 17, 4));
end;

procedure TLspRefactoringsTests.ResolvesWithOverTheIndex;
begin
  // Name gehört zu TKunde (K), Ort zu TAdresse (D).
  Assert.AreEqual(StringReplace(UnitHaupt, '  with K, D do'#10'    Name := Ort;'#10, '  K.Name := D.Ort;'#10, []),
    Applied(UnitHaupt, 'with auflösen', 25, 3));
end;

procedure TLspRefactoringsTests.NoWithActionForUnknownNames;
begin
  // TFremd ist nirgends deklariert: ob Name dazugehört, ist offen, also rät Atlas nicht.
  Assert.AreEqual('-', Applied(UnitHaupt, 'with auflösen', 30, 3));
end;

procedure TLspRefactoringsTests.ProbeFindsTypeAndKind;
var
  Probe: TTypeProbe;
  Probed: TProbedType;
  Text: string;
begin
  Probe := TLspRefactorings.Probe(Context);
  Text := StringReplace(UnitHaupt, '  with K, D do'#10, '  var AtlasProbe := K;'#10'  with K, D do'#10, []);
  Probed := Probe(Text, TTextPosition.Create(25, 6));
  Assert.AreEqual('TKunde', Probed.Name);
  Assert.IsTrue(Probed.IsReference);
  Assert.AreEqual('', Probed.UnitName);
  Text := StringReplace(UnitHaupt, '  case A of'#10, '  var AtlasProbe := A;'#10'  case A of'#10, []);
  Probed := Probe(Text, TTextPosition.Create(17, 6));
  Assert.AreEqual('TAlign', Probed.Name);
  Assert.IsTrue(Probed.IsValue);
  Assert.IsFalse(Probed.IsReference);
end;

procedure TLspRefactoringsTests.SettingsSwitchActionsOff;
var
  Off: TRefactoringContext;
begin
  Assert.AreEqual('case vervollständigen (4 fehlende Werte)|', Titles(UnitHaupt, 17, 4, Context));
  Assert.AreEqual('with auflösen|', Titles(UnitHaupt, 25, 3, Context));
  Off := Context;
  Off.Settings.CompleteCase := False;
  Off.Settings.ResolveWith := False;
  Assert.AreEqual('', Titles(UnitHaupt, 17, 4, Off));
  Assert.AreEqual('', Titles(UnitHaupt, 25, 3, Off));
end;

procedure TLspRefactoringsTests.CompletionOffersWithItem;
var
  Store: IDocumentStore;
  Completion: TLspCompletion;
  Dispatcher: TJsonRpcDispatcher;
  Uri, Answer: string;
  Asked: Integer;

  function Ask(ACharacter: Integer): string;
  var
    Request, Response: TJSONObject;
  begin
    Request := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":1,"method":"textDocument/completion",' +
      '"params":{"textDocument":{"uri":"' + Uri.Replace('\', '\\') + '"},"position":{"line":25,"character":' +
      IntToStr(ACharacter) + '}}}') as TJSONObject;
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
  Uri := TDocumentUris.FromPath(HauptFile);
  Store := TDocumentStore.Create;
  Store.Open(Uri, 'delphi', 1, UnitHaupt);
  Asked := 0;
  Completion := TLspCompletion.Create(Store, FIndex);
  Dispatcher := TJsonRpcDispatcher.Create;
  try
    Completion.WithFor :=
      function(ARequest: TCompletionRequest; out AEdits: TArray<TTextEdit>): Boolean
      begin
        Inc(Asked);
        AEdits := [TTextEdit.Create(TTextRange.Create(TTextPosition.Create(25, 2), TTextPosition.Create(26, 15)),
          'K.Name := D.Ort')];
        Result := True;
      end;
    Completion.Attach(Dispatcher);
    // Auf "with" (ö kommt als \u00F6): Haupteintrag entfernt das Wort, der Rest kommt als Zusatzänderung.
    Answer := Ask(4);
    Assert.IsTrue(Answer.Contains('"label":"with aufl'), Answer);
    Assert.IsTrue(Answer.Contains('K.Name := D.Ort'), Answer);
    Assert.AreEqual(1, Asked);
    // Hinter dem Wort nicht.
    Answer := Ask(10);
    Assert.IsFalse(Answer.Contains('"label":"with aufl'), Answer);
  finally
    Dispatcher.Free;
    Completion.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspRefactoringsTests);

end.
