unit Atlas.Core.Designer.TabOrder.Tests;

// Tests der Tab-Reihenfolge im Designer ohne VCL (#1442, #603):
// Lesereihenfolge, Rücksprünge, Lücken und Doppelte, Pfade, Pfade mit
// Namen, Farbgruppen je Container, Sortieren nach
// Lesereihenfolge, Zuweisungen und der Modus „Reihenfolge klicken“ samt Esc,
// auf Steuerelementen und auf Fixture-DFMs über das Formularmodell.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasTabOrderTests = class
  public
    [Test]
    procedure ReadingOrder;
    [Test]
    procedure RightToLeftReadsRightFirst;
    [Test]
    procedure JumpBackIsMarked;
    [Test]
    procedure NotReachedSkipsJump;
    [Test]
    procedure DuplicatesAndGaps;
    [Test]
    procedure PathsFollowContainers;
    [Test]
    procedure NamedPathGivesWay;
    [Test]
    procedure GroupsDifferFromParentAndNeighbour;
    [Test]
    procedure GroupsOnlyForParents;
    [Test]
    procedure GroupsWithoutCount;
    [Test]
    procedure StopShownByDefault;
    [Test]
    procedure SortByReadingOrder;
    [Test]
    procedure AssignmentsAscendingPerParent;
    [Test]
    procedure FormFixture;
    [Test]
    procedure FormFixtureJump;
  end;

  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasTabClicksTests = class
  public
    [Test]
    procedure ClicksCountPerParent;
    [Test]
    procedure SecondClickIgnored;
    [Test]
    procedure RestoreGivesOldState;
  end;

implementation

uses
  System.Types,
  System.SysUtils,
  Atlas.Core.Designer.FormModel,
  Atlas.Core.Designer.TabOrder;

const
  cCrLf = #13#10;

  // Drei Edits und zwei Buttons; edtPlz mit TabOrder 4 liegt räumlich vor dem OK-Button mit 3.
  cAdresse =
    'object frmAdresse: TfrmAdresse' + cCrLf +
    '  Left = 0' + cCrLf +
    '  Top = 0' + cCrLf +
    '  object edtName: TEdit' + cCrLf +
    '    Left = 16' + cCrLf +
    '    Top = 16' + cCrLf +
    '    Width = 180' + cCrLf +
    '    Height = 23' + cCrLf +
    '    TabOrder = 0' + cCrLf +
    '  end' + cCrLf +
    '  object edtOrt: TEdit' + cCrLf +
    '    Left = 16' + cCrLf +
    '    Top = 48' + cCrLf +
    '    Width = 180' + cCrLf +
    '    Height = 23' + cCrLf +
    '    TabOrder = 1' + cCrLf +
    '  end' + cCrLf +
    '  object edtStrasse: TEdit' + cCrLf +
    '    Left = 16' + cCrLf +
    '    Top = 80' + cCrLf +
    '    Width = 180' + cCrLf +
    '    Height = 23' + cCrLf +
    '    TabOrder = 2' + cCrLf +
    '  end' + cCrLf +
    '  object btnOK: TButton' + cCrLf +
    '    Left = 216' + cCrLf +
    '    Top = 160' + cCrLf +
    '    Width = 75' + cCrLf +
    '    Height = 25' + cCrLf +
    '    Caption = ''OK''' + cCrLf +
    '    TabOrder = 3' + cCrLf +
    '  end' + cCrLf +
    '  object pnlPlz: TPanel' + cCrLf +
    '    Left = 216' + cCrLf +
    '    Top = 16' + cCrLf +
    '    Width = 200' + cCrLf +
    '    Height = 60' + cCrLf +
    '    TabOrder = 4' + cCrLf +
    '    object edtPlz: TEdit' + cCrLf +
    '      Left = 8' + cCrLf +
    '      Top = 8' + cCrLf +
    '      Width = 60' + cCrLf +
    '      Height = 23' + cCrLf +
    '      TabOrder = 1' + cCrLf +
    '    end' + cCrLf +
    '    object chkAusland: TCheckBox' + cCrLf +
    '      Left = 80' + cCrLf +
    '      Top = 8' + cCrLf +
    '      Width = 100' + cCrLf +
    '      Height = 17' + cCrLf +
    '      TabStop = False' + cCrLf +
    '      TabOrder = 0' + cCrLf +
    '    end' + cCrLf +
    '  end' + cCrLf +
    '  object btnAbbrechen: TButton' + cCrLf +
    '    Left = 300' + cCrLf +
    '    Top = 160' + cCrLf +
    '    Width = 75' + cCrLf +
    '    Height = 25' + cCrLf +
    '    TabOrder = 5' + cCrLf +
    '  end' + cCrLf +
    'end' + cCrLf;

