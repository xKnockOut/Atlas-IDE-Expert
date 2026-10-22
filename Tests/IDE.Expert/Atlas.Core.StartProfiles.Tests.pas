unit Atlas.Core.StartProfiles.Tests;

// Tests der Startprofile (#575) ohne IDE: gemeinsame und persönliche Profile
// zusammenführen, Startoptionen mit Pfaden und Umgebungsvariablen bilden,
// lokale Datei lesen und schreiben, aktives Profil und Startoptionen von
// vorher merken; vorübergehende Startparameter für „Test debuggen“ (#585).

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Settings.TeamFile,
  Atlas.Core.StartProfiles.Store;

type
  [TestFixture]
  TAtlasStartProfilesTests = class
  private
    function Team(const AText: string): TAtlasTeamSettings;
    function Profile(const AName, AParameters: string): TAtlasStartProfile;
    function TempFolder: string;
    procedure RemoveFolder(const AFolder: string);
  public
    [Test]
    procedure MergeListsTeamFirstAndTeamWins;
    [Test]
    procedure InvalidTeamFileLeavesPersonalProfiles;
    [Test]
    procedure TwoProfilesGiveTheirOwnParameters;
    [Test]
    procedure OptionsResolvePathsAndKeepMacros;
    [Test]
    procedure EnvironmentIsWrittenLikeTheIde;
    [Test]
    procedure EnvironmentIsReadBack;
    [Test]
    procedure JsonRoundTripKeepsEverything;
    [Test]
    procedure ParseSkipsCommentsAndBrokenEntries;
    [Test]
    procedure ParseRejectsGarbageAndNewerFormat;
    [Test]
    procedure ActivateRemembersOptionsBeforeFirstProfile;
    [Test]
    procedure CurrentOptionsBecomePersonalProfile;
    [Test]
    procedure SaveAndLoadWithoutIde;
    [Test]
    procedure SaveKeepsNewerFormat;
    /// <summary>Unbrauchbare Datei liegt danach als .defekt daneben; eine beim Lesen gesperrte wird nicht
    /// überschrieben (Bericht N3).</summary>
    [Test]
    procedure BrokenFileSetAsideLockedFileKept;
    [Test]
    procedure TemporaryParametersAreRestored;
    [Test]
    procedure TemporaryEntrySurvivesInFile;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Atlas.Core.Files.DataFile;

const
  Project = 'C:\Repo\App\App.dproj';
  TeamFileName = 'C:\Repo\App\.atlas';

function TAtlasStartProfilesTests.Team(const AText: string): TAtlasTeamSettings;
begin
  Result := TAtlasTeamFile.Parse(AText, TeamFileName, 'C:\Repo');
end;

function TAtlasStartProfilesTests.Profile(const AName, AParameters: string): TAtlasStartProfile;
begin
  Result := Default(TAtlasStartProfile);
  Result.Name := AName;
  Result.Parameters := AParameters;
end;

function TAtlasStartProfilesTests.TempFolder: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'AtlasStartProfiles' + IntToStr(Random(1000000)));
end;

procedure TAtlasStartProfilesTests.RemoveFolder(const AFolder: string);
var
  Search: TSearchRec;
begin
  if FindFirst(IncludeTrailingPathDelimiter(AFolder) + '*', faAnyFile, Search) = 0 then
    try
      repeat
        if (Search.Attr and faDirectory) = 0 then
          System.SysUtils.DeleteFile(IncludeTrailingPathDelimiter(AFolder) + Search.Name);
      until FindNext(Search) <> 0;
    finally
      FindClose(Search);
    end;
  RemoveDir(AFolder);
end;

procedure TAtlasStartProfilesTests.MergeListsTeamFirstAndTeamWins;
var
  State: TAtlasStartProfileState;
  Entries: TArray<TAtlasStartProfileEntry>;
