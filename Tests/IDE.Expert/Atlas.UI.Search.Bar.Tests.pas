unit Atlas.UI.Search.Bar.Tests;

// Suchleiste der Atlas-Suche (#878): Felder nach der Suche setzen und
// zurücklesen, Bereich Auswahl nur mit Auswahl, Füllen erst mit Fenster,
// Tasten Enter/Umschalt+Enter/F3/Esc und Meldung jeder Änderung. Dazu (#893)
// Teile nach den Einstellungen, Ersetzen-Zeile mit Tasten, Fehler- und
// Vorschauzeile und Verlauf mit Pfeil hoch/runter.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
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
  Key: Word;
begin
  Key := AKey;
  ABar.TextEdit.OnKeyDown(ABar.TextEdit, Key, AShift);
  Assert.AreEqual(0, Integer(Key), 'Taste verbraucht');
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
  Host: TForm;
  Bar: TAtlasSearchBar;
  Query: TAtlasSearchQuery;
begin
  Host := NewHost;
  try
    Bar := NewBar(Host);
    Bar.Prepare(SampleQuery, ['procedure Inner;', 'function ReadLocation: Boolean;'], False);
    Assert.AreEqual('Open', Bar.TextEdit.Text);
    Assert.AreEqual(2, Integer(Bar.ScopeBox.Items.Count), 'Methode und Unit, keine Auswahl');
    Assert.AreEqual(Ord(TAtlasSearchScope.Method), Bar.ScopeBox.ItemIndex);
    Assert.AreEqual(1, Bar.LevelBox.ItemIndex);
    Assert.IsTrue(Bar.LevelBox.Visible, 'Stufe nur bei Methode');
    Assert.IsTrue(Bar.IdentifierBox.Checked);
    Assert.IsFalse(Bar.CaseBox.Enabled, 'Bezeichner-Modus ohne Groß-/Kleinschreibung');
    Assert.IsFalse(Bar.WholeBox.Enabled);
    Query := Bar.Query;
    Assert.AreEqual('Open', Query.Text);
    Assert.IsTrue(Query.Options.Identifier);
    Assert.AreEqual(Ord(TAtlasSearchScope.Method), Ord(Query.Scope));
    Assert.AreEqual(1, Query.Level);
    // Unit: keine Stufe.
    Bar.ScopeBox.ItemIndex := Ord(TAtlasSearchScope.UnitFile);
    Bar.ScopeBox.OnChange(Bar.ScopeBox);
    Assert.IsFalse(Bar.LevelBox.Visible);
    Assert.AreEqual(Ord(TAtlasSearchScope.UnitFile), Ord(Bar.Query.Scope));
  finally
    Host.Free;
  end;
end;

procedure TAtlasSearchBarTests.SelectionScopeOnlyWithSelection;
var
  Host: TForm;
  Bar: TAtlasSearchBar;
  Query: TAtlasSearchQuery;
begin
  Host := NewHost;
  try
    Bar := NewBar(Host);
    Query := SampleQuery;
    Query.Scope := TAtlasSearchScope.Selection;
    Bar.Prepare(Query, nil, False);
    Assert.AreEqual(Ord(TAtlasSearchScope.UnitFile), Bar.ScopeBox.ItemIndex, 'ohne Auswahl die Unit');
    Assert.IsFalse(Bar.LevelBox.Visible);
    Bar.Prepare(Query, nil, True);
    Assert.AreEqual(3, Integer(Bar.ScopeBox.Items.Count));
    Assert.AreEqual(Ord(TAtlasSearchScope.Selection), Bar.ScopeBox.ItemIndex);
    Assert.AreEqual(Ord(TAtlasSearchScope.Selection), Ord(Bar.Query.Scope));
  finally
    Host.Free;
  end;
end;

procedure TAtlasSearchBarTests.PrepareBeforeWindowIsAppliedWithWindow;
var
  Host: TForm;
  Bar: TAtlasSearchBar;
