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
  cFileName = 'C:\P\Haupt.pas';
  cFormFile = 'C:\P\Haupt.dfm';
  cText =
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
  Result := SameText(AFileName, cFormFile);
  if Result then
  begin
    AText := 'object Kunde: TKunde'#10'  object FLabel: TLabel'#10'  end'#10'end'#10;
  end;
end;

procedure TLspPromoteVariableTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cText, cFileName, nil));
end;

procedure TLspPromoteVariableTests.TearDown;
begin
  FIndex := nil;
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
      Result := TLspPromoteVariable.Actions(mTree, cText, TDocumentUris.FromPath(cFileName), TTextPosition.Create(ALine,
        ACharacter), TLspPromoteVariable.Lookup(mResolver, mTree, cFileName, ReadFile));
    finally
      mResolver.UnpinTree;
    end;
  finally
    mResolver.Free;
    mTree.Free;
  end;
end;

/// <summary>Antwort von atlas.server.promoteVariable an ALine/ACharacter mit dem Namen AName.</summary>
function ExecuteAt(const AIndex: ISymbolIndex; ALine, ACharacter: Integer; const AName: string): TJSONObject;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mContext: TPromoteVariableContext;
begin
  mTree := TPascalParser.Parse(cText);
  mResolver := TNameResolver.Create(AIndex);
  try
    mResolver.PinTree(mTree, cFileName);
    try
      mContext.Lookup := TLspPromoteVariable.Lookup(mResolver, mTree, cFileName, ReadFile);
      mContext.Style := TFormatStyle.Default;
      mContext.NewName := AName;
      Result := TLspPromoteVariable.Execute(mTree, cText, TDocumentUris.FromPath(cFileName), TTextPosition.Create(ALine,
        ACharacter), mContext);
    finally
      mResolver.UnpinTree;
    end;
  finally
    mResolver.Free;
    mTree.Free;
  end;
end;

procedure TLspPromoteVariableTests.ActionCarriesClientCommand;
var
  mActions: TArray<TJSONObject>;
  mAction: TJSONObject;
  mArguments: TJSONArray;
begin
  mActions := ActionsAt(FIndex, 16, 3);
  try
    Assert.AreEqual(1, Integer(Length(mActions)));
    Assert.AreEqual(TLspPromoteVariable.cKind, mActions[0].GetValue<string>('kind'));
    Assert.IsTrue(mActions[0].GetValue<string>('title').StartsWith(TPromoteVariable.ToFieldTitle + ' (LTotal'));
    Assert.AreEqual(TLspPromoteVariable.cClientCommand, mActions[0].GetValue<string>('command.command'));
    mArguments := mActions[0].GetValue<TJSONArray>('command.arguments');
    Assert.AreEqual(3, mArguments.Count);
    Assert.AreEqual(TDocumentUris.FromPath(cFileName), mArguments.Items[0].Value);
    Assert.AreEqual(16, mArguments.Items[1].GetValue<Integer>('line'));
    Assert.AreEqual('FTotal', mArguments.Items[2].Value);
  finally
    for mAction in mActions do
    begin
      mAction.Free;
    end;
  end;
  // Im Rumpf ohne Variable: nichts.
  mActions := ActionsAt(FIndex, 17, 1);
  Assert.AreEqual(0, Integer(Length(mActions)));
end;

procedure TLspPromoteVariableTests.ExecuteAnswersEditAndCounts;
var
  mAnswer, mChanges: TJSONObject;
  mEdits: TJSONArray;
begin
  mAnswer := ExecuteAt(FIndex, 16, 3, 'FSumme');
  try
    mChanges := mAnswer.GetValue<TJSONObject>('edit').GetValue('changes') as TJSONObject;
    Assert.AreEqual(1, mChanges.Count);
    Assert.AreEqual(TDocumentUris.FromPath(cFileName), mChanges.Pairs[0].JsonString.Value);
    mEdits := mChanges.Pairs[0].JsonValue as TJSONArray;
    Assert.IsTrue(mEdits.Count >= 4, mAnswer.ToJSON);
    // Zwei Verwendungen und die beiden Deklarationen.
    Assert.AreEqual(4, mAnswer.GetValue<Integer>('places'));
    Assert.AreEqual(1, mAnswer.GetValue<Integer>('files'));
    Assert.AreEqual(0, mAnswer.GetValue<TJSONArray>('warnings').Count);
  finally
    mAnswer.Free;
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
  mAnswer: TJSONObject;
begin
  // Inline-Variable ohne Typangabe: TKunde über die Ableitung; erzeugt und freigegeben: Warnung.
  mAnswer := ExecuteAt(FIndex, 19, 7, 'FNeu');
  try
    Assert.IsTrue(Pos('FNeu: TKunde;', mAnswer.ToJSON) > 0, mAnswer.ToJSON);
    Assert.AreEqual(1, mAnswer.GetValue<TJSONArray>('warnings').Count);
  finally
    mAnswer.Free;
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

initialization
  TDUnitX.RegisterTestFixture(TLspPromoteVariableTests);

end.
