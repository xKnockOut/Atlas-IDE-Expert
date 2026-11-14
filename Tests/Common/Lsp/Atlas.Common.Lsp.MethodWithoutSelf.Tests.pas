unit Atlas.Common.Lsp.MethodWithoutSelf.Tests;

// „Methode ohne Self umwandeln“ über das Protokoll (#686): Code-Aktionen mit
// Client-Befehl, keine Aktion bei implizitem Zugriff auf ein Feld (über die
// Namensauflösung) oder bei einem Ereignis der Formulardatei, Antwort des
// Server-Befehls über zwei Units samt Vorschau, Warnung bei sichtbarem
// Helper, Fehler mit Grund, Marken.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract;

type
  [TestFixture]
  TLspMethodWithoutSelfTests = class
  private
    FIndex: ISymbolIndex;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ActionsCarryClientCommand;
    [Test]
    procedure ImplicitFieldAndFormEventGiveNoAction;
    [Test]
    procedure ExecuteChangesBothUnits;
    [Test]
    procedure HelperWarnsAboutRtlHelper;
    [Test]
    procedure ErrorsCarryReason;
    [Test]
    procedure MarkersAtHeaderEnd;
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
  Atlas.Common.Editing.MethodWithoutSelf,
  Atlas.Common.Lsp.MethodWithoutSelf;

const
  cKundenFile = 'C:\P\Kunden.pas';
  cAufruferFile = 'C:\P\Aufrufer.pas';
  cFormFile = 'C:\P\Kunden.dfm';
  cKunden =
    'unit Kunden;'#10 +                                                  // 0
    'interface'#10 +                                                     // 1
    'uses System.SysUtils;'#10 +                                         // 2
    'type'#10 +                                                          // 3
    '  TKunde = class'#10 +                                              // 4
    '  private'#10 +                                                     // 5
    '    FName: string;'#10 +                                            // 6
    '  public'#10 +                                                      // 7
    '    function IsValidIban(const S: string; N: Integer): Boolean;'#10 + // 8
    '    procedure Zeige;'#10 +                                          // 9
    '    procedure Knopf(Sender: TObject);'#10 +                         // 10
    '  end;'#10 +                                                        // 11
    'implementation'#10 +                                                // 12
    'procedure TKunde.Zeige;'#10 +                                       // 13
    'begin'#10 +                                                         // 14
    '  if IsValidIban(FName, 2) then'#10 +                               // 15
    '    FName := '''';'#10 +                                            // 16
    'end;'#10 +                                                          // 17
    'function TKunde.IsValidIban(const S: string; N: Integer): Boolean;'#10 + // 18
    'begin'#10 +                                                         // 19
    '  Result := S <> '''';'#10 +                                        // 20
    'end;'#10 +                                                          // 21
    'procedure TKunde.Knopf(Sender: TObject);'#10 +                      // 22
    'begin'#10 +                                                         // 23
    'end;'#10 +                                                          // 24
    'end.'#10;

  cAufrufer =
    'unit Aufrufer;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'uses Kunden;'#10 +
    'procedure Pruefe(K: TKunde; const T: string);'#10 +
    'begin'#10 +
    '  if K.IsValidIban(T, 3) then'#10 +
    '    Exit;'#10 +
    'end;'#10 +
    'end.'#10;

function ReadFile(const AFileName: string; out AText: string): Boolean;
begin
  Result := True;
  if SameText(AFileName, cFormFile) then
  begin
    AText := 'object Kunde: TKunde'#10'  OnClick = Knopf'#10'end'#10;
  end
  else if SameText(AFileName, cAufruferFile) then
  begin
    AText := cAufrufer;
  end
  else if SameText(AFileName, cKundenFile) then
  begin
    AText := cKunden;
  end
  else
  begin
    Result := False;
  end;
end;

procedure TLspMethodWithoutSelfTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cKunden, cKundenFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cAufrufer, cAufruferFile, nil));
end;