begin
  Host := NewHost;
  try
    Bar := TAtlasSearchBar.Create(Host);
    Bar.Prepare(SampleQuery, ['procedure Inner;'], False);
    // Ohne Fenster lassen sich die Listen nicht füllen; Prepare merkt sich die Suche.
    Assert.IsFalse(Bar.HandleAllocated);
    Bar.Parent := Host;
    Bar.HandleNeeded;
    Assert.AreEqual(2, Integer(Bar.ScopeBox.Items.Count));
    Assert.AreEqual('Open', Bar.TextEdit.Text);
    Assert.AreEqual(0, Bar.LevelBox.ItemIndex, 'zu hohe Stufe fällt auf die innerste');
  finally
    Host.Free;
  end;
end;

procedure TAtlasSearchBarTests.KeysCallTheEvents;
var
  Host: TForm;
  Bar: TAtlasSearchBar;
  Log: string;
begin
  Host := NewHost;
  try
    Bar := NewBar(Host);
    Bar.Prepare(SampleQuery, nil, False);
    Log := '';
    Bar.OnStep :=
      procedure(ABackward: Boolean)
      begin
        if ABackward then
          Log := Log + 'zurück;'
        else
          Log := Log + 'vor;';
      end;
    Bar.OnList :=
      procedure
      begin
        Log := Log + 'liste;';
      end;
    Bar.OnClose :=
      procedure
      begin
        Log := Log + 'zu;';
      end;
    Press(Bar, VK_RETURN, []);
    Assert.AreEqual('vor;liste;', Log, 'Enter: weiter und Liste');
    Log := '';
    Press(Bar, VK_RETURN, [ssShift]);
    Assert.AreEqual('zurück;', Log, 'Umschalt+Enter: zurück ohne Liste');
    Log := '';
    Press(Bar, VK_F3, []);
    Press(Bar, VK_F3, [ssShift]);
    Assert.AreEqual('vor;zurück;', Log);
    Log := '';
    Press(Bar, VK_ESCAPE, []);
    Assert.AreEqual('zu;', Log);
    // Ohne Liste in den Meldungen (search.resultsInMessages aus) springt Enter nur.
    Log := '';
    Bar.ListVisible := False;
    Press(Bar, VK_RETURN, []);
    Assert.AreEqual('vor;', Log);
  finally
    Host.Free;
    Log := '';
  end;
end;

procedure TAtlasSearchBarTests.ChangesAreReportedButNotWhilePreparing;
var
  Host: TForm;
  Bar: TAtlasSearchBar;
  Count: Integer;
begin
  Host := NewHost;
  try
    Bar := NewBar(Host);
    Count := 0;
    Bar.OnQueryChanged :=
      procedure
      begin
        Inc(Count);
      end;
    Bar.Prepare(SampleQuery, ['procedure Inner;'], False);
    Assert.AreEqual(0, Count, 'Vorbelegen meldet nichts');
    // Text per Programm löst bei TComboBox kein OnChange aus: wie beim Tippen melden.
    Bar.TextEdit.Text := 'Close';
    Bar.TextEdit.OnChange(Bar.TextEdit);
    Assert.AreEqual(1, Count);
    Assert.AreEqual('Close', Bar.Query.Text);
    Bar.IdentifierBox.Checked := False;
    Assert.AreEqual(2, Count);
    Assert.IsTrue(Bar.CaseBox.Enabled, 'ohne Bezeichner-Modus wieder wählbar');
    Bar.SetCounter('3 von 9');
    Assert.AreEqual('3 von 9', Bar.Counter);
  finally
    Host.Free;
  end;
end;

procedure TAtlasSearchBarTests.EnteringAFieldIsReported;
var
  Host: TForm;
  Bar: TAtlasSearchBar;
  Entered: TArray<TObject>;
