unit Atlas.Common.Lsp.Hover.UnitContents.Tests;

// Tests für den Inhalt einer Unit im Hover über ihren Namen (#1921).

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Lsp.Hover.UnitContents;

type
  [TestFixture]
  TLspHoverUnitContentsTests = class
  private
    FUnit: TUnitIndex;
    function Collected(const AText: string): TArray<THoverUnitEntry>;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Nur Deklarationen auf Unit-Ebene aus dem interface, nach Gruppe und Name, Überladungen einmal.
    /// </summary>
    [Test]
    procedure CollectsInterfaceDeclarationsByGroup;
    [Test]
    procedure MarksNamesUsedInTheFile;
    [Test]
    procedure SelectsByMode;
    [Test]
    procedure ReadsSetting;
    [Test]
    procedure WritesSectionsWithUsedTypesFirst;
    [Test]
    procedure WritesNoteWhenNothingIsUsed;
    [Test]
    procedure WritesMarkdownAndPlainText;
    /// <summary>Über einem uses-Eintrag liefert der Hover den Inhalt der Unit.</summary>
    [Test]
    procedure HoverOverUsesEntryListsContents;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Lsp.Hover;

const
  WerkFile = 'C:\P\Werk.pas';

  UnitWerk =
    'unit Werk;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TKunde = class'#10 +
    '    procedure Speichern;'#10 +
    '  end;'#10 +
    '  IDienst = interface'#10 +
    '  end;'#10 +
    '  TPunkt = record'#10 +
    '    X: Integer;'#10 +
    '  end;'#10 +
    '  TFarbe = (Rot, Gruen);'#10 +
    '  TListe<T> = class'#10 +
    '  end;'#10 +
    '  TText = string;'#10 +
    '  TAuftrag = class'#10 +
    '  end;'#10 +
    '{$IFDEF NIE}'#10 +
    '  TAlt = class'#10 +
    '  end;'#10 +
    '{$ENDIF}'#10 +
    'const'#10 +
    '  Grenze = 10;'#10 +
    'var'#10 +
    '  Zaehler: Integer;'#10 +
    'procedure Lauf; overload;'#10 +
    'procedure Lauf(A: Integer); overload;'#10 +
    'implementation'#10 +
    'type'#10 +
    '  TIntern = class'#10 +
    '  end;'#10 +
    'procedure Lauf;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure Lauf(A: Integer);'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TKunde.Speichern;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

  UnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Werk;'#10 +
    'implementation'#10 +
    'procedure P;'#10 +
    'var'#10 +
    '  K: TKunde;'#10 +
    '  L: Werk.TListe<Integer>;'#10 +
    'begin'#10 +
    '  Lauf;'#10 +
    'end;'#10 +
    'end.';

function Names(const AEntries: TArray<THoverUnitEntry>): string;
var
  mEntry: THoverUnitEntry;
begin
  Result := '';
  for mEntry in AEntries do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + mEntry.Name;
    if mEntry.Used then
    begin
      Result := Result + '*';
    end;
  end;
end;

{ TLspHoverUnitContentsTests }

procedure TLspHoverUnitContentsTests.Setup;
begin
  FUnit := TIndexExtractor.ExtractText(UnitWerk, WerkFile, nil);
end;

procedure TLspHoverUnitContentsTests.TearDown;
begin
  FUnit := Default(TUnitIndex);
end;

function TLspHoverUnitContentsTests.Collected(const AText: string): TArray<THoverUnitEntry>;
begin
  Result := TLspHoverUnitContents.Collect(FUnit, TPascalLexer.Tokenize(AText));
end;

procedure TLspHoverUnitContentsTests.CollectsInterfaceDeclarationsByGroup;
var
  mEntries: TArray<THoverUnitEntry>;
begin
  mEntries := Collected('');
  Assert.AreEqual('TAuftrag,TKunde,TListe<T>,IDienst,TPunkt,TFarbe,TText,Lauf,Grenze,Zaehler', Names(mEntries));
  Assert.AreEqual(Ord(THoverUnitGroup.Classes), Ord(mEntries[0].Group));
  Assert.AreEqual(Ord(THoverUnitGroup.Interfaces), Ord(mEntries[3].Group));
  Assert.AreEqual(Ord(THoverUnitGroup.OtherTypes), Ord(mEntries[6].Group));
  Assert.AreEqual(Ord(THoverUnitGroup.Variables), Ord(mEntries[9].Group));
  // Fundort des Namens TKunde (Zeile 3, Spalte 2).
  Assert.AreEqual(WerkFile, mEntries[1].FileName);
  Assert.AreEqual(3, mEntries[1].Line);
  Assert.AreEqual(2, mEntries[1].Character);
