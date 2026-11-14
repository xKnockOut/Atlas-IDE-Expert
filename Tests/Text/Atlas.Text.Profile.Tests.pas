unit Atlas.Text.Profile.Tests;

// Tests für die Profildatei des Stichproben-Profilers (#2057): Zusammenfassen gleicher Rahmen und Stapel, JSON hin
// und zurück, kaputte Dateien, Ablage der letzten fünf Läufe und Bibliotheks-Units.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasProfileTests = class
  public
    [Test]
    procedure BuilderMergesFramesAndStacks;
    [Test]
    procedure BuilderTakesRepeatedSamples;
    [Test]
    procedure JsonRoundTrip;
    [Test]
    procedure ParseRejectsBrokenFiles;
    [Test]
    procedure StoreKeepsNewestFive;
    [Test]
    procedure LibraryUnits;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Text.Profile;

function Frame(const ARoutine: string; ALine: Integer; AIsLibrary: Boolean): TAtlasProfileFrame;
begin
  Result := Default(TAtlasProfileFrame);
  Result.Routine := ARoutine;
  Result.UnitName := 'U';
  Result.FileName := 'C:\Src\U.pas';
  Result.Line := ALine;
  Result.IsLibrary := AIsLibrary;
end;

function SampleProfile: TAtlasProfile;
var
  mBuilder: TAtlasProfileBuilder;
begin
  Result := Default(TAtlasProfile);
  Result.ProgramName := 'C:\Bin\App.exe';
  Result.Project := 'C:\Src\App.dproj';
  Result.Platform := 'Win64';
  Result.StartedAt := EncodeDateTime(2026, 11, 13, 10, 52, 7, 0);
  Result.DurationMs := 12400;
  Result.IntervalMs := 10;
  mBuilder := TAtlasProfileBuilder.Create;
  try
    mBuilder.AddSample([Frame('TWork.Expensive', 48, False), Frame('Main', 90, False)]);
    mBuilder.AddSample([Frame('TWork.Expensive', 48, False), Frame('Main', 90, False)]);
    mBuilder.AddSample([Frame('System.Sin', 10, True), Frame('TWork.Expensive', 48, False), Frame('Main', 90, False)]);
    mBuilder.AddSample(nil);
    mBuilder.FillProfile(Result);
  finally
    mBuilder.Free;
  end;
end;

procedure TAtlasProfileTests.BuilderMergesFramesAndStacks;
var
  mProfile: TAtlasProfile;
begin
  mProfile := SampleProfile;
  Assert.AreEqual(3, mProfile.Samples, 'leerer Stapel zählt nicht');
  Assert.AreEqual(3, Integer(Length(mProfile.Frames)));
  Assert.AreEqual(2, Integer(Length(mProfile.Stacks)));
  Assert.AreEqual(2, mProfile.Stacks[0].Count);
  Assert.AreEqual(1, mProfile.Stacks[1].Count);
  Assert.AreEqual('System.Sin', mProfile.Frames[mProfile.Stacks[1].Frames[0]].Routine);
end;

procedure TAtlasProfileTests.BuilderTakesRepeatedSamples;
var
  mBuilder: TAtlasProfileBuilder;
  mProfile: TAtlasProfile;
begin
  // Wer gleiche Stapel schon zusammengefasst hat, übergibt die Anzahl auf einmal.
  mProfile := Default(TAtlasProfile);
  mBuilder := TAtlasProfileBuilder.Create;
  try
    mBuilder.AddSample([Frame('Main', 90, False)], 5);
    mBuilder.AddSample([Frame('Main', 90, False)]);
    mBuilder.AddSample([Frame('Main', 90, False)], 0);
    mBuilder.FillProfile(mProfile);
  finally
    mBuilder.Free;
  end;
  Assert.AreEqual(6, mProfile.Samples, 'Anzahl 0 zählt nicht');
  Assert.AreEqual(1, Integer(Length(mProfile.Stacks)));
  Assert.AreEqual(6, mProfile.Stacks[0].Count);
