unit Atlas.Core.Welcome.Search.Tests;

// Tests des Suchfelds der Willkommensseite ohne VCL (#760): Leser für den
// Index-Cache (Format 15) ohne Server, Zuordnung der Caches zu Projekten,
// unscharfe Bewertung mit Tippfehlern, Gruppierung mit Grenze je Gruppe,
// Hinweis statt Symbolen ohne Server und die Liste „Closed Projects“.
// CacheBytes schreibt einen Cache wie Atlas.Common.Index.Cache.Serialize,
// mit gefüllten Symbol- und Verwendungsblöcken, die der Leser überspringt.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Atlas.Core.Welcome.IndexFiles,
  Atlas.Core.Welcome.Search;

type
  [TestFixture]
  TAtlasWelcomeIndexFilesTests = class
  public
    [Test]
    procedure ReadsProjectUnitsWithoutLibrary;
    [Test]
    procedure RejectsOtherVersion;
    [Test]
    procedure RejectsBadChecksum;
    [Test]
    procedure RejectsTruncatedData;
    [Test]
    procedure MainFileAndSameProject;
    [Test]
    procedure FindsCachesOfAllVersionsWithoutLibrary;
    [Test]
    procedure NewestCacheWinsPerProject;
  end;

  [TestFixture]
  TAtlasWelcomeSearchTests = class
  public
    [Test]
    procedure WelFindsFileAndCommand;
    [Test]
    procedure TypoFindsSameFile;
    [Test]
    procedure EmptyPatternFindsNothing;
    [Test]
    procedure GroupsInFixedOrder;
    [Test]
    procedure LimitsEachGroupToFour;
    [Test]
    procedure BetterMatchFirstThenSourceOrder;
    [Test]
    procedure SymbolHintWithoutServer;
    [Test]
    procedure NoSymbolGroupWithoutHintAndHits;
    [Test]
    procedure ServerSymbolsKeepOrder;
    [Test]
    procedure FlattenFollowsDisplayOrder;
    [Test]
    procedure RowsWithHeadersHintAndMore;
    [Test]
    procedure RecentProjectsInOrderWithoutDuplicates;
  end;

implementation

uses
  System.Classes,
  System.DateUtils,
  System.IOUtils;

type
  TUnitSpec = record
    Name: string;
    FileName: string;
    Library_: Boolean;
  end;

function Spec(const AName, AFileName: string; ALibrary: Boolean): TUnitSpec;
begin
  Result.Name := AName;
  Result.FileName := AFileName;
  Result.Library_ := ALibrary;
end;

procedure PutVar(var ABytes: TBytes; AValue: UInt64);
begin
  repeat
    if AValue >= $80 then
      ABytes := ABytes + [Byte((AValue and $7F) or $80)]
    else
      ABytes := ABytes + [Byte(AValue)];
    AValue := AValue shr 7;
  until AValue = 0;
end;

function Checksum(const AData: TBytes; AFrom: Integer): Cardinal;
var
  Index: Integer;
begin
  Result := 2166136261;
  for Index := AFrom to High(AData) do
    Result := Cardinal(UInt64(Result xor AData[Index]) * 16777619);
end;

/// <summary>Cache im Format von Atlas.Common.Index.Cache (Version AVersion).</summary>
function CacheBytes(const AUnits: TArray<TUnitSpec>; AVersion: Integer): TBytes;
var
  Strings: TList<string>;
  Body, Text: TBytes;
  Spec_: TUnitSpec;
  Value: string;
  Index, ChecksumAt: Integer;
  Sum: Cardinal;

  function IndexOf(const AValue: string): Integer;
  begin
    Result := Strings.IndexOf(AValue);
    if Result < 0 then
      Result := Strings.Add(AValue);
  end;

