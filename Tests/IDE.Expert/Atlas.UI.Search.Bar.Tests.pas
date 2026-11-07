unit Atlas.UI.Search.Bar.Tests;

// Suchleiste der Atlas-Suche (#878): Felder nach der Suche setzen und
// zurücklesen, Bereich Auswahl nur mit Auswahl, Füllen erst mit Fenster
// (Teile setzen und Suche lesen auch ohne, Delphi 12),
// Tasten Enter/Umschalt+Enter/F3/Esc und Meldung jeder Änderung. Dazu (#893)
// Teile nach den Einstellungen, Ersetzen-Zeile mit Tasten, Fehler- und
// Vorschauzeile und Verlauf mit Pfeil hoch/runter.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings,
  Atlas.UI.Search.Strings;

type
  [TestFixture]
  [Category('Atlas.IDE.Search')]
  TAtlasSearchBarTests = class
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
    procedure PrepareFillsFieldsAndQueryReadsThemBack;
    [Test]
    procedure SelectionScopeOnlyWithSelection;
    [Test]
    procedure PrepareBeforeWindowIsAppliedWithWindow;
    /// <summary>Delphi 12: Features vor dem Einhängen (CreateBar) legte für ItemIndex ein Fenster an und scheiterte
    /// ohne Eltern; nach drei Versuchen schaltete die Sicherung die Suche ab.</summary>
    [Test]
    procedure FeaturesBeforeWindowNeedNoWindow;
    [Test]
    procedure KeysCallTheEvents;
    [Test]
    procedure ChangesAreReportedButNotWhilePreparing;
    [Test]
    procedure EnteringAFieldIsReported;
    [Test]
    procedure FeaturesShowReplaceRegexAndFileScopes;
    [Test]
    procedure ReplaceKeysCallTheEvents;
    [Test]
    procedure ErrorAndPreviewShowInTheInfoRow;
    [Test]
    procedure ArrowKeysWalkTheHistory;
    /// <summary>#1243: Bearbeitungstasten bleiben im Suchfeld, Enter/F3/Esc nicht.</summary>
    [Test]
    procedure EditingKeysStayInTheField;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Winapi.Windows,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.Forms,
  Atlas.Core.Search.Matching,
  Atlas.Core.Search.History,
  Atlas.UI.Search.Bar;

function NewHost: TForm;
begin
  Result := TForm.CreateNew(nil);
  Result.SetBounds(0, 0, 1200, 200);
end;

function NewBar(AHost: TForm): TAtlasSearchBar;
begin
  Result := TAtlasSearchBar.Create(AHost);
  Result.Parent := AHost;
  Result.HandleNeeded;
end;

function SampleQuery: TAtlasSearchQuery;
begin
  Result := Default(TAtlasSearchQuery);
  Result.Text := 'Open';
  Result.Options := TAtlasSearchOptions.Create(False, False, True);
  Result.Scope := TAtlasSearchScope.Method;
  Result.Level := 1;
end;

procedure Press(ABar: TAtlasSearchBar; AKey: Word; AShift: TShiftState);
var
  mKey: Word;
begin
  mKey := AKey;
  ABar.Parts.TextEdit.OnKeyDown(ABar.Parts.TextEdit, mKey, AShift);
  Assert.AreEqual(0, Integer(mKey), 'Taste verbraucht');
end;

{ TAtlasSearchBarTests }

procedure TAtlasSearchBarTests.WarmUpFirstUse;
begin
  Setup;
  try
    PrepareFillsFieldsAndQueryReadsThemBack;
  finally
    TearDown;
  end;
end;

procedure TAtlasSearchBarTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasSearchBarTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasSearchBarTests.PrepareFillsFieldsAndQueryReadsThemBack;
var
  mHost: TForm;
  mBar: TAtlasSearchBar;
  mQuery: TAtlasSearchQuery;
