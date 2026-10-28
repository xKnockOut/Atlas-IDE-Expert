unit Atlas.Common.Lsp.Overloads.Tests;

// Überladung anlegen über das Protokoll (#674): beide Aktionen mit
// Client-Befehl auf dem Kopf, abgeschaltete Aktion mit Grund, Antwort mit
// Änderungen und Platzhaltern, Standardwerte über die Namensauflösung
// (erstes Element einer Aufzählung, nil bei Klassen) und Fehler mit Grund.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract;

type
  [TestFixture]
  TLspOverloadsTests = class
  private
    FIndex: ISymbolIndex;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ActionsOnHeader;
    [Test]
    procedure DisabledActionCarriesReason;
    [Test]
    procedure ExecuteAnswersWithPlaceholders;
    [Test]
    procedure DefaultsFromResolver;
    [Test]
    procedure ErrorsCarryReason;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.Overloads,
  Atlas.Common.Lsp.Overloads;

const
  LogFile = 'C:\P\Log.pas';
  Log =
    'unit Log;'#10 +                                                         // 0
    'interface'#10 +                                                         // 1
    'type'#10 +                                                              // 2
    '  TLogLevel = (llInfo, llWarning);'#10 +                                // 3
    '  TSink = class'#10 +                                                   // 4
    '  end;'#10 +                                                            // 5
    '  TLog = class'#10 +                                                    // 6
    '    procedure Write(const AText: string; ALevel: TLogLevel);'#10 +      // 7
    '    procedure Attach(const AName: string; ASink: TSink);'#10 +          // 8
    '    destructor Destroy; override;'#10 +                                 // 9
    '  end;'#10 +                                                            // 10
    'implementation'#10 +                                                    // 11
    'procedure TLog.Write(const AText: string; ALevel: TLogLevel);'#10 +     // 12
    'begin'#10 +                                                             // 13
    'end;'#10 +                                                              // 14
    'procedure TLog.Attach(const AName: string; ASink: TSink);'#10 +         // 15
    'begin'#10 +                                                             // 16
    'end;'#10 +                                                              // 17
    'destructor TLog.Destroy;'#10 +                                          // 18
    'begin'#10 +                                                             // 19
    'end;'#10 +                                                              // 20
    'end.'#10;

procedure TLspOverloadsTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(Log, LogFile, nil));
end;

procedure TLspOverloadsTests.TearDown;
begin
  FIndex := nil;
end;

function ActionsAt(ALine, ACharacter: Integer): TArray<TJSONObject>;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(Log);
  try
    Result := TLspOverloads.Actions(Tree, Log, TDocumentUris.FromPath(LogFile), TTextPosition.Create(ALine, ACharacter));
  finally
    Tree.Free;
  end;
end;

procedure FreeAll(const AActions: TArray<TJSONObject>);
var
  Action: TJSONObject;
begin
  for Action in AActions do
    Action.Free;
end;

procedure TLspOverloadsTests.ActionsOnHeader;
var
  Actions: TArray<TJSONObject>;
  Arguments: TJSONArray;
begin
  Actions := ActionsAt(7, 16);
  try
    Assert.AreEqual(2, Integer(Length(Actions)));
    Assert.AreEqual(TOverloads.ForwardTitle, Actions[0].GetValue<string>('title'));
    Assert.AreEqual(TOverloads.CopyTitle, Actions[1].GetValue<string>('title'));
    Assert.AreEqual(TLspOverloads.ClientCommand, Actions[0].GetValue<string>('command.command'));
    Arguments := Actions[0].GetValue<TJSONArray>('command.arguments');
    Assert.AreEqual(3, Arguments.Count);
    Assert.AreEqual(TDocumentUris.FromPath(LogFile), Arguments.Items[0].Value);
    Assert.AreEqual(TLspOverloads.ForwardName, Arguments.Items[2].Value);
    Assert.AreEqual(TLspOverloads.CopyName, Actions[1].GetValue<TJSONArray>('command.arguments').Items[2].Value);
  finally
    FreeAll(Actions);
  end;
  // Nicht auf einem Kopf: keine Aktion.
  Actions := ActionsAt(13, 2);
  try
    Assert.AreEqual(0, Integer(Length(Actions)));
  finally
    FreeAll(Actions);
  end;
