unit Atlas.Core.Search.Files.Tests;

// Tests für die Atlas-Suche über mehrere Dateien (#893): Quellen (einmal,
// nur Quelltexte, Puffer vor Platte, aktive Datei zuerst), Lauf mit Abbruch
// und übersprungenen Dateien, Laden von der Platte, F3 über Dateien.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
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
  Source: TAtlasSearchSource;
begin
  Result := '';
  for Source in ASources do
  begin
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + ExtractFileName(Source.FileName);
    if Source.HasText then
      Result := Result + '*';
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
    TDirectory.Delete(FFolder, True);
  FFolder := '';
end;

procedure TAtlasSearchFilesTests.SourcesAreUniqueSourceFilesWithBuffersFirst;
var
  Sources: TArray<TAtlasSearchSource>;
begin
  Sources := TAtlasFileSearch.Sources(TArray<string>.Create('C:\P\A.pas', 'C:\P\B.pas', 'c:\p\a.PAS',
    'C:\P\Projekt.dproj', 'C:\P\Bild.png', 'C:\P\Form.dfm', 'C:\P\Main.dpr', 'C:\P\X.inc'),
    TArray<TAtlasSearchSource>.Create(TAtlasSearchSource.FromBuffer('C:\P\b.pas', 'ungespeichert')), 'C:\P\Main.dpr');
  Assert.AreEqual('Main.dpr A.pas B.pas* Form.dfm X.inc', Names(Sources));
  Assert.AreEqual('ungespeichert', Sources[2].Text, 'Puffer der IDE vor der Platte');
  // Die aktive Datei steht nur vorn, wenn sie zum Bereich gehört.
  Sources := TAtlasFileSearch.Sources(TArray<string>.Create('C:\P\A.pas'), nil, 'C:\Q\Fremd.pas');
  Assert.AreEqual('A.pas', Names(Sources));
end;

procedure TAtlasSearchFilesTests.RunReportsFilesWithHitsAndSkipsBinaryAndUnreadable;
var
  Sources: TArray<TAtlasSearchSource>;
  Found: TArray<string>;
  Summary: TAtlasFileSearchSummary;
  Load: TAtlasSearchLoader;
  Report: TProc<TAtlasFileHits>;
begin
  Sources := TArray<TAtlasSearchSource>.Create(TAtlasSearchSource.FromBuffer('A.pas', 'foo foo'),
    TAtlasSearchSource.FromDisk('B.pas'), TAtlasSearchSource.FromDisk('Fehlt.pas'),
    TAtlasSearchSource.FromDisk('Binaer.dfm'), TAtlasSearchSource.FromDisk('Leer.pas'));
  Load :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := AFileName <> 'Fehlt.pas';
      AText := '';
      if AFileName = 'B.pas' then
        AText := 'x' + #13#10 + 'Foo';
      if AFileName = 'Binaer.dfm' then
        AText := 'TPF0'#0'foo';
      if AFileName = 'Leer.pas' then
        AText := 'nichts';
    end;
  Found := nil;
  Report :=
    procedure(AHits: TAtlasFileHits)
    begin
      Found := Found + [Format('%s:%d', [AHits.FileName, Length(AHits.Hits)])];
    end;
  Summary := TAtlasFileSearch.Run(Sources, Query('foo'), Load, nil, Report);
  Assert.AreEqual('A.pas:2 B.pas:1', string.Join(' ', Found));
  Assert.AreEqual(3, Summary.Files);
  Assert.AreEqual(2, Summary.FilesWithHits);
  Assert.AreEqual(3, Summary.Hits);
  Assert.AreEqual(2, Summary.Skipped, 'fehlende und binäre Datei');
  Assert.IsFalse(Summary.Cancelled);
end;

procedure TAtlasSearchFilesTests.RunStopsWhenCancelled;
var
  Sources: TArray<TAtlasSearchSource>;
  Count: Integer;
  Summary: TAtlasFileSearchSummary;
  Cancelled: TFunc<Boolean>;
  Report: TProc<TAtlasFileHits>;
