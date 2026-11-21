unit Atlas.Core.Welcome.Contract.Tests;

// Datentypen der Willkommensseite im Vertrag: Schalter eines Bereichs, Breite eines Platzes, zuletzt bearbeiteter
// Reiter, Projekt oder Gruppe, Vergleich von Registry-Werten, ohne Datei und ohne Windows.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasWelcomeContractTests = class
  public
    [Test]
    procedure SectionWithoutSwitchIsEnabled;
    [Test]
    procedure SlotWidthStaysInRange;
    [Test]
    procedure LastIndexPrefersNewestChange;
    [Test]
    procedure LastIndexFallsBackToActiveTab;
    [Test]
    procedure EntryKnowsNameAndGroup;
    [Test]
    procedure RegValuesCompareNameWithoutCase;
    [Test]
    procedure RegValuesCompareLines;
    [Test]
    procedure WorkOrderPutsNewestFirstAndKeepsTies;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Welcome.Contract;

{ TAtlasWelcomeContractTests }

procedure TAtlasWelcomeContractTests.SectionWithoutSwitchIsEnabled;
var
  mSection: TAtlasWelcomeSection;
begin
  mSection := TAtlasWelcomeSection.Create('atlas.state', 'Zustand', 1, TAtlasWelcomeColumn.Left, nil);
  Assert.IsTrue(mSection.IsEnabled);
  mSection.Enabled :=
    function: Boolean
    begin
      Result := False;
    end;
  Assert.IsFalse(mSection.IsEnabled);
end;

procedure TAtlasWelcomeContractTests.SlotWidthStaysInRange;
begin
  Assert.AreEqual(TAtlasWelcomeLayout.cMaxWidth, TAtlasWelcomeSlot.Create('a', 0, 7, True).Width);
  Assert.AreEqual(TAtlasWelcomeLayout.cMinWidth, TAtlasWelcomeSlot.Create('a', 0, 0, True).Width);
  Assert.AreEqual(1, TAtlasWelcomeSlot.Create('a', 1).Width);
end;

procedure TAtlasWelcomeContractTests.LastIndexPrefersNewestChange;
var
  mState: TAtlasWorkState;
begin
  mState := TAtlasWorkState.Empty;
  mState.Tabs := [TAtlasWorkTab.Create('C:\A.pas', 1, 1), TAtlasWorkTab.Create('C:\B.pas', 2, 1),
    TAtlasWorkTab.Create('C:\C.pas', 3, 1)];
  mState.Tabs[0].Changed := True;
  mState.Tabs[0].ChangedAt := EncodeDate(2026, 11, 1);
  mState.Tabs[2].Changed := True;
  mState.Tabs[2].ChangedAt := EncodeDate(2026, 11, 2);
  mState.Active := 1;
  Assert.AreEqual(3, mState.TabCount);
  Assert.AreEqual(2, mState.LastIndex);
end;

procedure TAtlasWelcomeContractTests.LastIndexFallsBackToActiveTab;
var
  mState: TAtlasWorkState;
begin
  mState := TAtlasWorkState.Empty;
  Assert.AreEqual(-1, mState.LastIndex);
  mState.Tabs := [TAtlasWorkTab.Create('C:\A.pas', 1, 1), TAtlasWorkTab.Create('C:\B.pas', 2, 1)];
  mState.Active := 1;
  Assert.AreEqual(1, mState.LastIndex);
  mState.Active := 5;
  Assert.AreEqual(0, mState.LastIndex);
end;

procedure TAtlasWelcomeContractTests.EntryKnowsNameAndGroup;
var
  mEntry: TAtlasContinueEntry;
begin
  mEntry := Default(TAtlasContinueEntry);
  mEntry.Project := 'C:\Projekte\Kasse.groupproj';
  Assert.AreEqual('Kasse', mEntry.Name);
  Assert.IsTrue(mEntry.IsGroup);
  mEntry.Project := 'C:\Projekte\Kasse.dproj';
  Assert.IsFalse(mEntry.IsGroup);
end;

procedure TAtlasWelcomeContractTests.RegValuesCompareNameWithoutCase;
var
  mLeft, mRight: TAtlasRegValue;
begin
  mLeft := TAtlasRegValue.Create('Columns', TAtlasRegKind.Number, '2');
  mRight := TAtlasRegValue.Create('COLUMNS', TAtlasRegKind.Number, '2');
  Assert.IsTrue(TAtlasRegValue.Same(mLeft, mRight));
  mRight.Kind := TAtlasRegKind.Text;
  Assert.IsFalse(TAtlasRegValue.Same(mLeft, mRight));
end;

procedure TAtlasWelcomeContractTests.RegValuesCompareLines;
var
  mLeft, mRight: TAtlasRegValue;
begin
  mLeft := TAtlasRegValue.Create('Plugins', TAtlasRegKind.MultiText, '');
  mLeft.Lines := ['a', 'b'];
  mRight := mLeft;
  mRight.Lines := ['a', 'c'];
  Assert.IsFalse(TAtlasRegValue.Same(mLeft, mRight));
  mRight.Lines := ['a', 'b'];
  Assert.IsTrue(TAtlasRegValue.Same(mLeft, mRight));
end;

procedure TAtlasWelcomeContractTests.WorkOrderPutsNewestFirstAndKeepsTies;
var
  mFound: TArray<string>;
  mStateOf: TAtlasWorkStateOf<string>;
begin
  // Name "Zeit:Kennung": Zeit ist der Zeitpunkt des Arbeitsstands.
  mStateOf :=
    function(const AEntry: string): TAtlasWorkState
    begin
      Result := Default(TAtlasWorkState);
      Result.Known := True;
      Result.At := StrToInt(Copy(AEntry, 1, Pos(':', AEntry) - 1));
    end;
  mFound := nil;
  TAtlasWorkOrder.InsertNewestFirst<string>(mFound, '2:a', mStateOf);
  TAtlasWorkOrder.InsertNewestFirst<string>(mFound, '5:b', mStateOf);
  TAtlasWorkOrder.InsertNewestFirst<string>(mFound, '2:c', mStateOf);
  TAtlasWorkOrder.InsertNewestFirst<string>(mFound, '9:d', mStateOf);
  Assert.AreEqual('9:d,5:b,2:a,2:c', string.Join(',', mFound));
  mFound := nil;
  mStateOf := nil;
end;

end.