begin
  Strings := TList<string>.Create;
  try
    Strings.Add('');
    Body := nil;
    PutVar(Body, Length(AUnits));
    for Spec_ in AUnits do
    begin
      PutVar(Body, IndexOf(Spec_.Name));
      PutVar(Body, IndexOf(Spec_.FileName));
      PutVar(Body, 2 * 638000000000000000); // Zeitstempel (ZigZag)
      PutVar(Body, IndexOf('HASH-' + Spec_.Name));
      if Spec_.Library_ then
        PutVar(Body, 1 or 8)
      else
        PutVar(Body, 8);
      PutVar(Body, 2); // uses (interface)
      PutVar(Body, IndexOf('System.SysUtils'));
      PutVar(Body, IndexOf('System.Classes'));
      PutVar(Body, 0); // uses (implementation)
      PutVar(Body, 1); // Include-Dateien
      PutVar(Body, IndexOf('Atlas.inc'));
      PutVar(Body, 1); // Include-Zeitstempel
      PutVar(Body, 3); // -2 als ZigZag
      PutVar(Body, 2); // Symbolzahl
      PutVar(Body, 1); // nicht verfügbar
      PutVar(Body, 200); // Blocklänge über ein Byte hinaus
      for Index := 1 to 200 do
        Body := Body + [Byte(Index)];
      PutVar(Body, 1); // Verwendungen
      PutVar(Body, 3);
      Body := Body + [$FF, $80, $01];
    end;
    Result := TEncoding.ASCII.GetBytes('ATLASIDX');
    PutVar(Result, AVersion);
    ChecksumAt := Length(Result);
    Result := Result + [0, 0, 0, 0];
    PutVar(Result, Strings.Count);
    for Value in Strings do
    begin
      Text := TEncoding.UTF8.GetBytes(Value);
      PutVar(Result, Length(Text));
      Result := Result + Text;
    end;
    Result := Result + Body;
    Sum := Checksum(Result, ChecksumAt + 4);
    for Index := 0 to 3 do
      Result[ChecksumAt + Index] := Byte(Sum shr (8 * Index));
  finally
    Strings.Free;
  end;
end;

function SampleUnits: TArray<TUnitSpec>;
begin
  Result := [Spec('Atlas', 'C:\Projekte\Atlas\Atlas.dpr', False),
    Spec('Atlas.IDE.Expert.WelcomePage', 'C:\Projekte\Atlas\Atlas.IDE.Expert.WelcomePage.pas', False),
    Spec('System.SysUtils', 'C:\Delphi\source\rtl\sys\System.SysUtils.pas', True),
    Spec('Haupt', 'C:\Projekte\Atlas\Haupt.pas', False)];
end;

function TempFolder: string;
begin
  Result := IncludeTrailingPathDelimiter(TPath.GetTempPath) + 'atlas-760-' + IntToStr(Random(MaxInt));
  ForceDirectories(Result);
end;

procedure WriteCache(const AFileName: string; const AUnits: TArray<TUnitSpec>; AAge: TDateTime);
var
  Stream: TFileStream;
  Data: TBytes;
begin
  ForceDirectories(ExtractFileDir(AFileName));
  Data := CacheBytes(AUnits, TAtlasWelcomeIndexFiles.FormatVersion);
  Stream := TFileStream.Create(AFileName, fmCreate);
  try
    Stream.WriteBuffer(Data[0], Length(Data));
  finally
    Stream.Free;
  end;
  FileSetDate(AFileName, DateTimeToFileDate(AAge));
end;

procedure RemoveTree(const AFolder: string);
var
  Search: TSearchRec;
  Path: string;
begin
  Path := IncludeTrailingPathDelimiter(AFolder);
  if FindFirst(Path + '*', faAnyFile, Search) = 0 then
    try
      repeat
        if (Search.Name = '.') or (Search.Name = '..') then
          Continue;
        if (Search.Attr and faDirectory) <> 0 then
          RemoveTree(Path + Search.Name)
        else
          DeleteFile(Path + Search.Name);
      until FindNext(Search) <> 0;
    finally
      FindClose(Search);
    end;
  RemoveDir(AFolder);
end;

{ TAtlasWelcomeIndexFilesTests }

