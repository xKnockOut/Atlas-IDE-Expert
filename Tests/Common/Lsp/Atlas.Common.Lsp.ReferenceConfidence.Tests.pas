unit Atlas.Common.Lsp.ReferenceConfidence.Tests;

// Tests für die Treffersicherheit der Verwendungen (#1119): sichere und
// erschlossene Treffer je Grund, Einstellungen references.*, Ausgabe im LSP
// und über MCP, Umbenennen nur der sicheren Stellen.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.References;

type
  [TestFixture]
  TReferenceConfidenceTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function Settings(AInferred, ATextMatches: Boolean): TReferenceSettings;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function FindSpeichern(const ASettings: TReferenceSettings): TArray<TReferenceLocation>;
    /// <summary>"Datei:Zeile:Spalte=Stufe/Grund" je Treffer, durch Leerzeichen getrennt.</summary>
    function Describe(const ALocations: TArray<TReferenceLocation>): string;
    function HitAt(const ALocations: TArray<TReferenceLocation>; const AFileName: string; ALine: Integer;
      out ALocation: TReferenceLocation): Boolean;
  public
    /// <summary>Einmal-Belegungen vorwegnehmen; sie gehören nicht in die Leckmessung.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Ohne references.inferred nur sichere Treffer wie vor #1119, auch aus inaktiven Zweigen.</summary>
    [Test]
    procedure SureOnlyAsBefore;
    [Test]
    procedure InterfaceCallIsInferred;
    [Test]
    procedure VirtualCallIsInferred;
    [Test]
    procedure UnknownTypeIsUnresolved;
    /// <summary>Löst die Stelle im inaktiven Zweig auf das Symbol auf, wird sie mit umbenannt.</summary>
    [Test]
    procedure InactiveBranchMatchedIsRenameable;
    [Test]
    procedure TextMatchesOnlyWithSetting;
    /// <summary>Nicht eindeutige Überladung: Der Auflöser wählt das Symbol (Matched), die Stelle wird geprüft.
    /// </summary>
    [Test]
    procedure AmbiguousOverload;
    /// <summary>Der Baum des Editors (#845) führt die Tokens aller Zweige; Einstufung wie beim Vollbaum.</summary>
    [Test]
    procedure InactiveBranchInEditorTree;
    /// <summary>procedure TBasis.Speichern deklariert eine andere Methode und ruft TKunde.Speichern nicht.</summary>
    [Test]
    procedure RoutineHeaderIsNoHit;
    [Test]
    procedure ConfidenceJson;
    /// <summary>textDocument/references und textDocument/rename über den Dispatcher: atlasConfidence je Stelle,
    /// atlasUnchanged für nicht geänderte Stellen.</summary>
    [Test]
    procedure LspResponses;
    [Test]
    procedure RenameChangesOnlySure;
    [Test]
    procedure IncomingCallsGroupedByConfidence;
    [Test]
    procedure McpListsSureThenInferred;
    /// <summary>rename_symbol ändert die sicheren Stellen und nennt die übrigen zum Prüfen.</summary>
    [Test]
    procedure McpRenameListsUnchanged;
    /// <summary>Annahme aus #1119: erschlossene Treffer kosten höchstens 20 % mehr Zeit.</summary>
    [Test]
    [Category('Benchmark')]
    procedure InferredCostsLittle;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  System.Diagnostics,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.ReferenceConfidence,
  Atlas.Common.Lsp.Hierarchies,
  Atlas.Common.Lsp.Rename,
  Atlas.Common.Mcp.CodeTools,
  Atlas.Common.Mcp.EditTools;

