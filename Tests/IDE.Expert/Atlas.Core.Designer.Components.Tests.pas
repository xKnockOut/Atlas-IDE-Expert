unit Atlas.Core.Designer.Components.Tests;

// Tests der Designer-Leiste ohne VCL (#1442): Suche im Fenster „Komponenten
// suchen“ (Rang, Felder, Art, Weiterschalten), Gruppen der Trefferliste
// und Ausrichten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasDesignerSearchTests = class
  public
    [Test]
    procedure MatchKinds;
    [Test]
    procedure FindOrdersBestFirst;
    [Test]
    procedure CaptionAndClassRankAfterName;
    [Test]
    procedure EmptyPatternListsKind;
    [Test]
    procedure FuzzyFindsLettersInOrder;
    [Test]
    procedure StepStopsAtEdges;
  end;

  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasDesignerGroupsTests = class
  public
    [Test]
    procedure HierarchyGroupsByParent;
    [Test]
    procedure ClassAndFlat;
  end;

  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasDesignerAlignTests = class
  public
    [Test]
    procedure EdgesAndCenters;
    [Test]
    procedure SameSize;
    [Test]
    procedure CenterInParentKeepsGaps;
    [Test]
    procedure SpaceKeepsOuter;
    [Test]
    procedure NeedsEnoughControls;
  end;

implementation

uses
  System.Types,
  Atlas.Core.Designer.Components;

function Item(const AName, AClassName: string; AVisual: Boolean; const ACaption, AParent: string): TAtlasDesignerItem;
begin
  Result := TAtlasDesignerItem.Create(AName, AClassName, AVisual);
  Result.Caption := ACaption;
  Result.ParentName := AParent;
end;

function Items: TArray<TAtlasDesignerItem>;
begin
  Result := TArray<TAtlasDesignerItem>.Create(
    Item('btnOK', 'TButton', True, 'OK', 'pnlButtons'),
    Item('OKAction', 'TAction', False, 'Speichern', ''),
    Item('ok', 'TLabel', True, '', ''),
    Item('Lookup', 'TComboBox', True, '', 'pnlTop'),
    Item('qryKunden', 'TFDQuery', False, '', ''),
    Item('pnl_ok', 'TPanel', True, '', 'pnlTop'),
    Item('lblHinweis', 'TLabel', True, 'Mit OK speichern', ''));
  Result[5].Container := True;
end;

{ TAtlasDesignerSearchTests }

procedure TAtlasDesignerSearchTests.MatchKinds;
begin
  Assert.AreEqual(Ord(TAtlasDesignerMatch.Exact), Ord(TAtlasDesignerSearch.MatchOf('btnOK', 'BTNok')));
  Assert.AreEqual(Ord(TAtlasDesignerMatch.Prefix), Ord(TAtlasDesignerSearch.MatchOf('OKAction', 'ok')));
  Assert.AreEqual(Ord(TAtlasDesignerMatch.WordStart), Ord(TAtlasDesignerSearch.MatchOf('btnOK', 'ok')),
    'Großbuchstabe nach Kleinbuchstaben');
  Assert.AreEqual(Ord(TAtlasDesignerMatch.WordStart), Ord(TAtlasDesignerSearch.MatchOf('pnl_ok', 'ok')), 'nach _');
  Assert.AreEqual(Ord(TAtlasDesignerMatch.WordStart), Ord(TAtlasDesignerSearch.MatchOf('Mit OK', 'ok')),
    'nach Leerzeichen');
  Assert.AreEqual(Ord(TAtlasDesignerMatch.Contains), Ord(TAtlasDesignerSearch.MatchOf('Lookup', 'ok')));
  Assert.AreEqual(Ord(TAtlasDesignerMatch.None), Ord(TAtlasDesignerSearch.MatchOf('qryKunden', 'ok')));
  Assert.AreEqual(Ord(TAtlasDesignerMatch.Prefix), Ord(TAtlasDesignerSearch.MatchOf('qryKunden', ' qry ')),
    'Leerzeichen am Rand zählen nicht');