procedure TAtlasWelcomeIndexFilesTests.ReadsProjectUnitsWithoutLibrary;
var
  Files: TArray<TAtlasIndexFile>;
  Reason: string;
begin
  Files := TAtlasWelcomeIndexFiles.Read(CacheBytes(SampleUnits, 15), Reason);
  Assert.AreEqual('', Reason);
  Assert.AreEqual(3, Integer(Length(Files)));
  Assert.AreEqual('Atlas', Files[0].UnitName);
  Assert.AreEqual('C:\Projekte\Atlas\Atlas.IDE.Expert.WelcomePage.pas', Files[1].FileName);
  Assert.AreEqual('Haupt', Files[2].UnitName);
end;

procedure TAtlasWelcomeIndexFilesTests.RejectsOtherVersion;
var
  Reason: string;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasWelcomeIndexFiles.Read(CacheBytes(SampleUnits, 14), Reason))));
  Assert.AreEqual('andere Formatversion', Reason);
  Assert.AreEqual(0, Integer(Length(TAtlasWelcomeIndexFiles.Read(TEncoding.ASCII.GetBytes('{"units":[]}'), Reason))));
  Assert.AreNotEqual('', Reason);
end;

procedure TAtlasWelcomeIndexFilesTests.RejectsBadChecksum;
var
  Data: TBytes;
  Reason: string;
begin
  Data := CacheBytes(SampleUnits, 15);
  Data[High(Data) - 10] := Data[High(Data) - 10] xor $55;
  Assert.AreEqual(0, Integer(Length(TAtlasWelcomeIndexFiles.Read(Data, Reason))));
  Assert.AreEqual('Prüfsumme stimmt nicht', Reason);
end;

procedure TAtlasWelcomeIndexFilesTests.RejectsTruncatedData;
var
  Data, Cut: TBytes;
  Sum: Cardinal;
  Index: Integer;
  Reason: string;
begin
  // Abgeschnitten, Prüfsumme passend neu berechnet: der Inhalt selbst muss auffallen.
  Data := CacheBytes(SampleUnits, 15);
  Cut := Copy(Data, 0, Length(Data) - 50);
  Sum := Checksum(Cut, 13);
  for Index := 0 to 3 do
    Cut[9 + Index] := Byte(Sum shr (8 * Index));
  Assert.AreEqual(0, Integer(Length(TAtlasWelcomeIndexFiles.Read(Cut, Reason))));
  Assert.AreEqual('Inhalt beschädigt', Reason);
end;

procedure TAtlasWelcomeIndexFilesTests.MainFileAndSameProject;
var
  Files: TArray<TAtlasIndexFile>;
begin
  Files := TAtlasWelcomeIndexFiles.Read(CacheBytes(SampleUnits, 15));
  Assert.AreEqual('C:\Projekte\Atlas\Atlas.dpr', TAtlasWelcomeIndexFiles.MainFileOf(Files));
  Assert.IsTrue(TAtlasWelcomeIndexFiles.SameProject('c:\projekte\atlas\Atlas.dproj', 'C:\Projekte\Atlas\Atlas.dpr'));
  Assert.IsFalse(TAtlasWelcomeIndexFiles.SameProject('C:\Projekte\Atlas\AtlasTests.dproj',
    'C:\Projekte\Atlas\Atlas.dpr'));
  Assert.IsFalse(TAtlasWelcomeIndexFiles.SameProject('', ''));
  Assert.AreEqual('', TAtlasWelcomeIndexFiles.MainFileOf(nil));
end;

procedure TAtlasWelcomeIndexFilesTests.FindsCachesOfAllVersionsWithoutLibrary;
var
  Root: string;
  Found: TArray<string>;
