unit Atlas.Common.Lsp.Refactorings.Tests;

// Tests für die Code-Aktionen aus #50 mit Namensauflösung: „case
// vervollständigen“, „with auflösen“, Typabfrage und Schalter; dazu Einbetten
// (#103) über die Namensauflösung und aus einer anderen Unit.

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
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
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
    /// <summary>if-Kette und case (#646): Typ des Ausdrucks über den Index, Einrückung nach dem Formatstil.
    /// </summary>
    [Test]
    procedure ConvertsCaseAndIfChain;
    /// <summary>Bedingungen umformen (#656): angeboten auf dem if, abschaltbar.</summary>
    [Test]
    procedure RewritesConditions;
    /// <summary>Bedingungsausdruck (#684): Typen über den Index, vor Delphi 13 nur der Rückweg, abschaltbar.
    /// </summary>
    [Test]
    procedure ConvertsConditionalExpression;
    /// <summary>Strg+Leertaste auf dem Wort with bietet „with auflösen“ an.</summary>
    [Test]
    procedure CompletionOffersWithItem;
    /// <summary>#472: Abnahmefall, Prozedur, Bibliotheksklasse und Klasse in einer anderen Unit.</summary>
    [Test]
    procedure CreatesMethodFromCall;
    /// <summary>#472: Nach "(" als einziger Eintrag; bekannte Namen und Abschalten ohne Angebot.</summary>
    [Test]
    procedure CompletionOffersCreateAfterParen;
    /// <summary>#103: Methode aus einer anderen Unit, private Mitglieder, Variable mit Seiteneffekt und
    /// Schalter.</summary>
    [Test]
    procedure InlinesOverTheIndex;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
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

  RechnerFile = 'C:\P\Rechner.pas';
  KundenFile = 'C:\P\Kunden.pas';
  BibFile = 'C:\Lib\Bib.pas';

  UnitRechner =
    'unit Rechner;'#10 +                                       // 0
    'interface'#10 +                                           // 1
    'uses Kunden, Bib;'#10 +                                   // 2
    'type'#10 +                                                // 3
    '  TRechner = class'#10 +                                  // 4
    '  public'#10 +                                            // 5
    '    procedure Rechne(Customer: TCustomer);'#10 +          // 6
    '  end;'#10 +                                              // 7
    'implementation'#10 +                                      // 8
    'procedure TRechner.Rechne(Customer: TCustomer);'#10 +     // 9
    'var'#10 +                                                 // 10
    '  Total: Currency;'#10 +                                  // 11
    '  Liste: TBibListe;'#10 +                                 // 12
    'begin'#10 +                                               // 13
    '  Total := CalcDiscount(Customer, 0.1);'#10 +             // 14
    '  Protokolliere(Customer.Name);'#10 +                     // 15
    '  Liste.Sortiere(1);'#10 +                                // 16
    '  Customer.Pruefe(Total);'#10 +                           // 17
    '  Rechne(Customer);'#10 +                                 // 18
    'end;'#10 +                                                // 19
    'end.'#10;

  UnitKunden =
    'unit Kunden;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TCustomer = class'#10 +
    '  public'#10 +
    '    Name: string;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.'#10;

  UnitBib =
    'unit Bib;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TBibListe = class'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.'#10;

  LagerFile = 'C:\P\Lager.pas';
  KasseFile = 'C:\P\Kasse.pas';

  UnitLager =
    'unit Lager;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TLager = class'#10 +
    '  private'#10 +
    '    FBestand: Integer;'#10 +
    '  public'#10 +
    '    Anzahl: Integer;'#10 +
    '    function Doppelt: Integer;'#10 +
    '    procedure Zugang(AMenge: Integer);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function TLager.Doppelt: Integer;'#10 +
    'begin'#10 +
    '  Result := Anzahl * 2;'#10 +
    'end;'#10 +
    'procedure TLager.Zugang(AMenge: Integer);'#10 +
    'begin'#10 +
    '  FBestand := FBestand + AMenge;'#10 +
    'end;'#10 +
    'end.'#10;

  UnitKasse =
    'unit Kasse;'#10 +                         // 0
    'interface'#10 +                           // 1
    'uses Lager;'#10 +                         // 2
    'implementation'#10 +                      // 3
    'procedure Zeige(const A: Integer);'#10 +  // 4
    'begin'#10 +                               // 5
    'end;'#10 +                                // 6
    'procedure Buche(L: TLager);'#10 +         // 7
    'var'#10 +                                 // 8
    '  X: Integer;'#10 +                       // 9
    'begin'#10 +                               // 10
    '  X := L.Doppelt + 1;'#10 +               // 11
    '  Zeige(X);'#10 +                         // 12
    '  L.Zugang(X);'#10 +                      // 13
    'end;'#10 +                                // 14
    'end.'#10;