begin
  mHost := NewHost;
  try
    mBar := NewBar(mHost);
    mBar.Prepare(SampleQuery, ['procedure Inner;', 'function ReadLocation: Boolean;'], False);
    Assert.AreEqual('Open', mBar.Parts.TextEdit.Text);
    Assert.AreEqual(2, Integer(mBar.Parts.ScopeBox.Items.Count), 'Methode und Unit, keine Auswahl');
    Assert.AreEqual(Ord(TAtlasSearchScope.Method), mBar.Parts.ScopeBox.ItemIndex);
    Assert.AreEqual(1, mBar.Parts.LevelBox.ItemIndex);
    Assert.IsTrue(mBar.Parts.LevelBox.Visible, 'Stufe nur bei Methode');
    Assert.IsTrue(mBar.Parts.IdentifierBox.Checked);
    Assert.IsFalse(mBar.Parts.CaseBox.Enabled, 'Bezeichner-Modus ohne Groß-/Kleinschreibung');
    Assert.IsFalse(mBar.Parts.WholeBox.Enabled);
    mQuery := mBar.Query;
    Assert.AreEqual('Open', mQuery.Text);
    Assert.IsTrue(mQuery.Options.Identifier);
    Assert.AreEqual(Ord(TAtlasSearchScope.Method), Ord(mQuery.Scope));
    Assert.AreEqual(1, mQuery.Level);
    // Unit: keine Stufe.
    mBar.Parts.ScopeBox.ItemIndex := Ord(TAtlasSearchScope.UnitFile);
    mBar.Parts.ScopeBox.OnChange(mBar.Parts.ScopeBox);
    Assert.IsFalse(mBar.Parts.LevelBox.Visible);
    Assert.AreEqual(Ord(TAtlasSearchScope.UnitFile), Ord(mBar.Query.Scope));
  finally
    mHost.Free;
  end;
end;

procedure TAtlasSearchBarTests.SelectionScopeOnlyWithSelection;
var
  mHost: TForm;
  mBar: TAtlasSearchBar;
  mQuery: TAtlasSearchQuery;
begin
  mHost := NewHost;
  try
    mBar := NewBar(mHost);
    mQuery := SampleQuery;
    mQuery.Scope := TAtlasSearchScope.Selection;
    mBar.Prepare(mQuery, nil, False);
    Assert.AreEqual(Ord(TAtlasSearchScope.UnitFile), mBar.Parts.ScopeBox.ItemIndex, 'ohne Auswahl die Unit');
    Assert.IsFalse(mBar.Parts.LevelBox.Visible);
    mBar.Prepare(mQuery, nil, True);
    Assert.AreEqual(3, Integer(mBar.Parts.ScopeBox.Items.Count));
    Assert.AreEqual(Ord(TAtlasSearchScope.Selection), mBar.Parts.ScopeBox.ItemIndex);
    Assert.AreEqual(Ord(TAtlasSearchScope.Selection), Ord(mBar.Query.Scope));
  finally
    mHost.Free;
  end;
end;

procedure TAtlasSearchBarTests.PrepareBeforeWindowIsAppliedWithWindow;
var
  mHost: TForm;
  mBar: TAtlasSearchBar;
begin
  mHost := NewHost;
  try
    mBar := TAtlasSearchBar.Create(mHost);
    mBar.Prepare(SampleQuery, ['procedure Inner;'], False);
    // Ohne Fenster lassen sich die Listen nicht füllen; Prepare merkt sich die Suche.
    Assert.IsFalse(mBar.HandleAllocated);
    mBar.Parent := mHost;
    mBar.HandleNeeded;
    Assert.AreEqual(2, Integer(mBar.Parts.ScopeBox.Items.Count));
    Assert.AreEqual('Open', mBar.Parts.TextEdit.Text);
    Assert.AreEqual(0, mBar.Parts.LevelBox.ItemIndex, 'zu hohe Stufe fällt auf die innerste');
  finally
    mHost.Free;
  end;
end;

procedure TAtlasSearchBarTests.FeaturesBeforeWindowNeedNoWindow;
var
  mHost: TForm;
  mBar: TAtlasSearchBar;
begin
  mHost := NewHost;
  try
    // Wie TAtlasIdeSearch.CreateBar: ohne Eltern anlegen, Teile setzen, erst danach einhängen.
    mBar := TAtlasSearchBar.Create(mHost);
    mBar.Features := TAtlasSearchBarFeatures.Create(True, True, True);
    Assert.IsFalse(mBar.HandleAllocated, 'Features darf kein Fenster anlegen');
    Assert.IsFalse(mBar.Parts.ScopeBox.HandleAllocated, 'auch nicht für die Bereichsliste');
    Assert.IsFalse(mBar.Parts.LevelBox.HandleAllocated, 'auch nicht für die Stufenliste');
    Assert.AreEqual(Ord(TAtlasSearchScope.UnitFile), Ord(mBar.Query.Scope), 'ohne Fenster der Bereich der Vorgabe');
    mBar.Prepare(SampleQuery, ['procedure Outer;', 'procedure Inner;'], False);
    Assert.AreEqual(Ord(TAtlasSearchScope.Method), Ord(mBar.Query.Scope), 'ohne Fenster der vorbereitete Bereich');
    Assert.AreEqual(1, mBar.Query.Level, 'ohne Fenster die vorbereitete Stufe');
    Assert.IsFalse(mBar.HandleAllocated, 'Query darf kein Fenster anlegen');
    mBar.Parent := mHost;
    mBar.HandleNeeded;
    Assert.AreEqual(5, Integer(mBar.Parts.ScopeBox.Items.Count), 'Unit, Methode, offene Dateien, Projekt, Projektgruppe');
    Assert.AreEqual(Ord(TAtlasSearchScope.Method), Ord(mBar.Query.Scope));
    Assert.AreEqual(1, mBar.Parts.LevelBox.ItemIndex);
    Assert.IsTrue(mBar.Parts.LevelBox.Visible, 'Stufe sichtbar bei Bereich Methode');
  finally
    mHost.Free;
  end;
