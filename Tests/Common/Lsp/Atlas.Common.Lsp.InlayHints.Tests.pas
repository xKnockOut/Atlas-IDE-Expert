unit Atlas.Common.Lsp.InlayHints.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.InlayHints;

type
  [TestFixture]
  TLspInlayHintsTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function Describe(const AHints: TArray<TInlayHint>): string;
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ParameterNamesBeforeArguments;
    [Test]
    procedure InferredTypesOfInlineVariables;
    [Test]
    procedure EndMarkersBehindLongBlocks;
    /// <summary>#862: hinter ^C in Konstanten der Code, nicht in Ausdrücken; abschaltbar; data.controlChar.</summary>
    [Test]
    procedure ControlCharCodesBehindConstants;
    /// <summary>#686: „ohne Self“ hinter dem Kopf von Methoden ohne Self; aus in Default; data.methodWithoutSelf.
    /// </summary>
    [Test]
    procedure MethodMarkersBehindHeaders;
    [Test]
    procedure SettingsSwitchHintsOffAndSort;
    /// <summary>#620: jede Blockart mit Beschriftung und Blockanfang, mit Mindestlänge 1.</summary>
    [Test]
    procedure EndMarkersForEveryBlockKind;
    /// <summary>#620: Kommentar hinter dem end, kurze Blöcke und lange Bedingungen.</summary>
    [Test]
    procedure EndMarkersSkipCommentsAndShorten;
    /// <summary>#620: Blockanfang in data, Mindestlänge aus der Anfrage.</summary>
    [Test]
    procedure EndMarkersCarryBlockStartAndRequestMinLines;
    /// <summary>#453: for var X in …, Inline-Konstanten und generische Typen.</summary>
    [Test]
    procedure InferredTypesOfForInConstAndGenerics;
    /// <summary>#453: „Typ ausschreiben“ mit uses-Eintrag für die Unit des Typs.</summary>
    [Test]
    procedure ExplicitTypeWritesTypeAndUses;
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
  Atlas.Common.Editing.CodeActions;