begin
  Root := TempFolder;
  try
    WriteCache(Root + PathDelim + 'Index' + PathDelim + '23.0' + PathDelim + 'AAAA' + PathDelim + 'index.atlasidx',
      SampleUnits, Now);
    WriteCache(Root + PathDelim + 'Index' + PathDelim + '37.0' + PathDelim + 'BBBB' + PathDelim + 'index.atlasidx',
      SampleUnits, Now);
    WriteCache(Root + PathDelim + 'Index' + PathDelim + '37.0' + PathDelim + 'Bibliothek' + PathDelim +
      'index.atlasidx', SampleUnits, Now);
    ForceDirectories(Root + PathDelim + 'Index' + PathDelim + '37.0' + PathDelim + 'LEER');
    Found := TAtlasWelcomeIndexFiles.CacheFiles(Root);
    Assert.AreEqual(2, Integer(Length(Found)));
    Assert.AreEqual(0, Integer(Length(TAtlasWelcomeIndexFiles.CacheFiles(Root + PathDelim + 'fehlt'))));
  finally
    RemoveTree(Root);
  end;
end;

procedure TAtlasWelcomeIndexFilesTests.NewestCacheWinsPerProject;
var
  Root: string;
  Projects: TAtlasIndexProjects;
  List: TArray<TAtlasIndexProject>;
begin
  Root := TempFolder;
  Projects := TAtlasIndexProjects.Create(Root);
  try
    // Zwei Konfigurationen desselben Projekts und ein zweites Projekt.
    WriteCache(Root + PathDelim + 'Index' + PathDelim + '37.0' + PathDelim + 'DEBUG' + PathDelim + 'index.atlasidx',
      SampleUnits, IncDay(Now, -3));
    WriteCache(Root + PathDelim + 'Index' + PathDelim + '37.0' + PathDelim + 'RELEASE' + PathDelim +
      'index.atlasidx', [Spec('Atlas', 'C:\Projekte\Atlas\Atlas.dpr', False),
      Spec('Neu', 'C:\Projekte\Atlas\Neu.pas', False)], IncDay(Now, -1));
    WriteCache(Root + PathDelim + 'Index' + PathDelim + '37.0' + PathDelim + 'TOOLS' + PathDelim + 'index.atlasidx',
      [Spec('Tools', 'C:\Projekte\Tools\Tools.dpk', False)], IncDay(Now, -2));
    Projects.Refresh;
    List := Projects.Projects;
    Assert.AreEqual(2, Integer(Length(List)));
    Assert.AreEqual('C:\Projekte\Atlas\Atlas.dpr', List[0].MainFile);
    Assert.AreEqual('C:\Projekte\Tools\Tools.dpk', List[1].MainFile);
    Assert.AreEqual('Neu', Projects.FilesOf('C:\Projekte\Atlas\Atlas.dproj')[1].UnitName);
    Assert.AreEqual(0, Integer(Length(Projects.FilesOf('C:\Projekte\Fremd\Fremd.dproj'))));
    // Gelöschter Cache verschwindet beim nächsten Refresh.
    RemoveTree(Root + PathDelim + 'Index' + PathDelim + '37.0' + PathDelim + 'TOOLS');
    Projects.Refresh;
    Assert.AreEqual(1, Integer(Length(Projects.Projects)));
  finally
    Projects.Free;
    RemoveTree(Root);
  end;
end;

{ TAtlasWelcomeSearchTests }

