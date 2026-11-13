unit Atlas.UI.Debug.MethodBreakpoints.Tests;

// Dialoge „Haltepunkt auf Methoden“ und „Haltepunktgruppen der Methoden“ (#855): Texte der Treffer mit Zeilen ab 1,
// Suche über die übergebene Funktion, Treffer ohne Quelltext grau und nicht gewählt, Auswahl und Gruppe, Fehler
// des Servers in der Hinweiszeile, Gruppenliste mit Aktionen.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings,
  Atlas.Core.Debug.MethodBreakpoints,
  Atlas.UI.Debug.MethodBreakpoints;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasMethodBreakpointsDialogTests = class
  private
    FLanguage: TAtlasLanguage;
    FQueries: Integer;
    FLastQuery: TAtlasMethodQuery;
    function Hits: TAtlasMethodHits;
    function SearchOk: TAtlasMethodSearch;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure HitTextsCountFromOne;
    [Test]
    procedure FooterNamesCountAndTruncation;
    [Test]
    procedure SearchFillsListAndSelection;
    [Test]
    procedure GroupKnowsAllHitsAndOptions;
    [Test]
    procedure SwitchSearchesAgain;
    [Test]
    procedure ServerErrorShowsNote;
    [Test]
    procedure GroupsListAndActions;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Controls;

function NewHit(const AContainer, AName: string; ALine: Integer; AReason: TAtlasMethodHitReason;
  const AVia: string): TAtlasMethodHit;
begin
  Result := Default(TAtlasMethodHit);
  Result.FileName := 'C:\P\Kunden.pas';
  Result.UnitName := 'Kunden';
  Result.Container := AContainer;
  Result.Name := AName;
  Result.Signature := 'procedure ' + AName + ';';
  Result.Line := ALine;
  Result.Reason := AReason;
  Result.Via := AVia;
end;

procedure TAtlasMethodBreakpointsDialogTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
  FQueries := 0;
  FLastQuery := Default(TAtlasMethodQuery);
end;

procedure TAtlasMethodBreakpointsDialogTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
  FLastQuery := Default(TAtlasMethodQuery);
end;

function TAtlasMethodBreakpointsDialogTests.Hits: TAtlasMethodHits;
begin
  Result := [NewHit('TKunde', 'Validiere', 41, TAtlasMethodHitReason.Match, ''),
    NewHit('TSpezial', 'Validiere', 56, TAtlasMethodHitReason.Override_, 'TKunde.Validiere'),
    NewHit('TListe', 'Validiere', -1, TAtlasMethodHitReason.Match, '')];
end;

function TAtlasMethodBreakpointsDialogTests.SearchOk: TAtlasMethodSearch;
begin
  Result :=
    function(const AQuery: TAtlasMethodQuery; out AAnswer: TAtlasMethodAnswer; out AError: string): Boolean
    begin
      Inc(FQueries);
      FLastQuery := AQuery;
      AAnswer := Default(TAtlasMethodAnswer);
      AAnswer.Hits := Hits;
      AError := '';
      Result := True;
    end;
end;

procedure TAtlasMethodBreakpointsDialogTests.HitTextsCountFromOne;
var
  mHits: TAtlasMethodHits;
begin
  mHits := Hits;
  Assert.AreEqual('Kunden.pas:42  TKunde.Validiere', TAtlasMethodBreakpointTexts.HitText(mHits[0]));
  Assert.AreEqual('Kunden.pas:57  TSpezial.Validiere  ·  überschreibt TKunde.Validiere',
    TAtlasMethodBreakpointTexts.HitText(mHits[1]));
  Assert.AreEqual('Kunden.pas  TListe.Validiere  ·  ohne Quelltext', TAtlasMethodBreakpointTexts.HitText(mHits[2]));
  mHits[2].Reason := TAtlasMethodHitReason.Implementation_;
  mHits[2].Via := 'IAuftrag.Pruefe';
  Assert.AreEqual('Kunden.pas  TListe.Validiere  ·  setzt IAuftrag.Pruefe um, ohne Quelltext',
    TAtlasMethodBreakpointTexts.HitText(mHits[2]));