begin
  State := TAtlasStartProfiles.Empty(Project);
  State.Profiles := [Profile('lokal', '-db C:\Daten\test.fdb'), Profile('demo', '-persoenlich')];
  Entries := TAtlasStartProfiles.Merge(Team('{"version": 1, "startProfiles": [{"name": "Demo", "parameters": "-demo"}]}'),
    State);
  Assert.AreEqual(2, Integer(Length(Entries)));
  Assert.AreEqual('Demo', Entries[0].Profile.Name);
  Assert.AreEqual('-demo', Entries[0].Profile.Parameters, 'gleichnamig: das Profil aus .atlas gilt');
  Assert.IsTrue(Entries[0].Source = TAtlasStartProfileSource.Team);
  Assert.AreEqual('C:\Repo\App', Entries[0].BaseFolder);
  Assert.AreEqual('lokal', Entries[1].Profile.Name);
  Assert.IsTrue(Entries[1].Source = TAtlasStartProfileSource.Personal);
  Assert.AreEqual('C:\Repo\App', Entries[1].BaseFolder, 'persönlich: ab dem Ordner der .dproj');
end;

procedure TAtlasStartProfilesTests.InvalidTeamFileLeavesPersonalProfiles;
var
  State: TAtlasStartProfileState;
  Entries: TArray<TAtlasStartProfileEntry>;
begin
  State := TAtlasStartProfiles.Empty(Project);
  State.Profiles := [Profile('Lokal', '-x')];
  Entries := TAtlasStartProfiles.Merge(Team('{ kaputt'), State);
  Assert.AreEqual(1, Integer(Length(Entries)));
  Assert.AreEqual('Lokal', Entries[0].Profile.Name);
  Entries := TAtlasStartProfiles.Merge(TAtlasTeamFile.Empty, TAtlasStartProfiles.Empty(Project));
  Assert.AreEqual(0, Integer(Length(Entries)));
end;

procedure TAtlasStartProfilesTests.TwoProfilesGiveTheirOwnParameters;
var
  State: TAtlasStartProfileState;
  Entries: TArray<TAtlasStartProfileEntry>;
  Entry: TAtlasStartProfileEntry;
begin
  // Akzeptanzkriterium: zwei Profile mit verschiedenen Parametern; Umschalten setzt die jeweiligen.
  State := TAtlasStartProfiles.Empty(Project);
  State.Profiles := [Profile('Test', '-modus test')];
  Entries := TAtlasStartProfiles.Merge(Team('{"version": 1, "startProfiles": [{"name": "Demo", ' +
    '"parameters": "-modus demo /silent"}]}'), State);
  Assert.IsTrue(TAtlasStartProfiles.Find(Entries, 'demo', Entry), 'ohne Groß-/Kleinschreibung');
  Assert.AreEqual('-modus demo /silent', TAtlasStartProfiles.OptionsOf(Entry).Parameters);
  Assert.IsTrue(TAtlasStartProfiles.Find(Entries, ' Test ', Entry));
  Assert.AreEqual('-modus test', TAtlasStartProfiles.OptionsOf(Entry).Parameters);
  Assert.IsFalse(TAtlasStartProfiles.Find(Entries, 'Fehlt', Entry));
  Assert.IsFalse(TAtlasStartProfiles.Find(Entries, '', Entry));
end;

procedure TAtlasStartProfilesTests.OptionsResolvePathsAndKeepMacros;
var
  Entry: TAtlasStartProfileEntry;
  Options: TAtlasStartOptions;
