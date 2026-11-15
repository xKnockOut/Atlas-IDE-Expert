unit Atlas.Core.StartProfiles.Picker.Tests;

// Tests für die Entscheidungen der Startprofile in der IDE (#575): Einträge
// der Auswahl, Inhalt des Statusfelds, Stempel für Änderungen und die
// Umgebungsvariablen in der Kurzbeschreibung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Build')]
  TAtlasStartProfilePickerTests = class
  public
    /// <summary>Jede feste Kennung und die eines Profils werden erkannt; Fremdes tut nichts.</summary>
    [Test]
    procedure ParsesPickedEntries;
    /// <summary>„Kein Startprofil“ nur mit aktivem Profil.</summary>
    [Test]
    procedure OffersNoneOnlyWithActiveProfile;
    /// <summary>Kein Feld ohne Projekt oder ohne Profile; „–“, aktiv oder fehlend.</summary>
    [Test]
    procedure StatusKindByProfiles;
    /// <summary>Stempel mit Zeiten nur für vorhandene Dateien; ohne Projekt leer.</summary>
    [Test]
    procedure StampChangesWithFiles;
    /// <summary>Variablen als „Name=Wert“ mit Komma.</summary>
    [Test]
    procedure EnvironmentTextJoinsVariables;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Settings.TeamFile,
  Atlas.Core.StartProfiles.Picker;

{ TAtlasStartProfilePickerTests }

procedure TAtlasStartProfilePickerTests.ParsesPickedEntries;
var
  mName: string;
begin
  Assert.AreEqual(Ord(TAtlasStartProfilePick.NoProfile),
    Ord(TAtlasStartProfilePicker.Parse(TAtlasStartProfilePicker.cNoneId, mName)));
  Assert.AreEqual(Ord(TAtlasStartProfilePick.SaveCurrent),
    Ord(TAtlasStartProfilePicker.Parse(TAtlasStartProfilePicker.cSaveId, mName)));
  Assert.AreEqual(Ord(TAtlasStartProfilePick.EditPersonal),
    Ord(TAtlasStartProfilePicker.Parse(TAtlasStartProfilePicker.cEditPersonalId, mName)));
  Assert.AreEqual(Ord(TAtlasStartProfilePick.EditTeam),
    Ord(TAtlasStartProfilePicker.Parse(TAtlasStartProfilePicker.cEditTeamId, mName)));
  Assert.AreEqual('', mName);
  Assert.AreEqual(Ord(TAtlasStartProfilePick.Profile),
    Ord(TAtlasStartProfilePicker.Parse(TAtlasStartProfilePicker.ProfileId('Server: Test'), mName)));
  Assert.AreEqual('Server: Test', mName, 'Doppelpunkte im Namen bleiben');
  Assert.AreEqual(Ord(TAtlasStartProfilePick.Unknown), Ord(TAtlasStartProfilePicker.Parse('Atlas.Other', mName)));
  Assert.AreEqual('', mName);
  mName := '';
end;

procedure TAtlasStartProfilePickerTests.OffersNoneOnlyWithActiveProfile;
begin
  Assert.IsTrue(TAtlasStartProfilePicker.OffersNone('Debug'));
  Assert.IsFalse(TAtlasStartProfilePicker.OffersNone(''));
end;

procedure TAtlasStartProfilePickerTests.StatusKindByProfiles;
const
  cProject = 'C:\P\App.dproj';
begin
  Assert.AreEqual(Ord(TAtlasStartProfileStatusKind.Hidden),
    Ord(TAtlasStartProfilePicker.StatusKind('', 3, 'Debug', True)), 'ohne Projekt');
  Assert.AreEqual(Ord(TAtlasStartProfileStatusKind.Hidden),
    Ord(TAtlasStartProfilePicker.StatusKind(cProject, 0, '', False)), 'ohne Profile');
  Assert.AreEqual(Ord(TAtlasStartProfileStatusKind.NoneActive),
    Ord(TAtlasStartProfilePicker.StatusKind(cProject, 2, '', False)));
  Assert.AreEqual(Ord(TAtlasStartProfileStatusKind.Active),
    Ord(TAtlasStartProfilePicker.StatusKind(cProject, 2, 'Debug', True)));
  Assert.AreEqual(Ord(TAtlasStartProfileStatusKind.Missing),
    Ord(TAtlasStartProfilePicker.StatusKind(cProject, 2, 'Alt', False)));
  Assert.AreEqual(Ord(TAtlasStartProfileStatusKind.Missing),
    Ord(TAtlasStartProfilePicker.StatusKind(cProject, 0, 'Alt', False)), 'gemerkt, aber alle Profile weg');
end;

procedure TAtlasStartProfilePickerTests.StampChangesWithFiles;
var
  mNone, mOld, mNew: TAtlasStartProfileFileAge;
  mStamp: string;
begin
  mNone := TAtlasStartProfileFileAge.Make(False, 0);
  mOld := TAtlasStartProfileFileAge.Make(True, 1.5);
  mNew := TAtlasStartProfileFileAge.Make(True, 2.25);
  Assert.AreEqual('', TAtlasStartProfilePicker.Stamp('', 'Debug', 'Win32', 'C:\P\.atlas', mOld, mOld));
  mStamp := TAtlasStartProfilePicker.Stamp('C:\P\App.dproj', 'Debug', 'Win32', '', mOld, mNone);
  Assert.AreEqual('C:\P\App.dproj|Debug|Win32|', mStamp, 'ohne .atlas zählt deren Zeit nicht');
  mStamp := TAtlasStartProfilePicker.Stamp('C:\P\App.dproj', 'Debug', 'Win32', 'C:\P\.atlas', mOld, mNew);
  Assert.AreEqual('C:\P\App.dproj|Debug|Win32|C:\P\.atlas|1.5|2.25', mStamp);
  Assert.AreNotEqual(mStamp, TAtlasStartProfilePicker.Stamp('C:\P\App.dproj', 'Release', 'Win32', 'C:\P\.atlas',
    mOld, mNew), 'andere Konfiguration');
  Assert.AreNotEqual(mStamp, TAtlasStartProfilePicker.Stamp('C:\P\App.dproj', 'Debug', 'Win32', 'C:\P\.atlas',
    mNew, mNew), 'geänderte .atlas');
  mStamp := '';
end;

procedure TAtlasStartProfilePickerTests.EnvironmentTextJoinsVariables;
var
  mVariables: TArray<TAtlasTeamVariable>;
begin
  Assert.AreEqual('', TAtlasStartProfilePicker.EnvironmentText(nil));
  SetLength(mVariables, 2);
  mVariables[0].Name := 'MODE';
  mVariables[0].Value := 'test';
  mVariables[1].Name := 'PORT';
  mVariables[1].Value := '8080';
  Assert.AreEqual('MODE=test, PORT=8080', TAtlasStartProfilePicker.EnvironmentText(mVariables));
  mVariables := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasStartProfilePickerTests);

end.