const
  cKundenFile = 'C:\P\Kunden.pas';
  cHauptFile = 'C:\P\Haupt.pas';
  cWerteFile = 'C:\P\Werte.pas';

  cUnitKunden =
    'unit Kunden;'#10 +                                          // 0
    'interface'#10 +                                             // 1
    'type'#10 +                                                  // 2
    '  ISpeicherbar = interface'#10 +                            // 3
    '    procedure Speichern;'#10 +                              // 4
    '  end;'#10 +                                                // 5
    '  TBasis = class(TInterfacedObject, ISpeicherbar)'#10 +     // 6
    '    procedure Speichern; virtual;'#10 +                     // 7
    '  end;'#10 +                                                // 8
    '  TKunde = class(TBasis)'#10 +                              // 9
    '    procedure Speichern; override;'#10 +                    // 10
    '  end;'#10 +                                                // 11
    'implementation'#10 +                                        // 12
    'procedure TBasis.Speichern;'#10 +                           // 13
    'begin'#10 +                                                 // 14
    'end;'#10 +                                                  // 15
    'procedure TKunde.Speichern;'#10 +                           // 16
    'begin'#10 +                                                 // 17
    'end;'#10 +                                                  // 18
    'end.';

  cUnitHaupt =
    'unit Haupt;'#10 +                                           // 0
    'interface'#10 +                                             // 1
    'uses Kunden;'#10 +                                          // 2
    'implementation'#10 +                                        // 3
    'procedure Lauf(S: ISpeicherbar; B: TBasis; K: TKunde; U: TUnbekannt);'#10 + // 4
    'begin'#10 +                                                 // 5
    '  K.Speichern;'#10 +                                        // 6
    '  S.Speichern;'#10 +                                        // 7
    '  B.Speichern;'#10 +                                        // 8
    '  U.Speichern;'#10 +                                        // 9
    '  {$IFDEF NIE}'#10 +                                        // 10
    '  K.Speichern;'#10 +                                        // 11
    '  {$ENDIF}'#10 +                                            // 12
    '  Protokoll(''Speichern'');'#10 +                           // 13
    'end;'#10 +                                                  // 14
    'end.';

  cUnitWerte =
    'unit Werte;'#10 +                                           // 0
    'interface'#10 +                                             // 1
    'procedure Zeige(A: Integer); overload;'#10 +                // 2
    'procedure Zeige(const A: string); overload;'#10 +           // 3
    'implementation'#10 +                                        // 4
    'procedure Zeige(A: Integer);'#10 +                          // 5
    'begin'#10 +                                                 // 6
    'end;'#10 +                                                  // 7
    'procedure Zeige(const A: string);'#10 +                     // 8
    'begin'#10 +                                                 // 9
    'end;'#10 +                                                  // 10
    'procedure Lauf(V: TUnbekannt);'#10 +                        // 11
    'begin'#10 +                                                 // 12
    '  Zeige(V);'#10 +                                           // 13
    '  Zeige(1);'#10 +                                           // 14
    'end;'#10 +                                                  // 15
    'end.';

function PositionOf(const AText, AMarker: string): TTextPosition;
var
  mIndex, mLine, mLineStart, I: Integer;
begin
  mIndex := Pos(AMarker, AText);
  if mIndex = 0 then
  begin
    raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
  end;
  mLine := 0;
  mLineStart := 1;
  for I := 1 to mIndex - 1 do
  begin
    if AText[I] = #10 then
    begin
      Inc(mLine);
      mLineStart := I + 1;
    end;
  end;
  Result := TTextPosition.Create(mLine, mIndex - mLineStart);
end;

{ TReferenceConfidenceTests }

procedure TReferenceConfidenceTests.WarmUpFirstUse;
begin
  Setup;
  try
    LspResponses;
  finally
    TearDown;
  end;
end;

procedure TReferenceConfidenceTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitKunden, cKundenFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitWerte, cWerteFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TReferenceConfidenceTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TReferenceConfidenceTests.Settings(AInferred, ATextMatches: Boolean): TReferenceSettings;
begin
  Result.Inferred := AInferred;
  Result.TextMatches := ATextMatches;
end;

function TReferenceConfidenceTests.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  Result := True;
  if SameText(AFileName, cKundenFile) then
  begin
    AText := cUnitKunden;
  end
  else if SameText(AFileName, cHauptFile) then
  begin
    AText := cUnitHaupt;
  end
  else if SameText(AFileName, cWerteFile) then
  begin
    AText := cUnitWerte;
  end
  else
  begin
    Result := False;
  end;
end;

function TReferenceConfidenceTests.FindSpeichern(const ASettings: TReferenceSettings): TArray<TReferenceLocation>;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cUnitKunden);
  try
    Result := TLspReferences.Find(FResolver, FIndex, mTree, TReferenceSearch.Create(cKundenFile, PositionOf(cUnitKunden,
      'Speichern; override'), True, [cKundenFile, cHauptFile], ReadText), ASettings, nil);
  finally
    mTree.Free;
  end;
end;

function TReferenceConfidenceTests.Describe(const ALocations: TArray<TReferenceLocation>): string;
var
  mLocation: TReferenceLocation;
