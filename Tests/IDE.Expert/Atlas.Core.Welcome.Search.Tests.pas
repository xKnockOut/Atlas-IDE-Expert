unit Atlas.Core.Welcome.Search.Tests;

// Tests des Suchfelds der Willkommensseite ohne VCL (#760): Leser für den
// Index-Cache (aktuelle Formatversion) ohne Server, Zuordnung der Caches zu Projekten,
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
  [Category('Atlas.IDE.Welcome')]
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
    [Test]
    procedure FormatVersionMatchesServer;
    [Test]
    procedure FindsLibraryCachesPerKey;
    /// <summary>Den Cache, den der Server schreibt, liest das Plugin (#1326): Die Konstanten allein sichern das
    /// Format nicht, #1123 hatte den Unit-Kopf erweitert.</summary>
    [Test]
    procedure ReadsCacheOfServer;
  end;

  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
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
  System.IOUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Cache,
  Atlas.Common.Index.Adapters.CacheDirectory;

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
    begin
      ABytes := ABytes + [Byte((AValue and $7F) or $80)];
    end
    else
    begin
      ABytes := ABytes + [Byte(AValue)];
    end;
    AValue := AValue shr 7;
  until AValue = 0;
end;

function Checksum(const AData: TBytes; AFrom: Integer): Cardinal;
var
  mIndex: Integer;
begin
  Result := 2166136261;
  for mIndex := AFrom to High(AData) do
  begin
    Result := Cardinal(UInt64(Result xor AData[mIndex]) * 16777619);
  end;
end;

/// <summary>Nummer von AValue in der Stringtabelle; neue Werte werden angehängt.</summary>
function StringIndex(const AStrings: TList<string>; const AValue: string): Integer;
begin
  Result := AStrings.IndexOf(AValue);
  if Result < 0 then
  begin
    Result := AStrings.Add(AValue);
  end;
end;

/// <summary>Ein Unit-Satz des Index-Caches mit allen Abschnitten der aktuellen Fassung.</summary>
procedure PutUnitRecord(var ABody: TBytes; const AStrings: TList<string>; const ASpec: TUnitSpec);
var
  mIndex: Integer;
begin
  PutVar(ABody, StringIndex(AStrings, ASpec.Name));
  PutVar(ABody, StringIndex(AStrings, ASpec.FileName));
  PutVar(ABody, 2 * 638000000000000000); // Zeitstempel (ZigZag)
  PutVar(ABody, StringIndex(AStrings, 'HASH-' + ASpec.Name));
  if ASpec.Library_ then
  begin
    PutVar(ABody, 1 or 8);
  end
  else
  begin
    PutVar(ABody, 8);
  end;
  PutVar(ABody, 2); // uses (interface)
  PutVar(ABody, StringIndex(AStrings, 'System.SysUtils'));
  PutVar(ABody, StringIndex(AStrings, 'System.Classes'));
  PutVar(ABody, 0); // uses (implementation)
  PutVar(ABody, 1); // Include-Dateien
  PutVar(ABody, StringIndex(AStrings, 'Atlas.inc'));
  PutVar(ABody, 1); // Include-Zeitstempel
  PutVar(ABody, 3); // -2 als ZigZag
  for mIndex := 1 to 6 do
  begin
    PutVar(ABody, mIndex);
  end; // Präfix-Zählung (#452)
  PutVar(ABody, 1); // Hinweise im Unit-Kopf (#1018)
  PutVar(ABody, StringIndex(AStrings, 'deprecated'));
  PutVar(ABody, StringIndex(AStrings, 'Nutze Neu')); // Grund
  PutVar(ABody, 1); // Begründungen der Unit (#1123)
  PutVar(ABody, StringIndex(AStrings, 'W|3|Weil'));
  PutVar(ABody, 2); // Symbolzahl
  PutVar(ABody, 1); // nicht verfügbar
  PutVar(ABody, 200); // Blocklänge über ein Byte hinaus
  for mIndex := 1 to 200 do
  begin
    ABody := ABody + [Byte(mIndex)];
  end;
  PutVar(ABody, 1); // Verwendungen
  PutVar(ABody, 3);
  ABody := ABody + [$FF, $80, $01];
end;

