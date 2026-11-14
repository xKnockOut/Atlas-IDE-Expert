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
  Host: TForm;
  Frame: TAtlasProblemsFrame;
begin
  Host := TForm.CreateNew(nil);
  try
    Frame := NewFrame(Host);
    // Icon, Art, Kategorie, Meldung, Zeile, Stelle, Regel, Compiler (#1024).
    Assert.AreEqual(8, Integer(Frame.List.Columns.Count));
    Assert.AreEqual('Art', Frame.List.Columns[1].Caption);
    Assert.AreEqual('Regel', Frame.List.Columns[6].Caption);
    Assert.AreEqual('Compiler', Frame.List.Columns[7].Caption);
    // problems.showCompilerCode aus: ohne Spalte Compiler, Layout bleibt gemerkt.
    Frame.ShowCompilerCode := False;
    Assert.AreEqual(7, Integer(Frame.List.Columns.Count));
    Assert.Contains(Frame.ColumnsText, 'compiler');
    Frame.ShowCompilerCode := True;
    Assert.AreEqual(8, Integer(Frame.List.Columns.Count));
    // Nach Datei: Kunde.pas (2), dann ihre Befunde, dann Lager.pas (1) und sein Befund.
    Assert.AreEqual(5, Integer(Frame.List.Items.Count));
    Assert.AreEqual(#$25BE' Kunde.pas (2)', Frame.List.Items[0].SubItems[0]);
    Assert.AreEqual(-1, Frame.List.Items[0].ImageIndex, 'Gruppenzeile ohne Icon');
    // Fehler vor Warnungen.
    Assert.AreEqual('Error', Frame.List.Items[1].SubItems[0]);
    Assert.AreEqual(0, Frame.List.Items[1].ImageIndex);
    Assert.AreEqual('Bug', Frame.List.Items[1].SubItems[1]);
    Assert.AreEqual('X := 1', Frame.List.Items[1].SubItems[3]);
    Assert.AreEqual('Kunde.pas:6:3', Frame.List.Items[1].SubItems[4]);
    Assert.AreEqual('syntax', Frame.List.Items[1].SubItems[5]);
    Assert.AreEqual('Warnung', Frame.List.Items[2].SubItems[0]);
    Assert.AreEqual(1, Frame.List.Items[2].ImageIndex);
    Assert.AreEqual('Compiler', Frame.List.Items[4].SubItems[1]);
    // Gruppe zuklappen per Klick bzw. Leertaste: Zeilen bleiben gezählt.
    Frame.View.Toggle(0);
    Frame.Refill;
    Assert.AreEqual(3, Integer(Frame.List.Items.Count));
    Assert.AreEqual(#$25B8' Kunde.pas (2)', Frame.List.Items[0].SubItems[0]);
    Assert.IsFalse(Frame.EmptyLabel.Visible);
  finally
    Host.Free;
  end;
end;

procedure TAtlasProblemsFrameTests.KindToggleAndTextFilterNarrowTheList;
var
  Host: TForm;
  Frame: TAtlasProblemsFrame;
begin
  Host := TForm.CreateNew(nil);
  try
    Frame := NewFrame(Host);
    Frame.GroupingBox.ItemIndex := Ord(TAtlasFindingGrouping.None);
    Frame.GroupingBox.OnChange(Frame.GroupingBox);
    Assert.AreEqual(3, Integer(Frame.List.Items.Count));
    Assert.AreEqual('Error 1', Frame.KindButton(TAtlasFindingKind.Error).Caption);
    Assert.AreEqual('Warnung 2', Frame.KindButton(TAtlasFindingKind.Warning).Caption);
    Assert.AreEqual('Info 0', Frame.KindButton(TAtlasFindingKind.Info).Caption);
    // Warnungen aus: nur der Fehler bleibt, die Zähler auf den Umschaltern bleiben.
    Frame.KindButton(TAtlasFindingKind.Warning).Down := False;
    Frame.KindButton(TAtlasFindingKind.Warning).OnClick(Frame.KindButton(TAtlasFindingKind.Warning));
    Assert.AreEqual(1, Integer(Frame.List.Items.Count));
    Assert.AreEqual('Warnung 2', Frame.KindButton(TAtlasFindingKind.Warning).Caption);
    Frame.KindButton(TAtlasFindingKind.Warning).Down := True;
    Frame.KindButton(TAtlasFindingKind.Warning).OnClick(Frame.KindButton(TAtlasFindingKind.Warning));
    // Kategorie „Compiler“.
    Frame.CategoryBox.ItemIndex := 1 + Ord(TAtlasFindingCategory.Compiler);
    Frame.CategoryBox.OnChange(Frame.CategoryBox);
    Assert.AreEqual(1, Integer(Frame.List.Items.Count));
    Frame.CategoryBox.ItemIndex := 0;
    Frame.CategoryBox.OnChange(Frame.CategoryBox);
    Frame.FilterEdit.Text := 'except';
    Assert.AreEqual(1, Integer(Frame.List.Items.Count), 'Textfilter über Meldung, Regel und Datei');
    Frame.FilterEdit.Text := 'lager';
    Assert.AreEqual(1, Integer(Frame.List.Items.Count));
    Assert.AreEqual('W1036', Frame.List.Items[0].SubItems[5]);
    Frame.FilterEdit.Text := 'gibtsnicht';
    Assert.AreEqual(0, Integer(Frame.List.Items.Count));
    Assert.IsTrue(Frame.EmptyLabel.Visible);
    Frame.FilterEdit.Text := '';
    Assert.AreEqual(3, Integer(Frame.List.Items.Count));
  finally
    Host.Free;
  end;
end;

procedure TAtlasProblemsFrameTests.OpenFirstPinsDimsAndSkipsSections;
var
  Host: TForm;
  Frame: TAtlasProblemsFrame;
  Key: Word;
  Saved: Boolean;
begin
  Host := TForm.CreateNew(nil);
  try
    Frame := NewFrame(Host);
    Frame.ApplyTierSettings(True, TAtlasClosedUnits.Dimmed, True);
    Assert.IsTrue(Frame.OpenFirst);
    Assert.IsTrue(Frame.OpenFirstButton.Down);
    Frame.SetOpenFiles('C:\P\Lager.pas', ['C:\P\Lager.pas'], True);
    Assert.AreEqual(6, Integer(Frame.List.Items.Count));
    Assert.AreEqual(#$25BE' '#$D83D#$DCCC' Lager.pas (1) '#$00B7' aktiver Editor', Frame.List.Items[0].SubItems[0]);
    Assert.AreEqual(1, Frame.List.Items[1].ImageIndex, 'aktive Unit mit normalem Symbol');
    Assert.AreEqual('Nicht geöffnet '#$00B7' 1 Units '#$00B7' 2 Befunde', Frame.List.Items[2].SubItems[0]);
    Assert.AreEqual(-1, Frame.List.Items[2].ImageIndex, 'Trennzeile ohne Symbol');
    Assert.AreEqual(#$25BE' Kunde.pas (2) '#$00B7' nicht geöffnet', Frame.List.Items[3].SubItems[0]);
    Assert.AreEqual(3, Frame.List.Items[4].ImageIndex, 'ausgegrautes Fehlersymbol');
    // ↓ von der letzten Zeile der aktiven Unit springt über die Trennzeile.
    Frame.List.ItemIndex := 1;
    Frame.View.Select(1);
    Key := VK_DOWN;
    Frame.List.OnKeyDown(Frame.List, Key, []);
    Assert.AreEqual(0, Integer(Key));
    Assert.AreEqual(3, Frame.List.ItemIndex);
    // Knopf aus: wie #909, und die Einstellung wird gespeichert.
    Saved := False;
    Frame.OnLayout :=
      procedure
      begin
        Saved := True;
      end;
    Frame.OpenFirstButton.Down := False;
    Frame.OpenFirstButton.OnClick(Frame.OpenFirstButton);
    Assert.IsTrue(Saved);
    Assert.IsFalse(Frame.OpenFirst);
    Assert.AreEqual(5, Integer(Frame.List.Items.Count));
    Assert.AreEqual(#$25BE' Kunde.pas (2)', Frame.List.Items[0].SubItems[0]);
  finally
    Host.Free;
  end;
end;

procedure TAtlasProblemsFrameTests.RefillReselectsWithoutFetchingEveryRow;
var
  Host: TForm;
  Frame: TAtlasProblemsFrame;
  Counter: TFetchCounter;
  Problems: TArray<TAtlasProblem>;
  Index: Integer;
begin
  SetLength(Problems, 300);
  for Index := 0 to High(Problems) do
  begin
    Problems[Index] := Problem(Index, 'Atlas', 'empty-except', 'Leerer except-Block', TAtlasProblemSeverity.Warning,
      '');
  end;
  Host := TForm.CreateNew(nil);
  Counter := TFetchCounter.Create;
  try
    Frame := NewFrame(Host);
    Frame.SetFindings(TAtlasFindings.FromProblems('C:\P\Kunde.pas', Problems, nil), 'C:\P\Kunde.pas', nil);
    // Zwei Zeilen markiert, dann wählt die Sicht eine dritte.
    Frame.List.ItemIndex := 1;
    Frame.List.ItemIndex := 2; // lsp-ignore: duplicate-assignment -- markiert eine zweite Zeile (Mehrfachauswahl)
    Assert.AreEqual(2, Integer(Frame.List.SelCount));
    Counter.Inner := Frame.List.OnData;
    Frame.List.OnData := Counter.Fetch;
    try
      Frame.View.Select(4);
      Frame.Refill;
    finally
      Frame.List.OnData := Counter.Inner;
    end;
    Assert.AreEqual(1, Integer(Frame.List.SelCount));
    Assert.AreEqual(4, Frame.List.ItemIndex);
    // Mit ClearSelection holte das jede der 301 Zeilen mindestens einmal.
    Assert.IsTrue(Counter.Count < 30, Format('%d Abrufe für %d Zeilen', [Counter.Count, Frame.List.Items.Count]));
  finally
    Host.Free;
    Counter.Free;
  end;
end;

procedure TAtlasProblemsFrameTests.KeysOpenAndFix;
var
  Host: TForm;
  Frame: TAtlasProblemsFrame;
  Opened, Fixed: string;
  Key: Word;
begin
  Host := TForm.CreateNew(nil);
  try
    Frame := NewFrame(Host);
    Frame.OnOpen :=
      procedure(const AFinding: TAtlasFinding)
      begin
        Opened := AFinding.Location;
      end;
    Frame.OnFix :=
      procedure(const AFinding: TAtlasFinding)
      begin
        Fixed := AFinding.Problem.FixTitle;
      end;
    Frame.List.ItemIndex := 2;
    Frame.View.Select(2);
    Key := VK_RETURN;
    Frame.List.OnKeyDown(Frame.List, Key, []);
    Assert.AreEqual('Kunde.pas:4:3', Opened);
    Key := VK_RETURN;
    Frame.List.OnKeyDown(Frame.List, Key, [ssAlt]);
    Assert.AreEqual('raise ergänzen', Fixed);
    // Enter auf einer Gruppe klappt sie nur.
    Opened := '';
    Frame.List.ItemIndex := 0;
    Key := VK_RETURN;
    Frame.List.OnKeyDown(Frame.List, Key, []);
    Assert.AreEqual('', Opened);
    Assert.AreEqual(3, Integer(Frame.List.Items.Count));
  finally
    Host.Free;
  end;
end;

procedure TAtlasProblemsFrameTests.MenuOffersRuleActionsOnlyForRules;
var
  Host: TForm;
  Frame: TAtlasProblemsFrame;

  function Item(const ACaption: string): TMenuItem;
  var
    Index: Integer;
  begin
    Result := nil;
    for Index := 0 to Frame.Menu.Items.Count - 1 do
    begin
      if StripHotkey(Frame.Menu.Items[Index].Caption).StartsWith(ACaption) then
      begin
        Exit(Frame.Menu.Items[Index]);
      end;
    end;
  end;

begin
  Host := TForm.CreateNew(nil);
  try
    Frame := NewFrame(Host);
    Frame.List.ItemIndex := 2;
    Frame.Menu.OnPopup(Frame.Menu);
    Assert.IsNotNull(Item('Schnellkorrektur: raise ergänzen'));
    Assert.IsTrue(Item('Schnellkorrektur').Enabled);
    Assert.IsTrue(Item('Für diese Zeile unterdrücken').Enabled);
    Assert.IsTrue(Item('Regel einstellen').Enabled);
    Assert.IsTrue(Item('Regel abschalten').Enabled);
    Assert.IsTrue(Item('Regel erklären').Enabled);
    // Compilermeldung: kein Unterdrücken, Einstellen, Abschalten oder Erklären.
    // Mehrfachauswahl: ItemIndex fügt nur hinzu, die erste markierte Zeile zählt.
    Frame.List.ClearSelection;
    Frame.List.ItemIndex := 4;
    Frame.Menu.OnPopup(Frame.Menu);
    Assert.IsFalse(Item('Schnellkorrektur').Enabled, 'Schnellkorrektur');
    Assert.IsFalse(Item('Für diese Zeile unterdrücken').Enabled, 'Unterdrücken');
    Assert.IsFalse(Item('Regel abschalten').Enabled, 'Abschalten');
    Assert.IsTrue(Item('Gehe zu').Enabled, 'Gehe zu');
  finally
    Host.Free;
  end;
end;

procedure TAtlasProblemsFrameTests.MenuFixAllFollowsSettingAndRule;
var
  Host: TForm;
  Frame: TAtlasProblemsFrame;
  Bulk: Boolean;
  Fired: string;

  function Item: TMenuItem;
  var
    Index: Integer;
  begin
    Result := nil;
    for Index := 0 to Frame.Menu.Items.Count - 1 do
    begin
      if StripHotkey(Frame.Menu.Items[Index].Caption).StartsWith('Alle sicheren Treffer von') then
      begin
        Exit(Frame.Menu.Items[Index]);
      end;
    end;
  end;

begin
  Host := TForm.CreateNew(nil);
  try
    Frame := NewFrame(Host);
    Bulk := False;
    Fired := '';
    Frame.OnFixAll :=
      procedure(const AFinding: TAtlasFinding)
      begin
        Fired := AFinding.Rule;
      end;
    Frame.CanFixAll :=
      function: Boolean
      begin
        Result := Bulk;
      end;
    Frame.List.ItemIndex := 2;
    Frame.Menu.OnPopup(Frame.Menu);
    Assert.IsNotNull(Item);
    Assert.IsFalse(Item.Visible, 'fix.bulk aus: kein Eintrag');
    Bulk := True;
    Frame.Menu.OnPopup(Frame.Menu);
    Assert.IsTrue(Item.Visible);
    Assert.IsTrue(Item.Enabled);
    Item.Click;
    Assert.AreNotEqual('', Fired);
    Assert.IsTrue(Pos(Fired, StripHotkey(Item.Caption)) > 0, Item.Caption);
    // Compilermeldung: keine Regel, also keine Sammelkorrektur.
    Frame.List.ClearSelection;
    Frame.List.ItemIndex := 4;
    Frame.Menu.OnPopup(Frame.Menu);
    Assert.IsFalse(Item.Enabled);
  finally
    Host.Free;
  end;
end;

procedure TAtlasProblemsFrameTests.ColumnsCanBeHiddenAndAreRemembered;
var
  Host: TForm;
  Frame: TAtlasProblemsFrame;
  Layout: Integer;
begin
  Host := TForm.CreateNew(nil);
  try
    Frame := NewFrame(Host);
    Layout := 0;
    Frame.OnLayout :=
      procedure
      begin
        Inc(Layout);
      end;
    Frame.ApplySettings(TAtlasFindingScope.Group, TAtlasFindingGrouping.None, 'rule,kind:90,-message', False);
    // Pflichtspalten bleiben, Meldung ist aus, Regel steht vorn (Reihenfolge der Anzeige).
    Assert.AreEqual(7, Integer(Frame.List.Columns.Count));
    Assert.Contains(Frame.ColumnsText, '-message');
    Assert.Contains(Frame.ColumnsText, 'kind:90');
    Assert.IsTrue(Frame.ColumnsText.StartsWith('rule'), Frame.ColumnsText);
    // Ohne Compilermeldungen.
    Assert.AreEqual(2, Integer(Frame.List.Items.Count));
    Assert.AreEqual(0, Layout, 'Übernehmen der Einstellungen meldet nichts');
  finally
    Host.Free;
  end;
end;

procedure TAtlasProblemsFrameTests.LiveAndPausedAndStatus;
var
  Host: TForm;
  Frame: TAtlasProblemsFrame;
begin
  Host := TForm.CreateNew(nil);
  try
    Frame := NewFrame(Host);
    Frame.SetUpdate(TAtlasProblemsUpdate.Live);
    Assert.AreEqual('● Live', Frame.LiveLabel.Caption);
    Frame.SetUpdate(TAtlasProblemsUpdate.Save);
    Assert.AreEqual('Beim Speichern', Frame.LiveLabel.Caption);
    Frame.SetUpdate(TAtlasProblemsUpdate.Manual);
    Assert.AreEqual('Manuell', Frame.LiveLabel.Caption);
    // Die aktuelle Datei prüft die Schaltfläche der Atlas-Statusleiste, das Fenster hat keinen eigenen Knopf.
    Assert.IsFalse(HasButton(Frame, 'Datei jetzt prüfen'), 'kein Knopf „Datei jetzt prüfen“');
    Frame.SetStatus('3 Befunde in 2 Dateien');
    Assert.AreEqual('3 Befunde in 2 Dateien', Frame.StatusLabel.Caption);
    Frame.SetFindings(nil, '', nil);
    Assert.IsTrue(Frame.EmptyLabel.Visible);
    Assert.AreEqual('Keine Befunde.', Frame.EmptyLabel.Caption);
  finally
    Host.Free;
  end;
end;

procedure TAtlasProblemsFrameTests.ExplainDialogShowsExamples;
var
  Explanation: TAtlasRuleExplanation;
  Dialog: TAtlasRuleExplainDialog;
begin
  Explanation := Default(TAtlasRuleExplanation);
  Explanation.Id := 'empty-except';
  Explanation.Name := 'Leerer except-Block';
  Explanation.Description := 'Fehler werden verschluckt.';
  Explanation.Bad := 'except end;';
  Explanation.Good := 'except raise; end;';
  Explanation.Experimental := True;
  Dialog := TAtlasRuleExplainDialog.CreateDialog(nil, Explanation);
  try
    Assert.AreEqual('Regel empty-except', Dialog.Caption);
    Assert.AreEqual('Leerer except-Block', Dialog.TitleLabel.Caption);
    Assert.IsTrue(Dialog.MarkLabel.Visible);
    Assert.AreEqual('Experimentell', Dialog.MarkLabel.Caption);
    Assert.AreEqual('except end;', Dialog.BadMemo.Lines.Text.Trim);
    Assert.AreEqual('except raise; end;', Dialog.GoodMemo.Lines.Text.Trim);
  finally
    Dialog.Free;
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
  TAtlasStrings.Language := TAtlasLanguage.English;
  Assert.AreEqual('Atlas.Tests (active)', Format(TAtlasProblemsScopeBox.Text(TAtlasScopeBoxText.ActiveMark),
    ['Atlas.Tests']));
  Assert.AreEqual('Individual projects of the group in the window''s scope list',
    TAtlasProblemsScopeBox.Text(TAtlasScopeBoxText.Setting));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasProblemsFrameTests);

end.