begin
  Entry := Default(TAtlasStartProfileEntry);
  Entry.BaseFolder := 'C:\Repo\App';
  Entry.Profile := Profile('Demo', '-demo');
  Entry.Profile.WorkingDir := 'Bin\Debug';
  Entry.Profile.Host := '$(BDS)\bin\bds.exe';
  Options := TAtlasStartProfiles.OptionsOf(Entry);
  Assert.AreEqual('C:\Repo\App\Bin\Debug', Options.WorkingDir);
  Assert.AreEqual('$(BDS)\bin\bds.exe', Options.Host, 'Makros setzt die IDE ein');
  Assert.AreEqual('', Options.Environment, 'ohne Variablen keine');
  Assert.AreEqual('C:\Repo\Daten', TAtlasStartProfiles.ResolvePath('C:\Repo\App', '..\Daten'));
  Assert.AreEqual('D:\Daten', TAtlasStartProfiles.ResolvePath('C:\Repo\App', 'D:\Daten'), 'absolut bleibt');
  Assert.AreEqual('\\srv\daten', TAtlasStartProfiles.ResolvePath('C:\Repo\App', '\\srv\daten'));
  Assert.AreEqual('', TAtlasStartProfiles.ResolvePath('C:\Repo\App', '  '));
  Assert.AreEqual('Bin', TAtlasStartProfiles.ResolvePath('', 'Bin'), 'ohne Basis unverändert');
end;

procedure TAtlasStartProfilesTests.EnvironmentIsWrittenLikeTheIde;
var
  Variables: TArray<TAtlasTeamVariable>;
begin
  SetLength(Variables, 2);
  Variables[0].Name := 'MODUS';
  Variables[0].Value := 'demo';
  Variables[1].Name := 'Path';
  Variables[1].Value := 'C:\a;C:\b';
  Assert.AreEqual('MODUS=demo;"Path=C:\a;C:\b"', TAtlasStartProfiles.EncodeEnvironment(Variables));
  Assert.AreEqual('MODUS=demo;"Path=C:\a;C:\b";$(Debugger_EnvVars)', TAtlasStartProfiles.EnvironmentValue(Variables),
    'mit Erbe wie die IDE');
  Assert.AreEqual('', TAtlasStartProfiles.EnvironmentValue(nil));
end;

procedure TAtlasStartProfilesTests.EnvironmentIsReadBack;
var
  Variables: TArray<TAtlasTeamVariable>;
begin
  // So steht es in .dproj-Dateien der IDE.
  Variables := TAtlasStartProfiles.DecodeEnvironment('DPMPACKAGECACHE=c:\temp\cache;"Path=C:\a;$(path)";' +
    '$(Debugger_EnvVars)');
  Assert.AreEqual(2, Integer(Length(Variables)));
  Assert.AreEqual('DPMPACKAGECACHE', Variables[0].Name);
  Assert.AreEqual('c:\temp\cache', Variables[0].Value);
  Assert.AreEqual('Path', Variables[1].Name);
  Assert.AreEqual('C:\a;$(path)', Variables[1].Value);
  Assert.AreEqual(0, Integer(Length(TAtlasStartProfiles.DecodeEnvironment(''))));
  Assert.AreEqual(0, Integer(Length(TAtlasStartProfiles.DecodeEnvironment('$(Debugger_EnvVars);=x;OHNE'))));
  Assert.AreEqual('A=', TAtlasStartProfiles.EncodeEnvironment(TAtlasStartProfiles.DecodeEnvironment('A=')),
    'leerer Wert bleibt');
end;

procedure TAtlasStartProfilesTests.JsonRoundTripKeepsEverything;
var
  State, Back: TAtlasStartProfileState;
  Item: TAtlasStartProfile;
  Valid: Boolean;