/// <summary>Cache im Format von Atlas.Common.Index.Cache (Version AVersion).</summary>
function CacheBytes(const AUnits: TArray<TUnitSpec>; AVersion: Integer): TBytes;
var
  mStrings: TList<string>;
  mBody, mText: TBytes;
  mSpec_: TUnitSpec;
  mValue: string;
  mIndex, mChecksumAt: Integer;
  mSum: Cardinal;
begin
  mStrings := TList<string>.Create;
  try
    mStrings.Add('');
    mBody := nil;
    PutVar(mBody, Length(AUnits));
    for mSpec_ in AUnits do
    begin
      PutUnitRecord(mBody, mStrings, mSpec_);
    end;
    Result := TEncoding.ASCII.GetBytes('ATLASIDX');
    PutVar(Result, AVersion);
    mChecksumAt := Length(Result);
    Result := Result + [0, 0, 0, 0];
    PutVar(Result, mStrings.Count);
    for mValue in mStrings do
    begin
      mText := TEncoding.UTF8.GetBytes(mValue);
      PutVar(Result, Length(mText));
      Result := Result + mText;
    end;
    Result := Result + mBody;
    mSum := Checksum(Result, mChecksumAt + 4);
    for mIndex := 0 to 3 do
    begin
      Result[mChecksumAt + mIndex] := Byte(mSum shr (8 * mIndex));
    end;
  finally
    mStrings.Free;
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
  mStream: TFileStream;
  mData: TBytes;
begin
  ForceDirectories(ExtractFileDir(AFileName));
  mData := CacheBytes(AUnits, TAtlasWelcomeIndexFiles.cFormatVersion);
  mStream := TFileStream.Create(AFileName, fmCreate);
  try
    mStream.WriteBuffer(mData[0], Length(mData));
  finally
    mStream.Free;
  end;
  FileSetDate(AFileName, DateTimeToFileDate(AAge));
end;

procedure RemoveTree(const AFolder: string);
var
  mSearch: TSearchRec;
  mPath: string;
begin
  mPath := IncludeTrailingPathDelimiter(AFolder);
  if FindFirst(mPath + '*', faAnyFile, mSearch) = 0 then
    try
      repeat
        if (mSearch.Name = '.') or (mSearch.Name = '..') then
        begin
          Continue;
        end;
        if (mSearch.Attr and faDirectory) <> 0 then
        begin
          RemoveTree(mPath + mSearch.Name);
        end
        else
        begin
          DeleteFile(mPath + mSearch.Name);
        end;
      until FindNext(mSearch) <> 0;
    finally
      FindClose(mSearch);
    end;
  RemoveDir(AFolder);
end;

{ TAtlasWelcomeIndexFilesTests }

procedure TAtlasWelcomeIndexFilesTests.ReadsProjectUnitsWithoutLibrary;
var
  mFiles: TArray<TAtlasIndexFile>;
  mReason: string;
begin
  mFiles := TAtlasWelcomeIndexFiles.Read(CacheBytes(SampleUnits, TAtlasWelcomeIndexFiles.cFormatVersion), mReason);
  Assert.AreEqual('', mReason);
  Assert.AreEqual(3, Integer(Length(mFiles)));
  Assert.AreEqual('Atlas', mFiles[0].UnitName);
  Assert.AreEqual('C:\Projekte\Atlas\Atlas.IDE.Expert.WelcomePage.pas', mFiles[1].FileName);
  Assert.AreEqual('Haupt', mFiles[2].UnitName);
end;

procedure TAtlasWelcomeIndexFilesTests.RejectsOtherVersion;
var
  mReason: string;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasWelcomeIndexFiles.Read(CacheBytes(SampleUnits, 15), mReason))));
  Assert.AreEqual('andere Formatversion', mReason);
  Assert.AreEqual(0, Integer(Length(TAtlasWelcomeIndexFiles.Read(TEncoding.ASCII.GetBytes('{"units":[]}'), mReason))));
  Assert.AreNotEqual('', mReason);
end;

procedure TAtlasWelcomeIndexFilesTests.FormatVersionMatchesServer;
begin
  // Code-Review K-05: Plugin und Server lesen dasselbe Cache-Format.
  Assert.AreEqual(TIndexCache.cFormatVersion, TAtlasWelcomeIndexFiles.cFormatVersion,
    'Plugin und Server lesen dasselbe Cache-Format; beide Konstanten zusammen erhöhen.');