procedure TLspMethodWithoutSelfTests.TearDown;
begin
  FIndex := nil;
end;

function ActionsAt(const AIndex: ISymbolIndex; ALine, ACharacter: Integer): TArray<TJSONObject>;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
begin
  mTree := TPascalParser.Parse(cKunden);
  mResolver := TNameResolver.Create(AIndex);
  try
    mResolver.PinTree(mTree, cKundenFile);
    try
      Result := TLspMethodWithoutSelf.Actions(mTree, cKunden, TDocumentUris.FromPath(cKundenFile),
        TTextPosition.Create(ALine, ACharacter), TLspMethodWithoutSelf.Lookup(mResolver, mTree, cKundenFile, ReadFile));
    finally
      mResolver.UnpinTree;
    end;
  finally
    mResolver.Free;
    mTree.Free;
  end;
end;

function ExecuteAt(const AIndex: ISymbolIndex; ALine, ACharacter: Integer; const AConversion: string): TJSONObject;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mContext: TMethodKindContext;
begin
  mContext := Default(TMethodKindContext);
  mContext.Index := AIndex;
  mContext.Files := [cKundenFile, cAufruferFile];
  mContext.ReadText := ReadFile;
  mContext.WithStatic := True;
  mContext.Conversion := AConversion;
  mContext.Style := TFormatStyle.Default;
  mTree := TPascalParser.Parse(cKunden);
  mResolver := TNameResolver.Create(AIndex);
  try
    Result := TLspMethodWithoutSelf.Execute(mResolver, mTree, cKundenFile, cKunden, TTextPosition.Create(ALine,
      ACharacter), mContext);
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

procedure TLspMethodWithoutSelfTests.ActionsCarryClientCommand;
var
  mActions: TArray<TJSONObject>;
  mArguments: TJSONArray;
begin
  mActions := ActionsAt(FIndex, 18, 20);
  try
    Assert.AreEqual(4, Integer(Length(mActions)));
    Assert.AreEqual(TMethodWithoutSelf.ClassMethodTitle, mActions[0].GetValue<string>('title'));
    Assert.AreEqual('In class-Methode umwandeln, Aufrufe über TKunde', mActions[1].GetValue<string>('title'));
    Assert.AreEqual(TMethodWithoutSelf.RoutineTitle, mActions[2].GetValue<string>('title'));
    Assert.AreEqual('In Record-Helper für string verschieben', mActions[3].GetValue<string>('title'));
    Assert.AreEqual(TLspMethodWithoutSelf.cKind, mActions[0].GetValue<string>('kind'));
    Assert.AreEqual(TLspMethodWithoutSelf.cClientCommand, mActions[2].GetValue<string>('command.command'));
    mArguments := mActions[2].GetValue<TJSONArray>('command.arguments');
    Assert.AreEqual(3, mArguments.Count);
    Assert.AreEqual(TDocumentUris.FromPath(cKundenFile), mArguments.Items[0].Value);
    Assert.AreEqual(18, mArguments.Items[1].GetValue<Integer>('line'));
    Assert.AreEqual('routine', mArguments.Items[2].Value);
  finally
    FreeAll(mActions);
  end;
end;

procedure TLspMethodWithoutSelfTests.ImplicitFieldAndFormEventGiveNoAction;
begin
  // Zeige liest FName ohne Self.
  Assert.AreEqual(0, Integer(Length(ActionsAt(FIndex, 13, 20))));
  // Knopf steht in Kunden.dfm.
  Assert.AreEqual(0, Integer(Length(ActionsAt(FIndex, 22, 20))));
end;

procedure TLspMethodWithoutSelfTests.ExecuteChangesBothUnits;
var
  mAnswer: TJSONObject;
  mJson: string;
