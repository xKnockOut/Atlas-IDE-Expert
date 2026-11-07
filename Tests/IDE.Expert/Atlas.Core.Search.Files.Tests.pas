unit Atlas.Core.Search.Files.Tests;

// Tests für die Atlas-Suche über mehrere Dateien (#893): Quellen (einmal,
// nur Quelltexte, Puffer vor Platte, aktive Datei zuerst), Lauf mit Abbruch
// und übersprungenen Dateien, Laden von der Platte, F3 über Dateien.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Search')]
  TAtlasSearchFilesTests = class
  private
    FFolder: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure SourcesAreUniqueSourceFilesWithBuffersFirst;
    [Test]
    procedure RunReportsFilesWithHitsAndSkipsBinaryAndUnreadable;
    [Test]
    procedure RunStopsWhenCancelled;
    [Test]
    procedure DiskLoaderReadsEncodedFiles;
    [Test]
    procedure NextLocationWalksAcrossFiles;
    [Test]
    procedure NextLocationStartsOutsideTheResults;
    [Test]
    procedure SpansFilesOnlyForTheFileScopes;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  Atlas.Core.Search.Matching,
  Atlas.Core.Search.Scopes,
  Atlas.Core.Search.Files;

function Query(const AText: string): TAtlasSearchQuery;
begin
  Result := Default(TAtlasSearchQuery);
  Result.Text := AText;
  Result.Options := TAtlasSearchOptions.Create(False, False, False);
end;

function Names(const ASources: TArray<TAtlasSearchSource>): string;
var
  mSource: TAtlasSearchSource;
begin
  Result := '';
  for mSource in ASources do
  begin
    if Result <> '' then
    begin
      Result := Result + ' ';
    end;
    Result := Result + ExtractFileName(mSource.FileName);
    if mSource.HasText then
    begin
      Result := Result + '*';
    end;
  end;
end;

procedure TAtlasSearchFilesTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'AtlasSearchFiles' + IntToStr(Random(1000000)));
  TDirectory.CreateDirectory(FFolder);
end;

procedure TAtlasSearchFilesTests.TearDown;
begin
  if TDirectory.Exists(FFolder) then
  begin
    TDirectory.Delete(FFolder, True);
  end;
  FFolder := '';
end;

procedure TAtlasSearchFilesTests.SourcesAreUniqueSourceFilesWithBuffersFirst;
var
  mSources: TArray<TAtlasSearchSource>;
begin
  mSources := TAtlasFileSearch.Sources(TArray<string>.Create('C:\P\A.pas', 'C:\P\B.pas', 'c:\p\a.PAS',
    'C:\P\Projekt.dproj', 'C:\P\Bild.png', 'C:\P\Form.dfm', 'C:\P\Main.dpr', 'C:\P\X.inc'),
    TArray<TAtlasSearchSource>.Create(TAtlasSearchSource.FromBuffer('C:\P\b.pas', 'ungespeichert')), 'C:\P\Main.dpr');
  Assert.AreEqual('Main.dpr A.pas B.pas* Form.dfm X.inc', Names(mSources));
  Assert.AreEqual('ungespeichert', mSources[2].Text, 'Puffer der IDE vor der Platte');
  // Die aktive Datei steht nur vorn, wenn sie zum Bereich gehört.
  mSources := TAtlasFileSearch.Sources(TArray<string>.Create('C:\P\A.pas'), nil, 'C:\Q\Fremd.pas');
  Assert.AreEqual('A.pas', Names(mSources));
end;

procedure TAtlasSearchFilesTests.RunReportsFilesWithHitsAndSkipsBinaryAndUnreadable;
var
  mSources: TArray<TAtlasSearchSource>;
  mFound: TArray<string>;
  mSummary: TAtlasFileSearchSummary;
  mLoad: TAtlasSearchLoader;
  mReport: TProc<TAtlasFileHits>;
begin
  mSources := TArray<TAtlasSearchSource>.Create(TAtlasSearchSource.FromBuffer('A.pas', 'foo foo'),
    TAtlasSearchSource.FromDisk('B.pas'), TAtlasSearchSource.FromDisk('Fehlt.pas'),
    TAtlasSearchSource.FromDisk('Binaer.dfm'), TAtlasSearchSource.FromDisk('Leer.pas'));
  mLoad :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := AFileName <> 'Fehlt.pas';
      AText := '';
      if AFileName = 'B.pas' then
      begin
        AText := 'x' + #13#10 + 'Foo';
      end;
      if AFileName = 'Binaer.dfm' then
      begin
        AText := 'TPF0'#0'foo';
      end;
      if AFileName = 'Leer.pas' then
      begin
        AText := 'nichts';
      end;
    end;
  mFound := nil;
  mReport :=
    procedure(AHits: TAtlasFileHits)
    begin
      mFound := mFound + [Format('%s:%d', [AHits.FileName, Length(AHits.Hits)])];
    end;
  mSummary := TAtlasFileSearch.Run(mSources, Query('foo'), mLoad, nil, mReport);
  Assert.AreEqual('A.pas:2 B.pas:1', string.Join(' ', mFound));
  Assert.AreEqual(3, mSummary.Files);
  Assert.AreEqual(2, mSummary.FilesWithHits);
  Assert.AreEqual(3, mSummary.Hits);
  Assert.AreEqual(2, mSummary.Skipped, 'fehlende und binäre Datei');
  Assert.IsFalse(mSummary.Cancelled);
end;

