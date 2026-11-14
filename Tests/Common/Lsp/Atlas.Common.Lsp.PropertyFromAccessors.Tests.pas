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
  cPanelsFile = 'C:\P\Panels.pas';
  cMainFile = 'C:\P\Main.pas';
  cOtherFile = 'C:\P\Other.pas';

  cUnitPanels =
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
  cUnitMain =
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
  cUnitOther =
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
  if SameText(AFileName, cPanelsFile) then
  begin
    Result := cUnitPanels;
  end
  else if SameText(AFileName, cMainFile) then
  begin
    Result := cUnitMain;
  end
  else if SameText(AFileName, cOtherFile) then
  begin
    Result := cUnitOther;
  end
  else
  begin
    Result := '';
  end;
end;

/// <summary>Wendet die Edits aus einem documentChanges-Eintrag auf AText an.</summary>
function Apply(const AText: string; ADocument: TJSONObject): string;
var
  mItem: TJSONValue;
  mEdits: TArray<TTextEdit>;
  mRange: TJSONObject;
begin
  mEdits := nil;
  for mItem in ADocument.GetValue('edits') as TJSONArray do
  begin
    mRange := TJSONObject(mItem).GetValue('range') as TJSONObject;
    mEdits := mEdits + [TTextEdit.Create(TTextRange.Create(TLspPositions.ReadPosition(mRange.GetValue('start')),
      TLspPositions.ReadPosition(mRange.GetValue('end'))), TJSONObject(mItem).GetValue('newText').Value)];
  end;
  Result := TChangeSignature.ApplyEdits(AText, mEdits);
end;

/// <summary>Ergebnis je Datei als "Name|Text" hintereinander; AWarnings: Zahl der Hinweise.</summary>
function Run(const AIndex: ISymbolIndex; const APosition: TTextPosition; AReplaceCalls: Boolean;
  const AOptions: TPropertyFromAccessorsOptions; out AWarnings: TArray<string>): TArray<string>;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mAnswer: TJSONObject;
  mContext: TPropertyFromAccessorsContext;
  mItem: TJSONValue;
  mDocument: TJSONObject;
  mFileName: string;
begin
  Result := nil;
  AWarnings := nil;
  mContext := Default(TPropertyFromAccessorsContext);
  mContext.Index := AIndex;
  mContext.Files := [cPanelsFile, cMainFile, cOtherFile];
  mContext.Options := AOptions;
  mContext.ReplaceCalls := AReplaceCalls;
  mContext.ReadText :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := TextOf(AFileName);
      Result := AText <> '';
    end;
  mTree := TPascalParser.Parse(cUnitPanels);
  mResolver := TNameResolver.Create(AIndex, nil);
  mAnswer := nil;
  try
    mAnswer := TLspPropertyFromAccessors.Execute(mResolver, mTree, cPanelsFile, cUnitPanels, APosition, mContext);
    for mItem in (mAnswer.GetValue('edit') as TJSONObject).GetValue('documentChanges') as TJSONArray do
    begin
      mDocument := TJSONObject(mItem);
      mFileName := TDocumentUris.ToPath((mDocument.GetValue('textDocument') as TJSONObject).GetValue('uri').Value);
      Result := Result + [ExtractFileName(mFileName) + '|' + Apply(TextOf(mFileName), mDocument)];
    end;
    for mItem in mAnswer.GetValue('warnings') as TJSONArray do
    begin
      AWarnings := AWarnings + [mItem.Value];
    end;
    Assert.IsNotNull(((mAnswer.GetValue('edit') as TJSONObject).GetValue('changeAnnotations') as TJSONObject)
      .GetValue(TLspPropertyFromAccessors.cAnnotationId));
  finally
    mAnswer.Free;
    mResolver.Free;
    mTree.Free;
  end;
end;

procedure TLspPropertyFromAccessorsTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitPanels, cPanelsFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitMain, cMainFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitOther, cOtherFile, nil));
end;

procedure TLspPropertyFromAccessorsTests.TearDown;
begin
  FIndex := nil;
end;

procedure TLspPropertyFromAccessorsTests.ReplacesCallsInSeveralUnits;
var
  mResults, mWarnings: TArray<string>;