begin
  mAnswer := ExecuteAt(FIndex, 18, 20, 'routine');
  try
    mJson := mAnswer.ToJSON;
    Assert.AreEqual(2, mAnswer.GetValue<Integer>('files'), mJson);
    Assert.AreEqual(1, mAnswer.GetValue<Integer>('calls'), mJson);
    Assert.IsTrue(Pos('"newText":"function IsValidIban(const S: string; N: Integer): Boolean;\n\n"', mJson) > 0,
      mJson);
    Assert.IsTrue(Pos(TDocumentUris.FromPath(cAufruferFile), mJson) > 0, mJson);
    Assert.IsTrue(Pos('"needsConfirmation":true', mJson) > 0, mJson);
    Assert.IsTrue(mAnswer.GetValue<string>('preview').StartsWith('TKunde.IsValidIban wird freie Routine'), mJson);
    Assert.IsTrue(Pos('Aufrufer.pas, Zeile 7: if K.IsValidIban(T, 3) then', mAnswer.GetValue<string>('preview')) > 0,
      mJson);
  finally
    mAnswer.Free;
  end;
  mAnswer := ExecuteAt(FIndex, 18, 20, 'classMethod');
  try
    mJson := mAnswer.ToJSON;
    Assert.AreEqual(1, mAnswer.GetValue<Integer>('files'), mJson);
    Assert.IsTrue(Pos('" static;"', mJson) > 0, mJson);
  finally
    mAnswer.Free;
  end;
end;

procedure TLspMethodWithoutSelfTests.HelperWarnsAboutRtlHelper;
var
  mAnswer: TJSONObject;
begin
  mAnswer := ExecuteAt(FIndex, 18, 20, 'helper');
  try
    Assert.AreEqual(1, mAnswer.GetValue<TJSONArray>('warnings').Count, mAnswer.ToJSON);
    Assert.IsTrue(Pos('TStringHelper', mAnswer.GetValue<TJSONArray>('warnings').Items[0].Value) > 0, mAnswer.ToJSON);
    Assert.IsTrue(Pos('TKundenStringHelper = record helper for string', mAnswer.ToJSON) > 0, mAnswer.ToJSON);
    Assert.IsTrue(Pos('"newText":"T.IsValidIban(3)"', mAnswer.ToJSON) > 0, mAnswer.ToJSON);
  finally
    mAnswer.Free;
  end;
end;

procedure TLspMethodWithoutSelfTests.ErrorsCarryReason;
begin
  Assert.WillRaise(
    procedure
    begin
      ExecuteAt(FIndex, 18, 20, 'unbekannt').Free;
    end, EJsonRpcError);
  Assert.WillRaise(
    procedure
    begin
      ExecuteAt(FIndex, 13, 20, 'routine').Free;
    end, EJsonRpcError);
end;

procedure TLspMethodWithoutSelfTests.MarkersAtHeaderEnd;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mFound: TArray<TTextPosition>;
begin
  mTree := TPascalParser.Parse(cKunden);
  mResolver := TNameResolver.Create(FIndex);
  try
    mResolver.PinTree(mTree, cKundenFile);
    try
      mFound := TLspMethodWithoutSelf.Markers(mTree, cKunden, TTextRange.Create(TTextPosition.Create(0, 0),
        TTextPosition.Create(30, 0)), TLspMethodWithoutSelf.Lookup(mResolver, mTree, cKundenFile, ReadFile));
      Assert.AreEqual(1, Integer(Length(mFound)));
      Assert.AreEqual(18, mFound[0].Line);
      Assert.AreEqual(66, mFound[0].Character);
      mFound := TLspMethodWithoutSelf.Markers(mTree, cKunden, TTextRange.Create(TTextPosition.Create(0, 0),
        TTextPosition.Create(10, 0)), TLspMethodWithoutSelf.Lookup(mResolver, mTree, cKundenFile, ReadFile));
      Assert.AreEqual(0, Integer(Length(mFound)));
    finally
      mResolver.UnpinTree;
    end;
  finally
    mResolver.Free;
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspMethodWithoutSelfTests);

end.