const
  HauptFile = 'C:\P\Haupt.pas';
  WerkzeugFile = 'C:\P\Werkzeug.pas';

  UnitWerkzeug =
    'unit Werkzeug;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFarbe = (Rot, Gruen);'#10 +
    '  TFoo = class'#10 +
    '    constructor Create;'#10 +
    '  end;'#10 +
    'function Rechne(Wert: Integer; const Faktor: Double): Integer;'#10 +
    'implementation'#10 +
    'constructor TFoo.Create;'#10 +
    'begin'#10 +
    'end;'#10 +
    'function Rechne(Wert: Integer; const Faktor: Double): Integer;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

  UnitHaupt =
    'unit Haupt;'#10 +                               // 0
    'interface'#10 +                                 // 1
    'uses Werkzeug;'#10 +                            // 2
    'implementation'#10 +                            // 3
    'procedure Arbeite(Wert: Integer);'#10 +         // 4
    'begin'#10 +                                     // 5
    '  Rechne(1, 2.5);'#10 +                         // 6
    '  Rechne(Wert, Wert);'#10 +                     // 7
    '  var A := 1;'#10 +                             // 8
    '  var B := ''Text'';'#10 +                      // 9
    '  var C := TFoo.Create;'#10 +                   // 10
    '  var D := Rechne(1, 2);'#10 +                  // 11
    '  var E: Integer := 3;'#10 +                    // 12
    '  var F := Rot;'#10 +                           // 13
    '  if Assigned(nil) then'#10 +                   // 14
    '  begin'#10 +                                   // 15
    '    A := 2;'#10 +                               // 16
    '  end;'#10 +                                    // 17
    'end;'#10 +                                      // 18
    'end.';

  UnitBloecke =
    'unit Bloecke;'#10 +                                   // 0
    'interface'#10 +                                       // 1
    'type'#10 +                                            // 2
    '  TKunde = class'#10 +                                // 3
    '    procedure Speichern;'#10 +                        // 4
    '  end;'#10 +                                          // 5
    '  TPunkt = record'#10 +                               // 6
    '    X: Integer;'#10 +                                 // 7
    '  end;'#10 +                                          // 8
    'implementation'#10 +                                  // 9
    'procedure TKunde.Speichern;'#10 +                     // 10
    'var'#10 +                                             // 11
    '  I, Art, Betrag, Limit: Integer;'#10 +               // 12
    'begin'#10 +                                           // 13
    '  for I := 0 to 9 do'#10 +                            // 14
    '  begin'#10 +                                         // 15
    '  end;'#10 +                                          // 16
    '  while not Fertig do'#10 +                           // 17
    '  begin'#10 +                                         // 18
    '  end;'#10 +                                          // 19
    '  case Art of'#10 +                                   // 20
    '    1: ;'#10 +                                        // 21
    '  end;'#10 +                                          // 22
    '  if Betrag > Limit then'#10 +                        // 23
    '  begin'#10 +                                         // 24
    '  end;'#10 +                                          // 25
    '  try'#10 +                                           // 26
    '  finally'#10 +                                       // 27
    '  end;'#10 +                                          // 28
    '  try'#10 +                                           // 29
    '  except'#10 +                                        // 30
    '  end;'#10 +                                          // 31
    'end;'#10 +                                            // 32
    'end.';

  UnitKommentar =
    'unit K;'#10 +                                         // 0
    'implementation'#10 +                                  // 1
    'procedure P;'#10 +                                    // 2
    'begin'#10 +                                           // 3
    '  if EineSehrLangeBedingungMitVielenZeichen and NochEineBedingung then'#10 + // 4
    '  begin'#10 +                                         // 5
    '  end;'#10 +                                          // 6
    '  while A do'#10 +                                    // 7
    '  begin'#10 +                                         // 8
    '  end; // Schleife'#10 +                              // 9
    'end;'#10 +                                            // 10
    'end.';

  DatenFile = 'C:\P\Daten.pas';
  QuelleFile = 'C:\P\Quelle.pas';
  NutzerFile = 'C:\P\Nutzer.pas';

  UnitDaten =
    'unit Daten;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TDaten = class'#10 +
    '  end;'#10 +
    '  TEnum<T> = class'#10 +
    '    function GetCurrent: T;'#10 +
    '    function MoveNext: Boolean;'#10 +
    '    property Current: T read GetCurrent;'#10 +
    '  end;'#10 +
    '  TListe<T> = class'#10 +
    '    function GetEnumerator: TEnum<T>;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function TEnum<T>.GetCurrent: T;'#10 +
    'begin'#10 +
    'end;'#10 +
    'function TEnum<T>.MoveNext: Boolean;'#10 +
    'begin'#10 +
    'end;'#10 +
    'function TListe<T>.GetEnumerator: TEnum<T>;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

  UnitQuelle =
    'unit Quelle;'#10 +
    'interface'#10 +
    'uses Daten;'#10 +
    'var'#10 +
    '  Kunden: TListe<TDaten>;'#10 +
    'function Lade: TDaten;'#10 +
    'implementation'#10 +
    'function Lade: TDaten;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

  UnitNutzer =
    'unit Nutzer;'#10 +                              // 0
    'interface'#10 +                                 // 1
    'uses Quelle;'#10 +                              // 2
    'implementation'#10 +                            // 3
    'procedure P;'#10 +                              // 4
    'var'#10 +                                       // 5
    '  Zahlen: TArray<Integer>;'#10 +                // 6
    '  Text: string;'#10 +                           // 7
    'begin'#10 +                                     // 8
    '  var X := Lade;'#10 +                          // 9
    '  for var Z in Zahlen do'#10 +                  // 10
    '    ;'#10 +                                     // 11
    '  for var K in Kunden do'#10 +                  // 12
    '    ;'#10 +                                     // 13
    '  for var C in Text do'#10 +                    // 14
    '    ;'#10 +                                     // 15
    '  const N = 5;'#10 +                            // 16
    '  for var T: Integer in Zahlen do'#10 +         // 17
    '    ;'#10 +                                     // 18
    'end;'#10 +                                      // 19
    'end.';

function ReadFile(const AFileName: string; out AText: string): Boolean;
begin
  AText := UnitWerkzeug;
  Result := SameText(AFileName, WerkzeugFile);
end;

function WholeFile: TTextRange;
begin
  Result := TTextRange.Create(TTextPosition.Create(0, 0), TTextPosition.Create(100, 0));
end;

{ TLspInlayHintsTests }

procedure TLspInlayHintsTests.WarmUpFirstUse;
begin
  Setup;
  try
    EndMarkersCarryBlockStartAndRequestMinLines;
  finally
    TearDown;
  end;
end;

procedure TLspInlayHintsTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitWerkzeug, WerkzeugFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspInlayHintsTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TLspInlayHintsTests.Describe(const AHints: TArray<TInlayHint>): string;
var
  Hint: TInlayHint;
begin
  Result := '';
  for Hint in AHints do
    Result := Result + Format('%d:%d %s|', [Hint.Position.Line, Hint.Position.Character, Hint.Text]);
end;

