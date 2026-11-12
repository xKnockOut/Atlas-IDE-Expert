unit Atlas.Core.Designer.DuplicateRow.Tests;

// Tests für „In Reihe duplizieren“ (#736): Lage in beiden Richtungen,
// erkannter Abstand, Namen aus Liste und Zähler, Captions, TabOrder,
// FocusControl und Überlauf samt Verschieben.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasDuplicateRowTests = class
  public
    [Test]
    procedure ListGivesCount;
    [Test]
    procedure LayoutDown;
    [Test]
    procedure LayoutRight;
    [Test]
    procedure GapFromNeighbour;
    [Test]
    procedure NamesFromList;
    [Test]
    procedure NamesCounted;
    [Test]
    procedure NamesUnique;
    [Test]
    procedure Captions;
    [Test]
    procedure TabOrderBehindOriginal;
    [Test]
    procedure FocusControlPointsToCopy;
    [Test]
    procedure Overflow;
    [Test]
    procedure PushFollowers;
  end;

implementation

uses
  System.Types,
  Atlas.Core.Designer.DuplicateRow;

function Request(const AGroup, AClient: TRect; const AOthers: TArray<TRect>; ADirection: TAtlasDuplicateDirection;
  ACount: Integer): TAtlasDuplicateRequest;
begin
  Result.Group := AGroup;
  Result.Client := AClient;
  Result.Others := AOthers;
  Result.Direction := ADirection;
  Result.Gap := 8;
  Result.Count := ACount;
  Result.Push := False;
end;

procedure TAtlasDuplicateRowTests.ListGivesCount;
var
  mList: TArray<string>;
begin
  mList := TAtlasDuplicateRow.ParseList(' Fax, Mobil;Privat ,, ');
  Assert.AreEqual(3, Integer(Length(mList)));
  Assert.AreEqual('Mobil', mList[1]);
  Assert.AreEqual(3, TAtlasDuplicateRow.CopyCount(mList, 7), 'Liste geht vor');
  Assert.AreEqual(2, TAtlasDuplicateRow.CopyCount(nil, 2));
  Assert.AreEqual(1, TAtlasDuplicateRow.CopyCount(nil, 0), 'mindestens eine');
end;

procedure TAtlasDuplicateRowTests.LayoutDown;
var
  mLayout: TAtlasDuplicateLayout;
  mGroup: TRect;
begin
  mGroup := TAtlasDuplicateRow.UnionOf([Rect(8, 40, 80, 57), Rect(90, 37, 250, 60)]);
  Assert.AreEqual(37, mGroup.Top);
  Assert.AreEqual(250, mGroup.Right);
  mLayout := TAtlasDuplicateRow.Layout(Request(mGroup, Rect(0, 0, 400, 300), nil, TAtlasDuplicateDirection.Down, 3));
  Assert.AreEqual(3, Integer(Length(mLayout.Copies)));
  Assert.AreEqual(68, mLayout.Copies[0].Top, '37 + 23 + 8');
  Assert.AreEqual(130, mLayout.Copies[2].Top, 'gleicher Abstand');
  Assert.AreEqual(8, mLayout.Copies[2].Left);
  Assert.IsFalse(mLayout.AnyBad);
end;

procedure TAtlasDuplicateRowTests.LayoutRight;
var
  mOffset: TPoint;
begin
  mOffset := TAtlasDuplicateRow.Offset(Rect(10, 10, 110, 35), TAtlasDuplicateDirection.Right, 6, 1);
  Assert.AreEqual(212, mOffset.X, '2 * (100 + 6)');
  Assert.AreEqual(0, mOffset.Y);
end;

procedure TAtlasDuplicateRowTests.GapFromNeighbour;
begin
  Assert.AreEqual(6, TAtlasDuplicateRow.DetectGap(Rect(8, 40, 250, 60), [Rect(8, 10, 250, 34), Rect(8, 90, 250, 110),
    Rect(300, 61, 350, 70)], TAtlasDuplicateDirection.Down), 'darüber 6, darunter 30, daneben zählt nicht');
  Assert.AreEqual(12, TAtlasDuplicateRow.DetectGap(Rect(8, 40, 100, 60), [Rect(112, 40, 200, 60)],
    TAtlasDuplicateDirection.Right));
  Assert.AreEqual(-1, TAtlasDuplicateRow.DetectGap(Rect(8, 40, 100, 60), [Rect(200, 100, 300, 120)],
    TAtlasDuplicateDirection.Down), 'kein Nachbar');
end;

procedure TAtlasDuplicateRowTests.NamesFromList;
var
  mNames: TArray<TArray<string>>;
