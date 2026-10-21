unit Atlas.UI.Search.Bar.Tests;

// Suchleiste der Atlas-Suche (#878): Felder nach der Suche setzen und
// zurücklesen, Bereich Auswahl nur mit Auswahl, Füllen erst mit Fenster,
// Tasten Enter/Umschalt+Enter/F3/Esc und Meldung jeder Änderung.

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
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Winapi.Windows,
  Vcl.Controls,
  Vcl.Forms,
  Atlas.Core.Search.Matching,
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
    Assert.AreEqual(2, Bar.ScopeBox.Items.Count, 'Methode und Unit, keine Auswahl');
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
    Assert.AreEqual(3, Bar.ScopeBox.Items.Count);
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
    Assert.AreEqual(2, Bar.ScopeBox.Items.Count);
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
    Bar.TextEdit.Text := 'Close';
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

initialization
  TDUnitX.RegisterTestFixture(TAtlasSearchBarTests);

end.
