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
  mHeader: TAtlasWelcomeHeaderFrame;
begin
  mHeader := TAtlasWelcomeHeaderFrame.Create(nil);
  try
    Assert.IsNull(mHeader.Search);
    Assert.AreEqual(0, mHeader.SearchHost.Width);
    mHeader.ShowSearch(True);
    Assert.IsNotNull(mHeader.Search);
    Assert.IsTrue(mHeader.Search.Visible);
    Assert.IsTrue(mHeader.SearchHost.Width > 0);
    mHeader.Search.Edit.Text := 'wel';
    mHeader.ShowSearch(False);
    Assert.IsFalse(mHeader.Search.Visible);
    Assert.AreEqual('', mHeader.Search.Edit.Text);
    Assert.AreEqual(0, mHeader.SearchHost.Width);
  finally
    mHeader.Free;
  end;
end;
procedure TAtlasWelcomeSearchBoxTests.QueryFillsHitsAndRows;
var
  mBox: TAtlasWelcomeSearchBox;
begin
  mBox := TAtlasWelcomeSearchBox.Create(nil);
  try
    mBox.OnQuery := SampleQuery();
    mBox.Edit.Text := 'wel';
    mBox.Query;
    // Dateien (2), Symbole mit Hinweis, Befehle (1).
    Assert.AreEqual(3, Integer(Length(mBox.Hits)));
    Assert.AreEqual(3, Integer(Length(mBox.Results)));
    Assert.AreEqual(7, Integer(Length(mBox.Rows)));
    Assert.AreEqual(0, mBox.Selected);
    mBox.Edit.Text := '';
    Assert.AreEqual(0, Integer(Length(mBox.Hits)));
    Assert.AreEqual(-1, mBox.Selected);
  finally
    mBox.Free;
  end;
end;
procedure TAtlasWelcomeSearchBoxTests.SelectStaysInRange;
var
  mBox: TAtlasWelcomeSearchBox;
begin
  mBox := TAtlasWelcomeSearchBox.Create(nil);
  try
    mBox.OnQuery := SampleQuery();
    mBox.Edit.Text := 'wel';
    mBox.Query;
    mBox.Select(-5);
    Assert.AreEqual(0, mBox.Selected);
    mBox.Select(2);
    Assert.AreEqual(2, mBox.Selected);
    mBox.Select(9);
    Assert.AreEqual(2, mBox.Selected);
  finally
    mBox.Free;
  end;
end;
procedure TAtlasWelcomeSearchBoxTests.OpenSelectedHandsHitAndClears;
var
  mBox: TAtlasWelcomeSearchBox;
  mOpened: string;
begin
  mOpened := '';
  mBox := TAtlasWelcomeSearchBox.Create(nil);
  try
    mBox.OnQuery := SampleQuery();
    mBox.OnOpen :=
      procedure(const AHit: TAtlasWelcomeHit)
      begin
        mOpened := AHit.Target;
      end;
    mBox.Edit.Text := 'wel';
    mBox.Query;
    mBox.Select(2);
    mBox.OpenSelected;
    // Geöffnet wird nach dem Schließen der Liste über die Warteschlange.
    Assert.AreEqual('', mBox.Edit.Text);
    Assert.AreEqual(0, Integer(Length(mBox.Hits)));
    CheckSynchronize;
    Assert.AreEqual('Atlas.WelcomeStart', mOpened);
    // Esc bzw. Clear ohne Treffer öffnet nichts.
    mOpened := '';
    mBox.OpenSelected;
    CheckSynchronize;
    Assert.AreEqual('', mOpened);
  finally
    mBox.Free;
  end;
end;
procedure TAtlasWelcomeSearchBoxTests.GroupCaptionsFollowLanguage;
var
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('Projekte', TAtlasWelcomeSearchBox.GroupCaption(TAtlasWelcomeSearchGroup.Projects));
    Assert.AreEqual('Befehle', TAtlasWelcomeSearchBox.GroupCaption(TAtlasWelcomeSearchGroup.Commands));
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('Files', TAtlasWelcomeSearchBox.GroupCaption(TAtlasWelcomeSearchGroup.Files));
    Assert.AreEqual('Symbols', TAtlasWelcomeSearchBox.GroupCaption(TAtlasWelcomeSearchGroup.Symbols));
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeSearchBoxTests);

end.