function FileHit(const AName, AProject: string): TAtlasWelcomeHit;
begin
  Result := TAtlasWelcomeHit.Create(TAtlasWelcomeSearchGroup.Files, AName, AProject, 'C:\P\' + AName);
  Result.Project := AProject;
end;

function CommandHit(const ACaption, AId: string): TAtlasWelcomeHit;
begin
  Result := TAtlasWelcomeHit.Create(TAtlasWelcomeSearchGroup.Commands, ACaption, '', AId);
  Result.Alias := AId.Replace('Atlas.', '');
end;

function Candidates: TArray<TAtlasWelcomeHit>;
begin
  Result := [TAtlasWelcomeHit.Create(TAtlasWelcomeSearchGroup.Projects, 'Atlas', 'C:\Projekte\Atlas',
    'C:\Projekte\Atlas\Atlas.dproj'),
    FileHit('Atlas.IDE.Expert.WelcomePage.pas', 'Atlas'),
    FileHit('Haupt.pas', 'Atlas'),
    CommandHit('Atlas-Layout anwenden', 'Atlas.WelcomeApply'),
    CommandHit('Protokoll zeigen', 'Atlas.Log')];
end;

function GroupOf(const AResults: TArray<TAtlasWelcomeSearchResult>; AGroup: TAtlasWelcomeSearchGroup;
  out AResult: TAtlasWelcomeSearchResult): Boolean;
var
  Entry: TAtlasWelcomeSearchResult;
begin
  for Entry in AResults do
    if Entry.Group = AGroup then
    begin
      AResult := Entry;
      Exit(True);
    end;
  Result := False;
end;

procedure TAtlasWelcomeSearchTests.WelFindsFileAndCommand;
var
  Results: TArray<TAtlasWelcomeSearchResult>;
  Group: TAtlasWelcomeSearchResult;
begin
  Results := TAtlasWelcomeSearch.Search('wel', Candidates, '');
  Assert.IsTrue(GroupOf(Results, TAtlasWelcomeSearchGroup.Files, Group));
  Assert.AreEqual(1, Integer(Length(Group.Hits)));
  Assert.AreEqual('Atlas.IDE.Expert.WelcomePage.pas', Group.Hits[0].Caption);
  Assert.IsTrue(GroupOf(Results, TAtlasWelcomeSearchGroup.Commands, Group));
  Assert.AreEqual(1, Integer(Length(Group.Hits)));
  Assert.AreEqual('Atlas-Layout anwenden', Group.Hits[0].Caption);
  Assert.IsFalse(GroupOf(Results, TAtlasWelcomeSearchGroup.Projects, Group));
end;

procedure TAtlasWelcomeSearchTests.TypoFindsSameFile;
var
  Results: TArray<TAtlasWelcomeSearchResult>;
  Group: TAtlasWelcomeSearchResult;
begin
  Results := TAtlasWelcomeSearch.Search('Wlecome', Candidates, '');
  Assert.IsTrue(GroupOf(Results, TAtlasWelcomeSearchGroup.Files, Group));
  Assert.AreEqual('Atlas.IDE.Expert.WelcomePage.pas', Group.Hits[0].Caption);
  Assert.IsTrue(Group.Hits[0].Score < 200);
  // Zu viele Fehler: kein Treffer.
  Assert.AreEqual(TAtlasWelcomeSearch.NoMatch, TAtlasWelcomeSearch.Score('Wxyzome', 'Atlas.IDE.Expert.WelcomePage.pas'));
  // Kurze Muster ohne Tippfehler-Toleranz.
  Assert.AreEqual(TAtlasWelcomeSearch.NoMatch, TAtlasWelcomeSearch.Score('Wx', 'WelcomePage'));
end;

procedure TAtlasWelcomeSearchTests.EmptyPatternFindsNothing;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasWelcomeSearch.Search('', Candidates, ''))));
  Assert.AreEqual(0, Integer(Length(TAtlasWelcomeSearch.Search('   ', Candidates, ''))));
end;

procedure TAtlasWelcomeSearchTests.GroupsInFixedOrder;
var
  Results: TArray<TAtlasWelcomeSearchResult>;
begin
  // "a" passt auf Projekt, Dateien und Befehle; Kandidaten in gemischter Reihenfolge.
  Results := TAtlasWelcomeSearch.Search('a', [Candidates[3], Candidates[1], Candidates[0]], 'Hinweis');
  Assert.AreEqual(4, Integer(Length(Results)));
  Assert.IsTrue(Results[0].Group = TAtlasWelcomeSearchGroup.Projects);
  Assert.IsTrue(Results[1].Group = TAtlasWelcomeSearchGroup.Files);
  Assert.IsTrue(Results[2].Group = TAtlasWelcomeSearchGroup.Symbols);
  Assert.IsTrue(Results[3].Group = TAtlasWelcomeSearchGroup.Commands);
