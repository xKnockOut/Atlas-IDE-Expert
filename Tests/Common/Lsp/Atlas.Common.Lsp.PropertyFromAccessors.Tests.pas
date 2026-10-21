unit Atlas.Common.Lsp.PropertyFromAccessors.Tests;

// Tests für „Property aus Getter und Setter“ über das Protokoll (#682): Aufrufe
// in mehreren Units umstellen, Methodenzeiger bleiben, Verbergen nur ohne
// Verwendung außerhalb der Klasse, Code-Aktionen nach replaceCalls und
// abgeschaltet.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract;

type
  [TestFixture]
  TLspPropertyFromAccessorsTests = class
  private
    FIndex: ISymbolIndex;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ReplacesCallsInSeveralUnits;
    [Test]
    procedure WithoutCallsOnlyTheClassChanges;
    [Test]
    procedure HidesOnlyUnusedAccessors;
    [Test]
    procedure ActionsFollowSettings;
    [Test]
    procedure KnowsProceduralTypes;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.PropertyFromAccessors,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.PropertyFromAccessors;

const
  PanelsFile = 'C:\P\Panels.pas';
  MainFile = 'C:\P\Main.pas';
  OtherFile = 'C:\P\Other.pas';

  UnitPanels =
    'unit Panels;'#10 +                                       // 0
    'interface'#10 +                                          // 1
    'type'#10 +                                               // 2
    '  TTextFunc = function: string of object;'#10 +          // 3
    '  TPanel = class'#10 +                                   // 4
    '  private'#10 +                                          // 5
    '    FCaption: string;'#10 +                              // 6
    '  public'#10 +                                           // 7
    '    function GetCaption: string;'#10 +                   // 8
    '    procedure SetCaption(const AValue: string);'#10 +    // 9
    '    procedure Reset;'#10 +                               // 10
    '  end;'#10 +                                             // 11
    'implementation'#10 +                                     // 12
    'function TPanel.GetCaption: string;'#10 +                // 13
    'begin'#10 +
    '  Result := FCaption;'#10 +
    'end;'#10 +
    'procedure TPanel.SetCaption(const AValue: string);'#10 +
    'begin'#10 +
    '  FCaption := AValue;'#10 +
    'end;'#10 +
    'procedure TPanel.Reset;'#10 +
    'begin'#10 +
    '  SetCaption('''');'#10 +
    'end;'#10 +
    'end.'#10;
  UnitMain =
    'unit Main;'#10 +
    'interface'#10 +
    'uses'#10 +
    '  Panels;'#10 +
    'procedure Run(P: TPanel);'#10 +
    'implementation'#10 +
    'procedure Hook(AFunc: TTextFunc);'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure Run(P: TPanel);'#10 +
    'var'#10 +
    '  S: string;'#10 +
    '  F: TTextFunc;'#10 +
    'begin'#10 +
    '  P.SetCaption(''Bereit'');'#10 +
    '  S := P.GetCaption;'#10 +
    '  F := P.GetCaption;'#10 +
    '  Hook(P.GetCaption);'#10 +
    'end;'#10 +
    'end.'#10;
  UnitOther =
    'unit Other;'#10 +
    'interface'#10 +
    'uses'#10 +
    '  Panels;'#10 +
    'procedure Show(P: TPanel);'#10 +
    'implementation'#10 +
    'procedure Show(P: TPanel);'#10 +
    'begin'#10 +
    '  if P.GetCaption <> '''' then'#10 +
    '    P.SetCaption(P.GetCaption + ''!'');'#10 +
    'end;'#10 +
    'end.'#10;

function TextOf(const AFileName: string): string;
begin
  if SameText(AFileName, PanelsFile) then
    Result := UnitPanels
  else if SameText(AFileName, MainFile) then
    Result := UnitMain
  else if SameText(AFileName, OtherFile) then
    Result := UnitOther
  else
    Result := '';
end;

/// <summary>Wendet die Edits aus einem documentChanges-Eintrag auf AText an.</summary>
function Apply(const AText: string; ADocument: TJSONObject): string;
var
  Item: TJSONValue;
  Edits: TArray<TTextEdit>;
  Range: TJSONObject;
begin
  Edits := nil;
  for Item in ADocument.GetValue('edits') as TJSONArray do
  begin
    Range := TJSONObject(Item).GetValue('range') as TJSONObject;
    Edits := Edits + [TTextEdit.Create(TTextRange.Create(TLspPositions.ReadPosition(Range.GetValue('start')),
      TLspPositions.ReadPosition(Range.GetValue('end'))), TJSONObject(Item).GetValue('newText').Value)];
  end;
  Result := TChangeSignature.ApplyEdits(AText, Edits);