end;

procedure TLspHoverUnitContentsTests.MarksNamesUsedInTheFile;
begin
  // TKunde direkt, TListe qualifiziert, Lauf als Aufruf; der uses-Eintrag selbst zählt nicht.
  Assert.AreEqual('TAuftrag,TKunde*,TListe<T>*,IDienst,TPunkt,TFarbe,TText,Lauf*,Grenze,Zaehler',
    Names(Collected(UnitHaupt)));
end;

procedure TLspHoverUnitContentsTests.SelectsByMode;
var
  mEntries: TArray<THoverUnitEntry>;
begin
  mEntries := Collected(UnitHaupt);
  Assert.IsTrue(TLspHoverUnitContents.Select(mEntries, THoverUnitMode.Off).IsEmpty);
  Assert.AreEqual('TAuftrag,TKunde*,TListe<T>*,IDienst,TPunkt,TFarbe,TText',
    Names(TLspHoverUnitContents.Select(mEntries, THoverUnitMode.Types).Entries));
  Assert.AreEqual(7, Integer(Length(TLspHoverUnitContents.Select(mEntries, THoverUnitMode.UsedFirst).Entries)));
  Assert.AreEqual(10, Integer(Length(TLspHoverUnitContents.Select(mEntries, THoverUnitMode.All).Entries)));
  Assert.IsTrue(TLspHoverUnitContents.Select(nil, THoverUnitMode.All).IsEmpty);
end;

procedure TLspHoverUnitContentsTests.ReadsSetting;
var
  mIssues: TArray<TConfigurationIssue>;
  mSettings: TServerSettings;