procedure TLspInlayHintsTests.ParameterNamesBeforeArguments;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(UnitHaupt);
  try
    // Zeile 7: Wert heißt schon so, Faktor nicht. Zeile 11 ebenso; der Kopf in Zeile 4 bekommt keine.
    Assert.AreEqual('6:9 Wert:|6:12 Faktor:|7:15 Faktor:|11:18 Wert:|11:21 Faktor:|',
      Describe(TLspInlayHints.ParameterNames(FResolver, FIndex, Tree, UnitHaupt, HauptFile, WholeFile, ReadFile)));
  finally
    Tree.Free;
  end;
end;

procedure TLspInlayHintsTests.InferredTypesOfInlineVariables;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(UnitHaupt);
  try
    Assert.AreEqual('8:7 : Integer|9:7 : string|10:7 : TFoo|11:7 : Integer|13:7 : TFarbe|',
      Describe(TLspInlayHints.InferredTypes(FResolver, Tree, HauptFile, WholeFile)));
  finally
    Tree.Free;
  end;
end;

procedure TLspInlayHintsTests.InferredTypesOfForInConstAndGenerics;
var
  Tree: TSyntaxTree;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitDaten, DatenFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitQuelle, QuelleFile, nil));
  Tree := TPascalParser.Parse(UnitNutzer);
  try
    // Zeile 17 hat schon einen Typ.
    Assert.AreEqual('9:7 : TDaten|10:11 : Integer|12:11 : TDaten|14:11 : Char|16:9 : Integer|',
      Describe(TLspInlayHints.InferredTypes(FResolver, Tree, NutzerFile, WholeFile)));
  finally
    Tree.Free;
  end;
end;

procedure TLspInlayHintsTests.ExplicitTypeWritesTypeAndUses;
var
  Tree: TSyntaxTree;
  Action: TCodeAction;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitDaten, DatenFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitQuelle, QuelleFile, nil));
  Tree := TPascalParser.Parse(UnitNutzer);
  try
    // Auf dem Namen X: ": TDaten" und uses Daten, weil Nutzer nur Quelle einbindet.
    Assert.IsTrue(TLspInlayHints.ExplicitTypeAction(FResolver, Tree, NutzerFile, TTextPosition.Create(9, 6), #10,
      Action));
    Assert.AreEqual('Typ ausschreiben', Action.Title);
    Assert.AreEqual(2, Integer(Length(Action.Edits)));
    Assert.AreEqual(': TDaten', Action.Edits[0].NewText);
    Assert.AreEqual(9, Action.Edits[0].Range.StartPos.Line);
    Assert.AreEqual(7, Action.Edits[0].Range.StartPos.Character);
    Assert.IsTrue(Action.Edits[1].NewText.Contains('Daten'), Action.Edits[1].NewText);
    // Integer braucht keine Unit.
    Assert.IsTrue(TLspInlayHints.ExplicitTypeAction(FResolver, Tree, NutzerFile, TTextPosition.Create(10, 10), #10,
      Action));
    Assert.AreEqual(1, Integer(Length(Action.Edits)));
    Assert.AreEqual(': Integer', Action.Edits[0].NewText);
    // Mit Typ bzw. neben dem Namen nichts.
    Assert.IsFalse(TLspInlayHints.ExplicitTypeAction(FResolver, Tree, NutzerFile, TTextPosition.Create(17, 10), #10,
      Action));
    Assert.IsFalse(TLspInlayHints.ExplicitTypeAction(FResolver, Tree, NutzerFile, TTextPosition.Create(9, 12), #10,
      Action));
  finally
    Tree.Free;
  end;
end;

procedure TLspInlayHintsTests.ControlCharCodesBehindConstants;
const
  Source = 'unit C;'#10'interface'#10'const'#10'  CtrlC = ^C;'#10'  Esc = ^[;'#10'  Text = ''a''^M;'#10 +
    'implementation'#10'procedure P(Key: Char);'#10'begin'#10'  if Key = ^M then'#10'    Exit;'#10'end;'#10'end.';
var
  Tree: TSyntaxTree;
  Settings: TInlayHintSettings;
  Json: TJSONArray;
