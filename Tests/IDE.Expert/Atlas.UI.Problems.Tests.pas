unit Atlas.UI.Problems.Tests;

// Fenster „Atlas-Prüfung“ (#909), Oberfläche: Spalten, Gruppenzeilen mit
// Anzahl, Umschalter je Art mit Zählern, Textfilter, Enter springt, Alt+Enter
// korrigiert, Kontextmenü (Compilermeldungen ohne Regelaktionen), Spalten
// aus- und einblenden, Live/Angehalten und der Dialog „Regel erklären“.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  TAtlasProblemsFrameTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ShowsColumnsGroupsAndCounts;
    [Test]
    procedure KindToggleAndTextFilterNarrowTheList;
    [Test]
    procedure KeysOpenAndFix;
    [Test]
    procedure MenuOffersRuleActionsOnlyForRules;
    /// <summary>#1352: „Alle sicheren Treffer von … korrigieren …“ nur mit fix.bulk, nur für Regeln.</summary>
    [Test]
    procedure MenuFixAllFollowsSettingAndRule;
    [Test]
    procedure ColumnsCanBeHiddenAndAreRemembered;
    [Test]
    procedure LiveAndPausedAndStatus;
    [Test]
    procedure ExplainDialogShowsExamples;
    /// <summary>#54: Compilermeldung mit Ursache und DocWiki-Knopf.</summary>
    [Test]
    procedure ExplainDialogShowsMessageCause;
    /// <summary>#1108: aktive Unit angepinnt, Trennzeile, nicht geöffnete ausgegraut, ↓ springt über die
    /// Trennzeile, Knopf „Offene zuerst“.</summary>
    [Test]
    procedure OpenFirstPinsDimsAndSkipsSections;
    /// <summary>Neue Markierung beim Auffüllen holt nicht jede Zeile über OnData (IDE hing bei vielen Befunden
    /// in TCustomListView.ClearSelection).</summary>
    [Test]
    procedure RefillReselectsWithoutFetchingEveryRow;
    /// <summary>#1843: Einzelprojekte der Gruppe unter einem Trennstrich, der Trennstrich lässt sich nicht wählen,
    /// ein fehlendes Projekt fällt auf das aktive zurück, Schalter aus = nur feste Einträge.</summary>
    [Test]
    procedure ScopeListOffersGroupProjects;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Winapi.Windows,
  Vcl.Forms,
  Vcl.Menus,
  Vcl.ComCtrls,
  Vcl.Buttons,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Findings,
  Atlas.Core.Problems.ScopeProjects,
  Atlas.Core.Settings.ProblemsUpdate,
  Atlas.UI.Problems.ScopeBox,
  Atlas.UI.Problems.Frame,
  Atlas.UI.Problems.Explain;

type
  /// <summary>Zählt die Abrufe der virtuellen Liste und reicht sie weiter.</summary>
  TFetchCounter = class
  public
    Inner: TLVOwnerDataEvent;
    Count: Integer;
    procedure Fetch(Sender: TObject; Item: TListItem);
  end;

procedure TFetchCounter.Fetch(Sender: TObject; Item: TListItem);
begin
  Inc(Count);
  if Assigned(Inner) then
  begin
    Inner(Sender, Item);
  end;
end;

function Problem(ALine: Integer; const ASource, ACode, AMessage: string; ASeverity: TAtlasProblemSeverity;
  const AFix: string): TAtlasProblem;
begin
  Result := Default(TAtlasProblem);
  Result.StartLine := ALine;
  Result.StartCharacter := 2;
  Result.EndLine := ALine;
  Result.EndCharacter := 6;
  Result.Source := ASource;
  Result.Code := ACode;
  Result.Message := AMessage;
  Result.Severity := ASeverity;
  Result.Category := 'bug';
  Result.FixTitle := AFix;
end;

