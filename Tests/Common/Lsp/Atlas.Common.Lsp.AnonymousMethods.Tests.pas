unit Atlas.Common.Lsp.AnonymousMethods.Tests;

// „Anonyme Methode und Methode umwandeln“ über das Protokoll (#680): Code-Aktion
// mit Client-Befehl und Vorschlag, Antwort des Server-Befehls mit Vorschau,
// Fehler mit Grund, Form nach der Einstellung, Zieltypen über die
// Namensauflösung (reference to, of object, Alias) beim Einbetten, Ereignis
// in der Formulardatei.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract;

type
  [TestFixture]
  TLspAnonymousMethodsTests = class
  private
    FIndex: ISymbolIndex;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ActionCarriesClientCommand;
    [Test]
    procedure ExecuteAnswersEditAndPreview;
    [Test]
    procedure ConflictIsAnError;
    [Test]
    procedure EmbedFollowsTargetType;
    [Test]
    procedure EmbedSkipsFormEvent;
    [Test]
    procedure CaptureSetting;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.AnonymousMethods,
  Atlas.Common.Lsp.AnonymousMethods;

const
  cFileName = 'C:\P\Haupt.pas';
  cFormFile = 'C:\P\Haupt.dfm';
  cText =
    'unit Haupt;'#10 +                                               // 0
    'interface'#10 +                                                 // 1
    'type'#10 +                                                      // 2
    '  TAktion = reference to procedure(const AWert: Integer);'#10 + // 3
    '  TEreignis = procedure(Sender: TObject) of object;'#10 +       // 4
    '  TListe = class'#10 +                                          // 5
    '  public'#10 +                                                  // 6
    '    procedure ForEach(const AAktion: TAktion);'#10 +            // 7
    '    property OnTick: TEreignis read FOnTick write FOnTick;'#10 + // 8
    '  end;'#10 +                                                    // 9
    '  TKunde = class'#10 +                                          // 10
    '  private'#10 +                                                 // 11
    '    FListe: TListe;'#10 +                                       // 12
    '    FSumme: Integer;'#10 +                                      // 13
    '    procedure Addiere(const AWert: Integer);'#10 +              // 14
    '    procedure Tick(Sender: TObject);'#10 +                      // 15
    '    procedure Knopf(Sender: TObject);'#10 +                     // 16
    '  public'#10 +                                                  // 17
    '    procedure Run;'#10 +                                        // 18
    '  end;'#10 +                                                    // 19
    'implementation'#10 +                                            // 20
    'procedure TKunde.Run;'#10 +                                     // 21
    'begin'#10 +                                                     // 22
    '  FListe.ForEach(Addiere);'#10 +                                // 23
    '  FListe.OnTick := Tick;'#10 +                                  // 24
    '  FListe.ForEach(procedure(const AWert: Integer) begin FSumme := AWert; end);'#10 + // 25
    '  FListe.OnTick := Knopf;'#10 +                                 // 26
    'end;'#10 +                                                      // 27
    'procedure TKunde.Addiere(const AWert: Integer);'#10 +           // 28
    'begin'#10 +                                                     // 29
    '  FSumme := FSumme + AWert;'#10 +                               // 30
    'end;'#10 +                                                      // 31
    'procedure TKunde.Tick(Sender: TObject);'#10 +                   // 32
    'begin'#10 +                                                     // 33
    'end;'#10 +                                                      // 34
    'procedure TKunde.Knopf(Sender: TObject);'#10 +                  // 35
    'begin'#10 +                                                     // 36
    'end;'#10 +                                                      // 37
    'end.'#10;

function ReadFile(const AFileName: string; out AText: string): Boolean;
begin
  Result := SameText(AFileName, cFormFile);
  if Result then
  begin
    AText := 'object Kunde: TKunde'#10'  OnClick = Knopf'#10'end'#10;
  end;
end;

procedure TLspAnonymousMethodsTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cText, cFileName, nil));
end;

procedure TLspAnonymousMethodsTests.TearDown;
begin
  FIndex := nil;
end;

/// <summary>Anfrage an ALine/ACharacter mit Namensauflösung über AResolver.</summary>
function RequestAt(AResolver: TNameResolver; ATree: TSyntaxTree; ALine, ACharacter: Integer): TAnonymousMethodRequest;
begin
  Result := Default(TAnonymousMethodRequest);
  Result.Tree := ATree;
  Result.Text := cText;
  Result.Uri := TDocumentUris.FromPath(cFileName);
  Result.Position := TTextPosition.Create(ALine, ACharacter);
  Result.Lookup := TLspAnonymousMethods.Lookup(AResolver, ATree, cFileName, ReadFile);
  Result.Capture := TDeferredCapture.Forward;
  Result.Style := TFormatStyle.Default;
end;

/// <summary>Aktionen an ALine/ACharacter mit Namensauflösung.</summary>
function ActionsAt(const AIndex: ISymbolIndex; ALine, ACharacter: Integer): TArray<TJSONObject>;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
begin
  mTree := TPascalParser.Parse(cText);
  mResolver := TNameResolver.Create(AIndex);
  try
    mResolver.PinTree(mTree, cFileName);
    try
      Result := TLspAnonymousMethods.Actions(RequestAt(mResolver, mTree, ALine, ACharacter));
    finally
      mResolver.UnpinTree;
    end;
  finally
    mResolver.Free;
    mTree.Free;
  end;