end;

procedure TAtlasSearchBarTests.KeysCallTheEvents;
var
  mHost: TForm;
  mBar: TAtlasSearchBar;
  mLog: string;
begin
  mHost := NewHost;
  try
    mBar := NewBar(mHost);
    mBar.Prepare(SampleQuery, nil, False);
    mLog := '';
    mBar.Events.OnStep :=
      procedure(ABackward: Boolean)
      begin
        if ABackward then
        begin
          mLog := mLog + 'zurück;';
        end
        else
        begin
          mLog := mLog + 'vor;';
        end;
      end;
    mBar.Events.OnList :=
      procedure
      begin
        mLog := mLog + 'liste;';
      end;
    mBar.Events.OnClose :=
      procedure
      begin
        mLog := mLog + 'zu;';
      end;
    Press(mBar, VK_RETURN, []);
    Assert.AreEqual('vor;liste;', mLog, 'Enter: weiter und Liste');
    mLog := '';
    Press(mBar, VK_RETURN, [ssShift]);
    Assert.AreEqual('zurück;', mLog, 'Umschalt+Enter: zurück ohne Liste');
    mLog := '';
    Press(mBar, VK_F3, []);
    Press(mBar, VK_F3, [ssShift]);
    Assert.AreEqual('vor;zurück;', mLog);
    mLog := '';
    Press(mBar, VK_ESCAPE, []);
    Assert.AreEqual('zu;', mLog);
    // Ohne Liste in den Meldungen (search.resultsInMessages aus) springt Enter nur.
    mLog := '';
    mBar.SetListVisible(False);
    Press(mBar, VK_RETURN, []);
    Assert.AreEqual('vor;', mLog);
  finally
    mHost.Free;
    mLog := '';
  end;
end;

procedure TAtlasSearchBarTests.ChangesAreReportedButNotWhilePreparing;
var
  mHost: TForm;
  mBar: TAtlasSearchBar;
  mCount: Integer;
begin
  mHost := NewHost;
  try
    mBar := NewBar(mHost);
    mCount := 0;
    mBar.Events.OnQueryChanged :=
      procedure
      begin
        Inc(mCount);
      end;
    mBar.Prepare(SampleQuery, ['procedure Inner;'], False);
    Assert.AreEqual(0, mCount, 'Vorbelegen meldet nichts');
    // Text per Programm löst bei TComboBox kein OnChange aus: wie beim Tippen melden.
    mBar.Parts.TextEdit.Text := 'Close';
    mBar.Parts.TextEdit.OnChange(mBar.Parts.TextEdit);
    Assert.AreEqual(1, mCount);
    Assert.AreEqual('Close', mBar.Query.Text);
    mBar.Parts.IdentifierBox.Checked := False;
    Assert.AreEqual(2, mCount);
    Assert.IsTrue(mBar.Parts.CaseBox.Enabled, 'ohne Bezeichner-Modus wieder wählbar');
    mBar.SetCounter('3 von 9');
    Assert.AreEqual('3 von 9', mBar.Parts.CounterLabel.Caption);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasSearchBarTests.EnteringAFieldIsReported;
var
  mHost: TForm;
  mBar: TAtlasSearchBar;
  mEntered: TArray<TObject>;