function Stop(const AName, AParent: string; AOrder: Integer; const ABounds: TRect): TAtlasTabStop;
begin
  Result := TAtlasTabStop.Create(AName, AParent, AOrder, ABounds);
end;

{ TAtlasTabOrderTests }

procedure TAtlasTabOrderTests.ReadingOrder;
begin
  Assert.IsTrue(TAtlasTabOrder.ReadsBefore(Rect(0, 0, 50, 20), Rect(100, 4, 150, 24)), 'gleiche Zeile: links zuerst');
  Assert.IsFalse(TAtlasTabOrder.ReadsBefore(Rect(100, 0, 150, 20), Rect(0, 4, 50, 24)));
  Assert.IsTrue(TAtlasTabOrder.ReadsBefore(Rect(300, 0, 350, 20), Rect(0, 40, 50, 60)), 'obere Zeile zuerst');
end;

procedure TAtlasTabOrderTests.RightToLeftReadsRightFirst;
begin
  Assert.IsTrue(TAtlasTabOrder.ReadsBefore(Rect(100, 0, 150, 20), Rect(0, 4, 50, 24), True), 'rechts zuerst');
  Assert.IsFalse(TAtlasTabOrder.ReadsBefore(Rect(0, 0, 50, 20), Rect(100, 4, 150, 24), True));
  Assert.IsTrue(TAtlasTabOrder.ReadsBefore(Rect(0, 0, 50, 20), Rect(300, 40, 350, 60), True), 'Zeilen bleiben');
end;

procedure TAtlasTabOrderTests.JumpBackIsMarked;
var
  mStops: TArray<TAtlasTabStop>;
  mOut: TArray<Boolean>;
  mIssues: TArray<TAtlasTabIssue>;
begin
  // edtName 0, edtOrt 1, OK 2, edtPLZ 3 (rechts oben, Rücksprung), Abbrechen 4.
  mStops := TArray<TAtlasTabStop>.Create(
    Stop('edtName', '', 0, Rect(16, 40, 196, 64)),
    Stop('edtOrt', '', 1, Rect(16, 76, 196, 100)),
    Stop('edtPLZ', '', 3, Rect(216, 40, 396, 64)),
    Stop('btnOK', '', 2, Rect(236, 150, 320, 178)),
    Stop('btnAbbrechen', '', 4, Rect(330, 150, 414, 178)),
    Stop('edtInnen', 'pnlTop', 0, Rect(0, 0, 50, 20)));
  mOut := TAtlasTabOrder.OutOfOrder(mStops);
  Assert.IsFalse(mOut[0]);
  Assert.IsFalse(mOut[1]);
  Assert.IsTrue(mOut[2], 'edtPLZ nach OK springt nach oben');
  Assert.IsFalse(mOut[3]);
  Assert.IsFalse(mOut[4], 'Abbrechen liegt in der Lesereihenfolge nach edtPLZ');
  Assert.IsFalse(mOut[5], 'anderes Elternelement zählt für sich');
  mIssues := TAtlasTabOrder.Issues(mStops);
  Assert.AreEqual(Ord(TAtlasTabIssue.Jump), Ord(mIssues[2]));
  Assert.AreEqual(Ord(TAtlasTabIssue.None), Ord(mIssues[0]));
  Assert.AreEqual(Ord(TAtlasTabIssue.None), Ord(mIssues[5]));
end;

procedure TAtlasTabOrderTests.NotReachedSkipsJump;
var
  mStops: TArray<TAtlasTabStop>;
  mOut: TArray<Boolean>;
