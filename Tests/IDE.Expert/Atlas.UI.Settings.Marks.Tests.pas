unit Atlas.UI.Settings.Marks.Tests;

// Tests für die Abfragen der Bindungen zwischen Einstellungsnamen und Steuerelementen (#2372):
// Verzeichnisse je Name und Element, Stand der Lage während Filter und Sperren.

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Abfragen der Bindungen über Verzeichnisse und einen Stand der Lage (#2372).</summary>
  [TestFixture]
  TAtlasSettingsBindingQueryTests = class
  public
    /// <summary>Zwischen BeginQueries und EndQueries dieselben Antworten wie ohne Stand.</summary>
    [Test]
    procedure SnapshotAnswersLikeWalk;
    /// <summary>Erste Bindung je Name und je Element gewinnt, ohne Groß-/Kleinschreibung.</summary>
    [Test]
    procedure FirstBindingWins;
    /// <summary>Eine neue Bindung während des Stands ist darin sichtbar.</summary>
    [Test]
    procedure BindDuringQueriesRebuilds;
    /// <summary>Module der Abschnittszeilen: mit Stand dieselben Antworten, neue Zeilen sofort sichtbar.</summary>
    [Test]
    procedure SectionOwnersAnswerLikeWalk;
    [Test]
    [Category('Benchmark')]
    procedure ManyRowsQuickly;
  end;

implementation

uses
  Atlas.UI.Settings.Marks,
  Atlas.UI.Settings.Page.Host,
  System.Classes,
  System.Diagnostics,
  System.SysUtils,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.StdCtrls;

{ TAtlasSettingsBindingQueryTests }

/// <summary>Reiter mit ARows Zeilen; je Zeile Beschriftung und Kontrollkästchen, gebunden an „Name“ mit der
/// Zeilennummer und jede dritte zusätzlich an „Gemeinsam“.</summary>
function BuildRows(AOwner: TComponent; AMarks: TAtlasSettingsMarks; ARows: Integer): TPanel;
var
  mIndex: Integer;
  mRow: TPanel;
  mLabel: TLabel;
  mCheck: TCheckBox;
begin
  Result := TPanel.Create(AOwner);
  for mIndex := 0 to ARows - 1 do
  begin
    mRow := TPanel.Create(AOwner);
    mRow.Parent := Result;
    mLabel := TLabel.Create(AOwner);
    mLabel.Parent := mRow;
    mLabel.Caption := 'Zeile ' + IntToStr(mIndex);
    mCheck := TCheckBox.Create(AOwner);
    mCheck.Parent := mRow;
    mCheck.Caption := 'Schalter ' + IntToStr(mIndex);
    if mIndex mod 3 = 0 then
    begin
      AMarks.Bind(mCheck, ['Name' + IntToStr(mIndex), 'Gemeinsam']);
    end
    else
    begin
      AMarks.Bind(mCheck, ['Name' + IntToStr(mIndex)]);
    end;
  end;
end;

/// <summary>Alle Antworten der Lage zu AControl und seinen Kindern als Text.</summary>
function Answers(AMarks: TAtlasSettingsMarks; AControl: TControl): string;
var
  mIndex: Integer;
begin
  Result := '[' + string.Join(',', AMarks.NamesOf(AControl)) + '|' +
    string.Join(',', AMarks.NamesWithin(AControl));
  if AControl is TWinControl then
  begin
    Result := Result + '|' + string.Join(',', AMarks.NamesIn(TWinControl(AControl)));
    for mIndex := 0 to TWinControl(AControl).ControlCount - 1 do
    begin
      Result := Result + sLineBreak + Answers(AMarks, TWinControl(AControl).Controls[mIndex]);
    end;
  end;
end;

procedure TAtlasSettingsBindingQueryTests.SnapshotAnswersLikeWalk;
var
  mOwner: TComponent;
  mMarks: TAtlasSettingsMarks;
  mSheet: TPanel;
  mWalk: string;
begin
  mOwner := TComponent.Create(nil);
  try
    mMarks := TAtlasSettingsMarks.Create(mOwner);
    mSheet := BuildRows(mOwner, mMarks, 12);
    mWalk := Answers(mMarks, mSheet);
    Assert.Contains(mWalk, 'Name3,Gemeinsam');
    mMarks.BeginQueries;
    try
      Assert.AreEqual(mWalk, Answers(mMarks, mSheet));
      // Verschachtelt: der Stand bleibt bis zum äußeren Ende.
      mMarks.BeginQueries;
      mMarks.EndQueries;
      Assert.AreEqual(mWalk, Answers(mMarks, mSheet));
    finally
      mMarks.EndQueries;
    end;
    Assert.AreEqual(mWalk, Answers(mMarks, mSheet));
  finally
    mOwner.Free;
  end;
end;

procedure TAtlasSettingsBindingQueryTests.FirstBindingWins;
var
  mOwner: TComponent;
  mMarks: TAtlasSettingsMarks;
  mSheet: TPanel;
begin
  mOwner := TComponent.Create(nil);
  try
    mMarks := TAtlasSettingsMarks.Create(mOwner);
    mSheet := BuildRows(mOwner, mMarks, 6);
    // „Gemeinsam“ tragen Zeile 0 und 3: die erste.
    Assert.AreSame(TWinControl(mSheet.Controls[0]).Controls[1], mMarks.ControlOfName('GEMEINSAM'));
    Assert.AreEqual('Schalter 4', mMarks.TextOfName('name4'));
    Assert.IsNull(mMarks.ControlOfName('Fehlt'));
    Assert.AreEqual('', mMarks.TextOfName('Fehlt'));
    Assert.AreEqual('Name2', string.Join(',', mMarks.NamesOf(TWinControl(mSheet.Controls[2]).Controls[1])));
  finally
    mOwner.Free;
  end;
end;

procedure TAtlasSettingsBindingQueryTests.BindDuringQueriesRebuilds;
var
  mOwner: TComponent;
  mMarks: TAtlasSettingsMarks;
  mSheet: TPanel;
  mCheck: TCheckBox;
begin
  mOwner := TComponent.Create(nil);
  try
    mMarks := TAtlasSettingsMarks.Create(mOwner);
    mSheet := BuildRows(mOwner, mMarks, 3);
    mMarks.BeginQueries;
    try
      Assert.AreEqual(4, Integer(Length(mMarks.NamesIn(mSheet))));
      mCheck := TCheckBox.Create(mOwner);
      mCheck.Parent := mSheet;
      mMarks.Bind(mCheck, ['Neu']);
      Assert.AreEqual(5, Integer(Length(mMarks.NamesIn(mSheet))));
      Assert.AreEqual('Neu', string.Join(',', mMarks.NamesWithin(mCheck)));
    finally
      mMarks.EndQueries;
    end;
  finally
    mOwner.Free;
  end;
end;

/// <summary>Module aller Elemente von AControl abwärts als Text.</summary>
function OwnerAnswers(AOwners: TAtlasSettingsSectionOwners; AControl: TControl): string;
var
  mIndex: Integer;
begin
  Result := '[' + string.Join(',', AOwners.OwnersIn(AControl)) + ']';
  if AControl is TWinControl then
  begin
    for mIndex := 0 to TWinControl(AControl).ControlCount - 1 do
    begin
      Result := Result + OwnerAnswers(AOwners, TWinControl(AControl).Controls[mIndex]);
    end;
  end;
end;

procedure TAtlasSettingsBindingQueryTests.SectionOwnersAnswerLikeWalk;
var
  mOwner: TComponent;
  mMarks: TAtlasSettingsMarks;
  mOwners: TAtlasSettingsSectionOwners;
  mSheet: TPanel;
  mWalk: string;
begin
  mOwner := TComponent.Create(nil);
  mOwners := nil;
  try
    mMarks := TAtlasSettingsMarks.Create(mOwner);
    mOwners := TAtlasSettingsSectionOwners.Create(mMarks);
    mSheet := BuildRows(mOwner, mMarks, 6);
    mOwners.Mark(mSheet.Controls[1], 'Modul.A');
    mOwners.Mark(TWinControl(mSheet.Controls[4]).Controls[1], 'Modul.B');
    mWalk := OwnerAnswers(mOwners, mSheet);
    Assert.AreEqual(2, Integer(Length(mOwners.OwnersIn(mSheet))));
    Assert.AreEqual(0, Integer(Length(mOwners.OwnersIn(nil))));
    mOwners.BeginQueries;
    try
      Assert.AreEqual(mWalk, OwnerAnswers(mOwners, mSheet));
      mOwners.Mark(mSheet.Controls[0], 'Modul.C');
      Assert.AreEqual('Modul.C', string.Join(',', mOwners.OwnersIn(mSheet.Controls[0])));
      mOwners.Remove(mSheet.Controls[1]);
      Assert.AreEqual(0, Integer(Length(mOwners.OwnersIn(mSheet.Controls[1]))));
    finally
      mOwners.EndQueries;
    end;
    Assert.AreEqual(2, Integer(Length(mOwners.OwnersIn(mSheet))));
  finally
    mOwners.Free;
    mOwner.Free;
  end;
end;

procedure TAtlasSettingsBindingQueryTests.ManyRowsQuickly;
var
  mOwner: TComponent;
  mMarks: TAtlasSettingsMarks;
  mSheet: TPanel;
  mIndex, mFound: Integer;
  mWatch: TStopwatch;
begin
  // So viele Zeilen wie Einstellungen auf der Seite: Sperren fragen jede Zeile nach den Namen darin.
  mOwner := TComponent.Create(nil);
  try
    mMarks := TAtlasSettingsMarks.Create(mOwner);
    mSheet := BuildRows(mOwner, mMarks, 900);
    mFound := 0;
    mWatch := TStopwatch.StartNew;
    mMarks.BeginQueries;
    try
      for mIndex := 0 to mSheet.ControlCount - 1 do
      begin
        Inc(mFound, Length(mMarks.NamesWithin(mSheet.Controls[mIndex])));
        if mMarks.ControlOfName('Name' + IntToStr(mIndex)) <> nil then
        begin
          Inc(mFound);
        end;
      end;
    finally
      mMarks.EndQueries;
    end;
    mWatch.Stop;
    Assert.AreEqual(900 + 300 + 900, mFound);
    Assert.IsTrue(mWatch.ElapsedMilliseconds < 100, 'Dauer ' + IntToStr(mWatch.ElapsedMilliseconds) + ' ms');
  finally
    mOwner.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsBindingQueryTests);

end.