begin
  State := TAtlasStartProfiles.Empty(Project);
  State.Active := 'Prüfung';
  Item := Profile('Prüfung', '-db "C:\Daten\test.fdb" /ä');
  Item.WorkingDir := 'C:\Daten';
  Item.Host := '..\Host\host.exe';
  Item.Environment := TAtlasStartProfiles.DecodeEnvironment('MODUS=test;LEER=');
  State.Profiles := [Item, Profile('Zweites', '')];
  State.HasOriginal := True;
  State.Original.Parameters := '-alt';
  State.Original.Environment := 'A=1;$(Debugger_EnvVars)';
  Back := TAtlasStartProfiles.Parse(TAtlasStartProfiles.ToJson(State), 'C:\Anders.dproj', Valid);
  Assert.IsTrue(Valid);
  Assert.AreEqual(Project, Back.Project, 'Projekt aus der Datei');
  Assert.AreEqual('Prüfung', Back.Active);
  Assert.AreEqual(2, Integer(Length(Back.Profiles)));
  Assert.AreEqual('-db "C:\Daten\test.fdb" /ä', Back.Profiles[0].Parameters);
  Assert.AreEqual('C:\Daten', Back.Profiles[0].WorkingDir);
  Assert.AreEqual('..\Host\host.exe', Back.Profiles[0].Host);
  Assert.AreEqual(2, Integer(Length(Back.Profiles[0].Environment)));
  Assert.AreEqual('LEER', Back.Profiles[0].Environment[1].Name);
  Assert.AreEqual('', Back.Profiles[0].Environment[1].Value);
  Assert.AreEqual('Zweites', Back.Profiles[1].Name);
  Assert.IsTrue(Back.HasOriginal);
  Assert.AreEqual('-alt', Back.Original.Parameters);
  Assert.AreEqual('A=1;$(Debugger_EnvVars)', Back.Original.Environment);
  Assert.AreEqual(TAtlasStartProfiles.Format, TAtlasStartProfiles.FormatOf(TAtlasStartProfiles.ToJson(State)));
  // Ohne gemerkte Startoptionen fehlt der Abschnitt.
  State.HasOriginal := False;
  Assert.IsFalse(TAtlasStartProfiles.Parse(TAtlasStartProfiles.ToJson(State), Project).HasOriginal);
  Assert.IsFalse(TAtlasStartProfiles.Parse(TAtlasStartProfiles.ToJson(TAtlasStartProfiles.Empty(Project)),
    Project).HasOriginal);
end;

procedure TAtlasStartProfilesTests.ParseSkipsCommentsAndBrokenEntries;
var
  State: TAtlasStartProfileState;
  Valid: Boolean;
begin
  State := TAtlasStartProfiles.Parse(
    '{' + sLineBreak +
    '  // Von Hand bearbeitet' + sLineBreak +
    '  "format": 1, "active": " Demo ",' + sLineBreak +
    '  "profiles": [{"name": "Demo", "parameters": "-a", "environment": {"A": "1", "B": true, " ": "x"}},' + sLineBreak +
    '    {"parameters": "-ohne-name"}, "kein Objekt", {"name": "demo", "parameters": "-doppelt"}]' + sLineBreak +
    '}', Project, Valid);
  Assert.IsTrue(Valid);
  Assert.AreEqual('Demo', State.Active);
  Assert.AreEqual(1, Integer(Length(State.Profiles)), 'ohne Namen, kein Objekt und doppelt fallen weg');
  Assert.AreEqual('-a', State.Profiles[0].Parameters);
  Assert.AreEqual(1, Integer(Length(State.Profiles[0].Environment)), 'nur Texte mit Namen');
  Assert.AreEqual(Project, State.Project, 'ohne "project" gilt das übergebene');
  Assert.IsFalse(State.HasOriginal);
end;

procedure TAtlasStartProfilesTests.ParseRejectsGarbageAndNewerFormat;
var
  State: TAtlasStartProfileState;
  Valid: Boolean;
begin
  State := TAtlasStartProfiles.Parse('kein JSON', Project, Valid);
  Assert.IsFalse(Valid);
  Assert.AreEqual(0, Integer(Length(State.Profiles)));
  Assert.AreEqual(Project, State.Project);
  State := TAtlasStartProfiles.Parse('{"format": 2, "active": "X", "profiles": [{"name": "X"}]}', Project, Valid);
  Assert.IsFalse(Valid, 'neueres Format');
  Assert.AreEqual('', State.Active);
  Assert.AreEqual(2, TAtlasStartProfiles.FormatOf('{"format": 2}'));
  Assert.AreEqual(0, TAtlasStartProfiles.FormatOf(''));
  TAtlasStartProfiles.Parse('', Project, Valid);
  Assert.IsFalse(Valid);
end;

procedure TAtlasStartProfilesTests.ActivateRemembersOptionsBeforeFirstProfile;
var
  State: TAtlasStartProfileState;
  Before, Other, Original: TAtlasStartOptions;