begin
  // Das Label-artige Steuerelement ohne TabStop dazwischen zählt nicht: Tab springt von 0 direkt zu 2.
  mStops := TArray<TAtlasTabStop>.Create(
    Stop('edtA', '', 0, Rect(0, 0, 50, 20)),
    Stop('pbxBild', '', 1, Rect(0, 100, 50, 120)),
    Stop('edtB', '', 2, Rect(0, 40, 50, 60)));
  mStops[1].Focusable := False;
  mOut := TAtlasTabOrder.OutOfOrder(mStops);
  Assert.IsFalse(mOut[1], 'ohne TabStop keine Warnung');
  Assert.IsFalse(mOut[2], 'edtB folgt auf edtA, nicht auf pbxBild');
end;

procedure TAtlasTabOrderTests.DuplicatesAndGaps;
var
  mStops: TArray<TAtlasTabStop>;
  mIssues: TArray<TAtlasTabIssue>;
begin
  mStops := TArray<TAtlasTabStop>.Create(
    Stop('edtA', '', 0, Rect(0, 0, 50, 20)),
    Stop('edtB', '', 1, Rect(0, 40, 50, 60)),
    Stop('edtC', '', 1, Rect(0, 80, 50, 100)),
    Stop('edtD', '', 4, Rect(0, 120, 50, 140)),
    Stop('edtE', 'pnl', 2, Rect(0, 0, 50, 20)));
  mIssues := TAtlasTabOrder.Issues(mStops);
  Assert.AreEqual(Ord(TAtlasTabIssue.None), Ord(mIssues[0]));
  Assert.AreEqual(Ord(TAtlasTabIssue.Duplicate), Ord(mIssues[1]), 'beide Doppelten');
  Assert.AreEqual(Ord(TAtlasTabIssue.Duplicate), Ord(mIssues[2]));
  Assert.AreEqual(Ord(TAtlasTabIssue.Gap), Ord(mIssues[3]), '2 und 3 fehlen');
  Assert.AreEqual(Ord(TAtlasTabIssue.Gap), Ord(mIssues[4]), 'Folge im Panel beginnt nicht bei 0');
end;

procedure TAtlasTabOrderTests.PathsFollowContainers;
var
  mStops: TArray<TAtlasTabStop>;
  mPaths: TArray<string>;
begin
  mStops := TArray<TAtlasTabStop>.Create(
    Stop('edtA', '', 0, Rect(0, 0, 50, 20)),
    Stop('pnlAdresse', '', 2, Rect(0, 40, 300, 200)),
    Stop('edtPlz', 'pnlAdresse', 1, Rect(10, 50, 60, 70)),
    Stop('grpLand', 'pnlAdresse', 0, Rect(10, 80, 200, 190)),
    Stop('cbxLand', 'grpLand', 3, Rect(20, 100, 120, 120)));
  mStops[1].Container := True;
  mPaths := TAtlasTabOrder.Paths(mStops);
  Assert.AreEqual('0', mPaths[0]);
  Assert.AreEqual('2', mPaths[1]);
  Assert.AreEqual('2.1', mPaths[2]);
  Assert.AreEqual('2.0', mPaths[3]);
  Assert.AreEqual('2.0.3', mPaths[4]);
end;

/// <summary>Seiten (PageControl) › tsStamm › grpAdresse › pnlOrt › edPlz, daneben grpKontakt mit pnlNews.</summary>
function NestedStops: TArray<TAtlasTabStop>;
begin
  Result := TArray<TAtlasTabStop>.Create(
    Stop('edSuche', '', 0, Rect(0, 0, 300, 20)),
    Stop('pgcSeiten', '', 1, Rect(0, 40, 500, 300)),
    Stop('tsStamm', 'pgcSeiten', 0, Rect(4, 64, 496, 296)),
    Stop('tsHistorie', 'pgcSeiten', 1, Rect(4, 64, 496, 296)),
    Stop('grpAdresse', 'tsStamm', 0, Rect(10, 70, 240, 290)),
    Stop('grpKontakt', 'tsStamm', 1, Rect(250, 70, 490, 290)),
    Stop('pnlOrt', 'grpAdresse', 2, Rect(20, 160, 230, 200)),
    Stop('edPlz', 'pnlOrt', 0, Rect(24, 170, 80, 190)),
    Stop('pnlNews', 'grpKontakt', 2, Rect(260, 160, 480, 220)),
    Stop('cbNews', 'pnlNews', 0, Rect(264, 170, 400, 186)),
    Stop('lvHistorie', 'tsHistorie', 0, Rect(10, 70, 490, 290)));