begin
  Host := NewHost;
  try
    Bar := NewBar(Host);
    Entered := nil;
    Bar.OnControlEnter :=
      procedure(AControl: TWinControl)
      begin
        Entered := Entered + [AControl];
      end;
    Bar.TextEdit.OnEnter(Bar.TextEdit);
    Bar.ScopeBox.OnEnter(Bar.ScopeBox);
    Bar.IdentifierBox.OnEnter(Bar.IdentifierBox);
    Assert.AreEqual(3, Integer(Length(Entered)));
    Assert.AreSame(Bar.TextEdit, Entered[0]);
    Assert.AreSame(Bar.ScopeBox, Entered[1]);
    Assert.AreSame(Bar.IdentifierBox, Entered[2]);
  finally
    Host.Free;
    Entered := nil;
  end;
end;

procedure PressIn(AControl: TWinControl; AKey: Word; AShift: TShiftState);
var
  Key: Word;
begin
  Key := AKey;
  if AControl is TComboBox then
    TComboBox(AControl).OnKeyDown(AControl, Key, AShift);
  Assert.AreEqual(0, Integer(Key), 'Taste verbraucht');
end;

procedure TAtlasSearchBarTests.FeaturesShowReplaceRegexAndFileScopes;
var
  Host: TForm;
  Bar: TAtlasSearchBar;
begin
  Host := NewHost;
  try
    Bar := NewBar(Host);
    Bar.Prepare(SampleQuery, nil, False);
    // Vorgabe: alles aus wie vor #893.
    Assert.IsFalse(Bar.ToggleButton.Visible);
    Assert.IsFalse(Bar.RegexBox.Visible);
    Bar.ReplaceShown := True;
    Assert.IsFalse(Bar.ReplaceShown, 'ohne search.replace keine Ersetzen-Zeile');
    Assert.AreEqual(2, Integer(Bar.ScopeBox.Items.Count));
    Bar.Features := TAtlasSearchBarFeatures.Create(True, True, True);
    Assert.IsTrue(Bar.ToggleButton.Visible);
    Assert.IsTrue(Bar.RegexBox.Visible);
    Assert.AreEqual(5, Integer(Bar.ScopeBox.Items.Count), 'Unit, Methode, offene Dateien, Projekt, Projektgruppe');
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SearchScopeProject), Bar.ScopeBox.Items[3]);
    Bar.ReplaceShown := True;
    Assert.IsTrue(Bar.ReplaceRow.Visible);
    Bar.RegexBox.Checked := True;
    Assert.IsTrue(Bar.Query.Options.Regex);
    // search.regex aus: Option weg, Suche ohne Regex.
    Bar.Features := TAtlasSearchBarFeatures.Create(True, False, False);
    Assert.IsFalse(Bar.RegexBox.Visible);
    Assert.IsFalse(Bar.Query.Options.Regex);
    Assert.AreEqual(2, Integer(Bar.ScopeBox.Items.Count), 'ohne search.multiFile nur die Bereiche aus #878');
    Bar.Features := TAtlasSearchBarFeatures.Create(False, False, False);
    Assert.IsFalse(Bar.ReplaceShown);
    Assert.IsFalse(Bar.ReplaceRow.Visible);
  finally
    Host.Free;
  end;
end;

procedure TAtlasSearchBarTests.ReplaceKeysCallTheEvents;
var
  Host: TForm;
  Bar: TAtlasSearchBar;
  Log: string;
begin
  Host := NewHost;
  try
    Bar := NewBar(Host);
    Bar.Features := TAtlasSearchBarFeatures.Create(True, True, False);
    Bar.Prepare(SampleQuery, nil, False);
    Bar.ReplaceShown := True;
    Log := '';
    Bar.OnReplace :=
      procedure
      begin
        Log := Log + 'eins;';
      end;
    Bar.OnReplaceAll :=
      procedure
      begin
        Log := Log + 'alle;';
      end;
    Bar.OnStep :=
      procedure(ABackward: Boolean)
      begin
        Log := Log + 'vor;';
      end;
    PressIn(Bar.ReplaceEdit, VK_RETURN, []);
    PressIn(Bar.ReplaceEdit, VK_RETURN, [ssCtrl]);
    Assert.AreEqual('eins;alle;', Log, 'Enter ersetzt einen, Strg+Enter alle');
    Log := '';
    PressIn(Bar.ReplaceEdit, VK_F3, []);
    Assert.AreEqual('vor;', Log, 'F3 springt auch im Ersetzen-Feld');
  finally
    Host.Free;
    Log := '';
  end;