begin
  State := TAtlasStartProfiles.Empty(Project);
  Before := Default(TAtlasStartOptions);
  Before.Parameters := '-von-hand';
  Before.WorkingDir := 'C:\Alt';
  Other := Default(TAtlasStartOptions);
  Other.Parameters := '-demo';
  TAtlasStartProfiles.Activate(State, 'Demo', Before);
  Assert.AreEqual('Demo', State.Active);
  Assert.IsTrue(State.HasOriginal);
  // Wechsel auf ein zweites Profil: Die Startoptionen von vorher bleiben die von vor dem ersten.
  TAtlasStartProfiles.Activate(State, ' Test ', Other);
  Assert.AreEqual('Test', State.Active);
  Assert.IsTrue(State.Original.SameAs(Before));
  Assert.IsTrue(TAtlasStartProfiles.Deactivate(State, Original));
  Assert.IsTrue(Original.SameAs(Before));
  Assert.AreEqual('', State.Active);
  Assert.IsFalse(State.HasOriginal);
  Assert.IsFalse(TAtlasStartProfiles.Deactivate(State, Original), 'nichts mehr gemerkt');
  Assert.IsTrue(Original.IsEmpty);
  Assert.IsFalse(Before.SameAs(Other));
end;

procedure TAtlasStartProfilesTests.CurrentOptionsBecomePersonalProfile;
var
  State: TAtlasStartProfileState;
  Options: TAtlasStartOptions;
  Item: TAtlasStartProfile;
begin
  Options := Default(TAtlasStartOptions);
  Options.Parameters := '-db test';
  Options.WorkingDir := ' C:\Daten ';
  Options.Host := '';
  Options.Environment := 'MODUS=test;$(Debugger_EnvVars)';
  Item := TAtlasStartProfiles.ProfileFromOptions(' Von Hand ', Options);
  Assert.AreEqual('Von Hand', Item.Name);
  Assert.AreEqual('-db test', Item.Parameters);
  Assert.AreEqual('C:\Daten', Item.WorkingDir);
  Assert.AreEqual(1, Integer(Length(Item.Environment)));
  State := TAtlasStartProfiles.Empty(Project);
  Assert.IsTrue(TAtlasStartProfiles.PutPersonal(State, Item));
  Item.Parameters := '-neu';
  Item.Name := 'von hand';
  Assert.IsTrue(TAtlasStartProfiles.PutPersonal(State, Item), 'gleichnamig: ersetzt');
  Assert.AreEqual(1, Integer(Length(State.Profiles)));
  Assert.AreEqual('-neu', State.Profiles[0].Parameters);
  Item.Name := '  ';
  Assert.IsFalse(TAtlasStartProfiles.PutPersonal(State, Item), 'leerer Name');
  Assert.AreEqual(1, Integer(Length(State.Profiles)));
end;

procedure TAtlasStartProfilesTests.SaveAndLoadWithoutIde;
var
  Folder: string;
  State, Back: TAtlasStartProfileState;
  Entries: TArray<TAtlasStartProfileEntry>;
