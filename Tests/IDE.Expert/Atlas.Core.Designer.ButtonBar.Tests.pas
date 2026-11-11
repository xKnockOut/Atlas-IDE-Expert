unit Atlas.Core.Designer.ButtonBar.Tests;

// Tests der Knopfleiste (#732): Rollen aus Caption, Name, ModalResult und
// eigenen Begriffen, Reihenfolge, jede Lage, Anchors, häufigste Höhe und
// Handler, die selbst schließen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasButtonBarTests = class
  public
    [Test]
    procedure RolesFromCaptionAndName;
    [Test]
    procedure ModalResultDecides;
    [Test]
    procedure CustomTerms;
    [Test]
    procedure OrderPutsOtherBeforeHelp;
    [Test]
    procedure BottomRight;
    [Test]
    procedure OtherPositions;
    [Test]
    procedure Anchors;
    [Test]
    procedure CommonHeight;
    [Test]
    procedure HandlerCloses;
  end;

implementation

uses
  System.Types,
  Atlas.Core.Designer.ButtonBar;

const
  /// <summary>Beschriftungen wie in der Sprachtabelle des Moduls.</summary>
  cTerms = 'ok=OK|Speichern|Übernehmen und schließen|Fertig|Ja; cancel=Abbrechen|Schließen|Nein; ' +
    'apply=Übernehmen|Anwenden; help=Hilfe|?; ok=Save; cancel=Cancel';

procedure TAtlasButtonBarTests.RolesFromCaptionAndName;
begin
  Assert.IsTrue(TAtlasButtonBar.RoleOf('Button1', '&OK', 0, cTerms) = TAtlasButtonRole.Ok);
  Assert.IsTrue(TAtlasButtonBar.RoleOf('Button2', '&Abbrechen', 0, cTerms) = TAtlasButtonRole.Cancel);
  Assert.IsTrue(TAtlasButtonBar.RoleOf('Button3', 'Übernehmen', 0, cTerms) = TAtlasButtonRole.Apply);
  Assert.IsTrue(TAtlasButtonBar.RoleOf('Button4', 'ÜBERNEHMEN UND SCHLIEßEN', 0, cTerms) = TAtlasButtonRole.Ok);
  Assert.IsTrue(TAtlasButtonBar.RoleOf('btnHilfe', 'Mehr …', 0, cTerms) = TAtlasButtonRole.Help, 'Name');
  Assert.IsTrue(TAtlasButtonBar.RoleOf('btnDrucken', 'Drucken', 0, cTerms) = TAtlasButtonRole.Other);
end;

procedure TAtlasButtonBarTests.ModalResultDecides;
begin
  Assert.IsTrue(TAtlasButtonBar.RoleOf('btnCancel', 'Abbrechen', TAtlasButtonBar.cMrYes, '') =
    TAtlasButtonRole.Ok);
  Assert.IsTrue(TAtlasButtonBar.RoleOf('btnOk', 'OK', TAtlasButtonBar.cMrNo, '') = TAtlasButtonRole.Cancel);
end;

procedure TAtlasButtonBarTests.CustomTerms;
var
  mRole: TAtlasButtonRole;
begin
  Assert.IsTrue(TAtlasButtonBar.RoleOf('Button1', 'Weiter', 0, 'ok=Weiter|Los; cancel=Zurück') =
    TAtlasButtonRole.Ok);
  Assert.IsTrue(TAtlasButtonBar.RoleOf('Button1', 'OK', 0, 'cancel=ok;' + cTerms) = TAtlasButtonRole.Cancel,
    'eigene Begriffe gehen vor');
  Assert.IsFalse(TAtlasButtonBar.TryParseRole('quatsch', mRole));
end;

procedure TAtlasButtonBarTests.OrderPutsOtherBeforeHelp;
var
  mOrder: TArray<Integer>;
begin
  mOrder := TAtlasButtonBar.Order([TAtlasButtonRole.Help, TAtlasButtonRole.Other, TAtlasButtonRole.Cancel,
    TAtlasButtonRole.Ok, TAtlasButtonRole.Other], TAtlasButtonBar.cDefaultOrder);
  Assert.AreEqual(3, mOrder[0], 'OK zuerst');
  Assert.AreEqual(2, mOrder[1]);
  Assert.AreEqual(1, mOrder[2], 'other in bisheriger Folge');
  Assert.AreEqual(4, mOrder[3]);
  Assert.AreEqual(0, mOrder[4], 'Hilfe zuletzt');
end;

