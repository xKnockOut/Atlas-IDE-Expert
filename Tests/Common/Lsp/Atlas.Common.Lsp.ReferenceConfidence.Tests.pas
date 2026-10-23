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
  KundenFile = 'C:\P\Kunden.pas';
  HauptFile = 'C:\P\Haupt.pas';
  WerteFile = 'C:\P\Werte.pas';

  UnitKunden =
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

  UnitHaupt =
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

  UnitWerte =
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
  Index, Line, LineStart, I: Integer;
begin
  Index := Pos(AMarker, AText);
  if Index = 0 then
    raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
  Line := 0;
  LineStart := 1;
  for I := 1 to Index - 1 do
    if AText[I] = #10 then
    begin
      Inc(Line);
      LineStart := I + 1;
    end;
  Result := TTextPosition.Create(Line, Index - LineStart);
end;

{ TReferenceConfidenceTests }

procedure TReferenceConfidenceTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitKunden, KundenFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitWerte, WerteFile, nil));
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
  if SameText(AFileName, KundenFile) then
    AText := UnitKunden
  else if SameText(AFileName, HauptFile) then
    AText := UnitHaupt
  else if SameText(AFileName, WerteFile) then
    AText := UnitWerte
  else
    Result := False;
end;

function TReferenceConfidenceTests.FindSpeichern(const ASettings: TReferenceSettings): TArray<TReferenceLocation>;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(UnitKunden);
  try
    Result := TLspReferences.Find(FResolver, FIndex, Tree, KundenFile, PositionOf(UnitKunden, 'Speichern; override'),
      True, [KundenFile, HauptFile], ReadText, ASettings, nil);
  finally
    Tree.Free;
  end;
end;

function TReferenceConfidenceTests.Describe(const ALocations: TArray<TReferenceLocation>): string;
var
  Location: TReferenceLocation;
begin
  Result := '';
  for Location in ALocations do
  begin
    Result := Result + Format('%s:%d:%d=%s', [ChangeFileExt(ExtractFileName(Location.FileName), ''),
      Location.Range.StartPos.Line, Location.Range.StartPos.Character, Location.Confidence.LevelName]);
    if not Location.Confidence.IsSure then
      Result := Result + '/' + Location.Confidence.ReasonName;
    Result := Result + ' ';
  end;
  Result := Trim(Result);
end;

function TReferenceConfidenceTests.HitAt(const ALocations: TArray<TReferenceLocation>; const AFileName: string;
  ALine: Integer; out ALocation: TReferenceLocation): Boolean;
var
  Location: TReferenceLocation;
begin
  for Location in ALocations do
    if SameText(Location.FileName, AFileName) and (Location.Range.StartPos.Line = ALine) then
    begin
      ALocation := Location;
      Exit(True);
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
  Location: TReferenceLocation;
begin
  Assert.IsTrue(HitAt(FindSpeichern(Settings(True, False)), HauptFile, 7, Location), 'S.Speichern fehlt');
  Assert.AreEqual('interface', Location.Confidence.ReasonName);
  Assert.IsFalse(Location.Confidence.Renameable);
  Assert.IsTrue(Pos('ISpeicherbar.Speichern', Location.Confidence.Detail) > 0, Location.Confidence.Detail);
  Assert.IsTrue(Pos('eine von 2 Umsetzungen', Location.Confidence.Detail) > 0, Location.Confidence.Detail);
end;

procedure TReferenceConfidenceTests.VirtualCallIsInferred;
var
  Location: TReferenceLocation;
begin
  Assert.IsTrue(HitAt(FindSpeichern(Settings(True, False)), HauptFile, 8, Location), 'B.Speichern fehlt');
  Assert.AreEqual('virtual', Location.Confidence.ReasonName);
  Assert.IsTrue(Pos('TKunde.Speichern', Location.Confidence.Detail) > 0, Location.Confidence.Detail);
end;

procedure TReferenceConfidenceTests.UnknownTypeIsUnresolved;
var
  Location: TReferenceLocation;
begin
  Assert.IsTrue(HitAt(FindSpeichern(Settings(True, False)), HauptFile, 9, Location), 'U.Speichern fehlt');
  Assert.AreEqual('unresolved', Location.Confidence.ReasonName);
  Assert.IsFalse(Location.Confidence.Renameable);
