unit Atlas.Core.Designer.Components.Tests;

// Tests der Designer-Leiste ohne VCL (#1442): Teilwortsuche über die
// Komponentennamen mit Reihenfolge der Treffer und Weiterschalten, und was
// ausgeblendet ist (Name, Klasse, nichtvisuelle, wieder eingeblendete).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasDesignerSearchTests = class
  public
    [Test]
    procedure MatchKinds;
    [Test]
    procedure FindOrdersBestFirst;
    [Test]
    procedure EmptyPatternFindsNothing;
    [Test]
    procedure StepWrapsAround;
  end;

  [TestFixture]
  TAtlasDesignerHiddenTests = class
  public
    [Test]
    procedure NamesHideAndShow;
    [Test]
    procedure ClassAndNonVisualHideGroups;
    [Test]
    procedure ShownNameBeatsGroup;
    [Test]
    procedure ShowAllClearsEverything;
  end;

implementation

uses
  Atlas.Core.Designer.Components;

function Items: TArray<TAtlasDesignerItem>;
begin
  Result := TArray<TAtlasDesignerItem>.Create(
    TAtlasDesignerItem.Create('btnOK', 'TButton', True),
    TAtlasDesignerItem.Create('OKAction', 'TAction', False),
    TAtlasDesignerItem.Create('ok', 'TLabel', True),
    TAtlasDesignerItem.Create('Lookup', 'TComboBox', True),
    TAtlasDesignerItem.Create('qryKunden', 'TFDQuery', False),
    TAtlasDesignerItem.Create('pnl_ok', 'TPanel', True));
end;

{ TAtlasDesignerSearchTests }

procedure TAtlasDesignerSearchTests.MatchKinds;
begin
  Assert.AreEqual(Ord(TAtlasDesignerMatch.Exact), Ord(TAtlasDesignerSearch.MatchOf('btnOK', 'BTNok')));
  Assert.AreEqual(Ord(TAtlasDesignerMatch.Prefix), Ord(TAtlasDesignerSearch.MatchOf('OKAction', 'ok')));
  Assert.AreEqual(Ord(TAtlasDesignerMatch.WordStart), Ord(TAtlasDesignerSearch.MatchOf('btnOK', 'ok')),
    'Großbuchstabe nach Kleinbuchstaben');
  Assert.AreEqual(Ord(TAtlasDesignerMatch.WordStart), Ord(TAtlasDesignerSearch.MatchOf('pnl_ok', 'ok')), 'nach _');
  Assert.AreEqual(Ord(TAtlasDesignerMatch.Contains), Ord(TAtlasDesignerSearch.MatchOf('Lookup', 'ok')));
  Assert.AreEqual(Ord(TAtlasDesignerMatch.None), Ord(TAtlasDesignerSearch.MatchOf('qryKunden', 'ok')));
  Assert.AreEqual(Ord(TAtlasDesignerMatch.Prefix), Ord(TAtlasDesignerSearch.MatchOf('qryKunden', ' qry ')),
    'Leerzeichen am Rand zählen nicht');
end;

procedure TAtlasDesignerSearchTests.FindOrdersBestFirst;
var
  mHits: TArray<Integer>;
begin
  mHits := TAtlasDesignerSearch.Find(Items, 'ok');
  // ok (gleich), OKAction (Anfang), btnOK und pnl_ok (Wortanfang, nach Namen), Lookup (irgendwo).
  Assert.AreEqual(5, Integer(Length(mHits)));
  Assert.AreEqual(2, mHits[0]);
  Assert.AreEqual(1, mHits[1]);
  Assert.AreEqual(0, mHits[2]);
  Assert.AreEqual(5, mHits[3]);
  Assert.AreEqual(3, mHits[4]);
  mHits := TAtlasDesignerSearch.Find(Items, 'kund');
  Assert.AreEqual(1, Integer(Length(mHits)));
  Assert.AreEqual(4, mHits[0]);
end;

procedure TAtlasDesignerSearchTests.EmptyPatternFindsNothing;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasDesignerSearch.Find(Items, ''))));
  Assert.AreEqual(0, Integer(Length(TAtlasDesignerSearch.Find(Items, '   '))));
  Assert.AreEqual(0, Integer(Length(TAtlasDesignerSearch.Find(nil, 'ok'))));
end;

