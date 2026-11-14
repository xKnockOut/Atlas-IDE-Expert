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
  System.Generics.Collections,
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
  cLogFile = 'C:\P\Log.pas';
  cLogSource =
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
  FIndex.AddUnit(TIndexExtractor.ExtractText(cLogSource, cLogFile, nil));
end;

procedure TLspOverloadsTests.TearDown;
begin
  FIndex := nil;
end;

function ActionsAt(ALine, ACharacter: Integer): TArray<TJSONObject>;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cLogSource);
  try
    Result := TLspOverloads.Actions(mTree, cLogSource, TDocumentUris.FromPath(cLogFile),
      TTextPosition.Create(ALine, ACharacter));
  finally
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

procedure TLspOverloadsTests.ActionsOnHeader;
var
  mActions: TArray<TJSONObject>;
  mArguments: TJSONArray;
begin
  mActions := ActionsAt(7, 16);
  try
    Assert.AreEqual(2, Integer(Length(mActions)));
    Assert.AreEqual(TOverloads.ForwardTitle, mActions[0].GetValue<string>('title'));
    Assert.AreEqual(TOverloads.CopyTitle, mActions[1].GetValue<string>('title'));
    Assert.AreEqual(TLspOverloads.cClientCommand, mActions[0].GetValue<string>('command.command'));
    mArguments := mActions[0].GetValue<TJSONArray>('command.arguments');
    Assert.AreEqual(3, mArguments.Count);
    Assert.AreEqual(TDocumentUris.FromPath(cLogFile), mArguments.Items[0].Value);
    Assert.AreEqual(TLspOverloads.cForwardName, mArguments.Items[2].Value);
    Assert.AreEqual(TLspOverloads.cCopyName, mActions[1].GetValue<TJSONArray>('command.arguments').Items[2].Value);
  finally
    FreeAll(mActions);
  end;
  // Nicht auf einem Kopf: keine Aktion.
  mActions := ActionsAt(13, 2);
  try
    Assert.AreEqual(0, Integer(Length(mActions)));
  finally
    FreeAll(mActions);
  end;
end;

procedure TLspOverloadsTests.DisabledActionCarriesReason;
var
  mActions: TArray<TJSONObject>;
begin
  mActions := ActionsAt(18, 18);
  try
    Assert.AreEqual(2, Integer(Length(mActions)));
    Assert.AreEqual(TOverloads.DestructorReason, mActions[0].GetValue<string>('disabled.reason'));
    Assert.IsNull(mActions[0].FindValue('command'));
  finally
    FreeAll(mActions);
  end;
end;

procedure TLspOverloadsTests.ExecuteAnswersWithPlaceholders;
var
  mTree: TSyntaxTree;
  mAnswer: TJSONObject;
  mPlaceholders: TJSONArray;
begin
  mTree := TPascalParser.Parse(cLogSource);
  try
    mAnswer := TLspOverloads.Execute(mTree, cLogFile, cLogSource, TTextPosition.Create(12, 18), 'copy', nil);
    try
      Assert.IsTrue(Pos('procedure Write(const AText: string; ALevel: TLogLevel); overload;', mAnswer.ToJSON) > 0,
        mAnswer.ToJSON);
      Assert.AreEqual(TDocumentUris.FromPath(cLogFile),
        (mAnswer.GetValue<TJSONArray>('edit.documentChanges').Items[0] as TJSONObject).GetValue<string>(
        'textDocument.uri'));
      mPlaceholders := mAnswer.GetValue<TJSONArray>('placeholders');
      Assert.AreEqual(4, mPlaceholders.Count);
      Assert.AreEqual(1, mPlaceholders.Items[0].GetValue<Integer>('number'));
      Assert.AreEqual(8, mPlaceholders.Items[0].GetValue<Integer>('range.start.line'));
      Assert.AreEqual(0, mPlaceholders.Items[3].GetValue<Integer>('number'));
      Assert.AreEqual(0, mAnswer.GetValue<TJSONArray>('warnings').Count);
    finally
      mAnswer.Free;
    end;
  finally
    mTree.Free;
  end;
end;

function ForwardJson(const AIndex: ISymbolIndex; ALine, ACharacter: Integer): string;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mAnswer: TJSONObject;
begin
  mTree := TPascalParser.Parse(cLogSource);
  mResolver := TNameResolver.Create(AIndex);
  try
    mResolver.PinTree(mTree, cLogFile);
    try
      mAnswer := TLspOverloads.Execute(mTree, cLogFile, cLogSource, TTextPosition.Create(ALine, ACharacter), 'forward',
        TLspOverloads.DefaultFunc(mResolver, AIndex, mTree, cLogFile, cLogSource));
      try
        Result := mAnswer.ToJSON;
      finally
        mAnswer.Free;
      end;
    finally
      mResolver.UnpinTree;
    end;
  finally
    mResolver.Free;
    mTree.Free;
  end;
end;

procedure TLspOverloadsTests.DefaultsFromResolver;
var
  mJson: string;
begin
  mJson := ForwardJson(FIndex, 7, 16);
  Assert.IsTrue(Pos('Write(AText, llInfo);', mJson) > 0, mJson);
  mJson := ForwardJson(FIndex, 15, 18);
  Assert.IsTrue(Pos('Attach(AName, nil);', mJson) > 0, mJson);
end;

procedure TLspOverloadsTests.ErrorsCarryReason;
begin
  Assert.WillRaise(
    procedure
    var
      Tree: TSyntaxTree;
    begin
      Tree := TPascalParser.Parse(cLogSource);
      try
        TLspOverloads.Execute(Tree, cLogFile, cLogSource, TTextPosition.Create(18, 18), 'copy', nil).Free;
      finally
        Tree.Free;
      end;
    end, EJsonRpcError);
  Assert.WillRaise(
    procedure
    var
      Tree: TSyntaxTree;
    begin
      Tree := TPascalParser.Parse(cLogSource);
      try
        TLspOverloads.Execute(Tree, cLogFile, cLogSource, TTextPosition.Create(12, 18), 'merge', nil).Free;
      finally
        Tree.Free;
      end;
    end, EJsonRpcError);
  Assert.WillRaise(
    procedure
    var
      Tree: TSyntaxTree;
    begin
      Tree := TPascalParser.Parse(cLogSource);
      try
        TLspOverloads.Execute(Tree, cLogFile, cLogSource, TTextPosition.Create(13, 2), 'copy', nil).Free;
      finally
        Tree.Free;
      end;
    end, EJsonRpcError);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspOverloadsTests);

end.