end;

procedure TAtlasWelcomeIndexFilesTests.FindsLibraryCachesPerKey;
var
  mRoot, mLibrary: string;
  mFound: TArray<string>;
begin
  // Der Server legt die Bibliothek je Schlüssel ab (Bibliothek\<Hash>\index-<Format>.atlasidx); Caches ohne
  // Format im Namen stammen von älteren Servern und zählen nicht.
  mRoot := TempFolder;
  try
    mLibrary := mRoot + PathDelim + 'Index' + PathDelim + '37.0' + PathDelim + 'Bibliothek' + PathDelim;
    WriteCache(mLibrary + 'WIN64' + PathDelim + TAtlasWelcomeIndexFiles.CacheFileName, SampleUnits, Now);
    WriteCache(mLibrary + 'WIN32' + PathDelim + TAtlasWelcomeIndexFiles.CacheFileName, SampleUnits, Now);
    WriteCache(mLibrary + 'ALT' + PathDelim + 'index.atlasidx', SampleUnits, Now);
    mFound := TAtlasWelcomeIndexFiles.LibraryCacheFiles(mRoot);
    Assert.AreEqual(2, Integer(Length(mFound)));
    Assert.AreEqual(TIndexCacheDirectory.CacheFileName, TAtlasWelcomeIndexFiles.CacheFileName,
      'Plugin und Server suchen dieselbe Datei.');
  finally
    RemoveTree(mRoot);
  end;
end;

procedure TAtlasWelcomeIndexFilesTests.ReadsCacheOfServer;
var
  mUnit: TUnitIndex;
  mFiles: TArray<TAtlasIndexFile>;
  mReason: string;
begin
  mUnit := Default(TUnitIndex);
  mUnit.UnitName := 'Haupt';
  mUnit.FileName := 'C:\Projekte\Atlas\Haupt.pas';
  mUnit.Directives := ['deprecated'];
  mUnit.DeprecatedText := 'Nutze Neu';
  mUnit.Rationale := ['W|3|Weil'];
  mFiles := TAtlasWelcomeIndexFiles.Read(TIndexCache.Serialize([mUnit]), mReason);
  Assert.AreEqual('', mReason);
  Assert.AreEqual(1, Integer(Length(mFiles)));
  Assert.AreEqual('C:\Projekte\Atlas\Haupt.pas', mFiles[0].FileName);
end;

procedure TAtlasWelcomeIndexFilesTests.RejectsBadChecksum;
var
  mData: TBytes;
  mReason: string;
begin
  mData := CacheBytes(SampleUnits, TAtlasWelcomeIndexFiles.cFormatVersion);
  mData[High(mData) - 10] := mData[High(mData) - 10] xor $55;
  Assert.AreEqual(0, Integer(Length(TAtlasWelcomeIndexFiles.Read(mData, mReason))));
  Assert.AreEqual('Prüfsumme stimmt nicht', mReason);
end;

procedure TAtlasWelcomeIndexFilesTests.RejectsTruncatedData;
var
  mData, mCut: TBytes;
  mSum: Cardinal;
  mIndex: Integer;
  mReason: string;
begin
  // Abgeschnitten, Prüfsumme passend neu berechnet: der Inhalt selbst muss auffallen.
  mData := CacheBytes(SampleUnits, TAtlasWelcomeIndexFiles.cFormatVersion);
  mCut := Copy(mData, 0, Length(mData) - 50);
  mSum := Checksum(mCut, 13);
  for mIndex := 0 to 3 do
  begin
    mCut[9 + mIndex] := Byte(mSum shr (8 * mIndex));
  end;
  Assert.AreEqual(0, Integer(Length(TAtlasWelcomeIndexFiles.Read(mCut, mReason))));
  Assert.AreEqual('Inhalt beschädigt', mReason);
end;

procedure TAtlasWelcomeIndexFilesTests.MainFileAndSameProject;
var
  mFiles: TArray<TAtlasIndexFile>;