end;

procedure TAtlasTabOrderTests.NamedPathGivesWay;
var
  mStops: TArray<TAtlasTabStop>;
begin
  mStops := NestedStops;
  Assert.AreEqual('edSuche 0', TAtlasTabOrder.NamedPath(mStops, 0), 'oberste Ebene: nur der eigene Name');
  Assert.AreEqual('pgcSeiten 1 › tsStamm 0 › grpAdresse 0 › pnlOrt 2 › edPlz 0',
    TAtlasTabOrder.NamedPath(mStops, 7));
end;

procedure TAtlasTabOrderTests.GroupsDifferFromParentAndNeighbour;
var
  mStops: TArray<TAtlasTabStop>;
  mGroups: TArray<Integer>;
  mIndex, mParent: Integer;
begin
  mStops := NestedStops;
  mGroups := TAtlasTabOrder.Groups(mStops, 3);
  for mIndex := 0 to High(mStops) do
  begin
    mParent := TAtlasTabOrder.IndexOf(mStops, mStops[mIndex].ParentName);
    if (mGroups[mIndex] >= 0) and (mParent >= 0) then
    begin
      Assert.AreNotEqual(mGroups[mParent], mGroups[mIndex], mStops[mIndex].Name + ' wie sein Elternelement');
    end;
    Assert.IsTrue(mGroups[mIndex] < 3, 'innerhalb der Zahl der Farben');
  end;
  Assert.AreNotEqual(mGroups[4], mGroups[5], 'grpAdresse und grpKontakt nebeneinander');
  Assert.AreNotEqual(mGroups[2], mGroups[3], 'Registerseiten nebeneinander');
  Assert.AreEqual(mGroups[6], TAtlasTabOrder.GroupOf(mStops, mGroups, 7), 'edPlz trägt die Farbe von pnlOrt');
  Assert.AreEqual(-1, TAtlasTabOrder.GroupOf(mStops, mGroups, 0), 'oberste Ebene ohne Gruppe');
  Assert.AreEqual(mGroups[1], TAtlasTabOrder.GroupOf(mStops, mGroups, 2));
end;

procedure TAtlasTabOrderTests.GroupsOnlyForParents;
var
  mStops: TArray<TAtlasTabStop>;
  mGroups, mAgain: TArray<Integer>;
  mIndex: Integer;
begin
  mStops := NestedStops;
  mGroups := TAtlasTabOrder.Groups(mStops, 6);
  Assert.AreEqual(-1, mGroups[0], 'edSuche hat keine Kinder');
  Assert.AreEqual(-1, mGroups[7], 'edPlz hat keine Kinder');
  Assert.AreEqual(0, mGroups[1], 'erster Container in Tab-Reihenfolge');
  Assert.IsTrue(mGroups[3] >= 0, 'verborgene Registerseite behält ihre Farbe');
  // Gleiche Eingabe in anderer Reihenfolge der Liste: gleiche Farben je Name.
  mAgain := TAtlasTabOrder.Groups(TArray<TAtlasTabStop>.Create(mStops[10], mStops[9], mStops[8], mStops[7],
    mStops[6], mStops[5], mStops[4], mStops[3], mStops[2], mStops[1], mStops[0]), 6);
  for mIndex := 0 to High(mStops) do
  begin
    Assert.AreEqual(mGroups[mIndex], mAgain[High(mStops) - mIndex], mStops[mIndex].Name);
  end;
end;

procedure TAtlasTabOrderTests.GroupsWithoutCount;
var
  mGroups: TArray<Integer>;
begin
  mGroups := TAtlasTabOrder.Groups(NestedStops, 0);
  Assert.AreEqual(11, Integer(Length(mGroups)));
  Assert.AreEqual(-1, mGroups[1], 'ohne Farben keine Gruppe');