end;

procedure TAtlasDesignerSearchTests.FindOrdersBestFirst;
var
  mHits: TArray<Integer>;
begin
  mHits := TAtlasDesignerSearch.Find(Items, 'ok', [TAtlasDesignerField.Name], TAtlasDesignerKind.All);
  // ok (gleich), OKAction (Anfang), btnOK und pnl_ok (Wortanfang, nach Namen), Lookup (irgendwo).
  Assert.AreEqual(5, Integer(Length(mHits)));
  Assert.AreEqual(2, mHits[0]);
  Assert.AreEqual(1, mHits[1]);
  Assert.AreEqual(0, mHits[2]);
  Assert.AreEqual(5, mHits[3]);
  Assert.AreEqual(3, mHits[4]);
  mHits := TAtlasDesignerSearch.Find(Items, 'ok', [TAtlasDesignerField.Name], TAtlasDesignerKind.NonVisual);
  Assert.AreEqual(1, Integer(Length(mHits)), 'nur nichtvisuelle');
  Assert.AreEqual(1, mHits[0]);
  mHits := TAtlasDesignerSearch.Find(Items, 'ok', [TAtlasDesignerField.Name], TAtlasDesignerKind.Containers);
  Assert.AreEqual(1, Integer(Length(mHits)), 'nur Container');
  Assert.AreEqual(5, mHits[0]);
end;

procedure TAtlasDesignerSearchTests.CaptionAndClassRankAfterName;
var
  mHits: TArray<Integer>;
begin
  mHits := TAtlasDesignerSearch.Find(Items, 'speichern', [TAtlasDesignerField.Name], TAtlasDesignerKind.All);
  Assert.AreEqual(0, Integer(Length(mHits)), 'ohne Caption nichts');
  mHits := TAtlasDesignerSearch.Find(Items, 'speichern', [TAtlasDesignerField.Name, TAtlasDesignerField.Caption],
    TAtlasDesignerKind.All);
  // OKAction (Caption gleich) vor lblHinweis (Caption Wortanfang).
  Assert.AreEqual(2, Integer(Length(mHits)));
  Assert.AreEqual(1, mHits[0]);
  Assert.AreEqual(6, mHits[1]);
  mHits := TAtlasDesignerSearch.Find(Items, 'ok', [TAtlasDesignerField.Name, TAtlasDesignerField.Caption],
    TAtlasDesignerKind.All);
  Assert.AreEqual(6, Integer(Length(mHits)), 'lblHinweis über die Caption dazu');
  Assert.AreEqual(6, mHits[5], 'Caption-Treffer nach allen Namenstreffern');
  mHits := TAtlasDesignerSearch.Find(Items, 'tlabel', [TAtlasDesignerField.ClassName], TAtlasDesignerKind.All);
  Assert.AreEqual(2, Integer(Length(mHits)));
  Assert.AreEqual(6, mHits[0], 'gleicher Rang: nach Namen (lblHinweis vor ok)');
  Assert.AreEqual(2, mHits[1]);
end;

procedure TAtlasDesignerSearchTests.EmptyPatternListsKind;
var
  mHits: TArray<Integer>;
begin
  mHits := TAtlasDesignerSearch.Find(Items, '  ', [TAtlasDesignerField.Name], TAtlasDesignerKind.All);
  Assert.AreEqual(7, Integer(Length(mHits)), 'ohne Suchwort alle');
  Assert.AreEqual(0, mHits[0], 'nach Namen: btnOK zuerst');
  mHits := TAtlasDesignerSearch.Find(Items, '', [TAtlasDesignerField.Name], TAtlasDesignerKind.NonVisual);
  Assert.AreEqual(2, Integer(Length(mHits)));
  Assert.AreEqual(1, mHits[0]);
  Assert.AreEqual(4, mHits[1]);
  Assert.AreEqual(0, Integer(Length(TAtlasDesignerSearch.Find(nil, 'ok', [TAtlasDesignerField.Name],
    TAtlasDesignerKind.All))));