procedure TAtlasButtonBarTests.BottomRight;
var
  mRects: TArray<TRect>;
begin
  mRects := TAtlasButtonBar.Layout(3, TSize.Create(75, 25), TAtlasButtonBarPosition.BottomRight, Rect(0, 0, 400, 300), 8, 6);
  Assert.AreEqual(392, mRects[2].Right);
  Assert.AreEqual(317, mRects[2].Left);
  Assert.AreEqual(311, mRects[1].Right, 'Abstand 6');
  Assert.AreEqual(155, mRects[0].Left);
  Assert.AreEqual(267, mRects[0].Top);
end;

procedure TAtlasButtonBarTests.OtherPositions;
var
  mRects: TArray<TRect>;
begin
  mRects := TAtlasButtonBar.Layout(2, TSize.Create(75, 25), TAtlasButtonBarPosition.BottomLeft, Rect(0, 0, 400, 300), 8, 8);
  Assert.AreEqual(8, mRects[0].Left);
  Assert.AreEqual(91, mRects[1].Left);
  mRects := TAtlasButtonBar.Layout(2, TSize.Create(75, 25), TAtlasButtonBarPosition.RightTop, Rect(0, 0, 400, 300), 8, 8);
  Assert.AreEqual(317, mRects[0].Left);
  Assert.AreEqual(8, mRects[0].Top);
  Assert.AreEqual(41, mRects[1].Top, 'darunter');
  mRects := TAtlasButtonBar.Layout(2, TSize.Create(75, 25), TAtlasButtonBarPosition.RightBottom, Rect(0, 0, 400, 300), 8, 8);
  Assert.AreEqual(267, mRects[1].Top, 'letzter unten');
  Assert.AreEqual(234, mRects[0].Top);
  Assert.IsTrue(TAtlasButtonBar.PositionOf('RIGHTTOP') = TAtlasButtonBarPosition.RightTop);
  Assert.IsTrue(TAtlasButtonBar.PositionOf('') = TAtlasButtonBarPosition.BottomRight);
end;

procedure TAtlasButtonBarTests.Anchors;
begin
  Assert.IsTrue(TAtlasButtonBar.AnchorsOf(TAtlasButtonBarPosition.BottomRight) = [TAtlasButtonAnchor.Right,
    TAtlasButtonAnchor.Bottom]);
  Assert.IsTrue(TAtlasButtonBar.AnchorsOf(TAtlasButtonBarPosition.BottomLeft) = [TAtlasButtonAnchor.Left,
    TAtlasButtonAnchor.Bottom]);
  Assert.IsTrue(TAtlasButtonBar.AnchorsOf(TAtlasButtonBarPosition.RightTop) = [TAtlasButtonAnchor.Top,
    TAtlasButtonAnchor.Right]);
end;

procedure TAtlasButtonBarTests.CommonHeight;
begin
  Assert.AreEqual(25, TAtlasButtonBar.CommonHeight([25, 31, 25, 0]));
  Assert.AreEqual(31, TAtlasButtonBar.CommonHeight([31, 25]), 'Gleichstand: der erste');
  Assert.AreEqual(0, TAtlasButtonBar.CommonHeight([]));
end;

procedure TAtlasButtonBarTests.HandlerCloses;
const
  cSource =
    'implementation' + #13#10 +
    'procedure TForm1.btnOkClick(Sender: TObject);' + #13#10 +
    'begin' + #13#10 +
    '  Speichern;' + #13#10 +
    '  Close;' + #13#10 +
    'end;' + #13#10 +
    'procedure TForm1.btnCancelClick(Sender: TObject);' + #13#10 +
    'begin' + #13#10 +
    '  Verwerfen;' + #13#10 +
    'end;' + #13#10 +
    'procedure TForm1.btnApplyClick(Sender: TObject);' + #13#10 +
    'begin' + #13#10 +
    '  ModalResult := mrOk;' + #13#10 +
    'end;' + #13#10 +
    'end.';
begin
  Assert.IsTrue(TAtlasButtonBar.HandlerCloses(cSource, 'btnOkClick'));
  Assert.IsFalse(TAtlasButtonBar.HandlerCloses(cSource, 'btnCancelClick'));
  Assert.IsTrue(TAtlasButtonBar.HandlerCloses(cSource, 'BTNAPPLYCLICK'));
  Assert.IsFalse(TAtlasButtonBar.HandlerCloses(cSource, 'Fehlt'));
  Assert.IsFalse(TAtlasButtonBar.HandlerCloses(cSource, ''));
end;

end.
