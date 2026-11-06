unit Shell.Composition.Navigation.Tests;

// Navigation des Servers: Lesezeichen der Projektdateien kommen über die Dienste der Komposition, die Namensräume
// des Projekts bei den Navigationen an.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Documents.Contract,
  Shell.Composition.Navigation;

type
  [TestFixture]
  TShellNavigationTests = class
  private
    FDocuments: IDocumentStore;
    FReads: Integer;
    function NewServices: TShellNavigationServices;
    function ReadMarked(const AFileName: string; out AText: string): Boolean;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Lesezeichen einer Projektdatei auf der Platte liest die Navigation über den Dienst.</summary>
    [Test]
    procedure CollectsBookmarksOfProjectFiles;
    /// <summary>Unveränderte Dateien liest die Navigation nur einmal; das Öffnen im Editor liest neu.</summary>
    [Test]
    procedure ReadsAgainOnlyAfterOpening;
    /// <summary>Gesetzte Namensräume liest die Navigation unverändert zurück.</summary>
    [Test]
    procedure SetNamespacesReachesNavigation;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Editing.Bookmarks;

const
  cFileName = '/tmp/atlas-navigation-tests/A.pas';
  cDiskText = '// @bookmark Platte'#10'unit A;'#10'end.'#10;
  cEditorText = '// @bookmark Editor'#10'unit A;'#10'end.'#10;

function OneProjectFile: TArray<string>;
begin
  Result := TArray<string>.Create(cFileName);
end;

procedure TShellNavigationTests.Setup;
begin
  FDocuments := TDocumentStore.Create;
  FReads := 0;
end;

procedure TShellNavigationTests.TearDown;
begin
  FDocuments := nil;
end;

function TShellNavigationTests.ReadMarked(const AFileName: string; out AText: string): Boolean;
begin
  Inc(FReads);
  AText := cDiskText;
  Result := True;
end;

function TShellNavigationTests.NewServices: TShellNavigationServices;
begin
  Result := Default(TShellNavigationServices);
  Result.Documents := FDocuments;
  Result.ReadText := ReadMarked;
  Result.ProjectFiles := OneProjectFile;
end;

procedure TShellNavigationTests.CollectsBookmarksOfProjectFiles;
var
  mNavigation: TShellNavigation;
  mHits: TArray<TBookmarkHit>;
begin
  mNavigation := TShellNavigation.Create(NewServices);
  try
    mHits := mNavigation.CollectBookmarks;
    Assert.AreEqual(1, Integer(Length(mHits)));
    Assert.AreEqual('Platte', mHits[0].Bookmark.Name);
    Assert.AreEqual(cFileName, mHits[0].FileName);
  finally
    mNavigation.Free;
  end;
end;

procedure TShellNavigationTests.ReadsAgainOnlyAfterOpening;
var
  mNavigation: TShellNavigation;
begin
  mNavigation := TShellNavigation.Create(NewServices);
  try
    mNavigation.CollectBookmarks;
    mNavigation.CollectBookmarks;
    Assert.AreEqual(1, FReads);
    FDocuments.Open(TDocumentUris.FromPath(cFileName), 'pascal', 1, cEditorText);
    mNavigation.CollectBookmarks;
    Assert.AreEqual(2, FReads);
  finally
    mNavigation.Free;
  end;
end;

procedure TShellNavigationTests.SetNamespacesReachesNavigation;
var
  mNavigation: TShellNavigation;
  mNamespaces: TArray<string>;
begin
  mNavigation := TShellNavigation.Create(NewServices);
  try
    mNavigation.SetNamespaces(TArray<string>.Create('System', 'Vcl'));
    mNamespaces := mNavigation.Namespaces;
    Assert.AreEqual(2, Integer(Length(mNamespaces)));
    Assert.AreEqual('Vcl', mNamespaces[1]);
  finally
    mNavigation.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TShellNavigationTests);

end.