begin
  Result := '';
  for mLocation in ALocations do
  begin
    Result := Result + Format('%s:%d:%d=%s', [ChangeFileExt(ExtractFileName(mLocation.FileName), ''),
      mLocation.Range.StartPos.Line, mLocation.Range.StartPos.Character, mLocation.Confidence.LevelName]);
    if not mLocation.Confidence.IsSure then
    begin
      Result := Result + '/' + mLocation.Confidence.ReasonName;
    end;
    Result := Result + ' ';
  end;
  Result := Trim(Result);
end;

function TReferenceConfidenceTests.HitAt(const ALocations: TArray<TReferenceLocation>; const AFileName: string;
  ALine: Integer; out ALocation: TReferenceLocation): Boolean;
var
  mLocation: TReferenceLocation;
begin
  for mLocation in ALocations do
  begin
    if SameText(mLocation.FileName, AFileName) and (mLocation.Range.StartPos.Line = ALine) then
    begin
      ALocation := mLocation;
      Exit(True);
    end;
  end;
  ALocation := Default(TReferenceLocation);
  Result := False;
end;

procedure TReferenceConfidenceTests.SureOnlyAsBefore;
begin
  // Der vollständige Baum von Haupt enthält beide Zweige; ohne Einstufung zählt die Stelle in NIE wie bisher.
  Assert.AreEqual('Kunden:10:14=sure Kunden:16:17=sure Haupt:6:4=sure Haupt:11:4=sure',
    Describe(FindSpeichern(Settings(False, True))));
end;

procedure TReferenceConfidenceTests.InterfaceCallIsInferred;
var
  mLocation: TReferenceLocation;
begin
  Assert.IsTrue(HitAt(FindSpeichern(Settings(True, False)), cHauptFile, 7, mLocation), 'S.Speichern fehlt');
  Assert.AreEqual('interface', mLocation.Confidence.ReasonName);
  Assert.IsFalse(mLocation.Confidence.Renameable);
  Assert.IsTrue(Pos('ISpeicherbar.Speichern', mLocation.Confidence.Detail) > 0, mLocation.Confidence.Detail);
  Assert.IsTrue(Pos('eine von 2 Umsetzungen', mLocation.Confidence.Detail) > 0, mLocation.Confidence.Detail);
end;

procedure TReferenceConfidenceTests.VirtualCallIsInferred;
var
  mLocation: TReferenceLocation;
begin
  Assert.IsTrue(HitAt(FindSpeichern(Settings(True, False)), cHauptFile, 8, mLocation), 'B.Speichern fehlt');
  Assert.AreEqual('virtual', mLocation.Confidence.ReasonName);
  Assert.IsTrue(Pos('TKunde.Speichern', mLocation.Confidence.Detail) > 0, mLocation.Confidence.Detail);
end;

procedure TReferenceConfidenceTests.UnknownTypeIsUnresolved;
var
  mLocation: TReferenceLocation;
begin
  Assert.IsTrue(HitAt(FindSpeichern(Settings(True, False)), cHauptFile, 9, mLocation), 'U.Speichern fehlt');
  Assert.AreEqual('unresolved', mLocation.Confidence.ReasonName);
  Assert.IsFalse(mLocation.Confidence.Renameable);
end;

procedure TReferenceConfidenceTests.InactiveBranchMatchedIsRenameable;
var
  mLocation: TReferenceLocation;
begin
  Assert.IsTrue(HitAt(FindSpeichern(Settings(True, False)), cHauptFile, 11, mLocation), 'Stelle in NIE fehlt');
  Assert.AreEqual('inactiveBranch', mLocation.Confidence.ReasonName);
  Assert.IsTrue(mLocation.Confidence.Matched);
  Assert.IsTrue(mLocation.Confidence.Renameable);
  Assert.IsTrue(Pos('NIE', mLocation.Confidence.Detail) > 0, mLocation.Confidence.Detail);
end;

procedure TReferenceConfidenceTests.TextMatchesOnlyWithSetting;
var
  mLocation: TReferenceLocation;
begin
  Assert.IsFalse(HitAt(FindSpeichern(Settings(True, False)), cHauptFile, 13, mLocation), 'ohne textMatches');
  Assert.IsTrue(HitAt(FindSpeichern(Settings(True, True)), cHauptFile, 13, mLocation), 'mit textMatches');
  Assert.AreEqual('text', mLocation.Confidence.ReasonName);
  // Nur der Name zwischen den Hochkommas.
  Assert.AreEqual(13, mLocation.Range.StartPos.Character);
  Assert.AreEqual(22, mLocation.Range.EndPos.Character);
