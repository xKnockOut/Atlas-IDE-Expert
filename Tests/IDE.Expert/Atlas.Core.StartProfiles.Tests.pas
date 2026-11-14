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
    /// überschrieben.</summary>
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
  cProject = 'C:\Repo\App\App.dproj';
  cTeamFileName = 'C:\Repo\App\.atlas';

function TAtlasStartProfilesTests.Team(const AText: string): TAtlasTeamSettings;
begin
  Result := TAtlasTeamFile.Parse(AText, cTeamFileName, 'C:\Repo');
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
  mSearch: TSearchRec;
begin
  if FindFirst(IncludeTrailingPathDelimiter(AFolder) + '*', faAnyFile, mSearch) = 0 then
    try
      repeat
        if (mSearch.Attr and faDirectory) = 0 then
        begin
          System.SysUtils.DeleteFile(IncludeTrailingPathDelimiter(AFolder) + mSearch.Name);
        end;
      until FindNext(mSearch) <> 0;
    finally
      FindClose(mSearch);
    end;
  RemoveDir(AFolder);
end;

procedure TAtlasStartProfilesTests.MergeListsTeamFirstAndTeamWins;
var
  mState: TAtlasStartProfileState;
  mEntries: TArray<TAtlasStartProfileEntry>;
begin
  mState := TAtlasStartProfiles.Empty(cProject);
  mState.Profiles := [Profile('lokal', '-db C:\Daten\test.fdb'), Profile('demo', '-persoenlich')];
  mEntries := TAtlasStartProfiles.Merge(Team('{"version": 1, "startProfiles": [{"name": "Demo", "parameters": "-demo"}]}'),
    mState);
  Assert.AreEqual(2, Integer(Length(mEntries)));
  Assert.AreEqual('Demo', mEntries[0].Profile.Name);
  Assert.AreEqual('-demo', mEntries[0].Profile.Parameters, 'gleichnamig: das Profil aus .atlas gilt');
  Assert.AreEqual<TAtlasStartProfileSource>(TAtlasStartProfileSource.Team, mEntries[0].Source);
  Assert.AreEqual('C:\Repo\App', mEntries[0].BaseFolder);
  Assert.AreEqual('lokal', mEntries[1].Profile.Name);
  Assert.AreEqual<TAtlasStartProfileSource>(TAtlasStartProfileSource.Personal, mEntries[1].Source);
  Assert.AreEqual('C:\Repo\App', mEntries[1].BaseFolder, 'persönlich: ab dem Ordner der .dproj');
end;

procedure TAtlasStartProfilesTests.InvalidTeamFileLeavesPersonalProfiles;
var
  mState: TAtlasStartProfileState;
  mEntries: TArray<TAtlasStartProfileEntry>;
begin
  mState := TAtlasStartProfiles.Empty(cProject);
  mState.Profiles := [Profile('Lokal', '-x')];
  mEntries := TAtlasStartProfiles.Merge(Team('{ kaputt'), mState);
  Assert.AreEqual(1, Integer(Length(mEntries)));
  Assert.AreEqual('Lokal', mEntries[0].Profile.Name);
  mEntries := TAtlasStartProfiles.Merge(TAtlasTeamFile.Empty, TAtlasStartProfiles.Empty(cProject));
  Assert.AreEqual(0, Integer(Length(mEntries)));
end;

procedure TAtlasStartProfilesTests.TwoProfilesGiveTheirOwnParameters;
var
  mState: TAtlasStartProfileState;
  mEntries: TArray<TAtlasStartProfileEntry>;
  mEntry: TAtlasStartProfileEntry;
begin
  // Akzeptanzkriterium: zwei Profile mit verschiedenen Parametern; Umschalten setzt die jeweiligen.
  mState := TAtlasStartProfiles.Empty(cProject);
  mState.Profiles := [Profile('Test', '-modus test')];
  mEntries := TAtlasStartProfiles.Merge(Team('{"version": 1, "startProfiles": [{"name": "Demo", ' +
    '"parameters": "-modus demo /silent"}]}'), mState);
  Assert.IsTrue(TAtlasStartProfiles.Find(mEntries, 'demo', mEntry), 'ohne Groß-/Kleinschreibung');
  Assert.AreEqual('-modus demo /silent', TAtlasStartProfiles.OptionsOf(mEntry).Parameters);
  Assert.IsTrue(TAtlasStartProfiles.Find(mEntries, ' Test ', mEntry));
  Assert.AreEqual('-modus test', TAtlasStartProfiles.OptionsOf(mEntry).Parameters);
  Assert.IsFalse(TAtlasStartProfiles.Find(mEntries, 'Fehlt', mEntry));
  Assert.IsFalse(TAtlasStartProfiles.Find(mEntries, '', mEntry));