end;

procedure TAtlasMethodBreakpointsDialogTests.FooterNamesCountAndTruncation;
var
  mAnswer: TAtlasMethodAnswer;
begin
  mAnswer := Default(TAtlasMethodAnswer);
  mAnswer.Hits := Hits;
  Assert.AreEqual('3 Treffer, 2 gewählt', TAtlasMethodBreakpointTexts.FooterText(mAnswer, 2));
  mAnswer.Truncated := True;
  Assert.AreEqual('Mehr als 3 Treffer, Muster enger fassen; 2 gewählt',
    TAtlasMethodBreakpointTexts.FooterText(mAnswer, 2));
end;

procedure TAtlasMethodBreakpointsDialogTests.SearchFillsListAndSelection;
var
  mGroup: TAtlasMethodGroup;
  mDialog: TAtlasMethodBreakpointsDialog;
begin
  mGroup := Default(TAtlasMethodGroup);
  mGroup.Pattern := '*.Validiere';
  mGroup.Overrides := True;
  mGroup.Overloads := True;
  mDialog := TAtlasMethodBreakpointsDialog.CreateDialog(nil, mGroup, SearchOk);
  try
    mDialog.HandleNeeded;
    mDialog.HitList.HandleNeeded;
    Assert.IsFalse(mDialog.SetButton.Enabled, 'vor der Suche');
    mDialog.RunSearch;
    Assert.AreEqual(1, FQueries);
    Assert.AreEqual('*.Validiere', FLastQuery.Pattern);
    Assert.AreEqual(3, mDialog.HitList.Items.Count);
    Assert.IsTrue(mDialog.HitList.Checked[0]);
    Assert.IsTrue(mDialog.HitList.Checked[1]);
    // Ohne Quelltext: grau und nicht gewählt.
    Assert.IsFalse(mDialog.HitList.Checked[2]);
    Assert.IsFalse(mDialog.HitList.ItemEnabled[2]);
    Assert.AreEqual(2, Integer(Length(mDialog.Selected)));
    Assert.AreEqual('Setzen (2)', mDialog.SetButton.Caption);
    Assert.AreEqual('3 Treffer, 2 gewählt', mDialog.Note.Caption);
    mDialog.HitList.Checked[1] := False;
    Assert.AreEqual(1, Integer(Length(mDialog.Selected)));
    Assert.AreEqual('TKunde.Validiere', mDialog.Selected[0].DisplayName);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasMethodBreakpointsDialogTests.GroupKnowsAllHitsAndOptions;
var
  mGroup: TAtlasMethodGroup;
  mDialog: TAtlasMethodBreakpointsDialog;
begin
  mGroup := Default(TAtlasMethodGroup);
  mGroup.Pattern := 'TKunde.*';
  mDialog := TAtlasMethodBreakpointsDialog.CreateDialog(nil, mGroup, SearchOk);
  try
    mDialog.HandleNeeded;
    mDialog.HitList.HandleNeeded;
    mDialog.PatternEdit.Text := '  *.Validiere  ';
    mDialog.GrowBox.Checked := True;
    mDialog.LogOnlyBox.Checked := True;
    mDialog.ConditionEdit.Text := 'Betrag > 0';
    mDialog.RunSearch;
    mDialog.HitList.Checked[1] := False;
    mGroup := mDialog.Group;
    Assert.AreEqual('*.Validiere', mGroup.Pattern);
    Assert.IsTrue(mGroup.Grow);
    Assert.IsTrue(mGroup.LogOnly);
    Assert.AreEqual('Betrag > 0', mGroup.Condition);
    // Auch abgewählte und Treffer ohne Quelltext gelten als gesehen.
    Assert.AreEqual(3, Integer(Length(mGroup.Known)));
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasMethodBreakpointsDialogTests.SwitchSearchesAgain;
var
  mGroup: TAtlasMethodGroup;
  mDialog: TAtlasMethodBreakpointsDialog;