begin
  Sources := TArray<TAtlasSearchSource>.Create(TAtlasSearchSource.FromBuffer('A.pas', 'foo'),
    TAtlasSearchSource.FromBuffer('B.pas', 'foo'), TAtlasSearchSource.FromBuffer('C.pas', 'foo'));
  Count := 0;
  Cancelled :=
    function: Boolean
    begin
      Result := Count >= 1;
    end;
  Report :=
    procedure(AHits: TAtlasFileHits)
    begin
      Inc(Count);
    end;
  Summary := TAtlasFileSearch.Run(Sources, Query('foo'), nil, Cancelled, Report);
  Assert.AreEqual(1, Count);
  Assert.IsTrue(Summary.Cancelled);
end;

procedure TAtlasSearchFilesTests.DiskLoaderReadsEncodedFiles;
var
  FileName, Text: string;
  Load: TAtlasSearchLoader;
begin
  FileName := TPath.Combine(FFolder, 'Umlaut.pas');
  TFile.WriteAllText(FileName, 'Größe := 1;', TEncoding.UTF8);
  Load := TAtlasFileSearch.DiskLoader;
  Assert.IsTrue(Load(FileName, Text));
  Assert.AreEqual('Größe := 1;', Text);
  Assert.IsFalse(Load(TPath.Combine(FFolder, 'Fehlt.pas'), Text));
end;

function Results: TArray<TAtlasFileHits>;
begin
  Result := TArray<TAtlasFileHits>.Create(TAtlasFileSearch.SearchText('A.pas', 'foo' + #13#10 + 'foo', Query('foo')),
    TAtlasFileSearch.SearchText('B.pas', 'nichts', Query('foo')),
    TAtlasFileSearch.SearchText('C.pas', 'x foo', Query('foo')));
end;

procedure TAtlasSearchFilesTests.NextLocationWalksAcrossFiles;
var
  FileIndex, HitIndex: Integer;
  Wrapped: Boolean;
begin
  Assert.IsTrue(TAtlasFileSearch.NextLocation(Results, 'a.pas', TAtlasSearchPos.Create(0, 1), False, FileIndex,
    HitIndex, Wrapped));
  Assert.AreEqual(0, FileIndex);
  Assert.AreEqual(1, HitIndex);
  // Hinter dem letzten Treffer von A geht es mit C weiter (B hat keinen).
  Assert.IsTrue(TAtlasFileSearch.NextLocation(Results, 'A.pas', TAtlasSearchPos.Create(1, 3), False, FileIndex,
    HitIndex, Wrapped));
  Assert.AreEqual(2, FileIndex);
  Assert.AreEqual(0, HitIndex);
  Assert.IsFalse(Wrapped);
  // Hinter C von vorn.
  Assert.IsTrue(TAtlasFileSearch.NextLocation(Results, 'C.pas', TAtlasSearchPos.Create(0, 5), False, FileIndex,
    HitIndex, Wrapped));
  Assert.AreEqual(0, FileIndex);
  Assert.AreEqual(0, HitIndex);
  Assert.IsTrue(Wrapped);
  // Rückwärts vor dem ersten Treffer von C: letzter Treffer von A.
  Assert.IsTrue(TAtlasFileSearch.NextLocation(Results, 'C.pas', TAtlasSearchPos.Create(0, 2), True, FileIndex,
    HitIndex, Wrapped));
  Assert.AreEqual(0, FileIndex);
  Assert.AreEqual(1, HitIndex);
  Assert.IsFalse(Wrapped);
  Assert.IsFalse(TAtlasFileSearch.NextLocation(nil, 'A.pas', TAtlasSearchPos.Create(0, 0), False, FileIndex,
    HitIndex, Wrapped));
  Assert.AreEqual(3, TAtlasFileSearch.HitCount(Results));
end;

procedure TAtlasSearchFilesTests.NextLocationStartsOutsideTheResults;
var
  FileIndex, HitIndex: Integer;
  Wrapped: Boolean;
begin
  Assert.IsTrue(TAtlasFileSearch.NextLocation(Results, 'Fremd.pas', TAtlasSearchPos.Create(9, 9), False, FileIndex,
    HitIndex, Wrapped));
  Assert.AreEqual(0, FileIndex);
  Assert.AreEqual(0, HitIndex);
  Assert.IsTrue(TAtlasFileSearch.NextLocation(Results, 'Fremd.pas', TAtlasSearchPos.Create(9, 9), True, FileIndex,
    HitIndex, Wrapped));
  Assert.AreEqual(2, FileIndex);
  Assert.AreEqual(0, HitIndex);
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