end;

procedure TAtlasStartProfilesTests.OptionsResolvePathsAndKeepMacros;
var
  mEntry: TAtlasStartProfileEntry;
  mOptions: TAtlasStartOptions;
begin
  mEntry := Default(TAtlasStartProfileEntry);
  mEntry.BaseFolder := 'C:\Repo\App';
  mEntry.Profile := Profile('Demo', '-demo');
  mEntry.Profile.WorkingDir := 'Bin\Debug';
  mEntry.Profile.Host := '$(BDS)\bin\bds.exe';
  mOptions := TAtlasStartProfiles.OptionsOf(mEntry);
  Assert.AreEqual('C:\Repo\App\Bin\Debug', mOptions.WorkingDir);
  Assert.AreEqual('$(BDS)\bin\bds.exe', mOptions.Host, 'Makros setzt die IDE ein');
  Assert.AreEqual('', mOptions.Environment, 'ohne Variablen keine');
  Assert.AreEqual('C:\Repo\Daten', TAtlasStartProfiles.ResolvePath('C:\Repo\App', '..\Daten'));
  Assert.AreEqual('D:\Daten', TAtlasStartProfiles.ResolvePath('C:\Repo\App', 'D:\Daten'), 'absolut bleibt');
  Assert.AreEqual('\\srv\daten', TAtlasStartProfiles.ResolvePath('C:\Repo\App', '\\srv\daten'));
  Assert.AreEqual('', TAtlasStartProfiles.ResolvePath('C:\Repo\App', '  '));
  Assert.AreEqual('Bin', TAtlasStartProfiles.ResolvePath('', 'Bin'), 'ohne Basis unverändert');
end;

procedure TAtlasStartProfilesTests.EnvironmentIsWrittenLikeTheIde;
var
  mVariables: TArray<TAtlasTeamVariable>;
begin
  SetLength(mVariables, 2);
  mVariables[0].Name := 'MODUS';
  mVariables[0].Value := 'demo';
  mVariables[1].Name := 'Path';
  mVariables[1].Value := 'C:\a;C:\b';
  Assert.AreEqual('MODUS=demo;"Path=C:\a;C:\b"', TAtlasStartProfiles.EncodeEnvironment(mVariables));
  Assert.AreEqual('MODUS=demo;"Path=C:\a;C:\b";$(Debugger_EnvVars)', TAtlasStartProfiles.EnvironmentValue(mVariables),
    'mit Erbe wie die IDE');
  Assert.AreEqual('', TAtlasStartProfiles.EnvironmentValue(nil));
end;

procedure TAtlasStartProfilesTests.EnvironmentIsReadBack;
var
  mVariables: TArray<TAtlasTeamVariable>;
begin
  // So steht es in .dproj-Dateien der IDE.
  mVariables := TAtlasStartProfiles.DecodeEnvironment('DPMPACKAGECACHE=c:\temp\cache;"Path=C:\a;$(path)";' +
    '$(Debugger_EnvVars)');
  Assert.AreEqual(2, Integer(Length(mVariables)));
  Assert.AreEqual('DPMPACKAGECACHE', mVariables[0].Name);
  Assert.AreEqual('c:\temp\cache', mVariables[0].Value);
  Assert.AreEqual('Path', mVariables[1].Name);
  Assert.AreEqual('C:\a;$(path)', mVariables[1].Value);
  Assert.AreEqual(0, Integer(Length(TAtlasStartProfiles.DecodeEnvironment(''))));
  Assert.AreEqual(0, Integer(Length(TAtlasStartProfiles.DecodeEnvironment('$(Debugger_EnvVars);=x;OHNE'))));
  Assert.AreEqual('A=', TAtlasStartProfiles.EncodeEnvironment(TAtlasStartProfiles.DecodeEnvironment('A=')),
    'leerer Wert bleibt');
end;

procedure TAtlasStartProfilesTests.JsonRoundTripKeepsEverything;
var
  mState, mBack: TAtlasStartProfileState;
  mItem: TAtlasStartProfile;
  mValid: Boolean;