begin
  // Akzeptanzkriterium: Speichern und Laden der Profile ohne IDE.
  Folder := TempFolder;
  try
    Back := TAtlasStartProfiles.Load(Folder, Project);
    Assert.AreEqual(0, Integer(Length(Back.Profiles)), 'ohne Datei leer');
    Assert.AreEqual(Project, Back.Project);
    State := TAtlasStartProfiles.Empty(Project);
    State.Profiles := [Profile('Lokal', '-lokal')];
    TAtlasStartProfiles.Activate(State, 'Demo', Default(TAtlasStartOptions));
    Assert.IsTrue(TAtlasStartProfiles.Save(Folder, State));
    Assert.IsTrue(FileExists(TAtlasStartProfiles.FileFor(Folder, Project)));
    Assert.Contains(TAtlasStartProfiles.FileFor(Folder, Project), '.json');
    Back := TAtlasStartProfiles.Load(Folder, Project);
    Assert.AreEqual('Demo', Back.Active, 'das aktive Profil ist je Projekt gemerkt');
    Assert.AreEqual(1, Integer(Length(Back.Profiles)));
    Assert.AreEqual('-lokal', Back.Profiles[0].Parameters);
    Assert.IsTrue(Back.HasOriginal);
    Assert.AreEqual(0, Integer(Length(TAtlasStartProfiles.Load(Folder, 'C:\Anderes\Projekt.dproj').Profiles)),
      'je Projekt eine Datei');
    // Willkommensseite (#764): gemeinsame und persönliche Profile ohne IDE.
    Entries := TAtlasStartProfiles.ForProject(Folder, Project,
      Team('{"version": 1, "startProfiles": [{"name": "Demo", "parameters": "-demo"}]}'));
    Assert.AreEqual(2, Integer(Length(Entries)));
    Assert.AreEqual('Demo', Entries[0].Profile.Name);
    Assert.AreEqual('Lokal', Entries[1].Profile.Name);
    Assert.IsFalse(TAtlasStartProfiles.Save('', State), 'ohne Ordner');
    Assert.IsFalse(TAtlasStartProfiles.Save(Folder, TAtlasStartProfiles.Empty('')), 'ohne Projekt');
  finally
    RemoveFolder(Folder);
  end;
end;

procedure TAtlasStartProfilesTests.SaveKeepsNewerFormat;
var
  Folder, FileName: string;
  Lines: TStringList;
begin
  Folder := TempFolder;
  try
    ForceDirectories(Folder);
    FileName := TAtlasStartProfiles.FileFor(Folder, Project);
    Lines := TStringList.Create;
    try
      Lines.Text := '{"format": 9, "profiles": []}';
      Lines.SaveToFile(FileName);
    finally
      Lines.Free;
    end;
    Assert.IsFalse(TAtlasStartProfiles.Save(Folder, TAtlasStartProfiles.Empty(Project)),
      'eine neuere Fassung hat die Datei geschrieben');
    Assert.AreEqual(9, TAtlasStartProfiles.FormatOf(TFile.ReadAllText(FileName)));
  finally
    RemoveFolder(Folder);
  end;
end;

procedure TAtlasStartProfilesTests.TemporaryParametersAreRestored;
var
  State: TAtlasStartProfileState;
  Current, Temporary, Before: TAtlasStartOptions;
begin
  Current := Default(TAtlasStartOptions);
  Current.Parameters := '-cfg a.ini';
  Current.WorkingDir := 'C:\Arbeit';
  Current.Environment := 'A=1';
  Temporary := TAtlasStartProfiles.TemporaryOptions(Current, '--run:U.T.A --exitbehavior:Continue');
  Assert.AreEqual('--run:U.T.A --exitbehavior:Continue', Temporary.Parameters);
  Assert.AreEqual('C:\Arbeit', Temporary.WorkingDir, 'Arbeitsordner bleibt');
  Assert.AreEqual('A=1', Temporary.Environment, 'Umgebung bleibt');
  State := TAtlasStartProfiles.Empty(Project);
  TAtlasStartProfiles.BeginTemporary(State, Current, Temporary.Parameters);
  Assert.IsTrue(State.HasTemporary);
  // Ein zweiter Lauf, bevor der erste aufgeräumt ist: die Optionen von ganz vorher bleiben.
  TAtlasStartProfiles.BeginTemporary(State, Temporary, '--run:U.T.B');
  Assert.AreEqual('-cfg a.ini', State.TemporaryBefore.Parameters);
  Assert.AreEqual('--run:U.T.B', State.TemporaryWritten);
  Temporary.Parameters := '--run:U.T.B';
  Assert.IsTrue(TAtlasStartProfiles.EndTemporary(State, Temporary, Before), 'unverändert: zurückstellen');
  Assert.AreEqual('-cfg a.ini', Before.Parameters);
  Assert.IsTrue(Before.SameAs(Current));
  Assert.IsFalse(State.HasTemporary, 'Eintrag entfernt');
  // Hat jemand die Parameter währenddessen geändert, bleiben sie.
  TAtlasStartProfiles.BeginTemporary(State, Current, '--run:U.T.A');
  Temporary.Parameters := '-von-hand';
  Assert.IsFalse(TAtlasStartProfiles.EndTemporary(State, Temporary, Before));
  Assert.IsFalse(State.HasTemporary);
  Assert.IsFalse(TAtlasStartProfiles.EndTemporary(State, Temporary, Before), 'ohne Eintrag nichts zu tun');