begin
  mFiles := TAtlasWelcomeIndexFiles.Read(CacheBytes(SampleUnits, TAtlasWelcomeIndexFiles.cFormatVersion));
  Assert.AreEqual('C:\Projekte\Atlas\Atlas.dpr', TAtlasWelcomeIndexFiles.MainFileOf(mFiles));
  Assert.IsTrue(TAtlasWelcomeIndexFiles.SameProject('c:\projekte\atlas\Atlas.dproj', 'C:\Projekte\Atlas\Atlas.dpr'));
  Assert.IsFalse(TAtlasWelcomeIndexFiles.SameProject('C:\Projekte\Atlas\AtlasTests.dproj',
    'C:\Projekte\Atlas\Atlas.dpr'));
  Assert.IsFalse(TAtlasWelcomeIndexFiles.SameProject('', ''));
  Assert.AreEqual('', TAtlasWelcomeIndexFiles.MainFileOf(nil));
end;

procedure TAtlasWelcomeIndexFilesTests.FindsCachesOfAllVersionsWithoutLibrary;
var
  mRoot: string;
  mFound: TArray<string>;
begin
  mRoot := TempFolder;
  try
    WriteCache(mRoot + PathDelim + 'Index' + PathDelim + '23.0' + PathDelim + 'AAAA' + PathDelim +
      TAtlasWelcomeIndexFiles.CacheFileName,
      SampleUnits, Now);
    WriteCache(mRoot + PathDelim + 'Index' + PathDelim + '37.0' + PathDelim + 'BBBB' + PathDelim +
      TAtlasWelcomeIndexFiles.CacheFileName,
      SampleUnits, Now);
    WriteCache(mRoot + PathDelim + 'Index' + PathDelim + '37.0' + PathDelim + 'Bibliothek' + PathDelim +
      TAtlasWelcomeIndexFiles.CacheFileName, SampleUnits, Now);
    ForceDirectories(mRoot + PathDelim + 'Index' + PathDelim + '37.0' + PathDelim + 'LEER');
    mFound := TAtlasWelcomeIndexFiles.CacheFiles(mRoot);
    Assert.AreEqual(2, Integer(Length(mFound)));
    Assert.AreEqual(0, Integer(Length(TAtlasWelcomeIndexFiles.CacheFiles(mRoot + PathDelim + 'fehlt'))));
  finally
    RemoveTree(mRoot);
  end;
end;

procedure TAtlasWelcomeIndexFilesTests.NewestCacheWinsPerProject;
var
  mRoot: string;
  mProjects: TAtlasIndexProjects;
  mList: TArray<TAtlasIndexProject>;
begin
  mRoot := TempFolder;
  mProjects := TAtlasIndexProjects.Create(mRoot);
  try
    // Zwei Konfigurationen desselben Projekts und ein zweites Projekt.
    WriteCache(mRoot + PathDelim + 'Index' + PathDelim + '37.0' + PathDelim + 'DEBUG' + PathDelim +
      TAtlasWelcomeIndexFiles.CacheFileName,
      SampleUnits, IncDay(Now, -3));
    WriteCache(mRoot + PathDelim + 'Index' + PathDelim + '37.0' + PathDelim + 'RELEASE' + PathDelim +
      TAtlasWelcomeIndexFiles.CacheFileName, [Spec('Atlas', 'C:\Projekte\Atlas\Atlas.dpr', False),
      Spec('Neu', 'C:\Projekte\Atlas\Neu.pas', False)], IncDay(Now, -1));
    WriteCache(mRoot + PathDelim + 'Index' + PathDelim + '37.0' + PathDelim + 'TOOLS' + PathDelim +
      TAtlasWelcomeIndexFiles.CacheFileName,
      [Spec('Tools', 'C:\Projekte\Tools\Tools.dpk', False)], IncDay(Now, -2));
    mProjects.Refresh;
    mList := mProjects.Projects;
    Assert.AreEqual(2, Integer(Length(mList)));
    Assert.AreEqual('C:\Projekte\Atlas\Atlas.dpr', mList[0].MainFile);
    Assert.AreEqual('C:\Projekte\Tools\Tools.dpk', mList[1].MainFile);
    Assert.AreEqual('Neu', mProjects.FilesOf('C:\Projekte\Atlas\Atlas.dproj')[1].UnitName);
    Assert.AreEqual(0, Integer(Length(mProjects.FilesOf('C:\Projekte\Fremd\Fremd.dproj'))));
    // Gelöschter Cache verschwindet beim nächsten Refresh.
    RemoveTree(mRoot + PathDelim + 'Index' + PathDelim + '37.0' + PathDelim + 'TOOLS');
    mProjects.Refresh;
    Assert.AreEqual(1, Integer(Length(mProjects.Projects)));
  finally
    mProjects.Free;
    RemoveTree(mRoot);
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
    CommandHit('Atlas-Start', 'Atlas.WelcomeStart'),
    CommandHit('Protokoll zeigen', 'Atlas.Log')];