end;

/// <summary>Ergebnis je Datei als "Name|Text" hintereinander; AWarnings: Zahl der Hinweise.</summary>
function Run(const AIndex: ISymbolIndex; const APosition: TTextPosition; AReplaceCalls: Boolean;
  const AOptions: TPropertyFromAccessorsOptions; out AWarnings: TArray<string>): TArray<string>;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Answer: TJSONObject;
  Context: TPropertyFromAccessorsContext;
  Item: TJSONValue;
  Document: TJSONObject;
  FileName: string;
begin
  Result := nil;
  AWarnings := nil;
  Context := Default(TPropertyFromAccessorsContext);
  Context.Index := AIndex;
  Context.Files := [PanelsFile, MainFile, OtherFile];
  Context.Options := AOptions;
  Context.ReadText :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := TextOf(AFileName);
      Result := AText <> '';
    end;
  Tree := TPascalParser.Parse(UnitPanels);
  Resolver := TNameResolver.Create(AIndex, nil);
  Answer := nil;
  try
    Answer := TLspPropertyFromAccessors.Execute(Resolver, Tree, PanelsFile, UnitPanels, APosition, AReplaceCalls,
      Context);
    for Item in (Answer.GetValue('edit') as TJSONObject).GetValue('documentChanges') as TJSONArray do
    begin
      Document := TJSONObject(Item);
      FileName := TDocumentUris.ToPath((Document.GetValue('textDocument') as TJSONObject).GetValue('uri').Value);
      Result := Result + [ExtractFileName(FileName) + '|' + Apply(TextOf(FileName), Document)];
    end;
    for Item in Answer.GetValue('warnings') as TJSONArray do
      AWarnings := AWarnings + [Item.Value];
    Assert.IsTrue(((Answer.GetValue('edit') as TJSONObject).GetValue('changeAnnotations') as TJSONObject)
      .GetValue(TLspPropertyFromAccessors.AnnotationId) <> nil);
  finally
    Answer.Free;
    Resolver.Free;
    Tree.Free;
  end;
end;

procedure TLspPropertyFromAccessorsTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitPanels, PanelsFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitMain, MainFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitOther, OtherFile, nil));
end;

procedure TLspPropertyFromAccessorsTests.TearDown;
begin
  FIndex := nil;
end;

procedure TLspPropertyFromAccessorsTests.ReplacesCallsInSeveralUnits;
var
  Results, Warnings: TArray<string>;