begin
  mNames := TAtlasDuplicateRow.Names(['lblTelefon', 'edtTelefon'], TAtlasDuplicateRow.ParseList('Fax, Mobil, Privat'),
    3, ['lblTelefon', 'edtTelefon']);
  Assert.AreEqual('lblFax', mNames[0][0]);
  Assert.AreEqual('edtFax', mNames[0][1]);
  Assert.AreEqual('edtPrivat', mNames[2][1]);
  Assert.AreEqual('LabelFax', TAtlasDuplicateRow.NameFor('Label1', 'Fax', 0), 'ohne Präfix');
  Assert.AreEqual('edtAdresse2', TAtlasDuplicateRow.NameFor('edtAdresse1', 'Adresse 2', 1));
  Assert.AreEqual('edtZurueck', TAtlasDuplicateRow.NameFor('edtWeiter', 'zur' + #$FC + 'ck', 0), 'Umlaut');
  Assert.AreEqual('', TAtlasDuplicateRow.PrefixOf('Edit1'));
  Assert.AreEqual('lbl', TAtlasDuplicateRow.PrefixOf('lblTelefon'));
end;

procedure TAtlasDuplicateRowTests.NamesCounted;
begin
  Assert.AreEqual('edtTelefon2', TAtlasDuplicateRow.NameFor('edtTelefon', '', 0));
  Assert.AreEqual('edtTelefon3', TAtlasDuplicateRow.NameFor('edtTelefon', '', 1));
  Assert.AreEqual('Edit4', TAtlasDuplicateRow.NameFor('Edit3', '', 0), 'Zahl am Ende wird hochgezählt');
end;

procedure TAtlasDuplicateRowTests.NamesUnique;
var
  mNames: TArray<TArray<string>>;
begin
  Assert.AreEqual('edtFax2', TAtlasDuplicateRow.UniqueName('edtFax', ['EDTFAX']));
  Assert.AreEqual('Edit5', TAtlasDuplicateRow.UniqueName('Edit4', ['Edit4']));
  mNames := TAtlasDuplicateRow.Names(['Edit1'], nil, 2, ['Edit1', 'Edit2']);
  Assert.AreEqual('Edit3', mNames[0][0], 'Edit2 ist vergeben');
  Assert.AreEqual('Edit4', mNames[1][0], 'nicht doppelt');
end;

procedure TAtlasDuplicateRowTests.Captions;
begin
  Assert.AreEqual('Fax:', TAtlasDuplicateRow.CaptionFor('Telefon:', 'Fax'));
  Assert.AreEqual('Fax', TAtlasDuplicateRow.CaptionFor('Telefon', 'Fax'));
  Assert.AreEqual('Telefon:', TAtlasDuplicateRow.CaptionFor('Telefon:', ''), 'ohne Liste unverändert');
end;

procedure TAtlasDuplicateRowTests.TabOrderBehindOriginal;
var
  mOrders: TArray<TArray<Integer>>;
begin
  mOrders := TAtlasDuplicateRow.TabOrders(4, 2, 3);
  Assert.AreEqual(5, mOrders[0][0]);
  Assert.AreEqual(6, mOrders[0][1]);
  Assert.AreEqual(7, mOrders[1][0]);
  Assert.AreEqual(10, mOrders[2][1]);
end;

procedure TAtlasDuplicateRowTests.FocusControlPointsToCopy;
begin
  Assert.AreEqual('edtFax', TAtlasDuplicateRow.MapReference('edtTelefon', ['lblTelefon', 'edtTelefon'],
    ['lblFax', 'edtFax']));
  Assert.AreEqual('edtName', TAtlasDuplicateRow.MapReference('edtName', ['lblTelefon', 'edtTelefon'],
    ['lblFax', 'edtFax']), 'außerhalb der Auswahl bleibt');
end;

procedure TAtlasDuplicateRowTests.Overflow;
var
  mLayout: TAtlasDuplicateLayout;
begin
  mLayout := TAtlasDuplicateRow.Layout(Request(Rect(8, 200, 250, 223), Rect(0, 0, 400, 260), [Rect(8, 240, 80, 255)],
    TAtlasDuplicateDirection.Down, 2));
  Assert.IsTrue(mLayout.Bad[0], 'überdeckt ein Steuerelement');
  Assert.IsTrue(mLayout.Bad[1], 'ragt heraus');
  Assert.IsTrue(mLayout.AnyBad);
end;

procedure TAtlasDuplicateRowTests.PushFollowers;
var
  mRequest: TAtlasDuplicateRequest;
  mLayout: TAtlasDuplicateLayout;
begin
  mRequest := Request(Rect(8, 40, 250, 63), Rect(0, 0, 400, 300), [Rect(8, 10, 250, 33), Rect(8, 71, 250, 94)],
    TAtlasDuplicateDirection.Down, 2);
  mRequest.Push := True;
  mLayout := TAtlasDuplicateRow.Layout(mRequest);
  Assert.AreEqual(10, mLayout.Others[0].Top, 'davor bleibt');
  Assert.AreEqual(133, mLayout.Others[1].Top, '71 + 2 * (23 + 8)');
  Assert.IsFalse(mLayout.AnyBad);
  Assert.AreEqual(1, Integer(Length(TAtlasDuplicateRow.Followers(mRequest.Group, mRequest.Others,
    TAtlasDuplicateDirection.Down))));
end;

end.