end;

procedure TAtlasDesignerSearchTests.FuzzyFindsLettersInOrder;
var
  mItems: TArray<TAtlasDesignerItem>;
  mHits: TArray<Integer>;
begin
  Assert.AreEqual(Ord(TAtlasDesignerMatch.Prefix), Ord(TAtlasDesignerSearch.MatchOf('btnSpeichern', 'btnspei', True)),
    'btnspei findet btnSpeichern');
  Assert.AreEqual(Ord(TAtlasDesignerMatch.Fuzzy), Ord(TAtlasDesignerSearch.MatchOf('btnSpeichern', 'bspei', True)));
  Assert.AreEqual(Ord(TAtlasDesignerMatch.Fuzzy), Ord(TAtlasDesignerSearch.MatchOf('btnSpeichern', 'b sp', True)),
    'Leerzeichen zählen nicht');
  Assert.AreEqual(Ord(TAtlasDesignerMatch.None), Ord(TAtlasDesignerSearch.MatchOf('btnSpeichern', 'bspei')),
    'ohne AFuzzy scharf');
  Assert.AreEqual(Ord(TAtlasDesignerMatch.None), Ord(TAtlasDesignerSearch.MatchOf('btnSpeichern', 'speib', True)),
    'Reihenfolge zählt');
  Assert.AreEqual(Ord(TAtlasDesignerMatch.None), Ord(TAtlasDesignerSearch.MatchOf('btnSpeichern', 'x', True)));
  mItems := Items + [Item('btnSpeichern', 'TButton', True, '', 'pnlButtons')];
  mHits := TAtlasDesignerSearch.Find(mItems, 'bspei', [TAtlasDesignerField.Name], TAtlasDesignerKind.All, True);
  Assert.AreEqual(1, Integer(Length(mHits)));
  Assert.AreEqual(7, mHits[0]);
  mHits := TAtlasDesignerSearch.Find(mItems, 'ok', [TAtlasDesignerField.Name, TAtlasDesignerField.Caption],
    TAtlasDesignerKind.All, True);
  // Dieselben sechs wie ohne AFuzzy: qryKunden und btnSpeichern haben kein „o“.
  Assert.AreEqual(6, Integer(Length(mHits)), 'unscharf kommt nichts vor die scharfen');
  mHits := TAtlasDesignerSearch.Find(mItems, 'lhw', [TAtlasDesignerField.Name, TAtlasDesignerField.Caption,
    TAtlasDesignerField.ClassName], TAtlasDesignerKind.All, True);
  Assert.AreEqual(1, Integer(Length(mHits)), 'lblHinweis unscharf im Namen');
  Assert.AreEqual(6, mHits[0]);
  mHits := TAtlasDesignerSearch.Find(mItems, 'tbtn', [TAtlasDesignerField.ClassName], TAtlasDesignerKind.All, True);
  Assert.AreEqual(0, Integer(Length(mHits)), 'Klasse nie unscharf');
end;

procedure TAtlasDesignerSearchTests.StepStopsAtEdges;
begin
  Assert.AreEqual(1, TAtlasDesignerSearch.Step(0, 3, 1));
  Assert.AreEqual(2, TAtlasDesignerSearch.Step(2, 3, 1), 'am Ende stehen bleiben');
  Assert.AreEqual(0, TAtlasDesignerSearch.Step(0, 3, -1), 'am Anfang stehen bleiben');
  Assert.AreEqual(2, TAtlasDesignerSearch.Step(0, 3, 10), 'Seite ab');
  Assert.AreEqual(0, TAtlasDesignerSearch.Step(-1, 3, 1));
  Assert.AreEqual(-1, TAtlasDesignerSearch.Step(0, 0, 1), 'ohne Zeilen');
end;

{ TAtlasDesignerGroupsTests }

procedure TAtlasDesignerGroupsTests.HierarchyGroupsByParent;
var
  mHits: TArray<Integer>;
  mRows: TArray<TAtlasDesignerRow>;
