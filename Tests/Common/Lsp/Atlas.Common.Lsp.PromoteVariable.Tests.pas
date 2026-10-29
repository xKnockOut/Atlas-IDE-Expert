unit Atlas.Common.Lsp.PromoteVariable.Tests;

// „Lokale Variable und Feld umwandeln“ über das Protokoll (#668): Code-Aktion
// mit Client-Befehl und Vorschlag, Antwort des Server-Befehls, Fehler mit
// Grund, Typ einer Inline-Variablen und geerbte Mitglieder über die
// Namensauflösung, Formulardatei über ReadText.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract;

type
  [TestFixture]
  TLspPromoteVariableTests = class
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
    procedure ExecuteAnswersEditAndCounts;
    [Test]
    procedure ConflictIsAnError;
    [Test]
    procedure ResolverSuppliesTypesAndAncestors;
    [Test]
    procedure FormFieldIsNotOffered;
    [Test]
    procedure MentionsWholeWords;
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
  Atlas.Common.Editing.PromoteVariable,
  Atlas.Common.Lsp.PromoteVariable;

const
  FileName = 'C:\P\Haupt.pas';
  FormFile = 'C:\P\Haupt.dfm';
  Text =
    'unit Haupt;'#10 +                              // 0
    'interface'#10 +                                // 1
    'type'#10 +                                     // 2
    '  TBasis = class'#10 +                         // 3
    '  public'#10 +                                 // 4
    '    FGeerbt: Integer; constructor Create;'#10 + // 5
    '  end;'#10 +                                   // 6
    '  TKunde = class(TBasis)'#10 +                 // 7
    '  private'#10 +                                // 8
    '    FLabel: Integer;'#10 +                     // 9
    '  public'#10 +                                 // 10
    '    procedure Run;'#10 +                       // 11
    '  end;'#10 +                                   // 12
    'implementation'#10 +                           // 13
    'procedure TKunde.Run;'#10 +                    // 14
    'var'#10 +                                      // 15
    '  LTotal: Integer;'#10 +                       // 16
    'begin'#10 +                                    // 17
    '  LTotal := 1;'#10 +                           // 18
    '  var LNeu := TKunde.Create;'#10 +             // 19
    '  LNeu.Free;'#10 +                             // 20
    '  FLabel := LTotal;'#10 +                      // 21
    'end;'#10 +                                     // 22
    'end.'#10;

function ReadFile(const AFileName: string; out AText: string): Boolean;
begin
  Result := SameText(AFileName, FormFile);
  if Result then
    AText := 'object Kunde: TKunde'#10'  object FLabel: TLabel'#10'  end'#10'end'#10;
end;

procedure TLspPromoteVariableTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(Text, FileName, nil));
end;

procedure TLspPromoteVariableTests.TearDown;
begin
  FIndex := nil;
end;

/// <summary>Aktionen an ALine/ACharacter mit Namensauflösung.</summary>
function ActionsAt(const AIndex: ISymbolIndex; ALine, ACharacter: Integer): TArray<TJSONObject>;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
begin
  Tree := TPascalParser.Parse(Text);
  Resolver := TNameResolver.Create(AIndex);
  try
    Resolver.PinTree(Tree, FileName);
    try
      Result := TLspPromoteVariable.Actions(Tree, Text, TDocumentUris.FromPath(FileName), TTextPosition.Create(ALine,
        ACharacter), TLspPromoteVariable.Lookup(Resolver, Tree, FileName, ReadFile));
    finally
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

/// <summary>Antwort von atlas.server.promoteVariable an ALine/ACharacter mit dem Namen AName.</summary>
function ExecuteAt(const AIndex: ISymbolIndex; ALine, ACharacter: Integer; const AName: string): TJSONObject;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
begin
  Tree := TPascalParser.Parse(Text);
  Resolver := TNameResolver.Create(AIndex);
  try
    Resolver.PinTree(Tree, FileName);
    try
      Result := TLspPromoteVariable.Execute(Tree, Text, TDocumentUris.FromPath(FileName), TTextPosition.Create(ALine,
        ACharacter), AName, TLspPromoteVariable.Lookup(Resolver, Tree, FileName, ReadFile), TFormatStyle.Default);
    finally
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

procedure TLspPromoteVariableTests.ActionCarriesClientCommand;
var
  Actions: TArray<TJSONObject>;
  Action: TJSONObject;
  Arguments: TJSONArray;