end;

function FindZeige(AResolver: TNameResolver; const AIndex: ISymbolIndex; const AMarker: string;
  const AReadText: TReferenceReadText; const ASettings: TReferenceSettings): TArray<TReferenceLocation>;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cUnitWerte);
  try
    Result := TLspReferences.Find(AResolver, AIndex, mTree, TReferenceSearch.Create(cWerteFile, PositionOf(cUnitWerte,
      AMarker), False, TArray<string>.Create(cWerteFile), AReadText), ASettings, nil);
  finally
    mTree.Free;
  end;
end;

procedure TReferenceConfidenceTests.AmbiguousOverload;
var
  mFound: TArray<TReferenceLocation>;
  mLocation: TReferenceLocation;
begin
  mFound := FindZeige(FResolver, FIndex, 'Zeige(A: Integer); overload', ReadText, Settings(True, False));
  Assert.IsTrue(HitAt(mFound, cWerteFile, 14, mLocation), 'Zeige(1) fehlt: ' + Describe(mFound));
  Assert.IsTrue(mLocation.Confidence.IsSure, Describe(mFound));
  Assert.IsTrue(HitAt(mFound, cWerteFile, 13, mLocation), 'Zeige(V) fehlt: ' + Describe(mFound));
  Assert.AreEqual('ambiguous', mLocation.Confidence.ReasonName);
  // Wie vor #1119 mit umbenannt.
  Assert.IsTrue(mLocation.Confidence.Matched);
  Assert.IsTrue(mLocation.Confidence.Renameable);
  // Köpfe von Deklaration und Rumpf sind keine Aufrufe.
  Assert.IsTrue(HitAt(mFound, cWerteFile, 5, mLocation), Describe(mFound));
  Assert.IsTrue(mLocation.Confidence.IsSure, Describe(mFound));
  // Ohne Einstufung sicher wie bisher.
  mFound := FindZeige(FResolver, FIndex, 'Zeige(A: Integer); overload', ReadText, Settings(False, False));
  Assert.IsTrue(HitAt(mFound, cWerteFile, 13, mLocation), Describe(mFound));
  Assert.IsTrue(mLocation.Confidence.IsSure);
end;

procedure TReferenceConfidenceTests.InactiveBranchInEditorTree;
var
  mTree: TSyntaxTree;
  mFound: TArray<TReferenceLocation>;
  mLocation: TReferenceLocation;
begin
  // Wie im Editor: Der Parser überspringt den Zweig NIE, die Token-Liste enthält ihn.
  mTree := TPascalParser.ParseActive(cUnitHaupt, nil);
  try
    mFound := TLspReferences.Find(FResolver, FIndex, mTree, TReferenceSearch.Create(cHauptFile, PositionOf(cUnitHaupt,
      'Speichern;'), False, [cKundenFile, cHauptFile], ReadText), Settings(True, False), nil);
    Assert.IsTrue(HitAt(mFound, cHauptFile, 11, mLocation), 'Stelle in NIE fehlt: ' + Describe(mFound));
    Assert.AreEqual('inactiveBranch', mLocation.Confidence.ReasonName);
    Assert.IsTrue(mLocation.Confidence.Renameable);
    // Ohne Einstufung wie vor #1119: sicher.
    mFound := TLspReferences.Find(FResolver, FIndex, mTree, TReferenceSearch.Create(cHauptFile, PositionOf(cUnitHaupt,
      'Speichern;'), False, [cKundenFile, cHauptFile], ReadText), Settings(False, False), nil);
    Assert.IsTrue(HitAt(mFound, cHauptFile, 11, mLocation), Describe(mFound));
    Assert.IsTrue(mLocation.Confidence.IsSure);
  finally
    mTree.Free;
  end;
end;

procedure TReferenceConfidenceTests.RoutineHeaderIsNoHit;
var
  mLocation: TReferenceLocation;
begin
  Assert.IsFalse(HitAt(FindSpeichern(Settings(True, True)), cKundenFile, 13, mLocation), 'TBasis.Speichern');
  Assert.IsFalse(HitAt(FindSpeichern(Settings(True, True)), cKundenFile, 7, mLocation), 'Deklaration in TBasis');
  Assert.IsFalse(HitAt(FindSpeichern(Settings(True, True)), cKundenFile, 4, mLocation), 'Deklaration im Interface');