begin
  mHost := NewHost;
  try
    mBar := NewBar(mHost);
    mEntered := nil;
    mBar.Events.OnControlEnter :=
      procedure(AControl: TWinControl)
      begin
        mEntered := mEntered + [AControl];
      end;
    mBar.Parts.TextEdit.OnEnter(mBar.Parts.TextEdit);
    mBar.Parts.ScopeBox.OnEnter(mBar.Parts.ScopeBox);
    mBar.Parts.IdentifierBox.OnEnter(mBar.Parts.IdentifierBox);
    Assert.AreEqual(3, Integer(Length(mEntered)));
    Assert.AreSame(mBar.Parts.TextEdit, mEntered[0]);
    Assert.AreSame(mBar.Parts.ScopeBox, mEntered[1]);
    Assert.AreSame(mBar.Parts.IdentifierBox, mEntered[2]);
  finally
    mHost.Free;
    mEntered := nil;
  end;
end;

procedure PressIn(AControl: TWinControl; AKey: Word; AShift: TShiftState);
var
  mKey: Word;
begin
  mKey := AKey;
  if AControl is TComboBox then
  begin
    TComboBox(AControl).OnKeyDown(AControl, mKey, AShift);
  end;
  Assert.AreEqual(0, Integer(mKey), 'Taste verbraucht');
end;

procedure TAtlasSearchBarTests.FeaturesShowReplaceRegexAndFileScopes;
var
  mHost: TForm;
  mBar: TAtlasSearchBar;
begin
  mHost := NewHost;
  try
    mBar := NewBar(mHost);
    mBar.Prepare(SampleQuery, nil, False);
    // Vorgabe: alles aus wie vor #893.
    Assert.IsFalse(mBar.Parts.ToggleButton.Visible);
    Assert.IsFalse(mBar.Parts.RegexBox.Visible);
    mBar.ReplaceShown := True;
    Assert.IsFalse(mBar.ReplaceShown, 'ohne search.replace keine Ersetzen-Zeile');
    Assert.AreEqual(2, Integer(mBar.Parts.ScopeBox.Items.Count));
    mBar.Features := TAtlasSearchBarFeatures.Create(True, True, True);
    Assert.IsTrue(mBar.Parts.ToggleButton.Visible);
    Assert.IsTrue(mBar.Parts.RegexBox.Visible);
    Assert.AreEqual(5, Integer(mBar.Parts.ScopeBox.Items.Count), 'Unit, Methode, offene Dateien, Projekt, Projektgruppe');
    Assert.AreEqual(TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchScopeProject), mBar.Parts.ScopeBox.Items[3]);
    mBar.ReplaceShown := True;
    Assert.IsTrue(mBar.Parts.ReplaceRow.Visible);
    mBar.Parts.RegexBox.Checked := True;
    Assert.IsTrue(mBar.Query.Options.Regex);
    // search.regex aus: Option weg, Suche ohne Regex.
    mBar.Features := TAtlasSearchBarFeatures.Create(True, False, False);
    Assert.IsFalse(mBar.Parts.RegexBox.Visible);
    Assert.IsFalse(mBar.Query.Options.Regex);
    Assert.AreEqual(2, Integer(mBar.Parts.ScopeBox.Items.Count), 'ohne search.multiFile nur die Bereiche aus #878');
    mBar.Features := TAtlasSearchBarFeatures.Create(False, False, False);
    Assert.IsFalse(mBar.ReplaceShown);
    Assert.IsFalse(mBar.Parts.ReplaceRow.Visible);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasSearchBarTests.ReplaceKeysCallTheEvents;
var
  mHost: TForm;
  mBar: TAtlasSearchBar;
  mLog: string;
begin
  mHost := NewHost;
  try
    mBar := NewBar(mHost);
    mBar.Features := TAtlasSearchBarFeatures.Create(True, True, False);
    mBar.Prepare(SampleQuery, nil, False);
    mBar.ReplaceShown := True;
    mLog := '';
    mBar.Events.OnReplace :=
      procedure
      begin
        mLog := mLog + 'eins;';
      end;
    mBar.Events.OnReplaceAll :=
      procedure
      begin
        mLog := mLog + 'alle;';
      end;
    mBar.Events.OnStep :=
      procedure(ABackward: Boolean)
      begin
        mLog := mLog + 'vor;';
      end;
    PressIn(mBar.Parts.ReplaceEdit, VK_RETURN, []);
    PressIn(mBar.Parts.ReplaceEdit, VK_RETURN, [ssCtrl]);
    Assert.AreEqual('eins;alle;', mLog, 'Enter ersetzt einen, Strg+Enter alle');
    mLog := '';
    PressIn(mBar.Parts.ReplaceEdit, VK_F3, []);
    Assert.AreEqual('vor;', mLog, 'F3 springt auch im Ersetzen-Feld');
  finally
    mHost.Free;
    mLog := '';
  end;