end;

function GroupOf(const AResults: TArray<TAtlasWelcomeSearchResult>; AGroup: TAtlasWelcomeSearchGroup;
  out AResult: TAtlasWelcomeSearchResult): Boolean;
var
  mEntry: TAtlasWelcomeSearchResult;
begin
  for mEntry in AResults do
  begin
    if mEntry.Group = AGroup then
    begin
      AResult := mEntry;
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TAtlasWelcomeSearchTests.WelFindsFileAndCommand;
var
  mResults: TArray<TAtlasWelcomeSearchResult>;
  mGroup: TAtlasWelcomeSearchResult;
begin
  mResults := TAtlasWelcomeSearch.Search('wel', Candidates, '');
  Assert.IsTrue(GroupOf(mResults, TAtlasWelcomeSearchGroup.Files, mGroup));
  Assert.AreEqual(1, Integer(Length(mGroup.Hits)));
  Assert.AreEqual('Atlas.IDE.Expert.WelcomePage.pas', mGroup.Hits[0].Caption);
  Assert.IsTrue(GroupOf(mResults, TAtlasWelcomeSearchGroup.Commands, mGroup));
  Assert.AreEqual(1, Integer(Length(mGroup.Hits)));
  Assert.AreEqual('Atlas-Start', mGroup.Hits[0].Caption);
  Assert.IsFalse(GroupOf(mResults, TAtlasWelcomeSearchGroup.Projects, mGroup));
end;

procedure TAtlasWelcomeSearchTests.TypoFindsSameFile;
var
  mResults: TArray<TAtlasWelcomeSearchResult>;
  mGroup: TAtlasWelcomeSearchResult;
begin
  mResults := TAtlasWelcomeSearch.Search('Wlecome', Candidates, '');
  Assert.IsTrue(GroupOf(mResults, TAtlasWelcomeSearchGroup.Files, mGroup));
  Assert.AreEqual('Atlas.IDE.Expert.WelcomePage.pas', mGroup.Hits[0].Caption);
  Assert.IsTrue(mGroup.Hits[0].Score < 200);
  // Zu viele Fehler: kein Treffer.
  Assert.AreEqual(TAtlasWelcomeSearch.cNoMatch, TAtlasWelcomeSearch.Score('Wxyzome', 'Atlas.IDE.Expert.WelcomePage.pas'));
  // Kurze Muster ohne Tippfehler-Toleranz.
  Assert.AreEqual(TAtlasWelcomeSearch.cNoMatch, TAtlasWelcomeSearch.Score('Wx', 'WelcomePage'));
end;

procedure TAtlasWelcomeSearchTests.EmptyPatternFindsNothing;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasWelcomeSearch.Search('', Candidates, ''))));
  Assert.AreEqual(0, Integer(Length(TAtlasWelcomeSearch.Search('   ', Candidates, ''))));
end;

procedure TAtlasWelcomeSearchTests.GroupsInFixedOrder;
var
  mResults: TArray<TAtlasWelcomeSearchResult>;
begin
  // "a" passt auf Projekt, Dateien und Befehle; Kandidaten in gemischter Reihenfolge.
  mResults := TAtlasWelcomeSearch.Search('a', [Candidates[3], Candidates[1], Candidates[0]], 'Hinweis');
  Assert.AreEqual(4, Integer(Length(mResults)));
  Assert.IsTrue(mResults[0].Group = TAtlasWelcomeSearchGroup.Projects);
  Assert.IsTrue(mResults[1].Group = TAtlasWelcomeSearchGroup.Files);
  Assert.IsTrue(mResults[2].Group = TAtlasWelcomeSearchGroup.Symbols);
  Assert.IsTrue(mResults[3].Group = TAtlasWelcomeSearchGroup.Commands);