begin
  // Auf der Kopfzeile der Klasse; der Getter liefert nur das Feld: read FCaption.
  mResults := Run(FIndex, TTextPosition.Create(4, 4), True, TPropertyFromAccessorsOptions.Default, mWarnings);
  Assert.AreEqual(3, Integer(Length(mResults)), string.Join(#10'----'#10, mResults));
  Assert.AreEqual('Panels.pas|' + StringReplace(StringReplace(cUnitPanels, '    procedure Reset;'#10,
    '    procedure Reset;'#10'    property Caption: string read FCaption write SetCaption;'#10, []),
    '  SetCaption('''');', '  Caption := '''';', []), mResults[0]);
  Assert.AreEqual('Main.pas|' + StringReplace(StringReplace(cUnitMain, '  P.SetCaption(''Bereit'');',
    '  P.Caption := ''Bereit'';', []), '  S := P.GetCaption;', '  S := P.Caption;', []), mResults[1]);
  Assert.AreEqual('Other.pas|' + StringReplace(StringReplace(cUnitOther, '  if P.GetCaption <>', '  if P.Caption <>',
    []), '    P.SetCaption(P.GetCaption + ''!'');', '    P.Caption := P.Caption + ''!'';', []), mResults[2]);
  // Zuweisung an einen Methodenzeiger und Übergabe als Methodenzeiger bleiben.
  Assert.AreEqual(2, Integer(Length(mWarnings)), string.Join(#10, mWarnings));
  Assert.Contains(mWarnings[0], 'Main.pas, Zeile 17');
  Assert.Contains(mWarnings[1], 'Main.pas, Zeile 18');
end;

procedure TLspPropertyFromAccessorsTests.WithoutCallsOnlyTheClassChanges;
var
  mResults, mWarnings: TArray<string>;
begin
  // Auf dem Setter; ohne Umstellen ändert sich nur die Klasse.
  mResults := Run(FIndex, TTextPosition.Create(9, 14), False, TPropertyFromAccessorsOptions.Default, mWarnings);
  Assert.AreEqual(1, Integer(Length(mResults)));
  Assert.AreEqual('Panels.pas|' + StringReplace(cUnitPanels, '    procedure Reset;'#10,
    '    procedure Reset;'#10'    property Caption: string read FCaption write SetCaption;'#10, []), mResults[0]);
  Assert.AreEqual(0, Integer(Length(mWarnings)));
end;

procedure TLspPropertyFromAccessorsTests.HidesOnlyUnusedAccessors;
var
  mResults, mWarnings: TArray<string>;
  mOptions: TPropertyFromAccessorsOptions;
begin
  mOptions := TPropertyFromAccessorsOptions.Default;
  mOptions.Hiding := TAccessorHiding.Private_;
  mResults := Run(FIndex, TTextPosition.Create(4, 4), True, mOptions, mWarnings);
  // SetCaption hat nach dem Umstellen keine Verwendung außerhalb mehr, GetCaption wird als Methodenzeiger benutzt.
  Assert.Contains(mResults[0], '  private'#10'    FCaption: string;'#10 +
    '    procedure SetCaption(const AValue: string);'#10'  public'#10'    function GetCaption: string;'#10 +
    '    procedure Reset;'#10'    property Caption: string read FCaption write SetCaption;'#10'  end;');
  Assert.Contains(mWarnings[High(mWarnings)], 'GetCaption bleibt sichtbar');
  // Ohne Umstellen bleibt auch SetCaption sichtbar.
  mResults := Run(FIndex, TTextPosition.Create(4, 4), False, mOptions, mWarnings);
  Assert.Contains(mResults[0], '  public'#10'    function GetCaption: string;'#10 +
    '    procedure SetCaption(const AValue: string);'#10);
  Assert.AreEqual(2, Integer(Length(mWarnings)), string.Join(#10, mWarnings));
end;

procedure TLspPropertyFromAccessorsTests.ActionsFollowSettings;
var
  mTree: TSyntaxTree;
  mActions: TArray<TJSONObject>;
  mAction: TJSONObject;

  function Titles(const AActions: TArray<TJSONObject>): string;
  var
    mItem: TJSONObject;
  begin
    Result := '';
    for mItem in AActions do
    begin
      Result := Result + mItem.GetValue('title').Value + '|';
      mItem.Free;
    end;
  end;

begin
  mTree := TPascalParser.Parse(cUnitPanels);
  try
    mActions := TLspPropertyFromAccessors.Actions(mTree, cUnitPanels, 'file:///C:/P/Panels.pas',
      TTextPosition.Create(8, 14), TPropertyFromAccessorsOptions.Default, TReplaceCalls.Ask);
    mAction := mActions[1];
    Assert.AreEqual(TLspPropertyFromAccessors.cClientCommand,
      (mAction.GetValue('command') as TJSONObject).GetValue('command').Value);
    Assert.AreEqual('Property Caption anlegen|Property Caption anlegen und Aufrufe umstellen|', Titles(mActions));
    Assert.AreEqual('Fehlende Properties anlegen (1) und Aufrufe umstellen|', Titles(
      TLspPropertyFromAccessors.Actions(mTree, cUnitPanels, 'file:///C:/P/Panels.pas', TTextPosition.Create(4, 4),
      TPropertyFromAccessorsOptions.Default, TReplaceCalls.Always)));
    Assert.AreEqual('Property Caption anlegen|', Titles(TLspPropertyFromAccessors.Actions(mTree, cUnitPanels,
      'file:///C:/P/Panels.pas', TTextPosition.Create(9, 14), TPropertyFromAccessorsOptions.Default,
      TReplaceCalls.Never)));
    // Neben den Zugriffsmethoden: nichts.
    Assert.AreEqual('', Titles(TLspPropertyFromAccessors.Actions(mTree, cUnitPanels, 'file:///C:/P/Panels.pas',
      TTextPosition.Create(10, 14), TPropertyFromAccessorsOptions.Default, TReplaceCalls.Ask)));
  finally
    mTree.Free;
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