end;

procedure TAtlasTabOrderTests.StopShownByDefault;
var
  mStop: TAtlasTabStop;
begin
  mStop := Stop('edA', '', 0, Rect(0, 0, 10, 10));
  Assert.IsTrue(mStop.Shown);
end;

procedure TAtlasTabOrderTests.SortByReadingOrder;
var
  mStops: TArray<TAtlasTabStop>;
  mOrders: TArray<Integer>;
begin
  mStops := TArray<TAtlasTabStop>.Create(
    Stop('btnOK', '', 0, Rect(200, 160, 275, 185)),
    Stop('edtPlz', '', 1, Rect(200, 16, 260, 39)),
    Stop('edtName', '', 2, Rect(16, 16, 196, 39)),
    Stop('edtOrt', '', 3, Rect(16, 48, 196, 71)),
    Stop('edtInnen', 'pnl', 5, Rect(0, 0, 50, 20)));
  mOrders := TAtlasTabOrder.ReadingOrder(mStops);
  Assert.AreEqual(3, mOrders[0], 'OK zuletzt');
  Assert.AreEqual(1, mOrders[1], 'Plz rechts neben Name');
  Assert.AreEqual(0, mOrders[2]);
  Assert.AreEqual(2, mOrders[3]);
  Assert.AreEqual(0, mOrders[4], 'eigene Folge im Panel');
  mOrders := TAtlasTabOrder.ReadingOrder(mStops, True);
  Assert.AreEqual(0, mOrders[1], 'rechts nach links: Plz zuerst');
  Assert.AreEqual(1, mOrders[2]);
end;

procedure TAtlasTabOrderTests.AssignmentsAscendingPerParent;
var
  mStops: TArray<TAtlasTabStop>;
  mList: TArray<TAtlasTabAssignment>;
begin
  mStops := TArray<TAtlasTabStop>.Create(
    Stop('a', '', 0, TRect.Empty),
    Stop('b', '', 1, TRect.Empty),
    Stop('c', '', 2, TRect.Empty),
    Stop('x', 'pnl', 0, TRect.Empty));
  Assert.AreEqual(0, Integer(Length(TAtlasTabOrder.Assignments(mStops, TArray<Integer>.Create(0, 1, 2, 0)))),
    'ohne Änderung nichts');
  mList := TAtlasTabOrder.Assignments(mStops, TArray<Integer>.Create(2, 0, 1, 0));
  Assert.AreEqual(4, Integer(Length(mList)));
  Assert.AreEqual('b', mList[0].Name);
  Assert.AreEqual(0, mList[0].Order);
  Assert.AreEqual('c', mList[1].Name);
  Assert.AreEqual('a', mList[2].Name);
  Assert.AreEqual(2, mList[2].Order);
  Assert.AreEqual('x', mList[3].Name);
end;

procedure TAtlasTabOrderTests.FormFixture;
var
  mStops: TArray<TAtlasTabStop>;
  mIndex: Integer;
  mPaths: TArray<string>;
begin
  mStops := TAtlasTabOrder.FromForm(TAtlasFormModel.Parse(cAdresse));
  Assert.AreEqual(8, Integer(Length(mStops)));
  mIndex := TAtlasTabOrder.IndexOf(mStops, 'edtPlz');
  Assert.AreEqual('pnlPlz', mStops[mIndex].ParentName);
  Assert.AreEqual(224, mStops[mIndex].Bounds.Left, 'Lage im Client der Wurzel');
  Assert.AreEqual(24, mStops[mIndex].Bounds.Top);
  Assert.AreEqual('', mStops[TAtlasTabOrder.IndexOf(mStops, 'btnOK')].ParentName, 'direkt auf dem Formular');
  Assert.IsFalse(mStops[TAtlasTabOrder.IndexOf(mStops, 'chkAusland')].Focusable, 'TabStop = False');
  Assert.IsTrue(mStops[TAtlasTabOrder.IndexOf(mStops, 'pnlPlz')].Container);
  mPaths := TAtlasTabOrder.Paths(mStops);
  Assert.AreEqual('4.1', mPaths[mIndex]);
end;