end;

procedure TAtlasWelcomeSearchTests.LimitsEachGroupToFour;
var
  mHits: TArray<TAtlasWelcomeHit>;
  mIndex: Integer;
  mResults: TArray<TAtlasWelcomeSearchResult>;
begin
  mHits := nil;
  for mIndex := 1 to 7 do
  begin
    mHits := mHits + [FileHit(Format('Unit%d.pas', [mIndex]), 'P')];
  end;
  for mIndex := 1 to 2 do
  begin
    mHits := mHits + [CommandHit(Format('Unit-Befehl %d', [mIndex]), 'Atlas.U' + IntToStr(mIndex))];
  end;
  mResults := TAtlasWelcomeSearch.Search('unit', mHits, '');
  Assert.AreEqual(2, Integer(Length(mResults)));
  Assert.AreEqual(4, Integer(Length(mResults[0].Hits)));
  Assert.AreEqual(3, mResults[0].More);
  Assert.AreEqual(2, Integer(Length(mResults[1].Hits)));
  Assert.AreEqual(0, mResults[1].More);
  mResults := TAtlasWelcomeSearch.Search('unit', mHits, '', 2);
  Assert.AreEqual(2, Integer(Length(mResults[0].Hits)));
  Assert.AreEqual(5, mResults[0].More);
end;

procedure TAtlasWelcomeSearchTests.BetterMatchFirstThenSourceOrder;
var
  mResults: TArray<TAtlasWelcomeSearchResult>;
begin
  mResults := TAtlasWelcomeSearch.Search('haupt',
    [FileHit('Nebenhaupt.pas', 'P'), FileHit('Haupt.pas', 'P'), FileHit('HauptForm.pas', 'P'),
    FileHit('HauptDaten.pas', 'P')], '');
  Assert.AreEqual('Haupt.pas', mResults[0].Hits[0].Caption);
  // Gleiche Stufe: Reihenfolge der Quelle (zuletzt geöffnet zuerst).
  Assert.AreEqual('HauptForm.pas', mResults[0].Hits[1].Caption);
  Assert.AreEqual('HauptDaten.pas', mResults[0].Hits[2].Caption);
  Assert.AreEqual('Nebenhaupt.pas', mResults[0].Hits[3].Caption);
end;

procedure TAtlasWelcomeSearchTests.SymbolHintWithoutServer;
var
  mResults: TArray<TAtlasWelcomeSearchResult>;
  mGroup: TAtlasWelcomeSearchResult;
begin
  mResults := TAtlasWelcomeSearch.Search('wel', Candidates, 'Symbole nach dem Öffnen eines Projekts');
  Assert.IsTrue(GroupOf(mResults, TAtlasWelcomeSearchGroup.Symbols, mGroup));
  Assert.AreEqual(0, Integer(Length(mGroup.Hits)));
  Assert.AreEqual('Symbole nach dem Öffnen eines Projekts', mGroup.Hint);
  // Auch wenn sonst nichts passt, steht der Hinweis da.
  Assert.AreEqual(1, Integer(Length(TAtlasWelcomeSearch.Search('qqq', Candidates, 'Hinweis'))));
end;

procedure TAtlasWelcomeSearchTests.NoSymbolGroupWithoutHintAndHits;
var
  mGroup: TAtlasWelcomeSearchResult;
begin
  // welcomePage.search.symbols aus: keine Kandidaten, kein Hinweis, keine Gruppe.
  Assert.IsFalse(GroupOf(TAtlasWelcomeSearch.Search('wel', Candidates, ''), TAtlasWelcomeSearchGroup.Symbols,
    mGroup));
end;

procedure TAtlasWelcomeSearchTests.ServerSymbolsKeepOrder;
var
  mFirst, mSecond: TAtlasWelcomeHit;
  mResults: TArray<TAtlasWelcomeSearchResult>;