function ReadFile(const AFileName: string; out AText: string): Boolean;
begin
  Result := True;
  if SameText(AFileName, HauptFile) then
    AText := UnitHaupt
  else if SameText(AFileName, RechnerFile) then
    AText := UnitRechner
  else if SameText(AFileName, KundenFile) then
    AText := UnitKunden
  else if SameText(AFileName, LagerFile) then
    AText := UnitLager
  else if SameText(AFileName, KasseFile) then
    AText := UnitKasse
  else
    Result := False;
end;

{ TLspRefactoringsTests }

procedure TLspRefactoringsTests.WarmUpFirstUse;
begin
  Setup;
  try
    CompletionOffersWithItem;
  finally
    TearDown;
  end;
end;

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
  Result.IfExpression := True;
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
      begin
        // case vervollständigen trägt die Kennung für das Plugin (#697).
        if ATitle.StartsWith('case ') then
          Assert.AreEqual(CaseCompleteTag, Action.Tag);
        Exit(TChangeSignature.ApplyEdits(AText, Action.Edits));
      end;
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
  Assert.AreEqual('case vervollständigen (4 fehlende Werte)|In if-Kette umwandeln|', Titles(UnitHaupt, 17, 4,
    Context));
  Assert.AreEqual('with auflösen|', Titles(UnitHaupt, 25, 3, Context));
  Off := Context;
  Off.Settings.CompleteCase := False;
  Off.Settings.ResolveWith := False;
  Off.Settings.IfCase := False;
  Assert.AreEqual('', Titles(UnitHaupt, 17, 4, Off));
  Assert.AreEqual('', Titles(UnitHaupt, 25, 3, Off));
end;

procedure TLspRefactoringsTests.ConvertsCaseAndIfChain;
var
  Chain: string;
