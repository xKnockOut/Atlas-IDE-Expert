unit Atlas.Core.Tests.ProjectChoice.Tests;

// Tests der gemerkten Wahl des Testprojekts (#585) ohne IDE: Schlüssel der
// Kandidaten, Wahl merken und wiederfinden, Datei lesen und schreiben, ein
// höheres Format bleibt unangetastet.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasTestProjectChoiceTests = class
  public
    [Test]
    procedure KeyIgnoresOrderCaseAndDoubles;
    [Test]
    procedure PickAsksOnlyForUnknownCandidates;
    [Test]
    procedure RememberReplacesAndLimits;
    [Test]
    procedure JsonRoundTrip;
    [Test]
    procedure ParseRejectsGarbageAndNewerFormat;
    [Test]
    procedure SaveAndLoadKeepNewerFormat;
    /// <summary>Unbrauchbare Datei liegt danach als .defekt daneben; eine beim Lesen gesperrte wird nicht
    /// überschrieben (Bericht N3).</summary>
    [Test]
    procedure BrokenFileSetAsideLockedFileKept;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Tests.ProjectChoice;

{ TAtlasTestProjectChoiceTests }

procedure TAtlasTestProjectChoiceTests.KeyIgnoresOrderCaseAndDoubles;
begin
  Assert.AreEqual('c:\a.dproj|c:\b.dproj',
    TAtlasTestProjectChoices.KeyOf(['C:\B.dproj', ' c:\a.dproj', 'C:\A.dproj', '']));
  Assert.AreEqual(TAtlasTestProjectChoices.KeyOf(['x', 'y']), TAtlasTestProjectChoices.KeyOf(['Y', 'X']));
  Assert.AreEqual('', TAtlasTestProjectChoices.KeyOf(nil));
end;

procedure TAtlasTestProjectChoiceTests.PickAsksOnlyForUnknownCandidates;
var
  mChoices: TArray<TAtlasTestProjectChoice>;
begin
  mChoices := nil;
  Assert.AreEqual(0, TAtlasTestProjectChoices.Pick(mChoices, ['C:\Einzig.dproj']), 'ein Kandidat: ohne Frage');
  Assert.AreEqual(-1, TAtlasTestProjectChoices.Pick(mChoices, nil));
  Assert.AreEqual(-1, TAtlasTestProjectChoices.Pick(mChoices, ['C:\A.dproj', 'C:\B.dproj']), 'fragen');
  TAtlasTestProjectChoices.Remember(mChoices, ['C:\A.dproj', 'C:\B.dproj'], 'C:\B.dproj');
  Assert.AreEqual(1, TAtlasTestProjectChoices.Pick(mChoices, ['C:\A.dproj', 'C:\B.dproj']));
  Assert.AreEqual(0, TAtlasTestProjectChoices.Pick(mChoices, ['c:\b.DPROJ', 'C:\A.dproj']), 'andere Reihenfolge');
  Assert.AreEqual(-1, TAtlasTestProjectChoices.Pick(mChoices, ['C:\A.dproj', 'C:\B.dproj', 'C:\C.dproj']),
    'neues Testprojekt in der Gruppe: wieder fragen');
end;

procedure TAtlasTestProjectChoiceTests.RememberReplacesAndLimits;
var
  mChoices: TArray<TAtlasTestProjectChoice>;
  mIndex: Integer;
begin
  mChoices := nil;
  TAtlasTestProjectChoices.Remember(mChoices, ['A', 'B'], 'A');
  TAtlasTestProjectChoices.Remember(mChoices, ['C', 'D'], 'D');
  TAtlasTestProjectChoices.Remember(mChoices, ['B', 'A'], 'B');
  Assert.AreEqual(2, Integer(Length(mChoices)));
  Assert.AreEqual('a|b', mChoices[0].Key, 'neueste zuerst');
  Assert.AreEqual('B', mChoices[0].Project);
  Assert.AreEqual('c|d', mChoices[1].Key);
  TAtlasTestProjectChoices.Remember(mChoices, ['A', 'B'], '');
  Assert.AreEqual('B', mChoices[0].Project, 'leeres Projekt ändert nichts');
  for mIndex := 1 to TAtlasTestProjectChoices.cMaxEntries + 5 do
  begin
    TAtlasTestProjectChoices.Remember(mChoices, ['P' + IntToStr(mIndex), 'Q'], 'Q');
  end;
  Assert.AreEqual(TAtlasTestProjectChoices.cMaxEntries, Integer(Length(mChoices)));
  Assert.AreEqual('p' + IntToStr(TAtlasTestProjectChoices.cMaxEntries + 5) + '|q', mChoices[0].Key);
end;

procedure TAtlasTestProjectChoiceTests.JsonRoundTrip;
var
  mChoices, mLoaded: TArray<TAtlasTestProjectChoice>;