end;

procedure TAtlasSearchBarTests.ErrorAndPreviewShowInTheInfoRow;
var
  Host: TForm;
  Bar: TAtlasSearchBar;
begin
  Host := NewHost;
  try
    Bar := NewBar(Host);
    Bar.Features := TAtlasSearchBarFeatures.Create(True, True, False);
    Bar.Prepare(SampleQuery, nil, False);
    Bar.SetError('missing )');
    Assert.IsTrue(Bar.HasError);
    Assert.AreEqual('Ungültiger Ausdruck: missing )', Bar.InfoText);
    Bar.SetError('');
    Assert.IsFalse(Bar.HasError);
    Assert.AreEqual('', Bar.InfoText);
    Bar.SetPreview('IntToStr(Kunde.Nr)', 'Kunde.Nr.ToString');
    Assert.AreEqual('Vorschau: IntToStr(Kunde.Nr) → Kunde.Nr.ToString', Bar.InfoText);
    Bar.SetNotice('12 Ersetzungen in 3 Dateien');
    Assert.AreEqual('Vorschau: IntToStr(Kunde.Nr) → Kunde.Nr.ToString   ·   12 Ersetzungen in 3 Dateien',
      Bar.InfoText, 'Vorschau und Meldung nach dem Ersetzen');
    Bar.ClearPreview;
    Assert.AreEqual('12 Ersetzungen in 3 Dateien', Bar.InfoText);
  finally
    Host.Free;
  end;
end;

procedure TAtlasSearchBarTests.ArrowKeysWalkTheHistory;
var
  Host: TForm;
  Bar: TAtlasSearchBar;
  Search, Replace: TAtlasSearchHistory;
  Count: Integer;
begin
  Host := NewHost;
  Search := TAtlasSearchHistory.Create(20);
  Replace := TAtlasSearchHistory.Create(20);
  try
    Bar := NewBar(Host);
    Bar.Features := TAtlasSearchBarFeatures.Create(True, False, False);
    Bar.SetHistories(Search, Replace);
    Bar.Prepare(SampleQuery, nil, False);
    Count := 0;
    Bar.OnQueryChanged :=
      procedure
      begin
        Inc(Count);
      end;
    Search.Remember('vorige');
    Search.Remember('Open');
    // Akzeptanzkriterium: Pfeil hoch holt die vorige Suche, auch wenn die letzte im Feld steht.
    PressIn(Bar.TextEdit, VK_UP, []);
    Assert.AreEqual('vorige', Bar.TextEdit.Text);
    Assert.AreEqual(1, Count, 'neue Suche angestoßen');
    PressIn(Bar.TextEdit, VK_DOWN, []);
    PressIn(Bar.TextEdit, VK_DOWN, []);
    Assert.AreEqual('Open', Bar.TextEdit.Text, 'zurück zum getippten Text');
    // Enter merkt den Text; im Ersetzen-Feld nur bei offener Zeile.
    Bar.ReplaceShown := True;
    Bar.ReplaceEdit.Text := '$1.ToString';
    Bar.Remember;
    Assert.AreEqual('$1.ToString', Replace.Items[0]);
    PressIn(Bar.ReplaceEdit, VK_UP, []);
    Assert.AreEqual('$1.ToString', Bar.ReplaceEdit.Text);
  finally
    Host.Free;
    Search.Free;
    Replace.Free;
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