function Sample: TArray<TAtlasFinding>;
begin
  Result := TAtlasFindings.FromProblems('C:\P\Kunde.pas', [
    Problem(3, 'Atlas', 'empty-except', 'Leerer except-Block', TAtlasProblemSeverity.Warning, 'raise ergänzen'),
    Problem(5, 'Atlas', 'syntax', 'Es fehlt ;', TAtlasProblemSeverity.Error, '')],
    ['', '', '', '  except end;', '', '  X := 1']) +
    TAtlasFindings.FromProblems('C:\P\Lager.pas', [
    Problem(0, 'dcc', 'W1036', 'Variable nicht initialisiert', TAtlasProblemSeverity.Warning, '')], nil);
end;

function NewFrame(AHost: TForm): TAtlasProblemsFrame;
begin
  Result := TAtlasProblemsFrame.Create(AHost);
  Result.Parent := AHost;
  Result.ApplySettings(TAtlasFindingScope.Group, TAtlasFindingGrouping.ByFile, '', True);
  Result.SetFindings(Sample, 'C:\P\Kunde.pas', nil);
end;

/// <summary>True, wenn AFrame einen Knopf mit der Beschriftung ACaption besitzt.</summary>
function HasButton(AFrame: TAtlasProblemsFrame; const ACaption: string): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 0 to AFrame.ComponentCount - 1 do
  begin
    if (AFrame.Components[mIndex] is TSpeedButton) and
      SameStr(TSpeedButton(AFrame.Components[mIndex]).Caption, ACaption) then
    begin
      Exit(True);
    end;
  end;
end;

{ TAtlasProblemsFrameTests }

procedure TAtlasProblemsFrameTests.WarmUpFirstUse;
begin
  Setup;
  try
    ShowsColumnsGroupsAndCounts;
  finally
    TearDown;
  end;
end;

procedure TAtlasProblemsFrameTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasProblemsFrameTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasProblemsFrameTests.ShowsColumnsGroupsAndCounts;
var
  mHost: TForm;
  mFrame: TAtlasProblemsFrame;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := NewFrame(mHost);
    // Icon, Art, Kategorie, Meldung, Zeile, Stelle, Regel, Compiler (#1024).
    Assert.AreEqual(8, Integer(mFrame.List.Columns.Count));
    Assert.AreEqual('Art', mFrame.List.Columns[1].Caption);
    Assert.AreEqual('Regel', mFrame.List.Columns[6].Caption);
    Assert.AreEqual('Compiler', mFrame.List.Columns[7].Caption);
    // problems.showCompilerCode aus: ohne Spalte Compiler, Layout bleibt gemerkt.
    mFrame.ShowCompilerCode := False;
    Assert.AreEqual(7, Integer(mFrame.List.Columns.Count));
    Assert.Contains(mFrame.ColumnsText, 'compiler');
    mFrame.ShowCompilerCode := True;
    Assert.AreEqual(8, Integer(mFrame.List.Columns.Count));
    // Nach Datei: Kunde.pas (2), dann ihre Befunde, dann Lager.pas (1) und sein Befund.
    Assert.AreEqual(5, Integer(mFrame.List.Items.Count));
    Assert.AreEqual(#$25BE' Kunde.pas (2)', mFrame.List.Items[0].SubItems[0]);
    Assert.AreEqual(-1, mFrame.List.Items[0].ImageIndex, 'Gruppenzeile ohne Icon');
    // Fehler vor Warnungen.
    Assert.AreEqual('Error', mFrame.List.Items[1].SubItems[0]);
    Assert.AreEqual(0, mFrame.List.Items[1].ImageIndex);
    Assert.AreEqual('Bug', mFrame.List.Items[1].SubItems[1]);
    Assert.AreEqual('X := 1', mFrame.List.Items[1].SubItems[3]);
    Assert.AreEqual('Kunde.pas:6:3', mFrame.List.Items[1].SubItems[4]);
    Assert.AreEqual('syntax', mFrame.List.Items[1].SubItems[5]);
    Assert.AreEqual('Warnung', mFrame.List.Items[2].SubItems[0]);
    Assert.AreEqual(1, mFrame.List.Items[2].ImageIndex);
    Assert.AreEqual('Compiler', mFrame.List.Items[4].SubItems[1]);
    // Gruppe zuklappen per Klick bzw. Leertaste: Zeilen bleiben gezählt.
    mFrame.View.Toggle(0);
    mFrame.Refill;
    Assert.AreEqual(3, Integer(mFrame.List.Items.Count));
    Assert.AreEqual(#$25B8' Kunde.pas (2)', mFrame.List.Items[0].SubItems[0]);
    Assert.IsFalse(mFrame.EmptyLabel.Visible);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasProblemsFrameTests.KindToggleAndTextFilterNarrowTheList;
var
  mHost: TForm;
  mFrame: TAtlasProblemsFrame;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := NewFrame(mHost);
    mFrame.GroupingBox.ItemIndex := Ord(TAtlasFindingGrouping.None);
    mFrame.GroupingBox.OnChange(mFrame.GroupingBox);
    Assert.AreEqual(3, Integer(mFrame.List.Items.Count));
    Assert.AreEqual('Error 1', mFrame.KindButton(TAtlasFindingKind.Error).Caption);
    Assert.AreEqual('Warnung 2', mFrame.KindButton(TAtlasFindingKind.Warning).Caption);
    Assert.AreEqual('Info 0', mFrame.KindButton(TAtlasFindingKind.Info).Caption);
    // Warnungen aus: nur der Fehler bleibt, die Zähler auf den Umschaltern bleiben.
    mFrame.KindButton(TAtlasFindingKind.Warning).Down := False;
    mFrame.KindButton(TAtlasFindingKind.Warning).OnClick(mFrame.KindButton(TAtlasFindingKind.Warning));
    Assert.AreEqual(1, Integer(mFrame.List.Items.Count));
    Assert.AreEqual('Warnung 2', mFrame.KindButton(TAtlasFindingKind.Warning).Caption);
    mFrame.KindButton(TAtlasFindingKind.Warning).Down := True;
    mFrame.KindButton(TAtlasFindingKind.Warning).OnClick(mFrame.KindButton(TAtlasFindingKind.Warning));
    // Kategorie „Compiler“.
    mFrame.CategoryBox.ItemIndex := 1 + Ord(TAtlasFindingCategory.Compiler);
    mFrame.CategoryBox.OnChange(mFrame.CategoryBox);
    Assert.AreEqual(1, Integer(mFrame.List.Items.Count));
    mFrame.CategoryBox.ItemIndex := 0;
    mFrame.CategoryBox.OnChange(mFrame.CategoryBox);
    mFrame.FilterEdit.Text := 'except';
    Assert.AreEqual(1, Integer(mFrame.List.Items.Count), 'Textfilter über Meldung, Regel und Datei');
    mFrame.FilterEdit.Text := 'lager';
    Assert.AreEqual(1, Integer(mFrame.List.Items.Count));
    Assert.AreEqual('W1036', mFrame.List.Items[0].SubItems[5]);
    mFrame.FilterEdit.Text := 'gibtsnicht';
    Assert.AreEqual(0, Integer(mFrame.List.Items.Count));
    Assert.IsTrue(mFrame.EmptyLabel.Visible);
    mFrame.FilterEdit.Text := '';
    Assert.AreEqual(3, Integer(mFrame.List.Items.Count));
  finally
    mHost.Free;
  end;
end;

procedure TAtlasProblemsFrameTests.OpenFirstPinsDimsAndSkipsSections;
var
  mHost: TForm;
  mFrame: TAtlasProblemsFrame;
  mKey: Word;
  mSaved: Boolean;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := NewFrame(mHost);
    mFrame.ApplyTierSettings(True, TAtlasClosedUnits.Dimmed, True);
    Assert.IsTrue(mFrame.OpenFirst);
    Assert.IsTrue(mFrame.OpenFirstButton.Down);
    mFrame.SetOpenFiles('C:\P\Lager.pas', ['C:\P\Lager.pas'], True);
    Assert.AreEqual(6, Integer(mFrame.List.Items.Count));
    Assert.AreEqual(#$25BE' '#$D83D#$DCCC' Lager.pas (1) '#$00B7' aktiver Editor', mFrame.List.Items[0].SubItems[0]);
    Assert.AreEqual(1, mFrame.List.Items[1].ImageIndex, 'aktive Unit mit normalem Symbol');
    Assert.AreEqual('Nicht geöffnet '#$00B7' 1 Units '#$00B7' 2 Befunde', mFrame.List.Items[2].SubItems[0]);
    Assert.AreEqual(-1, mFrame.List.Items[2].ImageIndex, 'Trennzeile ohne Symbol');
    Assert.AreEqual(#$25BE' Kunde.pas (2) '#$00B7' nicht geöffnet', mFrame.List.Items[3].SubItems[0]);
    Assert.AreEqual(3, mFrame.List.Items[4].ImageIndex, 'ausgegrautes Fehlersymbol');
    // ↓ von der letzten Zeile der aktiven Unit springt über die Trennzeile.
    mFrame.List.ItemIndex := 1;
    mFrame.View.Select(1);
    mKey := VK_DOWN;
    mFrame.List.OnKeyDown(mFrame.List, mKey, []);
    Assert.AreEqual(0, Integer(mKey));
    Assert.AreEqual(3, mFrame.List.ItemIndex);
    // Knopf aus: wie #909, und die Einstellung wird gespeichert.
    mSaved := False;
    mFrame.OnLayout :=
      procedure
      begin
        mSaved := True;
      end;
    mFrame.OpenFirstButton.Down := False;
    mFrame.OpenFirstButton.OnClick(mFrame.OpenFirstButton);
    Assert.IsTrue(mSaved);
    Assert.IsFalse(mFrame.OpenFirst);
    Assert.AreEqual(5, Integer(mFrame.List.Items.Count));
    Assert.AreEqual(#$25BE' Kunde.pas (2)', mFrame.List.Items[0].SubItems[0]);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasProblemsFrameTests.RefillReselectsWithoutFetchingEveryRow;
var
  mHost: TForm;
  mFrame: TAtlasProblemsFrame;
  mCounter: TFetchCounter;
  mProblems: TArray<TAtlasProblem>;
  mIndex: Integer;
begin
  SetLength(mProblems, 300);
  for mIndex := 0 to High(mProblems) do
  begin
    mProblems[mIndex] := Problem(mIndex, 'Atlas', 'empty-except', 'Leerer except-Block', TAtlasProblemSeverity.Warning,
      '');
  end;
  mHost := TForm.CreateNew(nil);
  mCounter := TFetchCounter.Create;
  try
    mFrame := NewFrame(mHost);
    mFrame.SetFindings(TAtlasFindings.FromProblems('C:\P\Kunde.pas', mProblems, nil), 'C:\P\Kunde.pas', nil);
    // Zwei Zeilen markiert, dann wählt die Sicht eine dritte.
    mFrame.List.ItemIndex := 1;
    mFrame.List.ItemIndex := 2; // lsp-ignore: duplicate-assignment -- markiert eine zweite Zeile (Mehrfachauswahl)
    Assert.AreEqual(2, Integer(mFrame.List.SelCount));
    mCounter.Inner := mFrame.List.OnData;
    mFrame.List.OnData := mCounter.Fetch;
    try
      mFrame.View.Select(4);
      mFrame.Refill;
    finally
      mFrame.List.OnData := mCounter.Inner;
    end;
    Assert.AreEqual(1, Integer(mFrame.List.SelCount));
    Assert.AreEqual(4, mFrame.List.ItemIndex);
    // Mit ClearSelection holte das jede der 301 Zeilen mindestens einmal.
    Assert.IsTrue(mCounter.Count < 30, Format('%d Abrufe für %d Zeilen', [mCounter.Count, mFrame.List.Items.Count]));
  finally
    mHost.Free;
    mCounter.Free;
  end;
end;

procedure TAtlasProblemsFrameTests.KeysOpenAndFix;
var
  mHost: TForm;
  mFrame: TAtlasProblemsFrame;
  mOpened, mFixed: string;
  mKey: Word;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := NewFrame(mHost);
    mFrame.OnOpen :=
      procedure(const AFinding: TAtlasFinding)
      begin
        mOpened := AFinding.Location;
      end;
    mFrame.OnFix :=
      procedure(const AFinding: TAtlasFinding)
      begin
        mFixed := AFinding.Problem.FixTitle;
      end;
    mFrame.List.ItemIndex := 2;
    mFrame.View.Select(2);
    mKey := VK_RETURN;
    mFrame.List.OnKeyDown(mFrame.List, mKey, []);
    Assert.AreEqual('Kunde.pas:4:3', mOpened);
    mKey := VK_RETURN;
    mFrame.List.OnKeyDown(mFrame.List, mKey, [ssAlt]);
    Assert.AreEqual('raise ergänzen', mFixed);
    // Enter auf einer Gruppe klappt sie nur.
    mOpened := '';
    mFrame.List.ItemIndex := 0;
    mKey := VK_RETURN;
    mFrame.List.OnKeyDown(mFrame.List, mKey, []);
    Assert.AreEqual('', mOpened);
    Assert.AreEqual(3, Integer(mFrame.List.Items.Count));
  finally
    mHost.Free;
  end;
end;

procedure TAtlasProblemsFrameTests.MenuOffersRuleActionsOnlyForRules;
var
  mHost: TForm;
  mFrame: TAtlasProblemsFrame;

  function Item(const ACaption: string): TMenuItem;
  var
    mIndex: Integer;
  begin
    Result := nil;
    for mIndex := 0 to mFrame.Menu.Items.Count - 1 do
    begin
      if StripHotkey(mFrame.Menu.Items[mIndex].Caption).StartsWith(ACaption) then
      begin
        Exit(mFrame.Menu.Items[mIndex]);
      end;
    end;
  end;

begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := NewFrame(mHost);
    mFrame.List.ItemIndex := 2;
    mFrame.Menu.OnPopup(mFrame.Menu);
    Assert.IsNotNull(Item('Schnellkorrektur: raise ergänzen'));
    Assert.IsTrue(Item('Schnellkorrektur').Enabled);
    Assert.IsTrue(Item('Für diese Zeile unterdrücken').Enabled);
    Assert.IsTrue(Item('Regel einstellen').Enabled);
    Assert.IsTrue(Item('Regel abschalten').Enabled);
    Assert.IsTrue(Item('Regel erklären').Enabled);
    // Compilermeldung: kein Unterdrücken, Einstellen, Abschalten oder Erklären.
    // Mehrfachauswahl: ItemIndex fügt nur hinzu, die erste markierte Zeile zählt.
    mFrame.List.ClearSelection;
    mFrame.List.ItemIndex := 4;
    mFrame.Menu.OnPopup(mFrame.Menu);
    Assert.IsFalse(Item('Schnellkorrektur').Enabled, 'Schnellkorrektur');
    Assert.IsFalse(Item('Für diese Zeile unterdrücken').Enabled, 'Unterdrücken');
    Assert.IsFalse(Item('Regel abschalten').Enabled, 'Abschalten');
    Assert.IsTrue(Item('Gehe zu').Enabled, 'Gehe zu');
  finally
    mHost.Free;
  end;
end;

procedure TAtlasProblemsFrameTests.MenuFixAllFollowsSettingAndRule;
var
  mHost: TForm;
  mFrame: TAtlasProblemsFrame;
  mBulk: Boolean;
  mFired: string;

  function Item: TMenuItem;
  var
    mIndex: Integer;
  begin
    Result := nil;
    for mIndex := 0 to mFrame.Menu.Items.Count - 1 do
    begin
      if StripHotkey(mFrame.Menu.Items[mIndex].Caption).StartsWith('Alle sicheren Treffer von') then
      begin
        Exit(mFrame.Menu.Items[mIndex]);
      end;
    end;
  end;

begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := NewFrame(mHost);
    mBulk := False;
    mFired := '';
    mFrame.OnFixAll :=
      procedure(const AFinding: TAtlasFinding)
      begin
        mFired := AFinding.Rule;
      end;
    mFrame.CanFixAll :=
      function: Boolean
      begin
        Result := mBulk;
      end;
    mFrame.List.ItemIndex := 2;
    mFrame.Menu.OnPopup(mFrame.Menu);
    Assert.IsNotNull(Item);
    Assert.IsFalse(Item.Visible, 'fix.bulk aus: kein Eintrag');
    mBulk := True;
    mFrame.Menu.OnPopup(mFrame.Menu);
    Assert.IsTrue(Item.Visible);
    Assert.IsTrue(Item.Enabled);
    Item.Click;
    Assert.AreNotEqual('', mFired);
    Assert.IsTrue(Pos(mFired, StripHotkey(Item.Caption)) > 0, Item.Caption);
    // Compilermeldung: keine Regel, also keine Sammelkorrektur.
    mFrame.List.ClearSelection;
    mFrame.List.ItemIndex := 4;
    mFrame.Menu.OnPopup(mFrame.Menu);
    Assert.IsFalse(Item.Enabled);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasProblemsFrameTests.ColumnsCanBeHiddenAndAreRemembered;
var
  mHost: TForm;
  mFrame: TAtlasProblemsFrame;
  mLayout: Integer;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := NewFrame(mHost);
    mLayout := 0;
    mFrame.OnLayout :=
      procedure
      begin
        Inc(mLayout);
      end;
    mFrame.ApplySettings(TAtlasFindingScope.Group, TAtlasFindingGrouping.None, 'rule,kind:90,-message', False);
    // Pflichtspalten bleiben, Meldung ist aus, Regel steht vorn (Reihenfolge der Anzeige).
    Assert.AreEqual(7, Integer(mFrame.List.Columns.Count));
    Assert.Contains(mFrame.ColumnsText, '-message');
    Assert.Contains(mFrame.ColumnsText, 'kind:90');
    Assert.IsTrue(mFrame.ColumnsText.StartsWith('rule'), mFrame.ColumnsText);
    // Ohne Compilermeldungen.
    Assert.AreEqual(2, Integer(mFrame.List.Items.Count));
    Assert.AreEqual(0, mLayout, 'Übernehmen der Einstellungen meldet nichts');
  finally
    mHost.Free;
  end;
end;

procedure TAtlasProblemsFrameTests.LiveAndPausedAndStatus;
var
  mHost: TForm;
  mFrame: TAtlasProblemsFrame;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := NewFrame(mHost);
    mFrame.SetUpdate(TAtlasProblemsUpdate.Live);
    Assert.AreEqual('● Live', mFrame.LiveLabel.Caption);
    mFrame.SetUpdate(TAtlasProblemsUpdate.Save);
    Assert.AreEqual('Beim Speichern', mFrame.LiveLabel.Caption);
    mFrame.SetUpdate(TAtlasProblemsUpdate.Manual);
    Assert.AreEqual('Manuell', mFrame.LiveLabel.Caption);
    // Die aktuelle Datei prüft die Schaltfläche der Atlas-Statusleiste, das Fenster hat keinen eigenen Knopf.
    Assert.IsFalse(HasButton(mFrame, 'Datei jetzt prüfen'), 'kein Knopf „Datei jetzt prüfen“');
    mFrame.SetStatus('3 Befunde in 2 Dateien');
    Assert.AreEqual('3 Befunde in 2 Dateien', mFrame.StatusLabel.Caption);
    mFrame.SetFindings(nil, '', nil);
    Assert.IsTrue(mFrame.EmptyLabel.Visible);
    Assert.AreEqual('Keine Befunde.', mFrame.EmptyLabel.Caption);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasProblemsFrameTests.ExplainDialogShowsExamples;
var
  mExplanation: TAtlasRuleExplanation;
  mDialog: TAtlasRuleExplainDialog;
begin
  mExplanation := Default(TAtlasRuleExplanation);
  mExplanation.Id := 'empty-except';
  mExplanation.Name := 'Leerer except-Block';
  mExplanation.Description := 'Fehler werden verschluckt.';
  mExplanation.Bad := 'except end;';
  mExplanation.Good := 'except raise; end;';
  mExplanation.Experimental := True;
  mDialog := TAtlasRuleExplainDialog.CreateDialog(nil, mExplanation);
  try
    Assert.AreEqual('Regel empty-except', mDialog.Caption);
    Assert.AreEqual('Leerer except-Block', mDialog.TitleLabel.Caption);
    Assert.IsTrue(mDialog.MarkLabel.Visible);
    Assert.AreEqual('Experimentell', mDialog.MarkLabel.Caption);
    Assert.AreEqual('except end;', mDialog.BadMemo.Lines.Text.Trim);
    Assert.AreEqual('except raise; end;', mDialog.GoodMemo.Lines.Text.Trim);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasProblemsFrameTests.ExplainDialogShowsMessageCause;
var
  mExplanation: TAtlasRuleExplanation;
  mDialog: TAtlasRuleExplainDialog;
  mOpened: string;
begin
  mExplanation := Default(TAtlasRuleExplanation);
  mExplanation.Id := 'E2003';
  mExplanation.Name := 'Undeklarierter Bezeichner';
  mExplanation.Cause := 'Unit fehlt in uses';
  mExplanation.DocWiki := 'https://docwiki.embarcadero.com/RADStudio/Athens/e/index.php?search=E2003';
  mOpened := '';
  mDialog := TAtlasRuleExplainDialog.CreateDialog(nil, mExplanation);
  try
    mDialog.OpenUrl :=
      procedure(AUrl: string)
      begin
        mOpened := AUrl;
      end;
    Assert.AreEqual('Meldung E2003', mDialog.Caption);
    Assert.AreEqual('Unit fehlt in uses', mDialog.CauseLabel.Caption);
    Assert.IsNotNull(mDialog.DocWikiButton);
    mDialog.DocWikiButton.Click;
    Assert.AreEqual(mExplanation.DocWiki, mOpened);
  finally
    mDialog.Free;
  end;
  // Regel: kein Ursachenfeld, kein Knopf.
  mExplanation := Default(TAtlasRuleExplanation);
  mExplanation.Id := 'empty-except';
  mDialog := TAtlasRuleExplainDialog.CreateDialog(nil, mExplanation);
  try
    Assert.IsNull(mDialog.CauseLabel);
    Assert.IsNull(mDialog.DocWikiButton);
  finally
    mDialog.Free;
  end;
end;

/// <summary>Englische Texte der Bereichsliste (Markierung des aktiven Projekts, Einstellung).</summary>
procedure CheckScopeTextsEnglish;
begin
  TAtlasStrings.Language := TAtlasLanguage.English;
  Assert.AreEqual('Atlas.Tests (active)', Format(TAtlasProblemsScopeBox.Text(TAtlasScopeBoxText.ActiveMark),
    ['Atlas.Tests']));
  Assert.AreEqual('Individual projects of the group in the window''s scope list',
    TAtlasProblemsScopeBox.Text(TAtlasScopeBoxText.Setting));
end;

procedure TAtlasProblemsFrameTests.ScopeListOffersGroupProjects;
var
  mHost: TForm;
  mFrame: TAtlasProblemsFrame;
  mScopes, mLayouts: Integer;
  mProjects: TArray<TAtlasScopeProject>;
begin
  mScopes := 0;
  mLayouts := 0;
  mProjects := TArray<TAtlasScopeProject>.Create(TAtlasScopeProject.Create('C:\G\Atlas.Common.dproj', False),
    TAtlasScopeProject.Create('C:\G\Atlas.IDE.Base.dproj', True));
  mHost := TForm.CreateNew(nil);
  try
    mFrame := NewFrame(mHost);
    mFrame.OnScope :=
      procedure(AScope: TAtlasFindingScope)
      begin
        Inc(mScopes);
      end;
    mFrame.OnLayout :=
      procedure
      begin
        Inc(mLayouts);
      end;
    mFrame.ScopeBox.HandleNeeded;
    Assert.AreEqual(3, Integer(mFrame.ScopeBox.Items.Count), 'ohne Gruppe nur die festen Einträge');
    Assert.AreEqual('Aktuelles Projekt', mFrame.ScopeBox.Items[1]);
    mFrame.SetScopeProjects(mProjects);
    Assert.AreEqual(6, Integer(mFrame.ScopeBox.Items.Count), 'Trennstrich und zwei Projekte');
    Assert.AreEqual('Atlas.Common', mFrame.ScopeBox.Items[4]);
    Assert.AreEqual('Atlas.IDE.Base (aktiv)', mFrame.ScopeBox.Items[5]);
    Assert.AreEqual(2, mFrame.ScopeBox.ItemIndex, 'Projektgruppe bleibt gewählt');
    // Trennstrich: die vorige Wahl bleibt.
    mFrame.ScopeBox.ItemIndex := 3;
    mFrame.ScopeBox.OnChange(mFrame.ScopeBox);
    Assert.AreEqual(2, mFrame.ScopeBox.ItemIndex);
    Assert.AreEqual(0, mScopes);
    // Einzelprojekt wählen.
    mFrame.ScopeBox.ItemIndex := 4;
    mFrame.ScopeBox.OnChange(mFrame.ScopeBox);
    Assert.AreEqual<TAtlasFindingScope>(TAtlasFindingScope.Project, mFrame.Scope);
    Assert.AreEqual('Atlas.Common', mFrame.ScopeProject);
    Assert.AreEqual(1, mScopes);
    Assert.AreEqual(1, mLayouts);
    // Das Projekt verlässt die Gruppe: aktives Projekt, gespeichert über OnLayout.
    mFrame.SetScopeProjects(TArray<TAtlasScopeProject>.Create(mProjects[1],
      TAtlasScopeProject.Create('C:\G\Atlas.Tests.dproj', False)));
    Assert.AreEqual('', mFrame.ScopeProject);
    Assert.AreEqual(1, mFrame.ScopeBox.ItemIndex);
    Assert.AreEqual(2, mLayouts);
    // Gespeichertes Einzelprojekt beim Start; Schalter aus: nur die festen Einträge.
    mFrame.ApplyScopeSettings(True, 'Atlas.Tests');
    Assert.AreEqual(5, mFrame.ScopeBox.ItemIndex);
    mFrame.ApplyScopeSettings(False, 'Atlas.Tests');
    Assert.AreEqual(3, Integer(mFrame.ScopeBox.Items.Count));
    Assert.AreEqual('', mFrame.ScopeProject);
    Assert.AreEqual(1, mFrame.ScopeBox.ItemIndex);
  finally
    mHost.Free;
  end;
  CheckScopeTextsEnglish;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasProblemsFrameTests);

end.
