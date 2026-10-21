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
    [Test]
    procedure ColumnsCanBeHiddenAndAreRemembered;
    [Test]
    procedure LiveAndPausedAndStatus;
    [Test]
    procedure ExplainDialogShowsExamples;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Winapi.Windows,
  Vcl.Forms,
  Vcl.Menus,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Findings,
  Atlas.UI.Problems.Frame,
  Atlas.UI.Problems.Explain;

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
    // Icon, Art, Kategorie, Meldung, Zeile, Stelle, Regel.
    Assert.AreEqual(7, Integer(Frame.List.Columns.Count));
    Assert.AreEqual('Art', Frame.List.Columns[1].Caption);
    Assert.AreEqual('Regel', Frame.List.Columns[6].Caption);
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
      if StripHotkey(Frame.Menu.Items[Index].Caption).StartsWith(ACaption) then
        Exit(Frame.Menu.Items[Index]);
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
    Frame.List.ItemIndex := 4;
    Frame.Menu.OnPopup(Frame.Menu);
    Assert.IsFalse(Item('Schnellkorrektur').Enabled);
    Assert.IsFalse(Item('Für diese Zeile unterdrücken').Enabled);
    Assert.IsFalse(Item('Regel abschalten').Enabled);
    Assert.IsTrue(Item('Gehe zu').Enabled);
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
    Assert.AreEqual(6, Integer(Frame.List.Columns.Count));
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
    Frame.SetLive(True);
    Assert.AreEqual('● Live', Frame.LiveLabel.Caption);
    Frame.SetLive(False);
    Assert.AreEqual('Angehalten', Frame.LiveLabel.Caption);
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

initialization
  TDUnitX.RegisterTestFixture(TAtlasProblemsFrameTests);

end.