end;

procedure TAtlasWelcomeSearchTests.LimitsEachGroupToFour;
var
  Hits: TArray<TAtlasWelcomeHit>;
  Index: Integer;
  Results: TArray<TAtlasWelcomeSearchResult>;
begin
  Hits := nil;
  for Index := 1 to 7 do
    Hits := Hits + [FileHit(Format('Unit%d.pas', [Index]), 'P')];
  for Index := 1 to 2 do
    Hits := Hits + [CommandHit(Format('Unit-Befehl %d', [Index]), 'Atlas.U' + IntToStr(Index))];
  Results := TAtlasWelcomeSearch.Search('unit', Hits, '');
  Assert.AreEqual(2, Integer(Length(Results)));
  Assert.AreEqual(4, Integer(Length(Results[0].Hits)));
  Assert.AreEqual(3, Results[0].More);
  Assert.AreEqual(2, Integer(Length(Results[1].Hits)));
  Assert.AreEqual(0, Results[1].More);
  Results := TAtlasWelcomeSearch.Search('unit', Hits, '', 2);
  Assert.AreEqual(2, Integer(Length(Results[0].Hits)));
  Assert.AreEqual(5, Results[0].More);
end;

procedure TAtlasWelcomeSearchTests.BetterMatchFirstThenSourceOrder;
var
  Results: TArray<TAtlasWelcomeSearchResult>;
begin
  Results := TAtlasWelcomeSearch.Search('haupt',
    [FileHit('Nebenhaupt.pas', 'P'), FileHit('Haupt.pas', 'P'), FileHit('HauptForm.pas', 'P'),
    FileHit('HauptDaten.pas', 'P')], '');
  Assert.AreEqual('Haupt.pas', Results[0].Hits[0].Caption);
  // Gleiche Stufe: Reihenfolge der Quelle (zuletzt geöffnet zuerst).
  Assert.AreEqual('HauptForm.pas', Results[0].Hits[1].Caption);
  Assert.AreEqual('HauptDaten.pas', Results[0].Hits[2].Caption);
  Assert.AreEqual('Nebenhaupt.pas', Results[0].Hits[3].Caption);
end;

procedure TAtlasWelcomeSearchTests.SymbolHintWithoutServer;
var
  Results: TArray<TAtlasWelcomeSearchResult>;
  Group: TAtlasWelcomeSearchResult;
begin
  Results := TAtlasWelcomeSearch.Search('wel', Candidates, 'Symbole nach dem Öffnen eines Projekts');
  Assert.IsTrue(GroupOf(Results, TAtlasWelcomeSearchGroup.Symbols, Group));
  Assert.AreEqual(0, Integer(Length(Group.Hits)));
  Assert.AreEqual('Symbole nach dem Öffnen eines Projekts', Group.Hint);
  // Auch wenn sonst nichts passt, steht der Hinweis da.
  Assert.AreEqual(1, Integer(Length(TAtlasWelcomeSearch.Search('qqq', Candidates, 'Hinweis'))));
end;

procedure TAtlasWelcomeSearchTests.NoSymbolGroupWithoutHintAndHits;
var
  Group: TAtlasWelcomeSearchResult;
begin
  // welcomePage.search.symbols aus: keine Kandidaten, kein Hinweis, keine Gruppe.
  Assert.IsFalse(GroupOf(TAtlasWelcomeSearch.Search('wel', Candidates, ''), TAtlasWelcomeSearchGroup.Symbols,
    Group));
end;

procedure TAtlasWelcomeSearchTests.ServerSymbolsKeepOrder;
var
  First, Second: TAtlasWelcomeHit;
  Results: TArray<TAtlasWelcomeSearchResult>;