end;

procedure TAtlasProfileTests.JsonRoundTrip;
var
  mProfile, mRead: TAtlasProfile;
  mText: string;
begin
  mProfile := SampleProfile;
  mText := TAtlasProfileJson.ToText(mProfile);
  Assert.IsTrue(TAtlasProfileJson.TryParse(mText, mRead), mText);
  Assert.AreEqual(mProfile.ProgramName, mRead.ProgramName);
  Assert.AreEqual(mProfile.Platform, mRead.Platform);
  Assert.AreEqual(Int64(12400), mRead.DurationMs);
  Assert.AreEqual(10, mRead.IntervalMs);
  Assert.AreEqual(3, mRead.Samples);
  Assert.IsTrue(SameDateTime(mProfile.StartedAt, mRead.StartedAt));
  Assert.AreEqual(Integer(Length(mProfile.Frames)), Integer(Length(mRead.Frames)));
  Assert.AreEqual(48, mRead.Frames[0].Line);
  Assert.IsTrue(mRead.Frames[2].IsLibrary);
  Assert.AreEqual(mText, TAtlasProfileJson.ToText(mRead));
end;

procedure TAtlasProfileTests.ParseRejectsBrokenFiles;
var
  mProfile: TAtlasProfile;
  mText: string;
begin
  Assert.IsFalse(TAtlasProfileJson.TryParse('kein json', mProfile));
  Assert.IsFalse(TAtlasProfileJson.TryParse('[]', mProfile));
  mText := TAtlasProfileJson.ToText(SampleProfile);
  Assert.IsFalse(TAtlasProfileJson.TryParse(mText.Replace('"version":1', '"version":2'), mProfile), 'Version');
  Assert.IsFalse(TAtlasProfileJson.TryParse(mText.Replace('"frames":[0,1]', '"frames":[0,9]'), mProfile),
    'Index außerhalb');
  Assert.AreEqual('', mProfile.ProgramName, 'nach Fehler leer');
end;

procedure TAtlasProfileTests.StoreKeepsNewestFive;
var
  mFiles: TArray<string>;
  mNewest: TArray<string>;
  mSurplus: TArray<string>;
begin
  Assert.AreEqual('profile-20261113-105207.json',
    TAtlasProfileStore.FileNameFor(EncodeDateTime(2026, 11, 13, 10, 52, 7, 0)));
  mFiles := TArray<string>.Create('p\profile-20261101-090000.json', 'p\notes.json', 'p\profile-20261113-105207.json',
    'p\profile-20261105-120000.json', 'p\profile-20261103-080000.json', 'p\profile-20261110-170000.json',
    'p\profile-20261112-070000.json');
  mNewest := TAtlasProfileStore.Newest(mFiles);
  Assert.AreEqual(6, Integer(Length(mNewest)), 'notes.json bleibt weg');
  Assert.AreEqual('p\profile-20261113-105207.json', mNewest[0]);
  mSurplus := TAtlasProfileStore.Surplus(mFiles, TAtlasProfileStore.cKeep);
  Assert.AreEqual(1, Integer(Length(mSurplus)));
  Assert.AreEqual('p\profile-20261101-090000.json', mSurplus[0]);
  Assert.EndsWith('profiles', TAtlasProfileStore.Folder('cache'));
end;

procedure TAtlasProfileTests.LibraryUnits;
begin
  Assert.IsTrue(TAtlasLibraryUnits.IsLibrary('System'));
  Assert.IsTrue(TAtlasLibraryUnits.IsLibrary('System.JSON'));
  Assert.IsTrue(TAtlasLibraryUnits.IsLibrary('Vcl.Forms'));
  Assert.IsTrue(TAtlasLibraryUnits.IsLibrary('winapi.windows'));
  Assert.IsFalse(TAtlasLibraryUnits.IsLibrary('Atlas.Core.Tracker.MyIssues'));
  Assert.IsFalse(TAtlasLibraryUnits.IsLibrary('SystemTools'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasProfileTests);

end.