begin
  mState := TAtlasStartProfiles.Empty(cProject);
  mState.Active := 'Prüfung';
  mItem := Profile('Prüfung', '-db "C:\Daten\test.fdb" /ä');
  mItem.WorkingDir := 'C:\Daten';
  mItem.Host := '..\Host\host.exe';
  mItem.Environment := TAtlasStartProfiles.DecodeEnvironment('MODUS=test;LEER=');
  mState.Profiles := [mItem, Profile('Zweites', '')];
  mState.HasOriginal := True;
  mState.Original.Parameters := '-alt';
  mState.Original.Environment := 'A=1;$(Debugger_EnvVars)';
  mBack := TAtlasStartProfiles.Parse(TAtlasStartProfiles.ToJson(mState), 'C:\Anders.dproj', mValid);
  Assert.IsTrue(mValid);
  Assert.AreEqual(cProject, mBack.Project, 'Projekt aus der Datei');
  Assert.AreEqual('Prüfung', mBack.Active);
  Assert.AreEqual(2, Integer(Length(mBack.Profiles)));
  Assert.AreEqual('-db "C:\Daten\test.fdb" /ä', mBack.Profiles[0].Parameters);
  Assert.AreEqual('C:\Daten', mBack.Profiles[0].WorkingDir);
  Assert.AreEqual('..\Host\host.exe', mBack.Profiles[0].Host);
  Assert.AreEqual(2, Integer(Length(mBack.Profiles[0].Environment)));
  Assert.AreEqual('LEER', mBack.Profiles[0].Environment[1].Name);
  Assert.AreEqual('', mBack.Profiles[0].Environment[1].Value);
  Assert.AreEqual('Zweites', mBack.Profiles[1].Name);
  Assert.IsTrue(mBack.HasOriginal);
  Assert.AreEqual('-alt', mBack.Original.Parameters);
  Assert.AreEqual('A=1;$(Debugger_EnvVars)', mBack.Original.Environment);
  Assert.AreEqual(TAtlasStartProfiles.cFormat, TAtlasStartProfiles.FormatOf(TAtlasStartProfiles.ToJson(mState)));
  // Ohne gemerkte Startoptionen fehlt der Abschnitt.
  mState.HasOriginal := False;
  Assert.IsFalse(TAtlasStartProfiles.Parse(TAtlasStartProfiles.ToJson(mState), cProject).HasOriginal);
  Assert.IsFalse(TAtlasStartProfiles.Parse(TAtlasStartProfiles.ToJson(TAtlasStartProfiles.Empty(cProject)),
    cProject).HasOriginal);
end;

procedure TAtlasStartProfilesTests.ParseSkipsCommentsAndBrokenEntries;
var
  mState: TAtlasStartProfileState;
  mValid: Boolean;
begin
  mState := TAtlasStartProfiles.Parse(
    '{' + sLineBreak +
    '  // Von Hand bearbeitet' + sLineBreak +
    '  "format": 1, "active": " Demo ",' + sLineBreak +
    '  "profiles": [{"name": "Demo", "parameters": "-a", "environment": {"A": "1", "B": true, " ": "x"}},' + sLineBreak +
    '    {"parameters": "-ohne-name"}, "kein Objekt", {"name": "demo", "parameters": "-doppelt"}]' + sLineBreak +
    '}', cProject, mValid);
  Assert.IsTrue(mValid);
  Assert.AreEqual('Demo', mState.Active);
  Assert.AreEqual(1, Integer(Length(mState.Profiles)), 'ohne Namen, kein Objekt und doppelt fallen weg');
  Assert.AreEqual('-a', mState.Profiles[0].Parameters);
  Assert.AreEqual(1, Integer(Length(mState.Profiles[0].Environment)), 'nur Texte mit Namen');
  Assert.AreEqual(cProject, mState.Project, 'ohne "project" gilt das übergebene');
  Assert.IsFalse(mState.HasOriginal);
end;

procedure TAtlasStartProfilesTests.ParseRejectsGarbageAndNewerFormat;
var
  mState: TAtlasStartProfileState;
  mValid: Boolean;