begin
  First := TAtlasWelcomeHit.Create(TAtlasWelcomeSearchGroup.Symbols, 'TWelcomeBoard', 'Atlas.UI', 'a.pas');
  First.Prefiltered := True;
  Second := TAtlasWelcomeHit.Create(TAtlasWelcomeSearchGroup.Symbols, 'Wel', 'Atlas.UI', 'b.pas');
  Second.Prefiltered := True;
  Results := TAtlasWelcomeSearch.Search('wel', [First, Second], 'Hinweis');
  Assert.AreEqual(1, Integer(Length(Results)));
  Assert.AreEqual('TWelcomeBoard', Results[0].Hits[0].Caption);
  Assert.AreEqual('Wel', Results[0].Hits[1].Caption);
  Assert.AreEqual('', Results[0].Hint);
end;

procedure TAtlasWelcomeSearchTests.FlattenFollowsDisplayOrder;
var
  Flat: TArray<TAtlasWelcomeHit>;
begin
  Flat := TAtlasWelcomeSearch.Flatten(TAtlasWelcomeSearch.Search('a', Candidates, 'Hinweis'));
  Assert.IsTrue(Flat[0].Group = TAtlasWelcomeSearchGroup.Projects);
  Assert.IsTrue(Flat[High(Flat)].Group = TAtlasWelcomeSearchGroup.Commands);
end;

procedure TAtlasWelcomeSearchTests.RowsWithHeadersHintAndMore;
var
  Hits: TArray<TAtlasWelcomeHit>;
  Index: Integer;
  Rows: TArray<TAtlasWelcomeSearchRow>;
begin
  Hits := [CommandHit('Unit-Befehl', 'Atlas.U')];
  for Index := 1 to 6 do
    Hits := Hits + [FileHit(Format('Unit%d.pas', [Index]), 'P')];
  Rows := TAtlasWelcomeSearch.Rows(TAtlasWelcomeSearch.Search('unit', Hits, 'Hinweis'));
  // Dateien: Kopf, 4 Treffer, „2 weitere“; Symbole: Kopf, Hinweis; Befehle: Kopf, Treffer.
  Assert.AreEqual(10, Integer(Length(Rows)));
  Assert.IsTrue(Rows[0].Kind = TAtlasWelcomeRowKind.Group);
  Assert.IsTrue(Rows[0].Group = TAtlasWelcomeSearchGroup.Files);
  Assert.AreEqual(0, Rows[1].Index);
  Assert.AreEqual(3, Rows[4].Index);
  Assert.IsTrue(Rows[5].Kind = TAtlasWelcomeRowKind.More);
  Assert.AreEqual(2, Rows[5].Index);
  Assert.IsTrue(Rows[7].Kind = TAtlasWelcomeRowKind.Hint);
  Assert.AreEqual('Hinweis', Rows[7].Text);
  Assert.IsTrue(Rows[9].Kind = TAtlasWelcomeRowKind.Hit);
  Assert.AreEqual(4, Rows[9].Index);
end;

procedure TAtlasWelcomeSearchTests.RecentProjectsInOrderWithoutDuplicates;
var
  Projects: TArray<string>;
begin
  Projects := TAtlasWelcomeSearch.RecentProjects([
    TPair<string, string>.Create('File_10', 'TProject,C:\P\Zehn.dproj,0,0'),
    TPair<string, string>.Create('File_0', 'TProjectGroup,C:\P\Gruppe.groupproj,1'),
    TPair<string, string>.Create('File_1', 'TProject,c:\p\gruppe.groupproj'),
    TPair<string, string>.Create('File_2', 'C:\P\Ohne Klasse.dproj'),
    TPair<string, string>.Create('File_3', 'TProject,Relativ.dproj'),
    TPair<string, string>.Create('Max Closed Files', '10')]);
  Assert.AreEqual(3, Integer(Length(Projects)));
  Assert.AreEqual('C:\P\Gruppe.groupproj', Projects[0]);
  Assert.AreEqual('C:\P\Ohne Klasse.dproj', Projects[1]);
  Assert.AreEqual('C:\P\Zehn.dproj', Projects[2]);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeIndexFilesTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeSearchTests);

end.