begin
  Assert.AreEqual(Ord(THoverUnitMode.UsedFirst), Ord(TLspHoverUnitContents.ModeOf(
    THintSettings.Default.UnitContents)));
  mSettings := TConfigurationParser.Parse('{"hints": {"unitContents": "off"}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual(Ord(THoverUnitMode.Off), Ord(TLspHoverUnitContents.ModeOf(mSettings.Hints.UnitContents)));
  mSettings := TConfigurationParser.Parse('{"hints": {"unitContents": "all"}}', mIssues);
  Assert.AreEqual(Ord(THoverUnitMode.All), Ord(TLspHoverUnitContents.ModeOf(mSettings.Hints.UnitContents)));
  mSettings := TConfigurationParser.Parse('{"hints": {"unitContents": "viel"}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.AreEqual(THintSettings.cUnitContentsUsedFirst, mSettings.Hints.UnitContents);
end;

procedure TLspHoverUnitContentsTests.WritesSectionsWithUsedTypesFirst;
var
  mContents: THoverUnitContents;
  mSections, mRuns: TJSONArray;
  mSection: TJSONObject;
begin
  mContents := TLspHoverUnitContents.Select(Collected(UnitHaupt), THoverUnitMode.UsedFirst);
  mSections := TJSONArray.Create;
  try
    mContents.AddSections(mSections);
    // Benutzt: Klassen; weiter: Klassen, Interfaces, Records, Aufzählungen, Sonstige.
    Assert.AreEqual(6, mSections.Count);
    mSection := mSections.Items[0] as TJSONObject;
    Assert.AreEqual('unitContents', mSection.GetValue<string>('kind'));
    Assert.AreEqual('IN DIESER DATEI BENUTZT (2)', mSection.GetValue<string>('heading'));
    Assert.AreEqual('Klassen', mSection.GetValue<string>('name'));
    mRuns := mSection.GetValue<TJSONArray>('runs');
    Assert.AreEqual(3, mRuns.Count);
    Assert.AreEqual('ref', mRuns.Items[0].GetValue<string>('kind'));
    Assert.AreEqual('TKunde', mRuns.Items[0].GetValue<string>('text'));
    Assert.AreEqual(WerkFile, mRuns.Items[0].GetValue<string>('file'));
    Assert.AreEqual(3, mRuns.Items[0].GetValue<Integer>('line'));
    Assert.AreEqual(', ', mRuns.Items[1].GetValue<string>('text'));
    Assert.AreEqual('TListe<T>', mRuns.Items[2].GetValue<string>('text'));
    mSection := mSections.Items[1] as TJSONObject;
    Assert.AreEqual('WEITERE TYPEN (5)', mSection.GetValue<string>('heading'));
    Assert.AreEqual('Klassen', mSection.GetValue<string>('name'));
    mSection := mSections.Items[5] as TJSONObject;
    Assert.AreEqual('Sonstige', mSection.GetValue<string>('name'));
  finally
    mSections.Free;
  end;
end;

procedure TLspHoverUnitContentsTests.WritesNoteWhenNothingIsUsed;
var
  mSections, mRuns: TJSONArray;
  mSection: TJSONObject;
begin
  mSections := TJSONArray.Create;
  try
    TLspHoverUnitContents.Select(Collected(''), THoverUnitMode.UsedFirst).AddSections(mSections);
    mSection := mSections.Items[0] as TJSONObject;
    Assert.AreEqual('IN DIESER DATEI BENUTZT (0)', mSection.GetValue<string>('heading'));
    Assert.AreEqual('', mSection.GetValue<string>('name'));
    mRuns := mSection.GetValue<TJSONArray>('runs');
    Assert.AreEqual('Kein Typ der Unit wird hier benutzt', mRuns.Items[0].GetValue<string>('text'));
    Assert.AreEqual('WEITERE TYPEN (7)', (mSections.Items[1] as TJSONObject).GetValue<string>('heading'));
  finally
    mSections.Free;
  end;
end;

procedure TLspHoverUnitContentsTests.WritesMarkdownAndPlainText;
var
  mContents: THoverUnitContents;
begin
  mContents := TLspHoverUnitContents.Select(Collected(UnitHaupt), THoverUnitMode.All);
  Assert.AreEqual('**IN DIESER DATEI BENUTZT (3)**'#10#10 +
    '- Klassen: `TKunde`, `TListe<T>`'#10 +
    '- Routinen: `Lauf`'#10#10 +
    '**WEITERE TYPEN (5)**'#10#10 +
    '- Klassen: `TAuftrag`'#10 +
    '- Interfaces: `IDienst`'#10 +
    '- Records: `TPunkt`'#10 +
    '- Aufzählungen: `TFarbe`'#10 +
    '- Sonstige: `TText`'#10#10 +
    '**ROUTINEN, KONSTANTEN UND VARIABLEN (2)**'#10#10 +
    '- Konstanten: `Grenze`'#10 +
    '- Variablen: `Zaehler`', mContents.ToMarkdown);
  mContents := TLspHoverUnitContents.Select(Collected(UnitHaupt), THoverUnitMode.Types);
  Assert.AreEqual('TYPEN (7)'#10 +
    'Klassen: TAuftrag, TKunde, TListe<T>'#10 +
    'Interfaces: IDienst'#10 +
    'Records: TPunkt'#10 +
    'Aufzählungen: TFarbe'#10 +
    'Sonstige: TText', mContents.ToPlainText);
end;

procedure TLspHoverUnitContentsTests.HoverOverUsesEntryListsContents;
var
  mIndex: ISymbolIndex;
  mResolver: TNameResolver;
  mTree: TSyntaxTree;
  mInfo: THoverInfo;
  mAtlas: TJSONObject;
  mSections: TJSONArray;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(FUnit);
  mResolver := TNameResolver.Create(mIndex);
  mTree := TPascalParser.Parse(UnitHaupt);
  try
    mInfo := TLspHover.InfoAt(THoverSource.Create(mResolver, mIndex, nil), mTree, UnitHaupt, 'C:\P\Haupt.pas',
      TTextPosition.Create(2, 6));
    Assert.AreEqual('unit Werk;', mInfo.Declaration);
    Assert.AreEqual(Ord(THoverUnitMode.All), Ord(mInfo.UnitContents.Mode));
    Assert.AreEqual('TAuftrag,TKunde*,TListe<T>*,IDienst,TPunkt,TFarbe,TText,Lauf*,Grenze,Zaehler',
      Names(mInfo.UnitContents.Entries));
    mAtlas := TLspHover.AtlasJson(mInfo);
    try
      Assert.AreEqual(WerkFile, mAtlas.GetValue<string>('documentationText'));
      mSections := mAtlas.GetValue<TJSONArray>('documentation.sections');
      Assert.AreEqual('unitContents', mSections.Items[0].GetValue<string>('kind'));
    finally
      mAtlas.Free;
    end;
  finally
    mTree.Free;
    mResolver.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspHoverUnitContentsTests);

end.