begin
  mState := TAtlasStartProfiles.Parse('kein JSON', cProject, mValid);
  Assert.IsFalse(mValid);
  Assert.AreEqual(0, Integer(Length(mState.Profiles)));
  Assert.AreEqual(cProject, mState.Project);
  mState := TAtlasStartProfiles.Parse('{"format": 2, "active": "X", "profiles": [{"name": "X"}]}', cProject, mValid);
  Assert.IsFalse(mValid, 'neueres Format');
  Assert.AreEqual('', mState.Active);
  Assert.AreEqual(2, TAtlasStartProfiles.FormatOf('{"format": 2}'));
  Assert.AreEqual(0, TAtlasStartProfiles.FormatOf(''));
  TAtlasStartProfiles.Parse('', cProject, mValid);
  Assert.IsFalse(mValid);
end;

procedure TAtlasStartProfilesTests.ActivateRemembersOptionsBeforeFirstProfile;
var
  mState: TAtlasStartProfileState;
  mBefore, mOther, mOriginal: TAtlasStartOptions;
begin
  mState := TAtlasStartProfiles.Empty(cProject);
  mBefore := Default(TAtlasStartOptions);
  mBefore.Parameters := '-von-hand';
  mBefore.WorkingDir := 'C:\Alt';
  mOther := Default(TAtlasStartOptions);
  mOther.Parameters := '-demo';
  TAtlasStartProfiles.Activate(mState, 'Demo', mBefore);
  Assert.AreEqual('Demo', mState.Active);
  Assert.IsTrue(mState.HasOriginal);
  // Wechsel auf ein zweites Profil: Die Startoptionen von vorher bleiben die von vor dem ersten.
  TAtlasStartProfiles.Activate(mState, ' Test ', mOther);
  Assert.AreEqual('Test', mState.Active);
  Assert.IsTrue(mState.Original.SameAs(mBefore));
  Assert.IsTrue(TAtlasStartProfiles.Deactivate(mState, mOriginal));
  Assert.IsTrue(mOriginal.SameAs(mBefore));
  Assert.AreEqual('', mState.Active);
  Assert.IsFalse(mState.HasOriginal);
  Assert.IsFalse(TAtlasStartProfiles.Deactivate(mState, mOriginal), 'nichts mehr gemerkt');
  Assert.IsTrue(mOriginal.IsEmpty);
  Assert.IsFalse(mBefore.SameAs(mOther));
end;

procedure TAtlasStartProfilesTests.CurrentOptionsBecomePersonalProfile;
var
  mState: TAtlasStartProfileState;
  mOptions: TAtlasStartOptions;
  mItem: TAtlasStartProfile;
begin
  mOptions := Default(TAtlasStartOptions);
  mOptions.Parameters := '-db test';
  mOptions.WorkingDir := ' C:\Daten ';
  mOptions.Host := '';
  mOptions.Environment := 'MODUS=test;$(Debugger_EnvVars)';
  mItem := TAtlasStartProfiles.ProfileFromOptions(' Von Hand ', mOptions);
  Assert.AreEqual('Von Hand', mItem.Name);
  Assert.AreEqual('-db test', mItem.Parameters);
  Assert.AreEqual('C:\Daten', mItem.WorkingDir);
  Assert.AreEqual(1, Integer(Length(mItem.Environment)));
  mState := TAtlasStartProfiles.Empty(cProject);
  Assert.IsTrue(TAtlasStartProfiles.PutPersonal(mState, mItem));
  mItem.Parameters := '-neu';
  mItem.Name := 'von hand';
  Assert.IsTrue(TAtlasStartProfiles.PutPersonal(mState, mItem), 'gleichnamig: ersetzt');
  Assert.AreEqual(1, Integer(Length(mState.Profiles)));
  Assert.AreEqual('-neu', mState.Profiles[0].Parameters);
  mItem.Name := '  ';
  Assert.IsFalse(TAtlasStartProfiles.PutPersonal(mState, mItem), 'leerer Name');
  Assert.AreEqual(1, Integer(Length(mState.Profiles)));
end;

procedure TAtlasStartProfilesTests.SaveAndLoadWithoutIde;
var
  mFolder: string;
  mState, mBack: TAtlasStartProfileState;
  mEntries: TArray<TAtlasStartProfileEntry>;