begin
  Tree := TPascalParser.Parse(Source);
  try
    Assert.AreEqual('3:12 #3|4:10 #27|', Describe(TLspInlayHints.ControlChars(Tree, Source, WholeFile)));
    Settings := TInlayHintSettings.Default;
    Settings.ParameterNames := False;
    Settings.InferredTypes := False;
    Settings.EndMarkers := False;
    Assert.AreEqual('3:12 #3|4:10 #27|', Describe(TLspInlayHints.Collect(FResolver, FIndex, Tree, Source, 'C.pas',
      WholeFile, Settings, nil)));
    Settings.ControlChars := False;
    Assert.AreEqual('', Describe(TLspInlayHints.Collect(FResolver, FIndex, Tree, Source, 'C.pas', WholeFile,
      Settings, nil)));
    Json := TLspInlayHints.ToJson(TLspInlayHints.ControlChars(Tree, Source, WholeFile));
    try
      Assert.AreEqual(27, Json.Items[1].GetValue<Integer>('data.controlChar.code'));
    finally
      Json.Free;
    end;
  finally
    Tree.Free;
  end;
end;

procedure TLspInlayHintsTests.MethodMarkersBehindHeaders;
const
  Source = 'unit R;'#10'interface'#10'type'#10'  TRechner = class'#10'  private'#10'    FWert: Integer;'#10 +
    '  public'#10'    function Doppelt(A: Integer): Integer;'#10'    function Wert: Integer;'#10'  end;'#10 +
    'implementation'#10'function TRechner.Doppelt(A: Integer): Integer;'#10'begin'#10'  Result := A * 2;'#10 +
    'end;'#10'function TRechner.Wert: Integer;'#10'begin'#10'  Result := FWert;'#10'end;'#10'end.';
var
  Tree: TSyntaxTree;
  Settings: TInlayHintSettings;
  Json: TJSONArray;
begin
  Tree := TPascalParser.Parse(Source);
  try
    Settings := TInlayHintSettings.Default;
    Settings.ParameterNames := False;
    Settings.InferredTypes := False;
    Settings.EndMarkers := False;
    Settings.ControlChars := False;
    Assert.IsFalse(Settings.MethodWithoutSelf);
    Assert.AreEqual('', Describe(TLspInlayHints.Collect(FResolver, FIndex, Tree, Source, 'R.pas', WholeFile,
      Settings, nil)));
    Settings.MethodWithoutSelf := True;
    Assert.AreEqual('11:47 ohne Self|', Describe(TLspInlayHints.Collect(FResolver, FIndex, Tree, Source, 'R.pas',
      WholeFile, Settings, nil)));
    Json := TLspInlayHints.ToJson(TLspInlayHints.MethodMarkers(FResolver, Tree, Source, 'R.pas', WholeFile, nil));
    try
      Assert.AreEqual(1, Integer(Json.Count));
      Assert.IsTrue(Json.Items[0].GetValue<Boolean>('data.methodWithoutSelf'));
    finally
      Json.Free;
    end;
  finally
    Tree.Free;
  end;
end;

procedure TLspInlayHintsTests.EndMarkersBehindLongBlocks;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(UnitHaupt);
  try
    // Reihenfolge der Knoten im Baum; Collect sortiert nach Position.
    Assert.AreEqual('18:4 // Arbeite|17:6 // if Assigned(nil)|',
      Describe(TLspInlayHints.EndMarkers(Tree, WholeFile, 4)));
    // Die Routine hat 15 Zeilen, der if-Block 4.
    Assert.AreEqual('18:4 // Arbeite|', Describe(TLspInlayHints.EndMarkers(Tree, WholeFile, 5)));
    Assert.AreEqual('', Describe(TLspInlayHints.EndMarkers(Tree, WholeFile, 20)));
  finally
    Tree.Free;
  end;
end;

procedure TLspInlayHintsTests.SettingsSwitchHintsOffAndSort;
var
  Tree: TSyntaxTree;
  Settings: TInlayHintSettings;
  Hints: TArray<TInlayHint>;
begin
  Tree := TPascalParser.Parse(UnitHaupt);
  try
    Settings := TInlayHintSettings.Default;
    Settings.ParameterNames := False;
    Settings.EndMarkerMinLines := 5;
    Hints := TLspInlayHints.Collect(FResolver, FIndex, Tree, UnitHaupt, HauptFile,
      TTextRange.Create(TTextPosition.Create(9, 0), TTextPosition.Create(30, 0)), Settings, ReadFile);
    Assert.AreEqual('9:7 : string|10:7 : TFoo|11:7 : Integer|13:7 : TFarbe|18:4 // Arbeite|', Describe(Hints));
  finally
    Tree.Free;
  end;
end;

/// <summary>Endmarken mit Blockanfang: "Zeile:Spalte Text @Anfangszeile:Anfangsspalte|".</summary>
function DescribeEnds(const AHints: TArray<TInlayHint>): string;
var
  Hint: TInlayHint;
begin
  Result := '';
  for Hint in AHints do
    Result := Result + Format('%d:%d %s @%d:%d|', [Hint.Position.Line, Hint.Position.Character, Hint.Text,
      Hint.BlockStart.Line, Hint.BlockStart.Character]);
