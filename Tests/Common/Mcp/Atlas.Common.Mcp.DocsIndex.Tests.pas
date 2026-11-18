unit Atlas.Common.Mcp.DocsIndex.Tests;

// Tests für den Suchindex von search_atlas_docs (#2376): Falten (Umlaute, Groß-/Kleinschreibung), Füllwörter,
// Gewichtung Kennung vor Name vor Fließtext, genaue Kennung zuerst, beide Sprachen, Art und Sprache der Abschnitte,
// ähnliche Kennungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDocsIndexTests = class
  public
    [Test]
    procedure FoldsUmlautsAndCase;
    [Test]
    procedure WordsWithoutFillers;
    [Test]
    procedure IdBeatsNameBeatsText;
    [Test]
    procedure ExactIdComesFirst;
    [Test]
    procedure FindsGermanAndEnglishWords;
    [Test]
    procedure FindsUmlautsBothWays;
    [Test]
    procedure FiltersKindAndSectionLanguage;
    [Test]
    procedure WindowAnchorIsExact;
    [Test]
    procedure SimilarIdsForTypos;
    [Test]
    procedure LimitCutsHits;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Mcp.DocsIndex;

const
  cIndex = '[' +
    '{"kind":"setting","id":"editor.breadcrumbs","source":"plugin","caption":"Brotkrumenleiste",' +
    '"captionEn":"Breadcrumbs","page":"Editor","description":"Pfad des Carets über dem Editor."},' +
    '{"kind":"setting","id":"editor.statusBar","source":"plugin","caption":"Atlas-Statusleiste",' +
    '"captionEn":"Status bar","page":"Editor","description":"Zeigt auch die Brotkrumen nicht."},' +
    '{"kind":"setting","id":"outline.filter","source":"plugin","caption":"Übersicht filtern",' +
    '"captionEn":"Filter outline","page":"Editor","description":"Filter der Gliederung.",' +
    '"keywords":["Navigationsleiste"]},' +
    '{"kind":"command","id":"keys.breadcrumbs","source":"plugin","default":"Strg+Umschalt+.",' +
    '"defaultEn":"Ctrl+Shift+.","page":"Editor","description":"Tastenkürzel Brotkrumenleiste."},' +
    '{"kind":"window","language":"de","page":"Navigieren.md","title":"Gliederung","path":"Navigieren › Gliederung",' +
    '"anchor":"window-atlasoutline","window":"atlasoutline","text":"Gliederung mit Filter."},' +
    '{"kind":"window","language":"en","page":"Navigating.md","title":"Outline","path":"Navigating › Outline",' +
    '"anchor":"window-atlasoutline","window":"atlasoutline","text":"Outline with filter."},' +
    '{"kind":"feature","language":"de","page":"Navigieren.md","title":"Brotkrumenleiste",' +
    '"path":"Navigieren › Leisten › Brotkrumenleiste","anchor":"brotkrumenleiste","text":"Leiste über dem Editor."}' +
    ']';

function Ids(const AHits: TArray<TDocsHit>): string;
var
  mHit: TDocsHit;
begin
  Result := '';
  for mHit in AHits do
  begin
    Result := Result + TDocsIndex.KindName(mHit.Entry.Kind) + ':' + mHit.Entry.Id + ' ';
  end;
  Result := Trim(Result);
end;

function SearchIds(ALanguage: TTextLanguage; const AQuery: string; AKind: TDocsKind): string;
var
  mIndex: TDocsIndex;
begin
  mIndex := TDocsIndex.Create(cIndex, ALanguage, nil, nil);
  try
    Result := Ids(mIndex.Search(AQuery, AKind, 10));
  finally
    mIndex.Free;
  end;
end;

{ TDocsIndexTests }

procedure TDocsIndexTests.FoldsUmlautsAndCase;
begin
  Assert.AreEqual('uebersicht strasse aeoe', TDocsIndex.Fold('Übersicht Straße ÄÖ'));
end;

procedure TDocsIndexTests.WordsWithoutFillers;
begin
  Assert.AreEqual('brotkrumen|method-order', string.Join('|',
    TDocsIndex.Words('Wie schalte ich die Brotkrumen ab, method-order?')));
  Assert.AreEqual('brotkrumen', string.Join('|', TDocsIndex.Words('Brotkrumen abschalten')));
  Assert.AreEqual('editor.breadcrumbs', string.Join('|', TDocsIndex.Words('editor.breadcrumbs.')));
end;