begin
  mGroup := Default(TAtlasMethodGroup);
  mGroup.Pattern := 'TKunde.*';
  mGroup.Overrides := True;
  mDialog := TAtlasMethodBreakpointsDialog.CreateDialog(nil, mGroup, SearchOk);
  try
    mDialog.HandleNeeded;
    mDialog.HitList.HandleNeeded;
    // Vor der ersten Suche fragt ein Schalter nicht.
    mDialog.OverloadsBox.Checked := True;
    Assert.AreEqual(0, FQueries);
    mDialog.RunSearch;
    mDialog.OverridesBox.Checked := False;
    Assert.AreEqual(2, FQueries);
    Assert.IsFalse(FLastQuery.Overrides);
    Assert.IsTrue(FLastQuery.Overloads);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasMethodBreakpointsDialogTests.ServerErrorShowsNote;
var
  mGroup: TAtlasMethodGroup;
  mDialog: TAtlasMethodBreakpointsDialog;
begin
  mGroup := Default(TAtlasMethodGroup);
  mGroup.Pattern := 'a..b';
  mDialog := TAtlasMethodBreakpointsDialog.CreateDialog(nil, mGroup,
    function(const AQuery: TAtlasMethodQuery; out AAnswer: TAtlasMethodAnswer; out AError: string): Boolean
    begin
      AAnswer := Default(TAtlasMethodAnswer);
      AAnswer.Error := 'Ungültiges Muster: a..b';
      AError := '';
      Result := True;
    end);
  try
    mDialog.HandleNeeded;
    mDialog.HitList.HandleNeeded;
    mDialog.RunSearch;
    Assert.AreEqual('Ungültiges Muster: a..b', mDialog.Note.Caption);
    Assert.AreEqual(0, mDialog.HitList.Items.Count);
    Assert.IsFalse(mDialog.SetButton.Enabled);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasMethodBreakpointsDialogTests.GroupsListAndActions;
var
  mStates: TAtlasMethodGroupStates;
  mDialog: TAtlasMethodGroupsDialog;
  mToggled: string;
begin
  SetLength(mStates, 2);
  mStates[0] := Default(TAtlasMethodGroupState);
  mStates[0].Group.Pattern := 'TKunde.*';
  mStates[0].Breakpoints := 4;
  mStates[0].Enabled := 3;
  mStates[1] := Default(TAtlasMethodGroupState);
  mStates[1].Group.Pattern := '*.Validiere*';
  mStates[1].Group.Grow := True;
  mStates[1].Breakpoints := 2;
  Assert.AreEqual('TKunde.*  ·  4 Haltepunkte, 3 aktiv', TAtlasMethodGroupsDialog.StateText(mStates[0]));
  Assert.AreEqual('*.Validiere*  ·  2 Haltepunkte, 0 aktiv  ·  wächst mit',
    TAtlasMethodGroupsDialog.StateText(mStates[1]));
  mToggled := '';
  mDialog := TAtlasMethodGroupsDialog.CreateDialog(nil,
    function: TAtlasMethodGroupStates
    begin
      Result := mStates;
    end,
    procedure(const AGroup: TAtlasMethodGroup)
    begin
      mToggled := AGroup.Pattern;
    end,
    procedure(const AGroup: TAtlasMethodGroup)
    begin
      SetLength(mStates, 0);
    end);
  try
    mDialog.HandleNeeded;
    mDialog.GroupList.HandleNeeded;
    mDialog.Refill;
    Assert.AreEqual(2, mDialog.GroupList.Items.Count);
    mDialog.GroupList.ItemIndex := 1;
    mDialog.ToggleButton.Click;
    Assert.AreEqual('*.Validiere*', mToggled);
    mDialog.RemoveButton.Click;
    // Ohne Gruppen: ein Hinweis, die Knöpfe sind aus.
    Assert.AreEqual(1, mDialog.GroupList.Items.Count);
    Assert.IsFalse(mDialog.RemoveButton.Enabled);
  finally
    mDialog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasMethodBreakpointsDialogTests);

end.
