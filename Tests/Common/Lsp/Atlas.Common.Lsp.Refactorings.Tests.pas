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
    /// <summary>Lokale Routine herauslösen (#663): Record über die Namensauflösung als const, Vorschau,
    /// abschaltbar.</summary>
    [Test]
    procedure ExtractsNestedRoutine;
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
  Atlas.Common.Editing.NestedRoutines,
  Atlas.Common.Lsp.Completion;

const
  cHauptFile = 'C:\P\Haupt.pas';

  cUnitHaupt =
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

  cRechnerFile = 'C:\P\Rechner.pas';
  cKundenFile = 'C:\P\Kunden.pas';
  cBibFile = 'C:\Lib\Bib.pas';

  cUnitRechner =
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

  cUnitKunden =
    'unit Kunden;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TCustomer = class'#10 +
    '  public'#10 +
    '    Name: string;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.'#10;

  cUnitBib =
    'unit Bib;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TBibListe = class'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.'#10;

  cLagerFile = 'C:\P\Lager.pas';
  cKasseFile = 'C:\P\Kasse.pas';

  cUnitLager =
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

  cUnitKasse =
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
  if SameText(AFileName, cHauptFile) then
  begin
    AText := cUnitHaupt;
  end
  else if SameText(AFileName, cRechnerFile) then
  begin
    AText := cUnitRechner;
  end
  else if SameText(AFileName, cKundenFile) then
  begin
    AText := cUnitKunden;
  end
  else if SameText(AFileName, cLagerFile) then
  begin
    AText := cUnitLager;
  end
  else if SameText(AFileName, cKasseFile) then
  begin
    AText := cUnitKasse;
  end
  else
  begin
    Result := False;
  end;
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
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitHaupt, cHauptFile, nil));
end;

procedure TLspRefactoringsTests.TearDown;
begin
  FIndex := nil;
end;

function TLspRefactoringsTests.Context: TRefactoringContext;
begin
  Result := Default(TRefactoringContext);
  Result.Index := FIndex;
  Result.FileName := cHauptFile;
  Result.ReadText := ReadFile;
  Result.Settings := TRefactoringSettings.Default;
  Result.InlineVar := True;
  Result.IfExpression := True;
  Result.Style := TFormatStyle.Default;
end;

function TLspRefactoringsTests.Titles(const AText: string; ALine, ACharacter: Integer;
  const AContext: TRefactoringContext): string;
var
  mTree: TSyntaxTree;
  mAction: TCodeAction;
begin
  Result := '';
  mTree := TPascalParser.Parse(AText);
  try
    for mAction in TLspRefactorings.Actions(mTree, AText, TTextRange.Create(TTextPosition.Create(ALine, ACharacter),
      TTextPosition.Create(ALine, ACharacter)), AContext) do
    begin
      Result := Result + mAction.Title + '|';
    end;
  finally
    mTree.Free;
  end;
end;

function TLspRefactoringsTests.Applied(const AText, ATitle: string; ALine, ACharacter: Integer): string;
var
  mTree: TSyntaxTree;
  mAction: TCodeAction;
begin
  Result := '-';
  mTree := TPascalParser.Parse(AText);
  try
    for mAction in TLspRefactorings.Actions(mTree, AText, TTextRange.Create(TTextPosition.Create(ALine, ACharacter),
      TTextPosition.Create(ALine, ACharacter)), Context) do
    begin
      if mAction.Title = ATitle then
      begin
        // case vervollständigen trägt die Kennung für das Plugin (#697).
        if ATitle.StartsWith('case ') then
        begin
          Assert.AreEqual(cCaseCompleteTag, mAction.Tag);
        end;
        Exit(TChangeSignature.ApplyEdits(AText, mAction.Edits));
      end;
    end;
  finally
    mTree.Free;
  end;
end;

procedure TLspRefactoringsTests.CompletesCaseOfEnumeration;
var
  mExpected: string;