end;

procedure TReferenceConfidenceTests.InactiveBranchMatchedIsRenameable;
var
  Location: TReferenceLocation;
begin
  Assert.IsTrue(HitAt(FindSpeichern(Settings(True, False)), HauptFile, 11, Location), 'Stelle in NIE fehlt');
  Assert.AreEqual('inactiveBranch', Location.Confidence.ReasonName);
  Assert.IsTrue(Location.Confidence.Matched);
  Assert.IsTrue(Location.Confidence.Renameable);
  Assert.IsTrue(Pos('NIE', Location.Confidence.Detail) > 0, Location.Confidence.Detail);
end;

procedure TReferenceConfidenceTests.TextMatchesOnlyWithSetting;
var
  Location: TReferenceLocation;
begin
  Assert.IsFalse(HitAt(FindSpeichern(Settings(True, False)), HauptFile, 13, Location), 'ohne textMatches');
  Assert.IsTrue(HitAt(FindSpeichern(Settings(True, True)), HauptFile, 13, Location), 'mit textMatches');
  Assert.AreEqual('text', Location.Confidence.ReasonName);
  // Nur der Name zwischen den Hochkommas.
  Assert.AreEqual(13, Location.Range.StartPos.Character);
  Assert.AreEqual(22, Location.Range.EndPos.Character);
end;

function FindZeige(AResolver: TNameResolver; const AIndex: ISymbolIndex; const AMarker: string;
  const AReadText: TReferenceReadText; const ASettings: TReferenceSettings): TArray<TReferenceLocation>;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(UnitWerte);
  try
    Result := TLspReferences.Find(AResolver, AIndex, Tree, WerteFile, PositionOf(UnitWerte, AMarker), False,
      TArray<string>.Create(WerteFile), AReadText, ASettings, nil);
  finally
    Tree.Free;
  end;
end;

procedure TReferenceConfidenceTests.AmbiguousOverload;
var
  Found: TArray<TReferenceLocation>;
  Location: TReferenceLocation;
begin
  Found := FindZeige(FResolver, FIndex, 'Zeige(A: Integer); overload', ReadText, Settings(True, False));
  Assert.IsTrue(HitAt(Found, WerteFile, 14, Location), 'Zeige(1) fehlt: ' + Describe(Found));
  Assert.IsTrue(Location.Confidence.IsSure, Describe(Found));
  Assert.IsTrue(HitAt(Found, WerteFile, 13, Location), 'Zeige(V) fehlt: ' + Describe(Found));
  Assert.AreEqual('ambiguous', Location.Confidence.ReasonName);
  // Wie vor #1119 mit umbenannt.
  Assert.IsTrue(Location.Confidence.Matched);
  Assert.IsTrue(Location.Confidence.Renameable);
  // Köpfe von Deklaration und Rumpf sind keine Aufrufe.
  Assert.IsTrue(HitAt(Found, WerteFile, 5, Location), Describe(Found));
  Assert.IsTrue(Location.Confidence.IsSure, Describe(Found));
  // Ohne Einstufung sicher wie bisher.
  Found := FindZeige(FResolver, FIndex, 'Zeige(A: Integer); overload', ReadText, Settings(False, False));
  Assert.IsTrue(HitAt(Found, WerteFile, 13, Location), Describe(Found));
  Assert.IsTrue(Location.Confidence.IsSure);
end;

procedure TReferenceConfidenceTests.InactiveBranchInEditorTree;
var
  Tree: TSyntaxTree;
  Found: TArray<TReferenceLocation>;
  Location: TReferenceLocation;