end;

/// <summary>Antwort von atlas.server.anonymousMethod an ALine/ACharacter mit dem Namen AName.</summary>
function ExecuteAt(const AIndex: ISymbolIndex; ALine, ACharacter: Integer; const AName: string): TJSONObject;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
begin
  mTree := TPascalParser.Parse(cText);
  mResolver := TNameResolver.Create(AIndex);
  try
    mResolver.PinTree(mTree, cFileName);
    try
      Result := TLspAnonymousMethods.Execute(RequestAt(mResolver, mTree, ALine, ACharacter), AName);
    finally
      mResolver.UnpinTree;
    end;
  finally
    mResolver.Free;
    mTree.Free;
  end;
end;

procedure FreeAll(const AActions: TArray<TJSONObject>);
var
  mAction: TJSONObject;
begin
  for mAction in AActions do
  begin
    mAction.Free;
  end;
end;

procedure TLspAnonymousMethodsTests.ActionCarriesClientCommand;
var
  mActions: TArray<TJSONObject>;
  mArguments: TJSONArray;
begin
  mActions := ActionsAt(FIndex, 25, 18);
  try
    Assert.AreEqual(1, Integer(Length(mActions)));
    Assert.AreEqual(TLspAnonymousMethods.cKind, mActions[0].GetValue<string>('kind'));
    Assert.AreEqual('In Methode umwandeln (ProcessItem)', mActions[0].GetValue<string>('title'));
    Assert.AreEqual(TLspAnonymousMethods.cClientCommand, mActions[0].GetValue<string>('command.command'));
    mArguments := mActions[0].GetValue<TJSONArray>('command.arguments');
    Assert.AreEqual(3, mArguments.Count);
    Assert.AreEqual(TDocumentUris.FromPath(cFileName), mArguments.Items[0].Value);
    Assert.AreEqual(25, mArguments.Items[1].GetValue<Integer>('line'));
    Assert.AreEqual('ProcessItem', mArguments.Items[2].Value);
  finally
    FreeAll(mActions);
  end;
  // Im Rumpf: nichts.
  mActions := ActionsAt(FIndex, 25, 58);
  Assert.AreEqual(0, Integer(Length(mActions)));
end;

procedure TLspAnonymousMethodsTests.ExecuteAnswersEditAndPreview;
var
  mAnswer: TJSONObject;
begin
  mAnswer := ExecuteAt(FIndex, 25, 18, 'Merke');
  try
    Assert.IsTrue(Pos('"newText":"Merke"', mAnswer.ToJSON) > 0, mAnswer.ToJSON);
    Assert.IsTrue(Pos('end;\n\n"', mAnswer.ToJSON) > 0, mAnswer.ToJSON);
    Assert.IsTrue(Pos('procedure TKunde.Merke(const AWert: Integer);', mAnswer.ToJSON) > 0, mAnswer.ToJSON);
    Assert.IsTrue(mAnswer.GetValue<string>('preview').StartsWith('Neue Methode: '), mAnswer.ToJSON);
    Assert.AreEqual(1, mAnswer.GetValue<Integer>('files'));
    Assert.AreEqual(0, mAnswer.GetValue<TJSONArray>('warnings').Count);
  finally
    mAnswer.Free;
  end;
end;

procedure TLspAnonymousMethodsTests.ConflictIsAnError;
begin
  Assert.WillRaise(
    procedure
    begin
      ExecuteAt(FIndex, 25, 18, 'Addiere').Free;
    end, EJsonRpcError);
  Assert.WillRaise(
    procedure
    begin
      ExecuteAt(FIndex, 25, 18, 'end').Free;
    end, EJsonRpcError);
end;

procedure TLspAnonymousMethodsTests.EmbedFollowsTargetType;
var
  mActions: TArray<TJSONObject>;
begin
  // Addiere geht an TAktion (reference to): einbetten mit Vorschau.
  mActions := ActionsAt(FIndex, 28, 18);
  try
    Assert.AreEqual(1, Integer(Length(mActions)));
    Assert.AreEqual(TAnonymousMethods.EmbedTitle, mActions[0].GetValue<string>('title'));
    Assert.AreNotEqual('', mActions[0].GetValue<string>('data.preview'), mActions[0].ToJSON);
    Assert.IsTrue(Pos('procedure(const AWert: Integer)', mActions[0].ToJSON) > 0, mActions[0].ToJSON);
  finally
    FreeAll(mActions);
  end;
  // Tick geht an TEreignis (of object): nicht.
  mActions := ActionsAt(FIndex, 32, 18);
  Assert.AreEqual(0, Integer(Length(mActions)));
end;

procedure TLspAnonymousMethodsTests.EmbedSkipsFormEvent;
begin
  // Knopf steht in Haupt.dfm.
  Assert.AreEqual(0, Integer(Length(ActionsAt(FIndex, 35, 18))));
end;

procedure TLspAnonymousMethodsTests.CaptureSetting;
begin
  Assert.AreEqual(Ord(TDeferredCapture.Fields), Ord(TLspAnonymousMethods.CaptureOf('fields')));
  Assert.AreEqual(Ord(TDeferredCapture.Forward), Ord(TLspAnonymousMethods.CaptureOf('forward')));
  Assert.AreEqual(Ord(TDeferredCapture.Forward), Ord(TLspAnonymousMethods.CaptureOf('')));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspAnonymousMethodsTests);

end.