begin
  mFirst := TAtlasWelcomeHit.Create(TAtlasWelcomeSearchGroup.Symbols, 'TWelcomeBoard', 'Atlas.UI', 'a.pas');
  mFirst.Prefiltered := True;
  mSecond := TAtlasWelcomeHit.Create(TAtlasWelcomeSearchGroup.Symbols, 'Wel', 'Atlas.UI', 'b.pas');
  mSecond.Prefiltered := True;
  mResults := TAtlasWelcomeSearch.Search('wel', [mFirst, mSecond], 'Hinweis');
  Assert.AreEqual(1, Integer(Length(mResults)));
  Assert.AreEqual('TWelcomeBoard', mResults[0].Hits[0].Caption);
  Assert.AreEqual('Wel', mResults[0].Hits[1].Caption);
  Assert.AreEqual('', mResults[0].Hint);
end;

procedure TAtlasWelcomeSearchTests.FlattenFollowsDisplayOrder;
var
  mFlat: TArray<TAtlasWelcomeHit>;
begin
  mFlat := TAtlasWelcomeSearch.Flatten(TAtlasWelcomeSearch.Search('a', Candidates, 'Hinweis'));
  Assert.IsTrue(mFlat[0].Group = TAtlasWelcomeSearchGroup.Projects);
  Assert.IsTrue(mFlat[High(mFlat)].Group = TAtlasWelcomeSearchGroup.Commands);
end;

procedure TAtlasWelcomeSearchTests.RowsWithHeadersHintAndMore;
var
  mHits: TArray<TAtlasWelcomeHit>;
  mIndex: Integer;
  mRows: TArray<TAtlasWelcomeSearchRow>;
begin
  mHits := [CommandHit('Unit-Befehl', 'Atlas.U')];
  for mIndex := 1 to 6 do
  begin
    mHits := mHits + [FileHit(Format('Unit%d.pas', [mIndex]), 'P')];
  end;
  mRows := TAtlasWelcomeSearch.Rows(TAtlasWelcomeSearch.Search('unit', mHits, 'Hinweis'));
  // Dateien: Kopf, 4 Treffer, „2 weitere“; Symbole: Kopf, Hinweis; Befehle: Kopf, Treffer.
  Assert.AreEqual(10, Integer(Length(mRows)));
  Assert.IsTrue(mRows[0].Kind = TAtlasWelcomeRowKind.Group);
  Assert.IsTrue(mRows[0].Group = TAtlasWelcomeSearchGroup.Files);
  Assert.AreEqual(0, mRows[1].Index);
  Assert.AreEqual(3, mRows[4].Index);
  Assert.IsTrue(mRows[5].Kind = TAtlasWelcomeRowKind.More);
  Assert.AreEqual(2, mRows[5].Index);
  Assert.IsTrue(mRows[7].Kind = TAtlasWelcomeRowKind.Hint);
  Assert.AreEqual('Hinweis', mRows[7].Text);
  Assert.IsTrue(mRows[9].Kind = TAtlasWelcomeRowKind.Hit);
  Assert.AreEqual(4, mRows[9].Index);
end;

procedure TAtlasWelcomeSearchTests.RecentProjectsInOrderWithoutDuplicates;
var
  mProjects: TArray<string>;
begin
  mProjects := TAtlasWelcomeSearch.RecentProjects([
    TPair<string, string>.Create('File_10', 'TProject,C:\P\Zehn.dproj,0,0'),
    TPair<string, string>.Create('File_0', 'TProjectGroup,C:\P\Gruppe.groupproj,1'),
    TPair<string, string>.Create('File_1', 'TProject,c:\p\gruppe.groupproj'),
    TPair<string, string>.Create('File_2', 'C:\P\Ohne Klasse.dproj'),
    TPair<string, string>.Create('File_3', 'TProject,Relativ.dproj'),
    // Delphi 13: Pfad in Hochkommas.
    TPair<string, string>.Create('File_4', 'TProjectGroup,''C:\P\Atlas.groupproj'',1'),
    TPair<string, string>.Create('Max Closed Files', '10')]);
  Assert.AreEqual(4, Integer(Length(mProjects)));
  Assert.AreEqual('C:\P\Gruppe.groupproj', mProjects[0]);
  Assert.AreEqual('C:\P\Ohne Klasse.dproj', mProjects[1]);
  Assert.AreEqual('C:\P\Atlas.groupproj', mProjects[2]);
  Assert.AreEqual('C:\P\Zehn.dproj', mProjects[3]);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeIndexFilesTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeSearchTests);

end.