end;

procedure TAtlasSearchBarTests.ErrorAndPreviewShowInTheInfoRow;
var
  mHost: TForm;
  mBar: TAtlasSearchBar;
begin
  mHost := NewHost;
  try
    mBar := NewBar(mHost);
    mBar.Features := TAtlasSearchBarFeatures.Create(True, True, False);
    mBar.Prepare(SampleQuery, nil, False);
    mBar.SetError('missing )');
    Assert.IsTrue(mBar.HasError);
    Assert.AreEqual('Ungültiger Ausdruck: missing )', mBar.InfoText);
    mBar.SetError('');
    Assert.IsFalse(mBar.HasError);
    Assert.AreEqual('', mBar.InfoText);
    mBar.SetPreview('IntToStr(Kunde.Nr)', 'Kunde.Nr.ToString');
    Assert.AreEqual('Vorschau: IntToStr(Kunde.Nr) → Kunde.Nr.ToString', mBar.InfoText);
    mBar.SetNotice('12 Ersetzungen in 3 Dateien');
    Assert.AreEqual('Vorschau: IntToStr(Kunde.Nr) → Kunde.Nr.ToString   ·   12 Ersetzungen in 3 Dateien',
      mBar.InfoText, 'Vorschau und Meldung nach dem Ersetzen');
    mBar.ClearPreview;
    Assert.AreEqual('12 Ersetzungen in 3 Dateien', mBar.InfoText);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasSearchBarTests.ArrowKeysWalkTheHistory;
var
  mHost: TForm;
  mBar: TAtlasSearchBar;
  mSearch, mReplace: TAtlasSearchHistory;
  mCount: Integer;
begin
  mHost := NewHost;
  mSearch := TAtlasSearchHistory.Create(20);
  mReplace := TAtlasSearchHistory.Create(20);
  try
    mBar := NewBar(mHost);
    mBar.Features := TAtlasSearchBarFeatures.Create(True, False, False);
    mBar.SetHistories(mSearch, mReplace);
    mBar.Prepare(SampleQuery, nil, False);
    mCount := 0;
    mBar.Events.OnQueryChanged :=
      procedure
      begin
        Inc(mCount);
      end;
    mSearch.Remember('vorige');
    mSearch.Remember('Open');
    // Akzeptanzkriterium: Pfeil hoch holt die vorige Suche, auch wenn die letzte im Feld steht.
    PressIn(mBar.Parts.TextEdit, VK_UP, []);
    Assert.AreEqual('vorige', mBar.Parts.TextEdit.Text);
    Assert.AreEqual(1, mCount, 'neue Suche angestoßen');
    PressIn(mBar.Parts.TextEdit, VK_DOWN, []);
    PressIn(mBar.Parts.TextEdit, VK_DOWN, []);
    Assert.AreEqual('Open', mBar.Parts.TextEdit.Text, 'zurück zum getippten Text');
    // Enter merkt den Text; im Ersetzen-Feld nur bei offener Zeile.
    mBar.ReplaceShown := True;
    mBar.Parts.ReplaceEdit.Text := '$1.ToString';
    mBar.Remember;
    Assert.AreEqual('$1.ToString', mReplace.Items[0]);
    PressIn(mBar.Parts.ReplaceEdit, VK_UP, []);
    Assert.AreEqual('$1.ToString', mBar.Parts.ReplaceEdit.Text);
  finally
    mHost.Free;
    mSearch.Free;
    mReplace.Free;
  end;
end;

procedure TAtlasSearchBarTests.EditingKeysStayInTheField;
begin
  Assert.IsTrue(TAtlasSearchCombo.KeepsKey(Ord('V'), [ssCtrl]), 'Strg+V');
  Assert.IsTrue(TAtlasSearchCombo.KeepsKey(Ord('A'), [ssCtrl]), 'Strg+A');
  Assert.IsTrue(TAtlasSearchCombo.KeepsKey(VK_INSERT, [ssShift]), 'Umschalt+Einfg');
  Assert.IsTrue(TAtlasSearchCombo.KeepsKey(VK_DELETE, []), 'Entf');
  Assert.IsFalse(TAtlasSearchCombo.KeepsKey(VK_RETURN, []), 'Enter');
  Assert.IsFalse(TAtlasSearchCombo.KeepsKey(VK_F3, []), 'F3');
  Assert.IsFalse(TAtlasSearchCombo.KeepsKey(Ord('F'), [ssCtrl]), 'Strg+F');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSearchBarTests);

end.