begin
  // Akzeptanzkriterium: Speichern und Laden der Profile ohne IDE.
  mFolder := TempFolder;
  try
    mBack := TAtlasStartProfiles.Load(mFolder, cProject);
    Assert.AreEqual(0, Integer(Length(mBack.Profiles)), 'ohne Datei leer');
    Assert.AreEqual(cProject, mBack.Project);
    mState := TAtlasStartProfiles.Empty(cProject);
    mState.Profiles := [Profile('Lokal', '-lokal')];
    TAtlasStartProfiles.Activate(mState, 'Demo', Default(TAtlasStartOptions));
    Assert.IsTrue(TAtlasStartProfiles.Save(mFolder, mState));
    Assert.IsTrue(FileExists(TAtlasStartProfiles.FileFor(mFolder, cProject)));
    Assert.Contains(TAtlasStartProfiles.FileFor(mFolder, cProject), '.json');
    mBack := TAtlasStartProfiles.Load(mFolder, cProject);
    Assert.AreEqual('Demo', mBack.Active, 'das aktive Profil ist je Projekt gemerkt');
    Assert.AreEqual(1, Integer(Length(mBack.Profiles)));
    Assert.AreEqual('-lokal', mBack.Profiles[0].Parameters);
    Assert.IsTrue(mBack.HasOriginal);
    Assert.AreEqual(0, Integer(Length(TAtlasStartProfiles.Load(mFolder, 'C:\Anderes\Projekt.dproj').Profiles)),
      'je Projekt eine Datei');
    // Willkommensseite (#764): gemeinsame und persönliche Profile ohne IDE.
    mEntries := TAtlasStartProfiles.ForProject(mFolder, cProject,
      Team('{"version": 1, "startProfiles": [{"name": "Demo", "parameters": "-demo"}]}'));
    Assert.AreEqual(2, Integer(Length(mEntries)));
    Assert.AreEqual('Demo', mEntries[0].Profile.Name);
    Assert.AreEqual('Lokal', mEntries[1].Profile.Name);
    Assert.IsFalse(TAtlasStartProfiles.Save('', mState), 'ohne Ordner');
    Assert.IsFalse(TAtlasStartProfiles.Save(mFolder, TAtlasStartProfiles.Empty('')), 'ohne Projekt');
  finally
    RemoveFolder(mFolder);
  end;
end;

procedure TAtlasStartProfilesTests.SaveKeepsNewerFormat;
var
  mFolder, mFileName: string;
  mLines: TStringList;
begin
  mFolder := TempFolder;
  try
    ForceDirectories(mFolder);
    mFileName := TAtlasStartProfiles.FileFor(mFolder, cProject);
    mLines := TStringList.Create;
    try
      mLines.Text := '{"format": 9, "profiles": []}';
      mLines.SaveToFile(mFileName, TEncoding.UTF8);
    finally
      mLines.Free;
    end;
    Assert.IsFalse(TAtlasStartProfiles.Save(mFolder, TAtlasStartProfiles.Empty(cProject)),
      'eine neuere Fassung hat die Datei geschrieben');
    Assert.AreEqual(9, TAtlasStartProfiles.FormatOf(TFile.ReadAllText(mFileName, TEncoding.UTF8)));
  finally
    RemoveFolder(mFolder);
  end;
end;

procedure TAtlasStartProfilesTests.TemporaryParametersAreRestored;
var
  mState: TAtlasStartProfileState;
  mCurrent, mTemporary, mBefore: TAtlasStartOptions;
begin
  mCurrent := Default(TAtlasStartOptions);
  mCurrent.Parameters := '-cfg a.ini';
  mCurrent.WorkingDir := 'C:\Arbeit';
  mCurrent.Environment := 'A=1';
  mTemporary := TAtlasStartProfiles.TemporaryOptions(mCurrent, '--run:U.T.A --exitbehavior:Continue');
  Assert.AreEqual('--run:U.T.A --exitbehavior:Continue', mTemporary.Parameters);
  Assert.AreEqual('C:\Arbeit', mTemporary.WorkingDir, 'Arbeitsordner bleibt');
  Assert.AreEqual('A=1', mTemporary.Environment, 'Umgebung bleibt');
  mState := TAtlasStartProfiles.Empty(cProject);
  TAtlasStartProfiles.BeginTemporary(mState, mCurrent, mTemporary.Parameters);
  Assert.IsTrue(mState.HasTemporary);
  // Ein zweiter Lauf, bevor der erste aufgeräumt ist: die Optionen von ganz vorher bleiben.
  TAtlasStartProfiles.BeginTemporary(mState, mTemporary, '--run:U.T.B');
  Assert.AreEqual('-cfg a.ini', mState.TemporaryBefore.Parameters);
  Assert.AreEqual('--run:U.T.B', mState.TemporaryWritten);
  mTemporary.Parameters := '--run:U.T.B';
  Assert.IsTrue(TAtlasStartProfiles.EndTemporary(mState, mTemporary, mBefore), 'unverändert: zurückstellen');
  Assert.AreEqual('-cfg a.ini', mBefore.Parameters);
  Assert.IsTrue(mBefore.SameAs(mCurrent));
  Assert.IsFalse(mState.HasTemporary, 'Eintrag entfernt');
  // Hat jemand die Parameter währenddessen geändert, bleiben sie.
  TAtlasStartProfiles.BeginTemporary(mState, mCurrent, '--run:U.T.A');
  mTemporary.Parameters := '-von-hand';
  Assert.IsFalse(TAtlasStartProfiles.EndTemporary(mState, mTemporary, mBefore));
  Assert.IsFalse(mState.HasTemporary);
  Assert.IsFalse(TAtlasStartProfiles.EndTemporary(mState, mTemporary, mBefore), 'ohne Eintrag nichts zu tun');