begin
  // Wie im Editor: Der Parser überspringt den Zweig NIE, die Token-Liste enthält ihn.
  Tree := TPascalParser.ParseActive(UnitHaupt, nil);
  try
    Found := TLspReferences.Find(FResolver, FIndex, Tree, HauptFile, PositionOf(UnitHaupt, 'Speichern;'),
      False, [KundenFile, HauptFile], ReadText, Settings(True, False), nil);
    Assert.IsTrue(HitAt(Found, HauptFile, 11, Location), 'Stelle in NIE fehlt: ' + Describe(Found));
    Assert.AreEqual('inactiveBranch', Location.Confidence.ReasonName);
    Assert.IsTrue(Location.Confidence.Renameable);
    // Ohne Einstufung wie vor #1119: sicher.
    Found := TLspReferences.Find(FResolver, FIndex, Tree, HauptFile, PositionOf(UnitHaupt, 'Speichern;'),
      False, [KundenFile, HauptFile], ReadText, Settings(False, False), nil);
    Assert.IsTrue(HitAt(Found, HauptFile, 11, Location), Describe(Found));
    Assert.IsTrue(Location.Confidence.IsSure);
  finally
    Tree.Free;
  end;
end;

procedure TReferenceConfidenceTests.RoutineHeaderIsNoHit;
var
  Location: TReferenceLocation;
begin
  Assert.IsFalse(HitAt(FindSpeichern(Settings(True, True)), KundenFile, 13, Location), 'TBasis.Speichern');
  Assert.IsFalse(HitAt(FindSpeichern(Settings(True, True)), KundenFile, 7, Location), 'Deklaration in TBasis');
  Assert.IsFalse(HitAt(FindSpeichern(Settings(True, True)), KundenFile, 4, Location), 'Deklaration im Interface');
end;

procedure TReferenceConfidenceTests.ConfidenceJson;
var
  Json: TJSONObject;
begin
  Json := TReferenceConfidence.Sure.ToJson;
  try
    Assert.AreEqual('{"level":"sure"}', Json.ToJSON);
  finally
    Json.Free;
  end;
  Json := TReferenceConfidence.Inferred(TReferenceReason.Interface_, 'Aufruf I.M', False).ToJson;
  try
    Assert.AreEqual('{"level":"inferred","reason":"interface","detail":"Aufruf I.M"}', Json.ToJSON);
  finally
    Json.Free;
  end;
end;

function Request(ADispatcher: TJsonRpcDispatcher; const AMethod, AParams: string): TJSONObject;
var
  Message: TJSONObject;
begin
  Message := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":1,"method":"' + AMethod + '","params":' + AParams +
    '}') as TJSONObject;
  try
    Result := ADispatcher.DispatchMessage(Message);
  finally
    Message.Free;
  end;
end;

procedure TReferenceConfidenceTests.LspResponses;
var
  Store: IDocumentStore;
  References: TLspReferences;
  Rename: TLspRename;
  Dispatcher: TJsonRpcDispatcher;
  Response: TJSONObject;
  Uri, Position, Reasons: string;
  Item: TJSONValue;
  Files: TReferenceFilesProvider;
  Provider: TReferenceSettingsProvider;