procedure TAtlasDesignerSearchTests.StepWrapsAround;
begin
  Assert.AreEqual(1, TAtlasDesignerSearch.Step(0, 3, 1));
  Assert.AreEqual(0, TAtlasDesignerSearch.Step(2, 3, 1), 'nach dem letzten wieder der erste');
  Assert.AreEqual(2, TAtlasDesignerSearch.Step(0, 3, -1), 'vor dem ersten der letzte');
  Assert.AreEqual(0, TAtlasDesignerSearch.Step(-1, 3, 1));
  Assert.AreEqual(2, TAtlasDesignerSearch.Step(-1, 3, -1));
  Assert.AreEqual(-1, TAtlasDesignerSearch.Step(0, 0, 1), 'ohne Treffer');
end;

{ TAtlasDesignerHiddenTests }

procedure TAtlasDesignerHiddenTests.NamesHideAndShow;
var
  mHidden: TAtlasDesignerHidden;
begin
  mHidden := TAtlasDesignerHidden.Create;
  try
    Assert.IsFalse(mHidden.Any);
    mHidden.HideName('btnOK');
    Assert.IsTrue(mHidden.Any);
    Assert.IsTrue(mHidden.IsHidden(TAtlasDesignerItem.Create('BTNOK', 'TButton', True)), 'Name ohne Groß/klein');
    Assert.IsFalse(mHidden.IsHidden(TAtlasDesignerItem.Create('btnCancel', 'TButton', True)));
    Assert.AreEqual(1, mHidden.CountIn(Items));
    mHidden.ShowName('btnOK');
    Assert.IsFalse(mHidden.IsHidden(TAtlasDesignerItem.Create('btnOK', 'TButton', True)));
    Assert.IsFalse(mHidden.Any);
    mHidden.HideName('');
    Assert.IsFalse(mHidden.Any, 'ohne Namen nichts');
  finally
    mHidden.Free;
  end;
end;

procedure TAtlasDesignerHiddenTests.ClassAndNonVisualHideGroups;
var
  mHidden: TAtlasDesignerHidden;
begin
  mHidden := TAtlasDesignerHidden.Create;
  try
    mHidden.HideClass('TButton');
    Assert.IsTrue(mHidden.ClassHidden('tbutton'));
    Assert.IsTrue(mHidden.IsHidden(TAtlasDesignerItem.Create('btnNeu', 'TButton', True)), 'auch neue der Klasse');
    Assert.AreEqual(1, mHidden.CountIn(Items));
    mHidden.NonVisual := True;
    // btnOK, OKAction, qryKunden.
    Assert.AreEqual(3, mHidden.CountIn(Items));
    mHidden.HideClass('TPanel');
    Assert.AreEqual(2, Integer(Length(mHidden.HiddenClasses)));
    Assert.AreEqual('TButton', mHidden.HiddenClasses[0], 'Schreibweise der Klasse');
    mHidden.ShowClass('TBUTTON');
    Assert.IsFalse(mHidden.ClassHidden('TButton'));
    mHidden.NonVisual := False;
    Assert.AreEqual(1, mHidden.CountIn(Items), 'nur noch pnl_ok');
  finally
    mHidden.Free;
  end;
end;

procedure TAtlasDesignerHiddenTests.ShownNameBeatsGroup;
var
  mHidden: TAtlasDesignerHidden;
begin
  mHidden := TAtlasDesignerHidden.Create;
  try
    mHidden.NonVisual := True;
    mHidden.ShowName('qryKunden');
    Assert.IsFalse(mHidden.IsHidden(TAtlasDesignerItem.Create('qryKunden', 'TFDQuery', False)),
      'ausdrücklich eingeblendet');
    Assert.IsTrue(mHidden.IsHidden(TAtlasDesignerItem.Create('OKAction', 'TAction', False)));
    mHidden.HideName('qryKunden');
    Assert.IsTrue(mHidden.IsHidden(TAtlasDesignerItem.Create('qryKunden', 'TFDQuery', False)), 'wieder aus');
  finally
    mHidden.Free;
  end;
end;

procedure TAtlasDesignerHiddenTests.ShowAllClearsEverything;
var
  mHidden: TAtlasDesignerHidden;
begin
  mHidden := TAtlasDesignerHidden.Create;
  try
    mHidden.HideName('ok');
    mHidden.HideClass('TComboBox');
    mHidden.NonVisual := True;
    Assert.AreEqual(4, mHidden.CountIn(Items));
    mHidden.ShowAll;
    Assert.IsFalse(mHidden.Any);
    Assert.IsFalse(mHidden.NonVisual);
    Assert.AreEqual(0, mHidden.CountIn(Items));
  finally
    mHidden.Free;
  end;
end;

end.