procedure TDocsIndexTests.IdBeatsNameBeatsText;
begin
  // filter: Kennung von outline.filter vor dem Fließtext der Gliederung.
  Assert.AreEqual('setting:outline.filter window:atlasoutline', SearchIds(TTextLanguage.German, 'filter',
    TDocsKind.All));
  // Gliederung: Titel des Fensters vor der Beschreibung von outline.filter.
  Assert.AreEqual('window:atlasoutline setting:outline.filter', SearchIds(TTextLanguage.German, 'Gliederung',
    TDocsKind.All));
  // Name (Brotkrumenleiste) vor Fließtext; bei Gleichstand Einstellung vor Abschnitt vor Befehl.
  Assert.AreEqual('setting:editor.breadcrumbs feature: setting:editor.statusBar command:keys.breadcrumbs',
    SearchIds(TTextLanguage.German, 'Brotkrumen', TDocsKind.All));
end;

procedure TDocsIndexTests.ExactIdComesFirst;
var
  mIndex: TDocsIndex;
  mHits: TArray<TDocsHit>;
begin
  mIndex := TDocsIndex.Create(cIndex, TTextLanguage.German, nil, nil);
  try
    mHits := mIndex.Search('Editor.Breadcrumbs', TDocsKind.All, 5);
    Assert.AreEqual('setting:editor.breadcrumbs', Ids(mHits));
    Assert.IsTrue(mHits[0].Exact);
    mHits := mIndex.Search('breadcrumbs', TDocsKind.All, 5);
    Assert.AreEqual('setting:editor.breadcrumbs command:keys.breadcrumbs', Ids(mHits));
    Assert.IsFalse(mHits[0].Exact);
  finally
    mIndex.Free;
  end;
end;

procedure TDocsIndexTests.FindsGermanAndEnglishWords;
begin
  Assert.AreEqual('setting:outline.filter', SearchIds(TTextLanguage.English, 'Übersicht', TDocsKind.Setting));
  Assert.AreEqual('setting:outline.filter window:atlasoutline', SearchIds(TTextLanguage.German, 'filter outline',
    TDocsKind.All));
  Assert.AreEqual('setting:outline.filter', SearchIds(TTextLanguage.German, 'Navigationsleiste', TDocsKind.All));
end;

procedure TDocsIndexTests.FindsUmlautsBothWays;
begin
  Assert.AreEqual('setting:outline.filter', SearchIds(TTextLanguage.German, 'uebersicht', TDocsKind.Setting));
  Assert.AreEqual('setting:outline.filter', SearchIds(TTextLanguage.German, 'ÜBERSICHT', TDocsKind.Setting));
end;

procedure TDocsIndexTests.FiltersKindAndSectionLanguage;
begin
  Assert.AreEqual('window:atlasoutline', SearchIds(TTextLanguage.German, 'Gliederung', TDocsKind.Window));
  Assert.AreEqual('', SearchIds(TTextLanguage.English, 'Gliederung', TDocsKind.Window));
  Assert.AreEqual('window:atlasoutline', SearchIds(TTextLanguage.English, 'Outline', TDocsKind.Window));
  // window umfasst die Abschnitte der Funktionsseiten, feature nur diese.
  Assert.AreEqual('feature:', SearchIds(TTextLanguage.German, 'Leiste über', TDocsKind.Feature));
  Assert.AreEqual('command:keys.breadcrumbs', SearchIds(TTextLanguage.German, 'Brotkrumen', TDocsKind.Command));
end;

procedure TDocsIndexTests.WindowAnchorIsExact;
var
  mIndex: TDocsIndex;
  mHits: TArray<TDocsHit>;
begin
  mIndex := TDocsIndex.Create(cIndex, TTextLanguage.German, nil, nil);
  try
    mHits := mIndex.Search('window-atlasoutline', TDocsKind.All, 5);
    Assert.AreEqual(1, Integer(Length(mHits)));
    Assert.IsTrue(mHits[0].Exact);
    mHits := mIndex.Search('Gliederung', TDocsKind.All, 5);
    Assert.IsFalse(mHits[0].Exact);
  finally
    mIndex.Free;
  end;
end;

procedure TDocsIndexTests.SimilarIdsForTypos;
var
  mIndex: TDocsIndex;
begin
  mIndex := TDocsIndex.Create(cIndex, TTextLanguage.German, nil, nil);
  try
    Assert.AreEqual(0, Integer(Length(mIndex.Search('editor.breadcrums', TDocsKind.All, 5))));
    Assert.AreEqual('editor.breadcrumbs', string.Join(',', mIndex.Similar('editor.breadcrums', TDocsKind.All, 5)));
    Assert.AreEqual('', string.Join(',', mIndex.Similar('editor.breadcrums', TDocsKind.Command, 5)));
  finally
    mIndex.Free;
  end;
end;

procedure TDocsIndexTests.LimitCutsHits;
var
  mIndex: TDocsIndex;
begin
  mIndex := TDocsIndex.Create(cIndex, TTextLanguage.German, nil, nil);
  try
    Assert.AreEqual(2, Integer(Length(mIndex.Search('Brotkrumen', TDocsKind.All, 2))));
  finally
    mIndex.Free;
  end;
end;

end.