end;

procedure TLspOverloadsTests.DisabledActionCarriesReason;
var
  Actions: TArray<TJSONObject>;
begin
  Actions := ActionsAt(18, 18);
  try
    Assert.AreEqual(2, Integer(Length(Actions)));
    Assert.AreEqual(TOverloads.DestructorReason, Actions[0].GetValue<string>('disabled.reason'));
    Assert.IsNull(Actions[0].FindValue('command'));
  finally
    FreeAll(Actions);
  end;
end;

procedure TLspOverloadsTests.ExecuteAnswersWithPlaceholders;
var
  Tree: TSyntaxTree;
  Answer: TJSONObject;
  Placeholders: TJSONArray;
begin
  Tree := TPascalParser.Parse(Log);
  try
    Answer := TLspOverloads.Execute(Tree, LogFile, Log, TTextPosition.Create(12, 18), 'copy', nil);
    try
      Assert.IsTrue(Pos('procedure Write(const AText: string; ALevel: TLogLevel); overload;', Answer.ToJSON) > 0,
        Answer.ToJSON);
      Assert.AreEqual(TDocumentUris.FromPath(LogFile),
        (Answer.GetValue<TJSONArray>('edit.documentChanges').Items[0] as TJSONObject).GetValue<string>(
        'textDocument.uri'));
      Placeholders := Answer.GetValue<TJSONArray>('placeholders');
      Assert.AreEqual(4, Placeholders.Count);
      Assert.AreEqual(1, Placeholders.Items[0].GetValue<Integer>('number'));
      Assert.AreEqual(8, Placeholders.Items[0].GetValue<Integer>('range.start.line'));
      Assert.AreEqual(0, Placeholders.Items[3].GetValue<Integer>('number'));
      Assert.AreEqual(0, Answer.GetValue<TJSONArray>('warnings').Count);
    finally
      Answer.Free;
    end;
  finally
    Tree.Free;
  end;
end;

function ForwardJson(const AIndex: ISymbolIndex; ALine, ACharacter: Integer): string;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Answer: TJSONObject;
begin
  Tree := TPascalParser.Parse(Log);
  Resolver := TNameResolver.Create(AIndex);
  try
    Resolver.PinTree(Tree, LogFile);
    try
      Answer := TLspOverloads.Execute(Tree, LogFile, Log, TTextPosition.Create(ALine, ACharacter), 'forward',
        TLspOverloads.DefaultFunc(Resolver, AIndex, Tree, LogFile, Log));
      try
        Result := Answer.ToJSON;
      finally
        Answer.Free;
      end;
    finally
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

procedure TLspOverloadsTests.DefaultsFromResolver;
var
  Json: string;
begin
  Json := ForwardJson(FIndex, 7, 16);
  Assert.IsTrue(Pos('Write(AText, llInfo);', Json) > 0, Json);
  Json := ForwardJson(FIndex, 15, 18);
  Assert.IsTrue(Pos('Attach(AName, nil);', Json) > 0, Json);
end;

procedure TLspOverloadsTests.ErrorsCarryReason;
begin
  Assert.WillRaise(
    procedure
    var
      Tree: TSyntaxTree;
    begin
      Tree := TPascalParser.Parse(Log);
      try
        TLspOverloads.Execute(Tree, LogFile, Log, TTextPosition.Create(18, 18), 'copy', nil).Free;
      finally
        Tree.Free;
      end;
    end, EJsonRpcError);
  Assert.WillRaise(
    procedure
    var
      Tree: TSyntaxTree;
    begin
      Tree := TPascalParser.Parse(Log);
      try
        TLspOverloads.Execute(Tree, LogFile, Log, TTextPosition.Create(12, 18), 'merge', nil).Free;
      finally
        Tree.Free;
      end;
    end, EJsonRpcError);
  Assert.WillRaise(
    procedure
    var
      Tree: TSyntaxTree;
    begin
      Tree := TPascalParser.Parse(Log);
      try
        TLspOverloads.Execute(Tree, LogFile, Log, TTextPosition.Create(13, 2), 'copy', nil).Free;
      finally
        Tree.Free;
      end;
    end, EJsonRpcError);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspOverloadsTests);

end.