end;

procedure TAtlasStartProfilesTests.TemporaryEntrySurvivesInFile;
var
  mState, mBack: TAtlasStartProfileState;
  mCurrent, mBefore: TAtlasStartOptions;
begin
  // Absturz während des Laufs: die Datei kennt die Startoptionen von vorher.
  mCurrent := Default(TAtlasStartOptions);
  mCurrent.Parameters := '-"x y"';
  mCurrent.Host := 'C:\Host.exe';
  mState := TAtlasStartProfiles.Empty(cProject);
  mState.Active := 'Demo';
  TAtlasStartProfiles.BeginTemporary(mState, mCurrent, '--run:U.T.A');
  mBack := TAtlasStartProfiles.Parse(TAtlasStartProfiles.ToJson(mState), cProject);
  Assert.IsTrue(mBack.HasTemporary);
  Assert.AreEqual('--run:U.T.A', mBack.TemporaryWritten);
  Assert.IsTrue(mBack.TemporaryBefore.SameAs(mCurrent));
  Assert.AreEqual('Demo', mBack.Active, 'das aktive Profil bleibt');
  mCurrent.Parameters := '--run:U.T.A';
  Assert.IsTrue(TAtlasStartProfiles.EndTemporary(mBack, mCurrent, mBefore));
  Assert.AreEqual('-"x y"', mBefore.Parameters);
  mBack := TAtlasStartProfiles.Parse(TAtlasStartProfiles.ToJson(mBack), cProject);
  Assert.IsFalse(mBack.HasTemporary, 'ohne Eintrag kein Abschnitt');
  Assert.DoesNotContain(TAtlasStartProfiles.ToJson(mBack), '"temporary"');
end;

procedure TAtlasStartProfilesTests.BrokenFileSetAsideLockedFileKept;
var
  mFolder, mFileName: string;
  mState: TAtlasStartProfileState;
  mLock: TFileStream;
begin
  mFolder := TempFolder;
  try
    ForceDirectories(mFolder);
    mFileName := TAtlasStartProfiles.FileFor(mFolder, cProject);
    TFile.WriteAllText(mFileName, '{"profiles": [');
    mState := TAtlasStartProfiles.Load(mFolder, cProject);
    Assert.AreEqual(0, Integer(Length(mState.Profiles)));
    Assert.IsTrue(FileExists(mFileName + TAtlasDataFile.cDefectExtension), 'beiseitegelegt');
    mState.Profiles := [Profile('Lokal', '-lokal')];
    Assert.IsTrue(TAtlasStartProfiles.Save(mFolder, mState));
    mLock := TFileStream.Create(mFileName, fmOpenRead or fmShareExclusive);
    try
      mState := TAtlasStartProfiles.Load(mFolder, cProject);
    finally
      mLock.Free;
    end;
    Assert.AreEqual(0, Integer(Length(mState.Profiles)));
    Assert.AreEqual(mFileName, mState.KeptFile);
    mState.Profiles := [Profile('Ersatz', '-ersatz')];
    Assert.IsFalse(TAtlasStartProfiles.Save(mFolder, mState), 'beim Laden gesperrt: nicht überschreiben');
    Assert.Contains(TFile.ReadAllText(mFileName, TEncoding.UTF8), '-lokal');
    Assert.DoesNotContain(TFile.ReadAllText(mFileName, TEncoding.UTF8), '-ersatz');
  finally
    RemoveFolder(mFolder);
  end;
  // Gemeldete Datendateien vergessen: Das Register bliebe sonst als Leck stehen.
  TAtlasDataFile.ForgetReports;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasStartProfilesTests);

end.