end;

procedure TLspInlayHintsTests.EndMarkersForEveryBlockKind;
var
  Tree: TSyntaxTree;
  Found: string;
begin
  Tree := TPascalParser.Parse(UnitBloecke);
  try
    Found := DescribeEnds(TLspInlayHints.EndMarkers(Tree, WholeFile, 1));
    Assert.IsTrue(Pos('5:6 // TKunde @3:2|', Found) > 0, Found);
    Assert.IsTrue(Pos('8:6 // TPunkt @6:2|', Found) > 0, Found);
    Assert.IsTrue(Pos('32:4 // TKunde.Speichern @10:0|', Found) > 0, Found);
    Assert.IsTrue(Pos('16:6 // for I := 0 to 9 @14:2|', Found) > 0, Found);
    Assert.IsTrue(Pos('19:6 // while not Fertig @17:2|', Found) > 0, Found);
    Assert.IsTrue(Pos('22:6 // case Art @20:2|', Found) > 0, Found);
    Assert.IsTrue(Pos('25:6 // if Betrag > Limit @23:2|', Found) > 0, Found);
    Assert.IsTrue(Pos('28:6 // try (finally) @26:2|', Found) > 0, Found);
    Assert.IsTrue(Pos('31:6 // try (except) @29:2|', Found) > 0, Found);
  finally
    Tree.Free;
  end;
end;

procedure TLspInlayHintsTests.EndMarkersSkipCommentsAndShorten;
var
  Tree: TSyntaxTree;
  Found: string;
begin
  Tree := TPascalParser.Parse(UnitKommentar);
  try
    Found := Describe(TLspInlayHints.EndMarkers(Tree, WholeFile, 1));
    // Nach 40 Zeichen gekürzt; hinter "end; // Schleife" keine Marke.
    Assert.IsTrue(Pos('6:6 // if EineSehrLangeBedingungMitVielenZeiche…|', Found) > 0, Found);
    Assert.AreEqual(0, Pos('// while', Found), Found);
    Assert.IsTrue(Pos('10:4 // P|', Found) > 0, Found);
    // Unter der Mindestlänge: nur die Routine (9 Zeilen).
    Assert.AreEqual('10:4 // P|', Describe(TLspInlayHints.EndMarkers(Tree, WholeFile, 4)));
  finally
    Tree.Free;
  end;
end;

procedure TLspInlayHintsTests.EndMarkersCarryBlockStartAndRequestMinLines;
var
  Store: IDocumentStore;
  Hints: TLspInlayHints;
  Dispatcher: TJsonRpcDispatcher;
  Uri: string;

  function Labels(const AExtra: string): string;
  var
    Request, Response: TJSONObject;
    Item: TJSONValue;
  begin
    Request := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":1,"method":"textDocument/inlayHint","params":' +
      '{"textDocument":{"uri":"' + Uri.Replace('\', '\\') + '"},"range":{"start":{"line":0,"character":0},' +
      '"end":{"line":40,"character":0}}' + AExtra + '}}') as TJSONObject;
    try
      Response := Dispatcher.DispatchMessage(Request);
    finally
      Request.Free;
    end;
    try
      Result := '';
      for Item in Response.GetValue<TJSONArray>('result') do
        if TJSONObject(Item).GetValue('data') <> nil then
          Result := Result + Format('%s @%d|', [TJSONObject(Item).GetValue<string>('label'),
            TJSONObject(Item).GetValue<Integer>('data.blockStart.line')]);
    finally
      Response.Free;
    end;
  end;

begin
  Store := TDocumentStore.Create;
  Hints := TLspInlayHints.Create(Store, FIndex, ReadFile,
    function(const AUri: string): TInlayHintSettings
    begin
      Result := TInlayHintSettings.Default;
      Result.ParameterNames := False;
      Result.InferredTypes := False;
    end);
  Dispatcher := TJsonRpcDispatcher.Create;
  try
    Hints.Attach(Dispatcher);
    Uri := TDocumentUris.FromPath(HauptFile);
    Store.Open(Uri, 'delphi', 1, UnitBloecke);
    // Vorgabe 20 Zeilen: nur die Routine (23 Zeilen).
    Assert.AreEqual('// TKunde.Speichern @10|', Labels(''));
    // Mindestlänge aus der Anfrage: auch die Klasse (3 Zeilen).
    Assert.IsTrue(Pos('// TKunde @3|', Labels(',"atlas":{"endMarkerMinLines":3}')) > 0);
  finally
    Dispatcher.Free;
    Hints.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspInlayHintsTests);

end.
