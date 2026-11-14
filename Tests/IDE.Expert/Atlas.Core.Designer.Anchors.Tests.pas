unit Atlas.Core.Designer.Anchors.Tests;

// Tests für „Anchors vorschlagen“ (#727): Suchdialog (Feld, Grid, Knöpfe),
// jede Randregel, Align, vorhandene Anchors, Reihen, Labels mit
// FocusControl, edgeDistance und füllende Klassen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasAnchorSuggestTests = class
  public
    [Test]
    procedure SearchDialog;
    [Test]
    procedure EdgeRules;
    [Test]
    procedure AlignedSkipped;
    [Test]
    procedure KeepExisting;
    [Test]
    procedure RowFollowsOutermost;
    [Test]
    procedure LabelFollowsField;
    [Test]
    procedure EdgeDistance;
  end;

implementation

uses
  System.Types,
  Atlas.Core.Designer.Anchors;

const
  cLT = [TAtlasAnchorSide.Left, TAtlasAnchorSide.Top];

function Item(const AName: string; ALeft, ATop, AWidth, AHeight: Integer;
  AFill: Boolean = False): TAtlasAnchorItem;
begin
  Result := TAtlasAnchorItem.Create(AName, Bounds(ALeft, ATop, AWidth, AHeight), False, AFill, cLT, '');
end;

function Texts(const AResult: TArray<TAtlasAnchorSuggestion>): string;
var
  mSuggestion: TAtlasAnchorSuggestion;
begin
  Result := '';
  for mSuggestion in AResult do
  begin
    Result := Result + '[' + TAtlasAnchorSuggest.Text(mSuggestion.Anchors) + ']';
  end;
end;

procedure TAtlasAnchorSuggestTests.SearchDialog;
var
  mResult: TArray<TAtlasAnchorSuggestion>;
begin
  // Client 400 x 300: Feld oben über die Breite, Grid darunter, OK/Abbrechen unten rechts.
  mResult := TAtlasAnchorSuggest.Suggest([Item('edtSearch', 8, 8, 384, 21), Item('grdHits', 8, 37, 384, 216, True),
    Item('btnOk', 236, 267, 75, 25), Item('btnCancel', 317, 267, 75, 25)], TSize.Create(400, 300), 16, True);
  Assert.AreEqual('[L T R -][L T R B][- - R B][- - R B]', Texts(mResult));
  Assert.AreEqual<TAtlasAnchorReason>(TAtlasAnchorReason.Row, mResult[2].Reason, 'OK folgt Abbrechen');
  Assert.AreEqual<TAtlasAnchorReason>(TAtlasAnchorReason.BottomRight, mResult[3].Reason);
  Assert.IsTrue(mResult[0].Changed);
end;

procedure TAtlasAnchorSuggestTests.EdgeRules;
begin
  Assert.AreEqual('[L - R B][- T R -][L - - B][L T - -]', Texts(TAtlasAnchorSuggest.Suggest([
    Item('pnlFoot', 8, 250, 384, 40), Item('btnHelp', 317, 100, 75, 25), Item('chkMore', 8, 270, 100, 17),
    Item('edtMid', 100, 100, 100, 21)], TSize.Create(400, 300), 16, True)));
end;

procedure TAtlasAnchorSuggestTests.AlignedSkipped;
var
  mItems: TArray<TAtlasAnchorItem>;
  mResult: TArray<TAtlasAnchorSuggestion>;
begin
  mItems := [Item('pnlBottom', 0, 260, 400, 40)];
  mItems[0].Aligned := True;
  mResult := TAtlasAnchorSuggest.Suggest(mItems, TSize.Create(400, 300), 16, True);
  Assert.AreEqual<TAtlasAnchorReason>(TAtlasAnchorReason.Aligned, mResult[0].Reason);
  Assert.IsFalse(mResult[0].Changed);
end;

procedure TAtlasAnchorSuggestTests.KeepExisting;
var
  mItems: TArray<TAtlasAnchorItem>;
  mResult: TArray<TAtlasAnchorSuggestion>;
begin
  mItems := [Item('btnOk', 317, 267, 75, 25)];
  mItems[0].Existing := [TAtlasAnchorSide.Top, TAtlasAnchorSide.Right];
  mResult := TAtlasAnchorSuggest.Suggest(mItems, TSize.Create(400, 300), 16, True);
  Assert.AreEqual<TAtlasAnchorReason>(TAtlasAnchorReason.Existing, mResult[0].Reason);
  Assert.IsFalse(mResult[0].Changed);
  mResult := TAtlasAnchorSuggest.Suggest(mItems, TSize.Create(400, 300), 16, False);
  Assert.AreEqual('[- - R B]', Texts(mResult));
  Assert.IsTrue(mResult[0].Changed);
end;

procedure TAtlasAnchorSuggestTests.RowFollowsOutermost;
begin
  // Reihe unten links: die linke ist die äußerste (L B), alle folgen.
  Assert.AreEqual('[L - - B][L - - B][L - - B]', Texts(TAtlasAnchorSuggest.Suggest([Item('a', 8, 267, 75, 25),
    Item('b', 89, 267, 75, 25), Item('c', 170, 268, 75, 25)], TSize.Create(400, 300), 16, True)));
end;

procedure TAtlasAnchorSuggestTests.LabelFollowsField;
var
  mItems: TArray<TAtlasAnchorItem>;
  mResult: TArray<TAtlasAnchorSuggestion>;
begin
  // Label links neben einem Feld über die volle Breite unten: senkrecht wie das Feld, nie rechts.
  mItems := [TAtlasAnchorItem.Create('lblNote', Bounds(8, 270, 40, 15), False, False, cLT, 'edtNote'),
    Item('edtNote', 8, 280, 384, 21)];
  mResult := TAtlasAnchorSuggest.Suggest(mItems, TSize.Create(400, 300), 16, True);
  Assert.AreEqual('[L - - B][L - R B]', Texts(mResult));
  Assert.AreEqual<TAtlasAnchorReason>(TAtlasAnchorReason.FollowsField, mResult[0].Reason);
end;

procedure TAtlasAnchorSuggestTests.EdgeDistance;
begin
  Assert.AreEqual('[L T - -]', Texts(TAtlasAnchorSuggest.Suggest([Item('btn', 300, 100, 75, 25)],
    TSize.Create(400, 300), 16, True)), '25 px Abstand');
  Assert.AreEqual('[- T R -]', Texts(TAtlasAnchorSuggest.Suggest([Item('btn', 300, 100, 75, 25)],
    TSize.Create(400, 300), 30, True)));
end;

end.