begin
  mChoices := nil;
  TAtlasTestProjectChoices.Remember(mChoices, ['C:\Mit "Zeichen"\A.dproj', 'C:\Ä\B.dproj'], 'C:\Ä\B.dproj');
  mLoaded := TAtlasTestProjectChoices.Parse(TAtlasTestProjectChoices.ToJson(mChoices));
  Assert.AreEqual(1, Integer(Length(mLoaded)));
  Assert.AreEqual(mChoices[0].Key, mLoaded[0].Key);
  Assert.AreEqual('C:\Ä\B.dproj', mLoaded[0].Project);
  Assert.AreEqual(1, TAtlasTestProjectChoices.FormatOf(TAtlasTestProjectChoices.ToJson(mChoices)));
  Assert.AreEqual(0, Integer(Length(TAtlasTestProjectChoices.Parse(TAtlasTestProjectChoices.ToJson(nil)))));
end;

procedure TAtlasTestProjectChoiceTests.ParseRejectsGarbageAndNewerFormat;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasTestProjectChoices.Parse(''))));
  Assert.AreEqual(0, Integer(Length(TAtlasTestProjectChoices.Parse('kein JSON'))));
  Assert.AreEqual(0, Integer(Length(TAtlasTestProjectChoices.Parse('[1, 2]'))));
  Assert.AreEqual(0, Integer(Length(TAtlasTestProjectChoices.Parse(
    '{"format": 2, "choices": [{"candidates": "a|b", "project": "a"}]}'))), 'höheres Format');
  Assert.AreEqual(2, TAtlasTestProjectChoices.FormatOf('{"format": 2}'));
  Assert.AreEqual(0, TAtlasTestProjectChoices.FormatOf('kein JSON'));
  Assert.AreEqual(1, Integer(Length(TAtlasTestProjectChoices.Parse(
    '{"format": 1, "choices": [{"candidates": "a|b", "project": "a"}, {"candidates": "", "project": "x"}, ' +
    '{"project": "y"}, 7]}'))), 'unvollständige Einträge fallen weg');
end;

procedure TAtlasTestProjectChoiceTests.SaveAndLoadKeepNewerFormat;
var
  mFolder, mFileName: string;
  mChoices: TArray<TAtlasTestProjectChoice>;
begin
  mFolder := IncludeTrailingPathDelimiter(TPath.GetTempPath) + 'atlas-test-' + IntToStr(Random(MaxInt));
  mFileName := IncludeTrailingPathDelimiter(mFolder) + TAtlasTestProjectChoices.cFileName;
  try
    Assert.AreEqual(0, Integer(Length(TAtlasTestProjectChoices.Load(mFileName))), 'ohne Datei');
    mChoices := nil;
    TAtlasTestProjectChoices.Remember(mChoices, ['A', 'B'], 'B');
    Assert.IsTrue(TAtlasTestProjectChoices.Save(mFileName, mChoices), 'legt den Ordner an');
    mChoices := TAtlasTestProjectChoices.Load(mFileName);
    Assert.AreEqual(1, Integer(Length(mChoices)));
    Assert.AreEqual('B', mChoices[0].Project);
    TFile.WriteAllText(mFileName, '{"format": 9, "choices": []}', TEncoding.UTF8);
    Assert.IsFalse(TAtlasTestProjectChoices.Save(mFileName, mChoices), 'neuere Fassung bleibt');
    Assert.AreEqual(9, TAtlasTestProjectChoices.FormatOf(TFile.ReadAllText(mFileName, TEncoding.UTF8)));
  finally
    if FileExists(mFileName) then
    begin
      System.SysUtils.DeleteFile(mFileName);
    end;
    RemoveDir(mFolder);
  end;
end;

procedure TAtlasTestProjectChoiceTests.BrokenFileSetAsideLockedFileKept;
var
  mFolder, mFileName: string;
  mChoices: TArray<TAtlasTestProjectChoice>;
  mLock: TFileStream;
begin
  mFolder := IncludeTrailingPathDelimiter(TPath.GetTempPath) + 'atlas-test-' + IntToStr(Random(MaxInt));
  mFileName := IncludeTrailingPathDelimiter(mFolder) + TAtlasTestProjectChoices.cFileName;
  ForceDirectories(mFolder);
  try
    TFile.WriteAllText(mFileName, '{"choices": [');
    Assert.IsTrue(TAtlasTestProjectChoices.Load(mFileName, mChoices) = TAtlasDataLoad.Renewed);
    Assert.IsTrue(FileExists(mFileName + TAtlasDataFile.DefectExtension), 'beiseitegelegt');
    TAtlasTestProjectChoices.Remember(mChoices, ['A', 'B'], 'B');
    Assert.IsTrue(TAtlasTestProjectChoices.Save(mFileName, mChoices));
    mLock := TFileStream.Create(mFileName, fmOpenRead or fmShareExclusive);
    try
      Assert.IsTrue(TAtlasTestProjectChoices.Load(mFileName, mChoices) = TAtlasDataLoad.Kept);
      Assert.AreEqual(0, Integer(Length(mChoices)));
      Assert.IsFalse(TAtlasTestProjectChoices.Save(mFileName, mChoices), 'gerade nicht lesbar: nicht überschreiben');
    finally
      mLock.Free;
    end;
    Assert.AreEqual(1, Integer(Length(TAtlasTestProjectChoices.Load(mFileName))));
  finally
    TDirectory.Delete(mFolder, True);
  end;
  // Gemeldete Datendateien vergessen: Das Register bliebe sonst als Leck stehen.
  TAtlasDataFile.ForgetReports;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTestProjectChoiceTests);

end.