procedure TAtlasSearchFilesTests.RunStopsWhenCancelled;
var
  mSources: TArray<TAtlasSearchSource>;
  mCount: Integer;
  mSummary: TAtlasFileSearchSummary;
  mCancelled: TFunc<Boolean>;
  mReport: TProc<TAtlasFileHits>;
begin
  mSources := TArray<TAtlasSearchSource>.Create(TAtlasSearchSource.FromBuffer('A.pas', 'foo'),
    TAtlasSearchSource.FromBuffer('B.pas', 'foo'), TAtlasSearchSource.FromBuffer('C.pas', 'foo'));
  mCount := 0;
  mCancelled :=
    function: Boolean
    begin
      Result := mCount >= 1;
    end;
  mReport :=
    procedure(AHits: TAtlasFileHits)
    begin
      Inc(mCount);
    end;
  mSummary := TAtlasFileSearch.Run(mSources, Query('foo'), nil, mCancelled, mReport);
  Assert.AreEqual(1, mCount);
  Assert.IsTrue(mSummary.Cancelled);
end;

procedure TAtlasSearchFilesTests.DiskLoaderReadsEncodedFiles;
var
  mFileName, mText: string;
  mLoad: TAtlasSearchLoader;
begin
  mFileName := TPath.Combine(FFolder, 'Umlaut.pas');
  TFile.WriteAllText(mFileName, 'Größe := 1;', TEncoding.UTF8);
  mLoad := TAtlasFileSearch.DiskLoader();
  Assert.IsTrue(mLoad(mFileName, mText));
  Assert.AreEqual('Größe := 1;', mText);
  Assert.IsFalse(mLoad(TPath.Combine(FFolder, 'Fehlt.pas'), mText));
end;

function Results: TArray<TAtlasFileHits>;
begin
  Result := TArray<TAtlasFileHits>.Create(TAtlasFileSearch.SearchText('A.pas', 'foo' + #13#10 + 'foo', Query('foo')),
    TAtlasFileSearch.SearchText('B.pas', 'nichts', Query('foo')),
    TAtlasFileSearch.SearchText('C.pas', 'x foo', Query('foo')));
end;

procedure TAtlasSearchFilesTests.NextLocationWalksAcrossFiles;
var
  mLocation: TAtlasFileLocation;
begin
  Assert.IsTrue(TAtlasFileSearch.NextLocation(Results, 'a.pas', TAtlasSearchPos.Create(0, 1), False,
    mLocation));
  Assert.AreEqual(0, mLocation.FileIndex);
  Assert.AreEqual(1, mLocation.HitIndex);
  // Hinter dem letzten Treffer von A geht es mit C weiter (B hat keinen).
  Assert.IsTrue(TAtlasFileSearch.NextLocation(Results, 'A.pas', TAtlasSearchPos.Create(1, 3), False,
    mLocation));
  Assert.AreEqual(2, mLocation.FileIndex);
  Assert.AreEqual(0, mLocation.HitIndex);
  Assert.IsFalse(mLocation.Wrapped);
  // Hinter C von vorn.
  Assert.IsTrue(TAtlasFileSearch.NextLocation(Results, 'C.pas', TAtlasSearchPos.Create(0, 5), False,
    mLocation));
  Assert.AreEqual(0, mLocation.FileIndex);
  Assert.AreEqual(0, mLocation.HitIndex);
  Assert.IsTrue(mLocation.Wrapped);
  // Rückwärts vor dem ersten Treffer von C: letzter Treffer von A.
  Assert.IsTrue(TAtlasFileSearch.NextLocation(Results, 'C.pas', TAtlasSearchPos.Create(0, 2), True,
    mLocation));
  Assert.AreEqual(0, mLocation.FileIndex);
  Assert.AreEqual(1, mLocation.HitIndex);
  Assert.IsFalse(mLocation.Wrapped);
  Assert.IsFalse(TAtlasFileSearch.NextLocation(nil, 'A.pas', TAtlasSearchPos.Create(0, 0), False,
    mLocation));
  Assert.AreEqual(3, TAtlasFileSearch.HitCount(Results));
end;

procedure TAtlasSearchFilesTests.NextLocationStartsOutsideTheResults;
var
  mLocation: TAtlasFileLocation;
begin
  Assert.IsTrue(TAtlasFileSearch.NextLocation(Results, 'Fremd.pas', TAtlasSearchPos.Create(9, 9), False,
    mLocation));
  Assert.AreEqual(0, mLocation.FileIndex);
  Assert.AreEqual(0, mLocation.HitIndex);
  Assert.IsTrue(TAtlasFileSearch.NextLocation(Results, 'Fremd.pas', TAtlasSearchPos.Create(9, 9), True,
    mLocation));
  Assert.AreEqual(2, mLocation.FileIndex);
  Assert.AreEqual(0, mLocation.HitIndex);
end;

procedure TAtlasSearchFilesTests.SpansFilesOnlyForTheFileScopes;
begin
  Assert.IsFalse(TAtlasSearchScopes.SpansFiles(TAtlasSearchScope.UnitFile));
  Assert.IsFalse(TAtlasSearchScopes.SpansFiles(TAtlasSearchScope.Method));
  Assert.IsFalse(TAtlasSearchScopes.SpansFiles(TAtlasSearchScope.Selection));
  Assert.IsTrue(TAtlasSearchScopes.SpansFiles(TAtlasSearchScope.OpenFiles));
  Assert.IsTrue(TAtlasSearchScopes.SpansFiles(TAtlasSearchScope.Project));
  Assert.IsTrue(TAtlasSearchScopes.SpansFiles(TAtlasSearchScope.ProjectGroup));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSearchFilesTests);

end.