end;

procedure TReferenceConfidenceTests.ConfidenceJson;
var
  mJson: TJSONObject;
begin
  mJson := TReferenceConfidence.Sure.ToJson;
  try
    Assert.AreEqual('{"level":"sure"}', mJson.ToJSON);
  finally
    mJson.Free;
  end;
  mJson := TReferenceConfidence.Inferred(TReferenceReason.Interface_, 'Aufruf I.M', False).ToJson;
  try
    Assert.AreEqual('{"level":"inferred","reason":"interface","detail":"Aufruf I.M"}', mJson.ToJSON);
  finally
    mJson.Free;
  end;
end;

function Request(ADispatcher: TJsonRpcDispatcher; const AMethod, AParams: string): TJSONObject;
var
  mMessage: TJSONObject;
begin
  mMessage := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":1,"method":"' + AMethod + '","params":' + AParams +
    '}') as TJSONObject;
  try
    Result := ADispatcher.DispatchMessage(mMessage);
  finally
    mMessage.Free;
  end;
end;

/// <summary>Referenzen tragen die Sicherheit je Fundstelle.</summary>
procedure AssertReferenceLevels(const ADispatcher: TJsonRpcDispatcher; const AUri, APosition: string);
var
  mResponse: TJSONObject;
  mReasons: string;
  mItem: TJSONValue;