end;

procedure TAtlasStartProfilesTests.TemporaryEntrySurvivesInFile;
var
  State, Back: TAtlasStartProfileState;
  Current, Before: TAtlasStartOptions;
begin
  // Absturz während des Laufs: die Datei kennt die Startoptionen von vorher.
  Current := Default(TAtlasStartOptions);
  Current.Parameters := '-"x y"';
  Current.Host := 'C:\Host.exe';
  State := TAtlasStartProfiles.Empty(Project);
  State.Active := 'Demo';
  TAtlasStartProfiles.BeginTemporary(State, Current, '--run:U.T.A');
  Back := TAtlasStartProfiles.Parse(TAtlasStartProfiles.ToJson(State), Project);
  Assert.IsTrue(Back.HasTemporary);
  Assert.AreEqual('--run:U.T.A', Back.TemporaryWritten);
  Assert.IsTrue(Back.TemporaryBefore.SameAs(Current));
  Assert.AreEqual('Demo', Back.Active, 'das aktive Profil bleibt');
  Current.Parameters := '--run:U.T.A';
  Assert.IsTrue(TAtlasStartProfiles.EndTemporary(Back, Current, Before));
  Assert.AreEqual('-"x y"', Before.Parameters);
  Back := TAtlasStartProfiles.Parse(TAtlasStartProfiles.ToJson(Back), Project);
  Assert.IsFalse(Back.HasTemporary, 'ohne Eintrag kein Abschnitt');
  Assert.DoesNotContain(TAtlasStartProfiles.ToJson(Back), '"temporary"');
end;

procedure TAtlasStartProfilesTests.BrokenFileSetAsideLockedFileKept;
var
  Folder, FileName: string;
  State: TAtlasStartProfileState;
  Lock: TFileStream;
begin
  Folder := TempFolder;
  try
    ForceDirectories(Folder);
    FileName := TAtlasStartProfiles.FileFor(Folder, Project);
    TFile.WriteAllText(FileName, '{"profiles": [');
    State := TAtlasStartProfiles.Load(Folder, Project);
    Assert.AreEqual(0, Integer(Length(State.Profiles)));
    Assert.IsTrue(FileExists(FileName + TAtlasDataFile.DefectExtension), 'beiseitegelegt');
    State.Profiles := [Profile('Lokal', '-lokal')];
    Assert.IsTrue(TAtlasStartProfiles.Save(Folder, State));
    Lock := TFileStream.Create(FileName, fmOpenRead or fmShareExclusive);
    try
      State := TAtlasStartProfiles.Load(Folder, Project);
    finally
      Lock.Free;
    end;
    Assert.AreEqual(0, Integer(Length(State.Profiles)));
    Assert.AreEqual(FileName, State.KeptFile);
    State.Profiles := [Profile('Ersatz', '-ersatz')];
    Assert.IsFalse(TAtlasStartProfiles.Save(Folder, State), 'beim Laden gesperrt: nicht überschreiben');
    Assert.Contains(TFile.ReadAllText(FileName), '-lokal');
    Assert.DoesNotContain(TFile.ReadAllText(FileName), '-ersatz');
  finally
    RemoveFolder(Folder);
  end;
  // Gemeldete Datendateien vergessen: Das Register bliebe sonst als Leck stehen.
  TAtlasDataFile.ForgetReports;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasStartProfilesTests);

end.