begin
  Chain := StringReplace(UnitHaupt, '  case A of'#10'    alNone: ;'#10'    alTop: ;'#10'    alBottom: ;'#10'  end;'#10,
    '  if A = alNone then'#10'    Exit'#10'  else if A in [alTop, alBottom] then'#10'    Exit;'#10, []);
  Assert.AreEqual(StringReplace(UnitHaupt, '  case A of'#10'    alNone: ;'#10'    alTop: ;'#10'    alBottom: ;'#10,
    '  case A of'#10'    alNone: Exit;'#10'    alTop, alBottom: Exit;'#10, []), Applied(Chain, 'In case umwandeln', 17,
    4));
  Assert.AreEqual('-', Applied(Chain, 'In if-Kette umwandeln', 17, 4));
end;

procedure TLspRefactoringsTests.RewritesConditions;
var
  Chain: string;
  Off: TRefactoringContext;
begin
  Chain := StringReplace(UnitHaupt, '  case A of'#10'    alNone: ;'#10'    alTop: ;'#10'    alBottom: ;'#10'  end;'#10,
    '  if A = alNone then'#10'    Exit'#10'  else if A in [alTop, alBottom] then'#10'    Exit;'#10, []);
  Assert.AreEqual(StringReplace(Chain, '  if A = alNone then'#10'    Exit'#10'  else if A in [alTop, alBottom] then'#10 +
    '    Exit;'#10, '  if A <> alNone then'#10'  begin'#10'    if A in [alTop, alBottom] then'#10'      Exit;'#10 +
    '  end'#10'  else'#10'    Exit;'#10, []), Applied(Chain, 'Bedingung umkehren', 17, 4));
  Assert.IsTrue(Pos('Bedingung umkehren|', Titles(Chain, 17, 4, Context)) > 0);
  Off := Context;
  Off.Settings.Conditions := False;
  Assert.AreEqual(0, Pos('Bedingung umkehren', Titles(Chain, 17, 4, Off)));
end;

procedure TLspRefactoringsTests.ConvertsConditionalExpression;
const
  CaseText = '  case A of'#10'    alNone: ;'#10'    alTop: ;'#10'    alBottom: ;'#10'  end;'#10;
var
  Statement, Expression: string;
  Old: TRefactoringContext;
begin
  Statement := StringReplace(UnitHaupt, CaseText, '  if A = alNone then'#10'    Zeige(alTop)'#10'  else'#10 +
    '    Zeige(alLeft);'#10, []);
  Expression := StringReplace(UnitHaupt, CaseText, '  Zeige(if A = alNone then alTop else alLeft);'#10, []);
  // Die Aufzählungswerte haben über die Namensauflösung denselben Typ.
  Assert.AreEqual(Expression, Applied(Statement, 'In bedingten Ausdruck umwandeln', 17, 3));
  Assert.AreEqual(Statement, Applied(Expression, 'In if-Anweisung umwandeln', 17, 9));
  // Delphi 12: nur der Rückweg.
  Old := Context;
  Old.IfExpression := False;
  Assert.AreEqual(0, Pos('In bedingten Ausdruck umwandeln', Titles(Statement, 17, 3, Old)));
  Assert.IsTrue(Pos('In if-Anweisung umwandeln|', Titles(Expression, 17, 9, Old)) > 0);
  Old := Context;
  Old.Settings.ConditionalExpression := False;
  Assert.AreEqual(0, Pos('In bedingten Ausdruck umwandeln', Titles(Statement, 17, 3, Old)));
  Assert.AreEqual(0, Pos('In if-Anweisung umwandeln', Titles(Expression, 17, 9, Old)));
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

/// <summary>Code-Aktion mit ATitle an ALine:ACharacter von UnitRechner; False ohne.</summary>
function RechnerAction(const AContext: TRefactoringContext; ALine, ACharacter: Integer; const ATitle: string;
  out AAction: TCodeAction): Boolean;
var
  Tree: TSyntaxTree;
  Action: TCodeAction;
begin
  Result := False;
  AAction := Default(TCodeAction);
  Tree := TPascalParser.Parse(UnitRechner);
  try
    for Action in TLspRefactorings.Actions(Tree, UnitRechner, TTextRange.Create(TTextPosition.Create(ALine,
      ACharacter), TTextPosition.Create(ALine, ACharacter)), AContext) do
      if Action.Title = ATitle then
      begin
        AAction := Action;
        Exit(True);
      end;
  finally
    Tree.Free;
  end;
end;

procedure AddRechnerUnits(const AIndex: ISymbolIndex);
var
  Bib: TUnitIndex;
begin
  AIndex.AddUnit(TIndexExtractor.ExtractText(UnitRechner, RechnerFile, nil));
  AIndex.AddUnit(TIndexExtractor.ExtractText(UnitKunden, KundenFile, nil));
  Bib := TIndexExtractor.ExtractText(UnitBib, BibFile, nil);
  Bib.Library_ := True;
  AIndex.AddUnit(Bib);
end;

procedure TLspRefactoringsTests.CreatesMethodFromCall;
var
  Rechner: TRefactoringContext;
  Action: TCodeAction;
  Result_: string;
begin
  AddRechnerUnits(FIndex);
  Rechner := Context;
  Rechner.FileName := RechnerFile;
  // Abnahmefall: Total: Currency, Customer: TCustomer, 0.1 ist ein Satz.
  Assert.IsTrue(RechnerAction(Rechner, 14, 13, 'Methode CalcDiscount anlegen', Action));
  Result_ := TChangeSignature.ApplyEdits(UnitRechner, Action.Edits);
  Assert.IsTrue(Result_.Contains('  private'#10'    function CalcDiscount(Customer: TCustomer; Rate: Double): ' +
    'Currency;'#10'  end;'), Result_);
  Assert.IsTrue(Result_.Contains(#10'function TRechner.CalcDiscount(Customer: TCustomer; Rate: Double): Currency;' +
    #10'begin'#10#10'end;'), Result_);
  // Ohne Zuweisung eine Prozedur; string als const.
  Assert.IsTrue(RechnerAction(Rechner, 15, 4, 'Methode Protokolliere anlegen', Action));
  Assert.IsTrue(TChangeSignature.ApplyEdits(UnitRechner, Action.Edits).Contains(
    'procedure Protokolliere(const Name: string);'), TChangeSignature.ApplyEdits(UnitRechner, Action.Edits));
  Rechner.Settings.ConstParameters := False;
  Assert.IsTrue(RechnerAction(Rechner, 15, 4, 'Methode Protokolliere anlegen', Action));
  Assert.IsTrue(TChangeSignature.ApplyEdits(UnitRechner, Action.Edits).Contains(
    'procedure Protokolliere(Name: string);'), TChangeSignature.ApplyEdits(UnitRechner, Action.Edits));
  // Klasse aus einer Bibliothek: kein Angebot.
  Assert.IsFalse(RechnerAction(Rechner, 16, 10, 'Methode Sortiere in TBibListe anlegen', Action));
  // Klasse einer anderen Unit des Projekts: dort public, als Änderung der anderen Datei.
  Assert.IsTrue(RechnerAction(Rechner, 17, 13, 'Methode Pruefe in TCustomer anlegen', Action));
  Assert.AreEqual(0, Integer(Length(Action.Edits)));
  Assert.AreEqual(1, Integer(Length(Action.FileEdits)));
  Assert.AreEqual(KundenFile, Action.FileEdits[0].FileName);
  Result_ := TChangeSignature.ApplyEdits(UnitKunden, Action.FileEdits[0].Edits);
  Assert.IsTrue(Result_.Contains('    Name: string;'#10'    procedure Pruefe(Total: Currency);'#10'  end;'), Result_);
  Assert.IsTrue(Result_.Contains('procedure TCustomer.Pruefe(Total: Currency);'), Result_);
  // Bekannter Name und abgeschaltet: nichts.
  Assert.IsFalse(RechnerAction(Rechner, 18, 4, 'Methode Rechne anlegen', Action));
  Rechner.Settings.CreateMethod := False;
  Assert.IsFalse(RechnerAction(Rechner, 14, 13, 'Methode CalcDiscount anlegen', Action));
end;

procedure TLspRefactoringsTests.CompletionOffersCreateAfterParen;
var
  Store: IDocumentStore;
  Completion: TLspCompletion;
  Dispatcher: TJsonRpcDispatcher;
  Uri, Text, Answer: string;
  Enabled: Boolean;

  function Ask(ALine, ACharacter: Integer; const ATrigger: string): string;
  var
    Request, Response: TJSONObject;
    Trigger: string;
  begin
    Trigger := '';
    if ATrigger <> '' then
      Trigger := ',"context":{"triggerKind":2,"triggerCharacter":"' + ATrigger + '"}';
    Request := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":1,"method":"textDocument/completion",' +
      '"params":{"textDocument":{"uri":"' + Uri.Replace('\', '\\') + '"},"position":{"line":' + IntToStr(ALine) +
      ',"character":' + IntToStr(ACharacter) + '}' + Trigger + '}}') as TJSONObject;
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
  AddRechnerUnits(FIndex);
  // Zeile 14 gerade getippt: "  Total := CalcDiscount(" ohne Argumente.
  Text := StringReplace(UnitRechner, '  Total := CalcDiscount(Customer, 0.1);', '  Total := CalcDiscount(', []);
  Uri := TDocumentUris.FromPath(RechnerFile);
  Store := TDocumentStore.Create;
  Store.Open(Uri, 'delphi', 1, Text);
  Enabled := True;
  Completion := TLspCompletion.Create(Store, FIndex);
  Dispatcher := TJsonRpcDispatcher.Create;
  try
    Completion.CreateFor :=
      function(ARequest: TCompletionRequest; out ATitle, ADetail: string; out AEdits: TArray<TTextEdit>): Boolean
      var
        Rechner: TRefactoringContext;
        Created: TCreatedMethod;
      begin
        Rechner := Context;
        Rechner.FileName := RechnerFile;
        Rechner.Settings.CreateMethodCaretInBody := True;
        Result := Enabled and TLspRefactorings.CreateMethod(ARequest.Resolver, ARequest.Tree, ARequest.Text,
          ARequest.Position, Rechner, True, Created);
        ATitle := Created.Title;
        ADetail := Created.Detail;
        AEdits := Created.Edits;
      end;
    Completion.Attach(Dispatcher);
    Answer := Ask(14, 24, '(');
    Assert.IsTrue(Answer.Contains('"label":"Methode CalcDiscount anlegen"'), Answer);
    Assert.IsTrue(Answer.Contains('function CalcDiscount: Currency'), Answer);
    // Cursor danach im Rumpf.
    Assert.IsTrue(Answer.Contains('begin\n  $0\nend;'), Answer);
    Assert.IsTrue(Answer.Contains('"action":"create"'), Answer);
    // Bekannter Name nach "(": leere Liste.
    Answer := Ask(18, 9, '(');
    Assert.IsFalse(Answer.Contains('anlegen'), Answer);
    Enabled := False;
    Answer := Ask(14, 24, '(');
    Assert.IsFalse(Answer.Contains('anlegen'), Answer);
  finally
    Dispatcher.Free;
    Completion.Free;
  end;
end;

procedure TLspRefactoringsTests.InlinesOverTheIndex;
var
  Kasse: TRefactoringContext;
  Tree: TSyntaxTree;
  Action: TCodeAction;
  Titles_, Result_: string;

  function Run(ALine, ACharacter: Integer; const ATitle: string): string;
  var
    Item: TCodeAction;
  begin
    Result := '-';
    Titles_ := '';
    for Item in TLspRefactorings.Actions(Tree, UnitKasse, TTextRange.Create(TTextPosition.Create(ALine, ACharacter),
      TTextPosition.Create(ALine, ACharacter)), Kasse) do
    begin
      Titles_ := Titles_ + Item.Title + '|';
      if Item.Title = ATitle then
        Result := TChangeSignature.ApplyEdits(UnitKasse, Item.Edits);
    end;
  end;

begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitLager, LagerFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitKasse, KasseFile, nil));
  Kasse := Context;
  Kasse.FileName := KasseFile;
  Tree := TPascalParser.Parse(UnitKasse);
  try
    // Experimentell: ohne Schalter nichts.
    Assert.AreEqual('-', Run(11, 10, 'Methode Doppelt einbetten'));
    Kasse.Settings.InlineCode := True;
    // Öffentliches Feld aus der anderen Unit: mit dem Empfänger eingesetzt.
    Result_ := Run(11, 10, 'Methode Doppelt einbetten');
    Assert.AreEqual(StringReplace(UnitKasse, 'X := L.Doppelt + 1;', 'X := (L.Anzahl * 2) + 1;', []), Result_);
    // Privates Feld einer anderen Unit: kein Angebot.
    Assert.AreEqual('-', Run(13, 5, 'Methode Zugang einbetten'));
    // Die Variable: Der Ausdruck ruft auf, wird aber nur einmal und ohne Lesen davor gebraucht. L.Zugang(X) kennt
    // die Datenflussanalyse nicht; X könnte dort ein var-Argument sein, also kein Angebot.
    Assert.AreEqual('-', Run(9, 2, 'Variable X einbetten'), Titles_);
    Result_ := StringReplace(UnitKasse, '  L.Zugang(X);'#10, '', []);
    Tree.Free;
    Tree := TPascalParser.Parse(Result_);
    for Action in TLspRefactorings.Actions(Tree, Result_, TTextRange.Create(TTextPosition.Create(9, 2),
      TTextPosition.Create(9, 2)), Kasse) do
      if Action.Title = 'Variable X einbetten' then
        Titles_ := TChangeSignature.ApplyEdits(Result_, Action.Edits);
    Assert.AreEqual(StringReplace(StringReplace(Result_, 'var'#10'  X: Integer;'#10, '', []),
      '  X := L.Doppelt + 1;'#10'  Zeige(X);', '  Zeige(L.Doppelt + 1);', []), Titles_);
  finally
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspRefactoringsTests);

end.