begin
  mResponse := Request(ADispatcher, 'textDocument/references', '{"textDocument":{"uri":"' + AUri.Replace('', '\') +
    '"},"position":' + APosition + ',"context":{"includeDeclaration":false}}');
  try
    Assert.IsTrue(mResponse.GetValue('result') is TJSONArray, mResponse.ToJSON);
    mReasons := '';
    for mItem in TJSONArray(mResponse.GetValue('result')) do
    begin
      mReasons := mReasons + TJSONObject(mItem).GetValue<string>('atlasConfidence.level') + ' ';
    end;
    Assert.AreEqual('sure sure inferred inferred inferred inferred', Trim(mReasons));
  finally
    mResponse.Free;
  end;
end;

/// <summary>Umbenennen nennt die Gründe der nicht geänderten Stellen.</summary>
procedure AssertRenameUnchangedReasons(const ADispatcher: TJsonRpcDispatcher; const AUri, APosition: string);
var
  mResponse: TJSONObject;
  mReasons: string;
  mItem: TJSONValue;
begin
  mResponse := Request(ADispatcher, 'textDocument/rename', '{"textDocument":{"uri":"' + AUri.Replace('', '\') +
    '"},"position":' + APosition + ',"newName":"Sichern"}');
  try
    Assert.IsTrue(mResponse.GetValue('result') is TJSONObject, mResponse.ToJSON);
    mReasons := '';
    for mItem in mResponse.GetValue<TJSONArray>('result.atlasUnchanged') do
    begin
      mReasons := mReasons + TJSONObject(mItem).GetValue<string>('atlasConfidence.reason') + ' ';
    end;
    Assert.AreEqual('interface virtual unresolved', Trim(mReasons));
  finally
    mResponse.Free;
  end;
end;

procedure TReferenceConfidenceTests.LspResponses;
var
  mStore: IDocumentStore;
  mReferences: TLspReferences;
  mRename: TLspRename;
  mDispatcher: TJsonRpcDispatcher;
  mUri, mPosition: string;
  mFiles: TReferenceFilesProvider;
  mProvider: TReferenceSettingsProvider;
begin
  mStore := TDocumentStore.Create;
  mUri := TDocumentUris.FromPath(cKundenFile);
  mStore.Open(mUri, 'delphi', 1, cUnitKunden);
  mFiles :=
    function: TArray<string>
    begin
      Result := TArray<string>.Create(cKundenFile, cHauptFile);
    end;
  mProvider :=
    function(const AUri: string): TReferenceSettings
    begin
      Result := TReferenceSettings.Default;
    end;
  mReferences := TLspReferences.Create(mStore, FIndex, ReadText, mFiles);
  mRename := TLspRename.Create(mStore, FIndex, ReadText, mFiles);
  mDispatcher := TJsonRpcDispatcher.Create;
  try
    mReferences.SettingsFor := mProvider;
    mRename.SettingsFor := mProvider;
    mReferences.Attach(mDispatcher);
    mRename.Attach(mDispatcher);
    mPosition := Format('{"line":%d,"character":%d}', [PositionOf(cUnitKunden, 'Speichern; override').Line,
      PositionOf(cUnitKunden, 'Speichern; override').Character]);
    AssertReferenceLevels(mDispatcher, mUri, mPosition);
    AssertRenameUnchangedReasons(mDispatcher, mUri, mPosition);
  finally
    mDispatcher.Free;
    mRename.Free;
    mReferences.Free;
    mFiles := nil;
    mProvider := nil;
    mStore := nil;
  end;
end;

procedure TReferenceConfidenceTests.RenameChangesOnlySure;
var
  mTree: TSyntaxTree;
  mEdits: TArray<TRenameEdit>;
  mEdit: TRenameEdit;
  mUnchanged: TArray<TReferenceLocation>;
  mLocation: TReferenceLocation;
  mLines: string;
begin
  mTree := TPascalParser.Parse(cUnitKunden);
  try
    mEdits := TLspRename.Edits(FResolver, FIndex, mTree, TReferenceSearch.Create(cKundenFile,
      PositionOf(cUnitKunden, 'Speichern; override'), True, [cKundenFile, cHauptFile], ReadText),
      TRenameRequest.Create('Sichern', False, Settings(True, False), nil), mUnchanged);
  finally
    mTree.Free;
  end;
  mLines := '';
  for mEdit in mEdits do
  begin
    mLines := mLines + Format('%s:%d ', [ChangeFileExt(ExtractFileName(mEdit.FileName), ''), mEdit.Range.StartPos.Line]);
  end;
  // Deklaration, Rumpf, sicherer Aufruf und die eindeutige Stelle im inaktiven Zweig.
  Assert.AreEqual('Kunden:10 Kunden:16 Haupt:6 Haupt:11', Trim(mLines));
  mLines := '';
  for mLocation in mUnchanged do
  begin
    mLines := mLines + Format('%d/%s ', [mLocation.Range.StartPos.Line, mLocation.Confidence.ReasonName]);
  end;
  Assert.AreEqual('7/interface 8/virtual 9/unresolved', Trim(mLines));
end;

procedure TReferenceConfidenceTests.IncomingCallsGroupedByConfidence;
var
  mItem: THierarchyItem;
  mCalls: TArray<THierarchyCall>;
  mCall: THierarchyCall;
  mJson: TJSONArray;
  mKinds: string;
begin
  mItem := Default(THierarchyItem);
  mItem.Name := 'Speichern';
  mItem.Container := 'TKunde';
  mItem.SymbolKind := TIndexSymbolKind.Method;
  mItem.FileName := cKundenFile;
  mItem.SelectionRange := TTextRange.Create(PositionOf(cUnitKunden, 'Speichern; override'),
    PositionOf(cUnitKunden, '; override'));
  mItem.Range := mItem.SelectionRange;
  mCalls := TLspHierarchies.IncomingCalls(THierarchyCallSource.Create(FResolver, FIndex, ReadText, nil), mItem,
    [cKundenFile, cHauptFile], Settings(True, False));
  mKinds := '';
  for mCall in mCalls do
  begin
    Assert.AreEqual('Lauf', mCall.Item.Name);
    mKinds := mKinds + mCall.Confidence.LevelName + '/' + mCall.Confidence.ReasonName + ' ';
  end;
  Assert.AreEqual('sure/ inferred/interface inferred/virtual inferred/unresolved inferred/inactiveBranch',
    Trim(mKinds));
  mJson := TLspHierarchies.CallsToJson(mCalls, 'from');
  try
    Assert.AreEqual('interface', (mJson.Items[1] as TJSONObject).GetValue<string>('atlasConfidence.reason'));
    Assert.AreEqual('sure', (mJson.Items[0] as TJSONObject).GetValue<string>('atlasConfidence.level'));
  finally
    mJson.Free;
  end;
  // Ohne Einstufung nur der sichere Aufrufer.
  Assert.AreEqual(1, Integer(Length(TLspHierarchies.IncomingCalls(THierarchyCallSource.Create(FResolver, FIndex,
    ReadText, nil), mItem, [cKundenFile, cHauptFile], Settings(False, False)))));
end;

procedure TReferenceConfidenceTests.McpListsSureThenInferred;
var
  mTools: TMcpCodeTools;
  mText: string;
begin
  mTools := TMcpCodeTools.Create(FIndex, ReadText,
    function: TArray<string>
    begin
      Result := TArray<string>.Create(cKundenFile, cHauptFile);
    end);
  try
    mText := mTools.References('TKunde.Speichern');
  finally
    mTools.Free;
  end;
  Assert.IsTrue(Pos('2 sicher, 4 erschlossen', mText) > 0, mText);
  Assert.IsTrue(Pos('Erschlossen, vor dem Umbenennen prüfen:', mText) > Pos('Haupt.pas:7: K.Speichern;', mText), mText);
  Assert.IsTrue(Pos('S.Speichern; – erschlossen (interface): Aufruf über ISpeicherbar.Speichern', mText) > 0, mText);
end;

procedure TReferenceConfidenceTests.McpRenameListsUnchanged;
var
  mTools: TMcpEditTools;
  mText: string;
begin
  mTools := TMcpEditTools.Create(FIndex, ReadText,
    procedure(const AFileName, AText: string)
    begin
    end,
    function: TArray<string>
    begin
      Result := TArray<string>.Create(cKundenFile, cHauptFile);
    end, nil);
  try
    mText := mTools.RenameSymbol(cKundenFile, 11, 15, 'Sichern', True);
  finally
    mTools.Free;
  end;
  Assert.IsTrue(Pos('Nicht geändert, bitte prüfen (3 erschlossene Stellen):', mText) > 0, mText);
  Assert.IsTrue(Pos('Haupt.pas:8:5 – interface:', mText) > 0, mText);
  Assert.IsTrue(Pos('K.Sichern;', mText) > 0, mText);
  Assert.IsFalse(Pos('S.Sichern;', mText) > 0, mText);
end;

procedure TReferenceConfidenceTests.InferredCostsLittle;
const
  cCount = 300;
  cRounds = 3;
var
  mText: string;
  mTree: TSyntaxTree;
  mIndex, mRound: Integer;
  mWatch: TStopwatch;
  mSure, mInferred: Int64;
  mRead: TReferenceReadText;
begin
  // Viele sichere Aufrufe: Die Einstufung darf sie kaum verteuern.
  mText := 'unit Haupt;'#10'interface'#10'uses Kunden;'#10'implementation'#10'procedure Lauf(K: TKunde);'#10 +
    'begin'#10;
  for mIndex := 1 to cCount do
  begin
    mText := mText + '  K.Speichern;'#10;
  end;
  mText := mText + 'end;'#10'end.';
  mRead :=
    function(const AFileName: string; out AResult: string): Boolean
    begin
      Result := True;
      if SameText(AFileName, cHauptFile) then
      begin
        AResult := mText;
      end
      else
      begin
        Result := ReadText(AFileName, AResult);
      end;
    end;
  mTree := TPascalParser.Parse(cUnitKunden);
  try
    mSure := 0;
    mInferred := 0;
    for mRound := 1 to cRounds do
    begin
      mWatch := TStopwatch.StartNew;
      Assert.AreEqual(cCount + 1, Integer(Length(TLspReferences.Find(FResolver, FIndex, mTree,
        TReferenceSearch.Create(cKundenFile, PositionOf(cUnitKunden, 'Speichern; override'), False, [cKundenFile,
        cHauptFile], mRead), Settings(False, False), nil))));
      Inc(mSure, mWatch.ElapsedMilliseconds);
      mWatch := TStopwatch.StartNew;
      Assert.AreEqual(cCount + 1, Integer(Length(TLspReferences.Find(FResolver, FIndex, mTree,
        TReferenceSearch.Create(cKundenFile, PositionOf(cUnitKunden, 'Speichern; override'), False, [cKundenFile,
        cHauptFile], mRead), Settings(True, True), nil))));
      Inc(mInferred, mWatch.ElapsedMilliseconds);
    end;
  finally
    mTree.Free;
  end;
  mText := '';
  mRead := nil;
  // 20 % plus 50 ms Spielraum für Zeitgeber und kurze Läufe.
  Assert.IsTrue(mInferred <= mSure * 6 div 5 + 50, Format('mit Einstufung %d ms, nur sicher %d ms',
    [mInferred, mSure]));
end;

initialization
  TDUnitX.RegisterTestFixture(TReferenceConfidenceTests);

end.