begin
  mHits := TAtlasDesignerSearch.Find(Items, 'ok', [TAtlasDesignerField.Name], TAtlasDesignerKind.All);
  mRows := TAtlasDesignerGroups.Rows(Items, mHits, TAtlasDesignerGrouping.Hierarchy, 'MainForm');
  // MainForm (ok, OKAction), pnlButtons (btnOK), pnlTop (pnl_ok, Lookup).
  Assert.AreEqual(8, Integer(Length(mRows)));
  Assert.IsTrue(mRows[0].Header);
  Assert.AreEqual('MainForm', mRows[0].Caption);
  Assert.AreEqual(2, mRows[0].Count);
  Assert.AreEqual(2, mRows[1].Item);
  Assert.AreEqual(1, mRows[2].Item);
  Assert.AreEqual('pnlButtons', mRows[3].Caption);
  Assert.AreEqual(-1, mRows[3].Item);
  Assert.AreEqual(0, mRows[4].Item);
  Assert.AreEqual('pnlTop', mRows[5].Caption);
  Assert.AreEqual(2, mRows[5].Count);
  Assert.AreEqual(3, mRows[7].Item);
end;

procedure TAtlasDesignerGroupsTests.ClassAndFlat;
var
  mHits: TArray<Integer>;
  mRows: TArray<TAtlasDesignerRow>;
begin
  mHits := TAtlasDesignerSearch.Find(Items, '', [TAtlasDesignerField.Name], TAtlasDesignerKind.All);
  mRows := TAtlasDesignerGroups.Rows(Items, mHits, TAtlasDesignerGrouping.ClassName, 'MainForm');
  // Sechs Klassen, TLabel mit zwei.
  Assert.AreEqual(13, Integer(Length(mRows)));
  mRows := TAtlasDesignerGroups.Rows(Items, mHits, TAtlasDesignerGrouping.Flat, 'MainForm');
  Assert.AreEqual(7, Integer(Length(mRows)));
  Assert.IsFalse(mRows[0].Header);
  Assert.AreEqual(mHits[6], mRows[6].Item);
end;

{ TAtlasDesignerAlignTests }

function Rects: TArray<TRect>;
begin
  Result := TArray<TRect>.Create(Rect(10, 10, 60, 30), Rect(30, 50, 110, 90), Rect(5, 100, 25, 110));
end;

procedure TAtlasDesignerAlignTests.EdgesAndCenters;
var
  mOut: TArray<TRect>;
begin
  mOut := TAtlasDesignerAlign.Apply(TAtlasAlignKind.Lefts, Rects, Rect(0, 0, 200, 200));
  Assert.AreEqual(10, mOut[1].Left);
  Assert.AreEqual(80, mOut[1].Width, 'Größe bleibt');
  Assert.AreEqual(10, mOut[2].Left);
  Assert.AreEqual(10, mOut[0].Left, 'Bezug bleibt');
  mOut := TAtlasDesignerAlign.Apply(TAtlasAlignKind.Rights, Rects, Rect(0, 0, 200, 200));
  Assert.AreEqual(60, mOut[1].Right);
  mOut := TAtlasDesignerAlign.Apply(TAtlasAlignKind.Bottoms, Rects, Rect(0, 0, 200, 200));
  Assert.AreEqual(30, mOut[2].Bottom);
  Assert.AreEqual(30, mOut[1].Left, 'nur senkrecht verschoben: Left bleibt');
  mOut := TAtlasDesignerAlign.Apply(TAtlasAlignKind.CentersH, Rects, Rect(0, 0, 200, 200));
  Assert.AreEqual(35, (mOut[1].Left + mOut[1].Right) div 2, 'Mitte des Bezugs');
  mOut := TAtlasDesignerAlign.Apply(TAtlasAlignKind.CentersV, Rects, Rect(0, 0, 200, 200));
  Assert.AreEqual(20, (mOut[2].Top + mOut[2].Bottom) div 2);
end;