begin
  // Abnahmefall: case über TAlign mit drei vorhandenen Werten ergänzt die vier fehlenden.
  mExpected := StringReplace(cUnitHaupt, '    alBottom: ;'#10,
    '    alBottom: ;'#10'    alLeft: ;'#10'    alRight: ;'#10'    alClient: ;'#10'    alCustom: ;'#10, []);
  Assert.AreEqual(mExpected, Applied(cUnitHaupt, 'case vervollständigen (4 fehlende Werte)', 17, 4));
end;

procedure TLspRefactoringsTests.ResolvesWithOverTheIndex;
begin
  // Name gehört zu TKunde (K), Ort zu TAdresse (D).
  Assert.AreEqual(StringReplace(cUnitHaupt, '  with K, D do'#10'    Name := Ort;'#10, '  K.Name := D.Ort;'#10, []),
    Applied(cUnitHaupt, 'with auflösen', 25, 3));
end;

procedure TLspRefactoringsTests.NoWithActionForUnknownNames;
begin
  // TFremd ist nirgends deklariert: ob Name dazugehört, ist offen, also rät Atlas nicht.
  Assert.AreEqual('-', Applied(cUnitHaupt, 'with auflösen', 30, 3));
end;

procedure TLspRefactoringsTests.ProbeFindsTypeAndKind;
var
  mProbe: TTypeProbe;
  mProbed: TProbedType;
  mText: string;
begin
  mProbe := TLspRefactorings.Probe(Context);
  mText := StringReplace(cUnitHaupt, '  with K, D do'#10, '  var AtlasProbe := K;'#10'  with K, D do'#10, []);
  mProbed := mProbe(mText, TTextPosition.Create(25, 6));
  Assert.AreEqual('TKunde', mProbed.Name);
  Assert.IsTrue(mProbed.IsReference);
  Assert.AreEqual('', mProbed.UnitName);
  mText := StringReplace(cUnitHaupt, '  case A of'#10, '  var AtlasProbe := A;'#10'  case A of'#10, []);
  mProbed := mProbe(mText, TTextPosition.Create(17, 6));
  Assert.AreEqual('TAlign', mProbed.Name);
  Assert.IsTrue(mProbed.IsValue);
  Assert.IsFalse(mProbed.IsReference);
end;

procedure TLspRefactoringsTests.SettingsSwitchActionsOff;
var
  mOff: TRefactoringContext;
begin
  Assert.AreEqual('case vervollständigen (4 fehlende Werte)|In if-Kette umwandeln|', Titles(cUnitHaupt, 17, 4,
    Context));
  Assert.AreEqual('with auflösen|', Titles(cUnitHaupt, 25, 3, Context));
  mOff := Context;
  mOff.Settings.CompleteCase := False;
  mOff.Settings.ResolveWith := False;
  mOff.Settings.IfCase := False;
  Assert.AreEqual('', Titles(cUnitHaupt, 17, 4, mOff));
  Assert.AreEqual('', Titles(cUnitHaupt, 25, 3, mOff));
end;

procedure TLspRefactoringsTests.ConvertsCaseAndIfChain;
var
  mChain: string;
begin
  mChain := StringReplace(cUnitHaupt, '  case A of'#10'    alNone: ;'#10'    alTop: ;'#10'    alBottom: ;'#10'  end;'#10,
    '  if A = alNone then'#10'    Exit'#10'  else if A in [alTop, alBottom] then'#10'    Exit;'#10, []);
  Assert.AreEqual(StringReplace(cUnitHaupt, '  case A of'#10'    alNone: ;'#10'    alTop: ;'#10'    alBottom: ;'#10,
    '  case A of'#10'    alNone: Exit;'#10'    alTop, alBottom: Exit;'#10, []), Applied(mChain, 'In case umwandeln', 17,
    4));
  Assert.AreEqual('-', Applied(mChain, 'In if-Kette umwandeln', 17, 4));
end;

procedure TLspRefactoringsTests.RewritesConditions;
var
  mChain: string;
  mOff: TRefactoringContext;
begin
  mChain := StringReplace(cUnitHaupt, '  case A of'#10'    alNone: ;'#10'    alTop: ;'#10'    alBottom: ;'#10'  end;'#10,
    '  if A = alNone then'#10'    Exit'#10'  else if A in [alTop, alBottom] then'#10'    Exit;'#10, []);
  Assert.AreEqual(StringReplace(mChain, '  if A = alNone then'#10'    Exit'#10'  else if A in [alTop, alBottom] then'#10 +
    '    Exit;'#10, '  if A <> alNone then'#10'  begin'#10'    if A in [alTop, alBottom] then'#10'      Exit;'#10 +
    '  end'#10'  else'#10'    Exit;'#10, []), Applied(mChain, 'Bedingung umkehren', 17, 4));
  Assert.IsTrue(Pos('Bedingung umkehren|', Titles(mChain, 17, 4, Context)) > 0);
  mOff := Context;
  mOff.Settings.Conditions := False;
  Assert.AreEqual(0, Pos('Bedingung umkehren', Titles(mChain, 17, 4, mOff)));
end;

procedure TLspRefactoringsTests.ConvertsConditionalExpression;
const
  cCaseText = '  case A of'#10'    alNone: ;'#10'    alTop: ;'#10'    alBottom: ;'#10'  end;'#10;
var
  mStatement, mExpression: string;
  mOld: TRefactoringContext;
begin
  mStatement := StringReplace(cUnitHaupt, cCaseText, '  if A = alNone then'#10'    Zeige(alTop)'#10'  else'#10 +
    '    Zeige(alLeft);'#10, []);
  mExpression := StringReplace(cUnitHaupt, cCaseText, '  Zeige(if A = alNone then alTop else alLeft);'#10, []);
  // Die Aufzählungswerte haben über die Namensauflösung denselben Typ.
  Assert.AreEqual(mExpression, Applied(mStatement, 'In bedingten Ausdruck umwandeln', 17, 3));
  Assert.AreEqual(mStatement, Applied(mExpression, 'In if-Anweisung umwandeln', 17, 9));
  // Delphi 12: nur der Rückweg.
  mOld := Context;
  mOld.IfExpression := False;
  Assert.AreEqual(0, Pos('In bedingten Ausdruck umwandeln', Titles(mStatement, 17, 3, mOld)));
  Assert.IsTrue(Pos('In if-Anweisung umwandeln|', Titles(mExpression, 17, 9, mOld)) > 0);
  mOld := Context;
  mOld.Settings.ConditionalExpression := False;
  Assert.AreEqual(0, Pos('In bedingten Ausdruck umwandeln', Titles(mStatement, 17, 3, mOld)));
  Assert.AreEqual(0, Pos('In if-Anweisung umwandeln', Titles(mExpression, 17, 9, mOld)));
end;

procedure TLspRefactoringsTests.ExtractsNestedRoutine;
const
  cText =
    'unit Haupt;'#10 +                            // 0
    'interface'#10 +                              // 1
    'type'#10 +                                   // 2
    '  TPunkt = record X: Integer; end;'#10 +     // 3
    'implementation'#10 +                         // 4
    'procedure Zeige;'#10 +                       // 5
    'var'#10 +                                    // 6
    '  P: TPunkt;'#10 +                           // 7
    '  N: Integer;'#10 +                          // 8
    #10 +                                         // 9
    '  procedure Lies;'#10 +                      // 10
    '  begin'#10 +                                // 11
    '    N := P.X;'#10 +                          // 12
    '  end;'#10 +                                 // 13
    #10 +                                         // 14
    'begin'#10 +                                  // 15
    '  Lies;'#10 +                                // 16
    'end;'#10 +                                   // 17
    'end.'#10;
var
  mDone: string;
  mOff: TRefactoringContext;
begin
  mDone := Applied(cText, TNestedRoutines.ToUnitRoutineTitle, 10, 4);
  Assert.IsTrue(Pos('procedure Lies(var N: Integer; const P: TPunkt);'#10'begin'#10'  N := P.X;', mDone) > 0, mDone);
  Assert.IsTrue(Pos('  Lies(N, P);'#10, mDone) > 0, mDone);
  Assert.IsTrue(Pos(TNestedRoutines.ToUnitRoutineTitle + '|', Titles(cText, 10, 4, Context)) > 0);
  mOff := Context;
  mOff.Settings.NestedRoutine := False;
  Assert.AreEqual(0, Pos(TNestedRoutines.ToUnitRoutineTitle, Titles(cText, 10, 4, mOff)));
end;

procedure TLspRefactoringsTests.CompletionOffersWithItem;
var
  mStore: IDocumentStore;
  mCompletion: TLspCompletion;
  mDispatcher: TJsonRpcDispatcher;
  mUri, mAnswer: string;
  mAsked: Integer;

  function Ask(ACharacter: Integer): string;
  var
    mRequest, mResponse: TJSONObject;
  begin
    mRequest := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":1,"method":"textDocument/completion",' +
      '"params":{"textDocument":{"uri":"' + mUri.Replace('\', '\\') + '"},"position":{"line":25,"character":' +
      IntToStr(ACharacter) + '}}}') as TJSONObject;
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
  mUri := TDocumentUris.FromPath(cHauptFile);
  mStore := TDocumentStore.Create;
  mStore.Open(mUri, 'delphi', 1, cUnitHaupt);
  mAsked := 0;
  mCompletion := TLspCompletion.Create(mStore, FIndex);
  mDispatcher := TJsonRpcDispatcher.Create;
  try
    mCompletion.Hooks.WithFor :=
      function(ARequest: TCompletionRequest; out AEdits: TArray<TTextEdit>): Boolean
      begin
        Inc(mAsked);
        AEdits := [TTextEdit.Create(TTextRange.Create(TTextPosition.Create(25, 2), TTextPosition.Create(26, 15)),
          'K.Name := D.Ort')];
        Result := True;
      end;
    mCompletion.Attach(mDispatcher);
    // Auf "with" (ö kommt als \u00F6): Haupteintrag entfernt das Wort, der Rest kommt als Zusatzänderung.
    mAnswer := Ask(4);
    Assert.IsTrue(mAnswer.Contains('"label":"with aufl'), mAnswer);
    Assert.IsTrue(mAnswer.Contains('K.Name := D.Ort'), mAnswer);
    Assert.AreEqual(1, mAsked);
    // Hinter dem Wort nicht.
    mAnswer := Ask(10);
    Assert.IsFalse(mAnswer.Contains('"label":"with aufl'), mAnswer);
  finally
    mDispatcher.Free;
    mCompletion.Free;
  end;
end;

/// <summary>Code-Aktion mit ATitle an ALine:ACharacter von UnitRechner; False ohne.</summary>
function RechnerAction(const AContext: TRefactoringContext; ALine, ACharacter: Integer; const ATitle: string;
  out AAction: TCodeAction): Boolean;
var
  mTree: TSyntaxTree;
  mAction: TCodeAction;
begin
  Result := False;
  AAction := Default(TCodeAction);
  mTree := TPascalParser.Parse(cUnitRechner);
  try
    for mAction in TLspRefactorings.Actions(mTree, cUnitRechner, TTextRange.Create(TTextPosition.Create(ALine,
      ACharacter), TTextPosition.Create(ALine, ACharacter)), AContext) do
    begin
      if mAction.Title = ATitle then
      begin
        AAction := mAction;
        Exit(True);
      end;
    end;
  finally
    mTree.Free;
  end;
end;

procedure AddRechnerUnits(const AIndex: ISymbolIndex);
var
  mBib: TUnitIndex;
begin
  AIndex.AddUnit(TIndexExtractor.ExtractText(cUnitRechner, cRechnerFile, nil));
  AIndex.AddUnit(TIndexExtractor.ExtractText(cUnitKunden, cKundenFile, nil));
  mBib := TIndexExtractor.ExtractText(cUnitBib, cBibFile, nil);
  mBib.Library_ := True;
  AIndex.AddUnit(mBib);
end;

procedure TLspRefactoringsTests.CreatesMethodFromCall;
var
  mRechner: TRefactoringContext;
  mAction: TCodeAction;
  mResult_: string;
begin
  AddRechnerUnits(FIndex);
  mRechner := Context;
  mRechner.FileName := cRechnerFile;
  // Abnahmefall: Total: Currency, Customer: TCustomer, 0.1 ist ein Satz.
  Assert.IsTrue(RechnerAction(mRechner, 14, 13, 'Methode CalcDiscount anlegen', mAction));
  mResult_ := TChangeSignature.ApplyEdits(cUnitRechner, mAction.Edits);
  Assert.IsTrue(mResult_.Contains('  private'#10'    function CalcDiscount(Customer: TCustomer; Rate: Double): ' +
    'Currency;'#10'  end;'), mResult_);
  Assert.IsTrue(mResult_.Contains(#10'function TRechner.CalcDiscount(Customer: TCustomer; Rate: Double): Currency;' +
    #10'begin'#10#10'end;'), mResult_);
  // Ohne Zuweisung eine Prozedur; string als const.
  Assert.IsTrue(RechnerAction(mRechner, 15, 4, 'Methode Protokolliere anlegen', mAction));
  Assert.IsTrue(TChangeSignature.ApplyEdits(cUnitRechner, mAction.Edits).Contains(
    'procedure Protokolliere(const Name: string);'), TChangeSignature.ApplyEdits(cUnitRechner, mAction.Edits));
  mRechner.Settings.ConstParameters := False;
  Assert.IsTrue(RechnerAction(mRechner, 15, 4, 'Methode Protokolliere anlegen', mAction));
  Assert.IsTrue(TChangeSignature.ApplyEdits(cUnitRechner, mAction.Edits).Contains(
    'procedure Protokolliere(Name: string);'), TChangeSignature.ApplyEdits(cUnitRechner, mAction.Edits));
  // Klasse aus einer Bibliothek: kein Angebot.
  Assert.IsFalse(RechnerAction(mRechner, 16, 10, 'Methode Sortiere in TBibListe anlegen', mAction));
  // Klasse einer anderen Unit des Projekts: dort public, als Änderung der anderen Datei.
  Assert.IsTrue(RechnerAction(mRechner, 17, 13, 'Methode Pruefe in TCustomer anlegen', mAction));
  Assert.AreEqual(0, Integer(Length(mAction.Edits)));
  Assert.AreEqual(1, Integer(Length(mAction.FileEdits)));
  Assert.AreEqual(cKundenFile, mAction.FileEdits[0].FileName);
  mResult_ := TChangeSignature.ApplyEdits(cUnitKunden, mAction.FileEdits[0].Edits);
  Assert.IsTrue(mResult_.Contains('    Name: string;'#10'    procedure Pruefe(Total: Currency);'#10'  end;'), mResult_);
  Assert.IsTrue(mResult_.Contains('procedure TCustomer.Pruefe(Total: Currency);'), mResult_);
  // Bekannter Name und abgeschaltet: nichts.
  Assert.IsFalse(RechnerAction(mRechner, 18, 4, 'Methode Rechne anlegen', mAction));
  mRechner.Settings.CreateMethod := False;
  Assert.IsFalse(RechnerAction(mRechner, 14, 13, 'Methode CalcDiscount anlegen', mAction));
end;

procedure TLspRefactoringsTests.CompletionOffersCreateAfterParen;
var
  mStore: IDocumentStore;
  mCompletion: TLspCompletion;
  mDispatcher: TJsonRpcDispatcher;
  mUri, mText, mAnswer: string;
  mEnabled: Boolean;

  function Ask(ALine, ACharacter: Integer; const ATrigger: string): string;
  var
    mRequest, mResponse: TJSONObject;
    mTrigger: string;
  begin
    mTrigger := '';
    if ATrigger <> '' then
    begin
      mTrigger := ',"context":{"triggerKind":2,"triggerCharacter":"' + ATrigger + '"}';
    end;
    mRequest := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":1,"method":"textDocument/completion",' +
      '"params":{"textDocument":{"uri":"' + mUri.Replace('\', '\\') + '"},"position":{"line":' + IntToStr(ALine) +
      ',"character":' + IntToStr(ACharacter) + '}' + mTrigger + '}}') as TJSONObject;
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
  AddRechnerUnits(FIndex);
  // Zeile 14 gerade getippt: "  Total := CalcDiscount(" ohne Argumente.
  mText := StringReplace(cUnitRechner, '  Total := CalcDiscount(Customer, 0.1);', '  Total := CalcDiscount(', []);
  mUri := TDocumentUris.FromPath(cRechnerFile);
  mStore := TDocumentStore.Create;
  mStore.Open(mUri, 'delphi', 1, mText);
  mEnabled := True;
  mCompletion := TLspCompletion.Create(mStore, FIndex);
  mDispatcher := TJsonRpcDispatcher.Create;
  try
    mCompletion.Hooks.CreateFor :=
      function(ARequest: TCompletionRequest; out ATitle, ADetail: string; out AEdits: TArray<TTextEdit>): Boolean
      var
        Rechner: TRefactoringContext;
        Created: TCreatedMethod;
      begin
        Rechner := Context;
        Rechner.FileName := cRechnerFile;
        Rechner.Settings.CreateMethodCaretInBody := True;
        Rechner.CaretMarker := True;
        Result := mEnabled and TLspRefactorings.CreateMethod(ARequest.Resolver, ARequest.Tree, ARequest.Text,
          ARequest.Position, Rechner, Created);
        ATitle := Created.Title;
        ADetail := Created.Detail;
        AEdits := Created.Edits;
      end;
    mCompletion.Attach(mDispatcher);
    mAnswer := Ask(14, 24, '(');
    Assert.IsTrue(mAnswer.Contains('"label":"Methode CalcDiscount anlegen"'), mAnswer);
    Assert.IsTrue(mAnswer.Contains('function CalcDiscount: Currency'), mAnswer);
    // Cursor danach im Rumpf.
    Assert.IsTrue(mAnswer.Contains('begin\n  $0\nend;'), mAnswer);
    Assert.IsTrue(mAnswer.Contains('"action":"create"'), mAnswer);
    // Bekannter Name nach "(": leere Liste.
    mAnswer := Ask(18, 9, '(');
    Assert.IsFalse(mAnswer.Contains('anlegen'), mAnswer);
    mEnabled := False;
    mAnswer := Ask(14, 24, '(');
    Assert.IsFalse(mAnswer.Contains('anlegen'), mAnswer);
  finally
    mDispatcher.Free;
    mCompletion.Free;
  end;
end;

procedure TLspRefactoringsTests.InlinesOverTheIndex;
var
  mKasse: TRefactoringContext;
  mTree: TSyntaxTree;
  mAction: TCodeAction;
  mTitles_, mResult_: string;

  function Run(ALine, ACharacter: Integer; const ATitle: string): string;
  var
    mItem: TCodeAction;
  begin
    Result := '-';
    mTitles_ := '';
    for mItem in TLspRefactorings.Actions(mTree, cUnitKasse, TTextRange.Create(TTextPosition.Create(ALine, ACharacter),
      TTextPosition.Create(ALine, ACharacter)), mKasse) do
    begin
      mTitles_ := mTitles_ + mItem.Title + '|';
      if mItem.Title = ATitle then
      begin
        Result := TChangeSignature.ApplyEdits(cUnitKasse, mItem.Edits);
      end;
    end;
  end;

begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitLager, cLagerFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitKasse, cKasseFile, nil));
  mKasse := Context;
  mKasse.FileName := cKasseFile;
  mTree := TPascalParser.Parse(cUnitKasse);
  try
    // Experimentell: ohne Schalter nichts.
    Assert.AreEqual('-', Run(11, 10, 'Methode Doppelt einbetten'));
    mKasse.Settings.InlineCode := True;
    // Öffentliches Feld aus der anderen Unit: mit dem Empfänger eingesetzt.
    mResult_ := Run(11, 10, 'Methode Doppelt einbetten');
    Assert.AreEqual(StringReplace(cUnitKasse, 'X := L.Doppelt + 1;', 'X := (L.Anzahl * 2) + 1;', []), mResult_);
    // Privates Feld einer anderen Unit: kein Angebot.
    Assert.AreEqual('-', Run(13, 5, 'Methode Zugang einbetten'));
    // Die Variable: Der Ausdruck ruft auf, wird aber nur einmal und ohne Lesen davor gebraucht. L.Zugang(X) kennt
    // die Datenflussanalyse nicht; X könnte dort ein var-Argument sein, also kein Angebot.
    Assert.AreEqual('-', Run(9, 2, 'Variable X einbetten'), mTitles_);
    mResult_ := StringReplace(cUnitKasse, '  L.Zugang(X);'#10, '', []);
    mTree.Free;
    mTree := TPascalParser.Parse(mResult_);
    for mAction in TLspRefactorings.Actions(mTree, mResult_, TTextRange.Create(TTextPosition.Create(9, 2),
      TTextPosition.Create(9, 2)), mKasse) do
    begin
      if mAction.Title = 'Variable X einbetten' then
      begin
        mTitles_ := TChangeSignature.ApplyEdits(mResult_, mAction.Edits);
      end;
    end;
    Assert.AreEqual(StringReplace(StringReplace(mResult_, 'var'#10'  X: Integer;'#10, '', []),
      '  X := L.Doppelt + 1;'#10'  Zeige(X);', '  Zeige(L.Doppelt + 1);', []), mTitles_);
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspRefactoringsTests);

end.