begin
  Actions := ActionsAt(FIndex, 16, 3);
  try
    Assert.AreEqual(1, Integer(Length(Actions)));
    Assert.AreEqual(TLspPromoteVariable.Kind, Actions[0].GetValue<string>('kind'));
    Assert.IsTrue(Actions[0].GetValue<string>('title').StartsWith(TPromoteVariable.ToFieldTitle + ' (LTotal'));
    Assert.AreEqual(TLspPromoteVariable.ClientCommand, Actions[0].GetValue<string>('command.command'));
    Arguments := Actions[0].GetValue<TJSONArray>('command.arguments');
    Assert.AreEqual(3, Arguments.Count);
    Assert.AreEqual(TDocumentUris.FromPath(FileName), Arguments.Items[0].Value);
    Assert.AreEqual(16, Arguments.Items[1].GetValue<Integer>('line'));
    Assert.AreEqual('FTotal', Arguments.Items[2].Value);
  finally
    for Action in Actions do
      Action.Free;
  end;
  // Im Rumpf ohne Variable: nichts.
  Actions := ActionsAt(FIndex, 17, 1);
  Assert.AreEqual(0, Integer(Length(Actions)));
end;

procedure TLspPromoteVariableTests.ExecuteAnswersEditAndCounts;
var
  Answer, Changes: TJSONObject;
  Edits: TJSONArray;
begin
  Answer := ExecuteAt(FIndex, 16, 3, 'FSumme');
  try
    Changes := Answer.GetValue<TJSONObject>('edit').GetValue('changes') as TJSONObject;
    Assert.AreEqual(1, Changes.Count);
    Assert.AreEqual(TDocumentUris.FromPath(FileName), Changes.Pairs[0].JsonString.Value);
    Edits := Changes.Pairs[0].JsonValue as TJSONArray;
    Assert.IsTrue(Edits.Count >= 4, Answer.ToJSON);
    // Zwei Verwendungen und die beiden Deklarationen.
    Assert.AreEqual(4, Answer.GetValue<Integer>('places'));
    Assert.AreEqual(1, Answer.GetValue<Integer>('files'));
    Assert.AreEqual(0, Answer.GetValue<TJSONArray>('warnings').Count);
  finally
    Answer.Free;
  end;
end;

procedure TLspPromoteVariableTests.ConflictIsAnError;
begin
  Assert.WillRaise(
    procedure
    begin
      ExecuteAt(FIndex, 16, 3, 'FLabel').Free;
    end, EJsonRpcError);
  Assert.WillRaise(
    procedure
    begin
      ExecuteAt(FIndex, 16, 3, 'begin').Free;
    end, EJsonRpcError);
end;

procedure TLspPromoteVariableTests.ResolverSuppliesTypesAndAncestors;
var
  Answer: TJSONObject;
begin
  // Inline-Variable ohne Typangabe: TKunde über die Ableitung; erzeugt und freigegeben: Warnung.
  Answer := ExecuteAt(FIndex, 19, 7, 'FNeu');
  try
    Assert.IsTrue(Pos('FNeu: TKunde;', Answer.ToJSON) > 0, Answer.ToJSON);
    Assert.AreEqual(1, Answer.GetValue<TJSONArray>('warnings').Count);
  finally
    Answer.Free;
  end;
  // Geerbtes Feld der Basisklasse.
  Assert.WillRaise(
    procedure
    begin
      ExecuteAt(FIndex, 16, 3, 'FGeerbt').Free;
    end, EJsonRpcError);
end;

procedure TLspPromoteVariableTests.FormFieldIsNotOffered;
begin
  // FLabel steht in Haupt.dfm: kein „In lokale Variable umwandeln“.
  Assert.AreEqual(0, Integer(Length(ActionsAt(FIndex, 9, 5))));
end;

procedure TLspPromoteVariableTests.MentionsWholeWords;
begin
  Assert.IsTrue(TLspPromoteVariable.MentionsWord('object FLabel: TLabel', 'flabel'));
  Assert.IsTrue(TLspPromoteVariable.MentionsWord('FLabel', 'FLabel'));
  Assert.IsFalse(TLspPromoteVariable.MentionsWord('object FLabel2: TLabel', 'FLabel'));
  Assert.IsFalse(TLspPromoteVariable.MentionsWord('object XFLabel: TLabel', 'FLabel'));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspPromoteVariableTests);

end.