begin
  // Auf der Kopfzeile der Klasse; der Getter liefert nur das Feld: read FCaption.
  Results := Run(FIndex, TTextPosition.Create(4, 4), True, TPropertyFromAccessorsOptions.Default, Warnings);
  Assert.AreEqual(3, Integer(Length(Results)), string.Join(#10'----'#10, Results));
  Assert.AreEqual('Panels.pas|' + StringReplace(StringReplace(UnitPanels, '    procedure Reset;'#10,
    '    procedure Reset;'#10'    property Caption: string read FCaption write SetCaption;'#10, []),
    '  SetCaption('''');', '  Caption := '''';', []), Results[0]);
  Assert.AreEqual('Main.pas|' + StringReplace(StringReplace(UnitMain, '  P.SetCaption(''Bereit'');',
    '  P.Caption := ''Bereit'';', []), '  S := P.GetCaption;', '  S := P.Caption;', []), Results[1]);
  Assert.AreEqual('Other.pas|' + StringReplace(StringReplace(UnitOther, '  if P.GetCaption <>', '  if P.Caption <>',
    []), '    P.SetCaption(P.GetCaption + ''!'');', '    P.Caption := P.Caption + ''!'';', []), Results[2]);
  // Zuweisung an einen Methodenzeiger und Übergabe als Methodenzeiger bleiben.
  Assert.AreEqual(2, Integer(Length(Warnings)), string.Join(#10, Warnings));
  Assert.Contains(Warnings[0], 'Main.pas, Zeile 17');
  Assert.Contains(Warnings[1], 'Main.pas, Zeile 18');
end;

procedure TLspPropertyFromAccessorsTests.WithoutCallsOnlyTheClassChanges;
var
  Results, Warnings: TArray<string>;
begin
  // Auf dem Setter; ohne Umstellen ändert sich nur die Klasse.
  Results := Run(FIndex, TTextPosition.Create(9, 14), False, TPropertyFromAccessorsOptions.Default, Warnings);
  Assert.AreEqual(1, Integer(Length(Results)));
  Assert.AreEqual('Panels.pas|' + StringReplace(UnitPanels, '    procedure Reset;'#10,
    '    procedure Reset;'#10'    property Caption: string read FCaption write SetCaption;'#10, []), Results[0]);
  Assert.AreEqual(0, Integer(Length(Warnings)));
end;

procedure TLspPropertyFromAccessorsTests.HidesOnlyUnusedAccessors;
var
  Results, Warnings: TArray<string>;
  Options: TPropertyFromAccessorsOptions;
begin
  Options := TPropertyFromAccessorsOptions.Default;
  Options.Hiding := TAccessorHiding.Private_;
  Results := Run(FIndex, TTextPosition.Create(4, 4), True, Options, Warnings);
  // SetCaption hat nach dem Umstellen keine Verwendung außerhalb mehr, GetCaption wird als Methodenzeiger benutzt.
  Assert.Contains(Results[0], '  private'#10'    FCaption: string;'#10 +
    '    procedure SetCaption(const AValue: string);'#10'  public'#10'    function GetCaption: string;'#10 +
    '    procedure Reset;'#10'    property Caption: string read FCaption write SetCaption;'#10'  end;');
  Assert.Contains(Warnings[High(Warnings)], 'GetCaption bleibt sichtbar');
  // Ohne Umstellen bleibt auch SetCaption sichtbar.
  Results := Run(FIndex, TTextPosition.Create(4, 4), False, Options, Warnings);
  Assert.Contains(Results[0], '  public'#10'    function GetCaption: string;'#10 +
    '    procedure SetCaption(const AValue: string);'#10);
  Assert.AreEqual(2, Integer(Length(Warnings)), string.Join(#10, Warnings));
end;

procedure TLspPropertyFromAccessorsTests.ActionsFollowSettings;
var
  Tree: TSyntaxTree;
  Actions: TArray<TJSONObject>;
  Action: TJSONObject;

  function Titles(const AActions: TArray<TJSONObject>): string;
  var
    Item: TJSONObject;
  begin
    Result := '';
    for Item in AActions do
    begin
      Result := Result + Item.GetValue('title').Value + '|';
      Item.Free;
    end;
  end;

begin
  Tree := TPascalParser.Parse(UnitPanels);
  try
    Actions := TLspPropertyFromAccessors.Actions(True, Tree, UnitPanels, 'file:///C:/P/Panels.pas',
      TTextPosition.Create(8, 14), TPropertyFromAccessorsOptions.Default, TReplaceCalls.Ask);
    Action := Actions[1];
    Assert.AreEqual(TLspPropertyFromAccessors.ClientCommand,
      (Action.GetValue('command') as TJSONObject).GetValue('command').Value);
    Assert.AreEqual('Property Caption anlegen|Property Caption anlegen und Aufrufe umstellen|', Titles(Actions));
    Assert.AreEqual('Fehlende Properties anlegen (1) und Aufrufe umstellen|', Titles(
      TLspPropertyFromAccessors.Actions(True, Tree, UnitPanels, 'file:///C:/P/Panels.pas', TTextPosition.Create(4, 4),
      TPropertyFromAccessorsOptions.Default, TReplaceCalls.Always)));
    Assert.AreEqual('Property Caption anlegen|', Titles(TLspPropertyFromAccessors.Actions(True, Tree, UnitPanels,
      'file:///C:/P/Panels.pas', TTextPosition.Create(9, 14), TPropertyFromAccessorsOptions.Default,
      TReplaceCalls.Never)));
    // Abgeschaltet oder neben den Zugriffsmethoden: nichts.
    Assert.AreEqual('', Titles(TLspPropertyFromAccessors.Actions(False, Tree, UnitPanels, 'file:///C:/P/Panels.pas',
      TTextPosition.Create(8, 14), TPropertyFromAccessorsOptions.Default, TReplaceCalls.Ask)));
    Assert.AreEqual('', Titles(TLspPropertyFromAccessors.Actions(True, Tree, UnitPanels, 'file:///C:/P/Panels.pas',
      TTextPosition.Create(10, 14), TPropertyFromAccessorsOptions.Default, TReplaceCalls.Ask)));
  finally
    Tree.Free;
  end;
end;

procedure TLspPropertyFromAccessorsTests.KnowsProceduralTypes;
begin
  Assert.IsTrue(TLspPropertyFromAccessors.IsProcedural('TTextFunc', FIndex));
  Assert.IsTrue(TLspPropertyFromAccessors.IsProcedural('TProc<Integer>', FIndex));
  Assert.IsTrue(TLspPropertyFromAccessors.IsProcedural('reference to function: string', FIndex));
  Assert.IsFalse(TLspPropertyFromAccessors.IsProcedural('TPanel', FIndex));
  Assert.IsFalse(TLspPropertyFromAccessors.IsProcedural('string', FIndex));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspPropertyFromAccessorsTests);

end.