begin
  Store := TDocumentStore.Create;
  Uri := TDocumentUris.FromPath(KundenFile);
  Store.Open(Uri, 'delphi', 1, UnitKunden);
  Files :=
    function: TArray<string>
    begin
      Result := TArray<string>.Create(KundenFile, HauptFile);
    end;
  Provider :=
    function(const AUri: string): TReferenceSettings
    begin
      Result := TReferenceSettings.Default;
    end;
  References := TLspReferences.Create(Store, FIndex, ReadText, Files);
  Rename := TLspRename.Create(Store, FIndex, ReadText, Files);
  Dispatcher := TJsonRpcDispatcher.Create;
  try
    References.SettingsFor := Provider;
    Rename.SettingsFor := Provider;
    References.Attach(Dispatcher);
    Rename.Attach(Dispatcher);
    Position := Format('{"line":%d,"character":%d}', [PositionOf(UnitKunden, 'Speichern; override').Line,
      PositionOf(UnitKunden, 'Speichern; override').Character]);
    Response := Request(Dispatcher, 'textDocument/references', '{"textDocument":{"uri":"' + Uri.Replace('', '\') +
      '"},"position":' + Position + ',"context":{"includeDeclaration":false}}');
    try
      Assert.IsTrue(Response.GetValue('result') is TJSONArray, Response.ToJSON);
      Reasons := '';
      for Item in TJSONArray(Response.GetValue('result')) do
        Reasons := Reasons + TJSONObject(Item).GetValue<string>('atlasConfidence.level') + ' ';
      Assert.AreEqual('sure sure inferred inferred inferred inferred', Trim(Reasons));
    finally
      Response.Free;
    end;
    Response := Request(Dispatcher, 'textDocument/rename', '{"textDocument":{"uri":"' + Uri.Replace('', '\') +
      '"},"position":' + Position + ',"newName":"Sichern"}');
    try
      Assert.IsTrue(Response.GetValue('result') is TJSONObject, Response.ToJSON);
      Reasons := '';
      for Item in Response.GetValue<TJSONArray>('result.atlasUnchanged') do
        Reasons := Reasons + TJSONObject(Item).GetValue<string>('atlasConfidence.reason') + ' ';
      Assert.AreEqual('interface virtual unresolved', Trim(Reasons));
    finally
      Response.Free;
    end;
  finally
    Dispatcher.Free;
    Rename.Free;
    References.Free;
    Files := nil;
    Provider := nil;
    Store := nil;
  end;
end;

procedure TReferenceConfidenceTests.RenameChangesOnlySure;
var
  Tree: TSyntaxTree;
  Edits: TArray<TRenameEdit>;
  Edit: TRenameEdit;
  Unchanged: TArray<TReferenceLocation>;
  Location: TReferenceLocation;
  Lines: string;
begin
  Tree := TPascalParser.Parse(UnitKunden);
  try
    Edits := TLspRename.Edits(FResolver, FIndex, Tree, KundenFile, PositionOf(UnitKunden, 'Speichern; override'),
      'Sichern', [KundenFile, HauptFile], ReadText, nil, False, Settings(True, False), Unchanged);
  finally
    Tree.Free;
  end;
  Lines := '';
  for Edit in Edits do
    Lines := Lines + Format('%s:%d ', [ChangeFileExt(ExtractFileName(Edit.FileName), ''), Edit.Range.StartPos.Line]);
  // Deklaration, Rumpf, sicherer Aufruf und die eindeutige Stelle im inaktiven Zweig.
  Assert.AreEqual('Kunden:10 Kunden:16 Haupt:6 Haupt:11', Trim(Lines));
  Lines := '';
  for Location in Unchanged do
    Lines := Lines + Format('%d/%s ', [Location.Range.StartPos.Line, Location.Confidence.ReasonName]);
  Assert.AreEqual('7/interface 8/virtual 9/unresolved', Trim(Lines));
end;

procedure TReferenceConfidenceTests.IncomingCallsGroupedByConfidence;
var
  Item: THierarchyItem;
  Calls: TArray<THierarchyCall>;
  Call: THierarchyCall;
  Json: TJSONArray;
  Kinds: string;
begin
  Item := Default(THierarchyItem);
  Item.Name := 'Speichern';
  Item.Container := 'TKunde';
  Item.SymbolKind := TIndexSymbolKind.Method;
  Item.FileName := KundenFile;
  Item.SelectionRange := TTextRange.Create(PositionOf(UnitKunden, 'Speichern; override'),
    PositionOf(UnitKunden, '; override'));
  Item.Range := Item.SelectionRange;
  Calls := TLspHierarchies.IncomingCalls(FResolver, FIndex, Item, [KundenFile, HauptFile], ReadText,
    Settings(True, False), nil);
  Kinds := '';
  for Call in Calls do
  begin
    Assert.AreEqual('Lauf', Call.Item.Name);
    Kinds := Kinds + Call.Confidence.LevelName + '/' + Call.Confidence.ReasonName + ' ';
  end;
  Assert.AreEqual('sure/ inferred/interface inferred/virtual inferred/unresolved inferred/inactiveBranch',
    Trim(Kinds));
  Json := TLspHierarchies.CallsToJson(Calls, 'from');
  try
    Assert.AreEqual('interface', (Json.Items[1] as TJSONObject).GetValue<string>('atlasConfidence.reason'));
    Assert.AreEqual('sure', (Json.Items[0] as TJSONObject).GetValue<string>('atlasConfidence.level'));
  finally
    Json.Free;
  end;
  // Ohne Einstufung nur der sichere Aufrufer.
  Assert.AreEqual(1, Integer(Length(TLspHierarchies.IncomingCalls(FResolver, FIndex, Item, [KundenFile, HauptFile],
    ReadText, Settings(False, False), nil))));
end;

procedure TReferenceConfidenceTests.McpListsSureThenInferred;
var
  Tools: TMcpCodeTools;
  Text: string;
begin
  Tools := TMcpCodeTools.Create(FIndex, ReadText,
    function: TArray<string>
    begin
      Result := TArray<string>.Create(KundenFile, HauptFile);
    end);
  try
    Text := Tools.References('TKunde.Speichern');
  finally
    Tools.Free;
  end;
  Assert.IsTrue(Pos('2 sicher, 4 erschlossen', Text) > 0, Text);
  Assert.IsTrue(Pos('Erschlossen, vor dem Umbenennen prüfen:', Text) > Pos('Haupt.pas:7: K.Speichern;', Text), Text);
  Assert.IsTrue(Pos('S.Speichern; – erschlossen (interface): Aufruf über ISpeicherbar.Speichern', Text) > 0, Text);
end;

procedure TReferenceConfidenceTests.McpRenameListsUnchanged;
var
  Tools: TMcpEditTools;
  Text: string;
begin
  Tools := TMcpEditTools.Create(FIndex, ReadText,
    procedure(const AFileName, AText: string)
    begin
    end,
    function: TArray<string>
    begin
      Result := TArray<string>.Create(KundenFile, HauptFile);
    end, nil);
  try
    Text := Tools.RenameSymbol(KundenFile, 11, 15, 'Sichern', True);
  finally
    Tools.Free;
  end;
  Assert.IsTrue(Pos('Nicht geändert, bitte prüfen (3 erschlossene Stellen):', Text) > 0, Text);
  Assert.IsTrue(Pos('Haupt.pas:8:5 – interface:', Text) > 0, Text);
  Assert.IsTrue(Pos('K.Sichern;', Text) > 0, Text);
  Assert.IsFalse(Pos('S.Sichern;', Text) > 0, Text);
end;

procedure TReferenceConfidenceTests.InferredCostsLittle;
const
  Count = 300;
  Rounds = 3;
var
  Text: string;
  Tree: TSyntaxTree;
  Index, Round: Integer;
  Watch: TStopwatch;
  Sure, Inferred: Int64;
  Read: TReferenceReadText;
begin
  // Viele sichere Aufrufe: Die Einstufung darf sie kaum verteuern.
  Text := 'unit Haupt;'#10'interface'#10'uses Kunden;'#10'implementation'#10'procedure Lauf(K: TKunde);'#10 +
    'begin'#10;
  for Index := 1 to Count do
    Text := Text + '  K.Speichern;'#10;
  Text := Text + 'end;'#10'end.';
  Read :=
    function(const AFileName: string; out AResult: string): Boolean
    begin
      Result := True;
      if SameText(AFileName, HauptFile) then
        AResult := Text
      else
        Result := ReadText(AFileName, AResult);
    end;
  Tree := TPascalParser.Parse(UnitKunden);
  try
    Sure := 0;
    Inferred := 0;
    for Round := 1 to Rounds do
    begin
      Watch := TStopwatch.StartNew;
      Assert.AreEqual(Count + 1, Integer(Length(TLspReferences.Find(FResolver, FIndex, Tree, KundenFile,
        PositionOf(UnitKunden, 'Speichern; override'), False, [KundenFile, HauptFile], Read,
        Settings(False, False), nil))));
      Inc(Sure, Watch.ElapsedMilliseconds);
      Watch := TStopwatch.StartNew;
      Assert.AreEqual(Count + 1, Integer(Length(TLspReferences.Find(FResolver, FIndex, Tree, KundenFile,
        PositionOf(UnitKunden, 'Speichern; override'), False, [KundenFile, HauptFile], Read,
        Settings(True, True), nil))));
      Inc(Inferred, Watch.ElapsedMilliseconds);
    end;
  finally
    Tree.Free;
  end;
  Text := '';
  Read := nil;
  // 20 % plus 50 ms Spielraum für Zeitgeber und kurze Läufe.
  Assert.IsTrue(Inferred <= Sure * 6 div 5 + 50, Format('mit Einstufung %d ms, nur sicher %d ms',
    [Inferred, Sure]));
end;

initialization
  TDUnitX.RegisterTestFixture(TReferenceConfidenceTests);

end.