procedure TAtlasDesignerAlignTests.SameSize;
var
  mOut: TArray<TRect>;
begin
  mOut := TAtlasDesignerAlign.Apply(TAtlasAlignKind.SameWidth, Rects, Rect(0, 0, 200, 200));
  Assert.AreEqual(50, mOut[1].Width);
  Assert.AreEqual(30, mOut[1].Left, 'Lage bleibt');
  mOut := TAtlasDesignerAlign.Apply(TAtlasAlignKind.SameHeight, Rects, Rect(0, 0, 200, 200));
  Assert.AreEqual(20, mOut[2].Height);
end;

procedure TAtlasDesignerAlignTests.CenterInParentKeepsGaps;
var
  mOut: TArray<TRect>;
begin
  mOut := TAtlasDesignerAlign.Apply(TAtlasAlignKind.CenterInParentH,
    TArray<TRect>.Create(Rect(0, 0, 20, 10), Rect(30, 0, 50, 10)), Rect(0, 0, 150, 100));
  // Box 0..50 → 50..100.
  Assert.AreEqual(50, mOut[0].Left);
  Assert.AreEqual(80, mOut[1].Left, 'Abstand bleibt');
  mOut := TAtlasDesignerAlign.Apply(TAtlasAlignKind.CenterInParentV, TArray<TRect>.Create(Rect(0, 0, 20, 10)),
    Rect(0, 0, 150, 100));
  Assert.AreEqual(45, mOut[0].Top, 'eine Komponente reicht');
end;

procedure TAtlasDesignerAlignTests.SpaceKeepsOuter;
var
  mOut: TArray<TRect>;
begin
  // Breiten 10, 20, 10 zwischen 0 und 100: Lücken (100 - 40) / 2 = 30.
  mOut := TAtlasDesignerAlign.Apply(TAtlasAlignKind.SpaceH,
    TArray<TRect>.Create(Rect(90, 0, 100, 10), Rect(15, 5, 35, 15), Rect(0, 0, 10, 10)), Rect(0, 0, 200, 200));
  Assert.AreEqual(0, mOut[2].Left, 'erstes bleibt');
  Assert.AreEqual(40, mOut[1].Left);
  Assert.AreEqual(5, mOut[1].Top, 'nur waagerecht');
  Assert.AreEqual(90, mOut[0].Left, 'letztes bleibt');
  mOut := TAtlasDesignerAlign.Apply(TAtlasAlignKind.SpaceV,
    TArray<TRect>.Create(Rect(0, 0, 10, 10), Rect(0, 11, 10, 21), Rect(0, 31, 10, 41)), Rect(0, 0, 200, 200));
  // Lücken (41 - 30) / 2 = 5 Rest 1: die erste Lücke bekommt 6.
  Assert.AreEqual(16, mOut[1].Top);
  Assert.AreEqual(31, mOut[2].Top);
end;

procedure TAtlasDesignerAlignTests.NeedsEnoughControls;
var
  mOut: TArray<TRect>;
begin
  Assert.IsFalse(TAtlasDesignerAlign.Applicable(TAtlasAlignKind.Lefts, 1));
  Assert.IsTrue(TAtlasDesignerAlign.Applicable(TAtlasAlignKind.Lefts, 2));
  Assert.IsFalse(TAtlasDesignerAlign.Applicable(TAtlasAlignKind.SpaceH, 2));
  Assert.IsTrue(TAtlasDesignerAlign.Applicable(TAtlasAlignKind.CenterInParentH, 1));
  mOut := TAtlasDesignerAlign.Apply(TAtlasAlignKind.SpaceH, TArray<TRect>.Create(Rect(0, 0, 10, 10),
    Rect(50, 0, 60, 10)), Rect(0, 0, 200, 200));
  Assert.AreEqual(50, mOut[1].Left, 'zu wenige: unverändert');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDesignerSearchTests);
  TDUnitX.RegisterTestFixture(TAtlasDesignerGroupsTests);
  TDUnitX.RegisterTestFixture(TAtlasDesignerAlignTests);

end.