procedure TAtlasTabOrderTests.FormFixtureJump;
var
  mStops: TArray<TAtlasTabStop>;
  mIssues: TArray<TAtlasTabIssue>;
  mOrders: TArray<Integer>;
begin
  mStops := TAtlasTabOrder.FromForm(TAtlasFormModel.Parse(cAdresse));
  mIssues := TAtlasTabOrder.Issues(mStops);
  // Das Panel mit edtPlz (4) liegt oben rechts, vor dem OK-Button (3).
  Assert.AreEqual(Ord(TAtlasTabIssue.Jump), Ord(mIssues[TAtlasTabOrder.IndexOf(mStops, 'pnlPlz')]));
  Assert.AreEqual(Ord(TAtlasTabIssue.None), Ord(mIssues[TAtlasTabOrder.IndexOf(mStops, 'btnOK')]));
  Assert.AreEqual(Ord(TAtlasTabIssue.None), Ord(mIssues[TAtlasTabOrder.IndexOf(mStops, 'btnAbbrechen')]));
  mOrders := TAtlasTabOrder.ReadingOrder(mStops);
  // Das hohe Panel steht in der Zeile von edtName und edtOrt, rechts von beiden.
  Assert.AreEqual(2, mOrders[TAtlasTabOrder.IndexOf(mStops, 'pnlPlz')], 'sortiert: Panel nach edtName und edtOrt');
  Assert.AreEqual(4, mOrders[TAtlasTabOrder.IndexOf(mStops, 'btnOK')]);
end;

{ TAtlasTabClicksTests }

procedure TAtlasTabClicksTests.ClicksCountPerParent;
var
  mClicks: TAtlasTabClicks;
begin
  mClicks := TAtlasTabClicks.Create;
  try
    mClicks.Start(nil);
    Assert.IsTrue(mClicks.Active);
    Assert.AreEqual(0, mClicks.Next('a', 'MainForm'));
    Assert.AreEqual(1, mClicks.Next('b', 'mainform'));
    Assert.AreEqual(0, mClicks.Next('c', 'pnlTop'));
    Assert.AreEqual(2, mClicks.Next('d', 'MainForm'));
    Assert.AreEqual(4, mClicks.Count);
    mClicks.Reset;
    Assert.IsFalse(mClicks.Active);
    Assert.AreEqual(0, mClicks.Next('a', 'MainForm'));
  finally
    mClicks.Free;
  end;
end;

procedure TAtlasTabClicksTests.SecondClickIgnored;
var
  mClicks: TAtlasTabClicks;
begin
  mClicks := TAtlasTabClicks.Create;
  try
    mClicks.Start(nil);
    Assert.AreEqual(0, mClicks.Next('edtName', ''));
    Assert.AreEqual(-1, mClicks.Next('EDTNAME', ''), 'schon vergeben');
    Assert.IsTrue(mClicks.Clicked('edtName'));
    Assert.IsFalse(mClicks.Clicked('edtOrt'));
    Assert.AreEqual(1, mClicks.Next('edtOrt', ''));
  finally
    mClicks.Free;
  end;
end;

procedure TAtlasTabClicksTests.RestoreGivesOldState;
var
  mClicks: TAtlasTabClicks;
  mList: TArray<TAtlasTabAssignment>;
begin
  mClicks := TAtlasTabClicks.Create;
  try
    mClicks.Start(TArray<TAtlasTabStop>.Create(
      Stop('c', '', 2, TRect.Empty),
      Stop('a', '', 0, TRect.Empty),
      Stop('b', '', 1, TRect.Empty)));
    mClicks.Next('c', '');
    mList := mClicks.Restore;
    Assert.AreEqual(3, Integer(Length(mList)), 'alle, auch die verschobenen Geschwister');
    Assert.AreEqual('a', mList[0].Name);
    Assert.AreEqual(0, mList[0].Order);
    Assert.AreEqual('b', mList[1].Name);
    Assert.AreEqual('c', mList[2].Name);
    Assert.AreEqual(2, mList[2].Order);
  finally
    mClicks.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTabOrderTests);
  TDUnitX.RegisterTestFixture(TAtlasTabClicksTests);

end.
