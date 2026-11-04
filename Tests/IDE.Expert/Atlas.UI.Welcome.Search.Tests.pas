unit Atlas.UI.Welcome.Search.Tests;

// Tests des Suchfelds der Willkommensseite.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasWelcomeSearchBoxTests = class
  public
    [Test]
    procedure HeaderShowsAndHidesSearch;
    [Test]
    procedure QueryFillsHitsAndRows;
    [Test]
    procedure SelectStaysInRange;
    [Test]
    procedure OpenSelectedHandsHitAndClears;
    [Test]
    procedure GroupCaptionsFollowLanguage;
  end;

implementation

uses
  System.Classes,
  Winapi.Windows,
  System.SysUtils,
  Atlas.UI.Strings,
  Atlas.UI.Welcome.Header,
  Atlas.Core.Welcome.Search,
  Atlas.UI.Welcome.Search;

{ TAtlasWelcomeSearchBoxTests }

function SampleQuery: TAtlasWelcomeSearchQuery;
begin
  Result :=
    function(const APattern: string): TArray<TAtlasWelcomeSearchResult>
    var
      Hits: TArray<TAtlasWelcomeHit>;
    begin
      Hits := [TAtlasWelcomeHit.Create(TAtlasWelcomeSearchGroup.Files, 'Atlas.IDE.Expert.WelcomePage.pas', 'Atlas',
        'C:\P\Atlas.IDE.Expert.WelcomePage.pas'),
        TAtlasWelcomeHit.Create(TAtlasWelcomeSearchGroup.Files, 'Welcome.pas', 'Atlas', 'C:\P\Welcome.pas'),
        TAtlasWelcomeHit.Create(TAtlasWelcomeSearchGroup.Commands, 'Atlas-Start', '', 'Atlas.WelcomeStart')];
      Hits[2].Alias := 'WelcomeStart';
      Result := TAtlasWelcomeSearch.Search(APattern, Hits, 'Hinweis');
    end;
end;
procedure TAtlasWelcomeSearchBoxTests.HeaderShowsAndHidesSearch;
var
  Header: TAtlasWelcomeHeaderFrame;
begin
  Header := TAtlasWelcomeHeaderFrame.Create(nil);
  try
    Assert.IsNull(Header.Search);
    Assert.AreEqual(0, Header.SearchHost.Width);
    Header.ShowSearch(True);
    Assert.IsNotNull(Header.Search);
    Assert.IsTrue(Header.Search.Visible);
    Assert.IsTrue(Header.SearchHost.Width > 0);
    Header.Search.Edit.Text := 'wel';
    Header.ShowSearch(False);
    Assert.IsFalse(Header.Search.Visible);
    Assert.AreEqual('', Header.Search.Edit.Text);
    Assert.AreEqual(0, Header.SearchHost.Width);
  finally
    Header.Free;
  end;
end;
procedure TAtlasWelcomeSearchBoxTests.QueryFillsHitsAndRows;
var
  Box: TAtlasWelcomeSearchBox;
begin
  Box := TAtlasWelcomeSearchBox.Create(nil);
  try
    Box.OnQuery := SampleQuery();
    Box.Edit.Text := 'wel';
    Box.Query;
    // Dateien (2), Symbole mit Hinweis, Befehle (1).
    Assert.AreEqual(3, Integer(Length(Box.Hits)));
    Assert.AreEqual(3, Integer(Length(Box.Results)));
    Assert.AreEqual(7, Integer(Length(Box.Rows)));
    Assert.AreEqual(0, Box.Selected);
    Box.Edit.Text := '';
    Assert.AreEqual(0, Integer(Length(Box.Hits)));
    Assert.AreEqual(-1, Box.Selected);
  finally
    Box.Free;
  end;
end;
procedure TAtlasWelcomeSearchBoxTests.SelectStaysInRange;
var
  Box: TAtlasWelcomeSearchBox;
begin
  Box := TAtlasWelcomeSearchBox.Create(nil);
  try
    Box.OnQuery := SampleQuery();
    Box.Edit.Text := 'wel';
    Box.Query;
    Box.Select(-5);
    Assert.AreEqual(0, Box.Selected);
    Box.Select(2);
    Assert.AreEqual(2, Box.Selected);
    Box.Select(9);
    Assert.AreEqual(2, Box.Selected);
  finally
    Box.Free;
  end;
end;
procedure TAtlasWelcomeSearchBoxTests.OpenSelectedHandsHitAndClears;
var
  Box: TAtlasWelcomeSearchBox;
  Opened: string;
begin
  Opened := '';
  Box := TAtlasWelcomeSearchBox.Create(nil);
  try
    Box.OnQuery := SampleQuery();
    Box.OnOpen :=
      procedure(const AHit: TAtlasWelcomeHit)
      begin
        Opened := AHit.Target;
      end;
    Box.Edit.Text := 'wel';
    Box.Query;
    Box.Select(2);
    Box.OpenSelected;
    // Geöffnet wird nach dem Schließen der Liste über die Warteschlange.
    Assert.AreEqual('', Box.Edit.Text);
    Assert.AreEqual(0, Integer(Length(Box.Hits)));
    CheckSynchronize;
    Assert.AreEqual('Atlas.WelcomeStart', Opened);
    // Esc bzw. Clear ohne Treffer öffnet nichts.
    Opened := '';
    Box.OpenSelected;
    CheckSynchronize;
    Assert.AreEqual('', Opened);
  finally
    Box.Free;
  end;
end;
procedure TAtlasWelcomeSearchBoxTests.GroupCaptionsFollowLanguage;
var
  Saved: TAtlasLanguage;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('Projekte', TAtlasWelcomeSearchBox.GroupCaption(TAtlasWelcomeSearchGroup.Projects));
    Assert.AreEqual('Befehle', TAtlasWelcomeSearchBox.GroupCaption(TAtlasWelcomeSearchGroup.Commands));
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('Files', TAtlasWelcomeSearchBox.GroupCaption(TAtlasWelcomeSearchGroup.Files));
    Assert.AreEqual('Symbols', TAtlasWelcomeSearchBox.GroupCaption(TAtlasWelcomeSearchGroup.Symbols));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeSearchBoxTests);

end.
