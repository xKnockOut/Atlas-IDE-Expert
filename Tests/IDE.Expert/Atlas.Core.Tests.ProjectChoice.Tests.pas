unit Atlas.Core.Tests.ProjectChoice.Tests;

// Tests der gemerkten Wahl des Testprojekts (#585) ohne IDE: Schlüssel der
// Kandidaten, Wahl merken und wiederfinden, Datei lesen und schreiben, ein
// höheres Format bleibt unangetastet.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
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
  Choices: TArray<TAtlasTestProjectChoice>;
begin
  Choices := nil;
  Assert.AreEqual(0, TAtlasTestProjectChoices.Pick(Choices, ['C:\Einzig.dproj']), 'ein Kandidat: ohne Frage');
  Assert.AreEqual(-1, TAtlasTestProjectChoices.Pick(Choices, nil));
  Assert.AreEqual(-1, TAtlasTestProjectChoices.Pick(Choices, ['C:\A.dproj', 'C:\B.dproj']), 'fragen');
  TAtlasTestProjectChoices.Remember(Choices, ['C:\A.dproj', 'C:\B.dproj'], 'C:\B.dproj');
  Assert.AreEqual(1, TAtlasTestProjectChoices.Pick(Choices, ['C:\A.dproj', 'C:\B.dproj']));
  Assert.AreEqual(0, TAtlasTestProjectChoices.Pick(Choices, ['c:\b.DPROJ', 'C:\A.dproj']), 'andere Reihenfolge');
  Assert.AreEqual(-1, TAtlasTestProjectChoices.Pick(Choices, ['C:\A.dproj', 'C:\B.dproj', 'C:\C.dproj']),
    'neues Testprojekt in der Gruppe: wieder fragen');
end;

procedure TAtlasTestProjectChoiceTests.RememberReplacesAndLimits;
var
  Choices: TArray<TAtlasTestProjectChoice>;
  Index: Integer;
begin
  Choices := nil;
  TAtlasTestProjectChoices.Remember(Choices, ['A', 'B'], 'A');
  TAtlasTestProjectChoices.Remember(Choices, ['C', 'D'], 'D');
  TAtlasTestProjectChoices.Remember(Choices, ['B', 'A'], 'B');
  Assert.AreEqual(2, Integer(Length(Choices)));
  Assert.AreEqual('a|b', Choices[0].Key, 'neueste zuerst');
  Assert.AreEqual('B', Choices[0].Project);
  Assert.AreEqual('c|d', Choices[1].Key);
  TAtlasTestProjectChoices.Remember(Choices, ['A', 'B'], '');
  Assert.AreEqual('B', Choices[0].Project, 'leeres Projekt ändert nichts');
  for Index := 1 to TAtlasTestProjectChoices.MaxEntries + 5 do
    TAtlasTestProjectChoices.Remember(Choices, ['P' + IntToStr(Index), 'Q'], 'Q');
  Assert.AreEqual(TAtlasTestProjectChoices.MaxEntries, Integer(Length(Choices)));
  Assert.AreEqual('p' + IntToStr(TAtlasTestProjectChoices.MaxEntries + 5) + '|q', Choices[0].Key);
end;

procedure TAtlasTestProjectChoiceTests.JsonRoundTrip;
var
  Choices, Loaded: TArray<TAtlasTestProjectChoice>;
begin
  Choices := nil;
  TAtlasTestProjectChoices.Remember(Choices, ['C:\Mit "Zeichen"\A.dproj', 'C:\Ä\B.dproj'], 'C:\Ä\B.dproj');
  Loaded := TAtlasTestProjectChoices.Parse(TAtlasTestProjectChoices.ToJson(Choices));
  Assert.AreEqual(1, Integer(Length(Loaded)));
  Assert.AreEqual(Choices[0].Key, Loaded[0].Key);
  Assert.AreEqual('C:\Ä\B.dproj', Loaded[0].Project);
  Assert.AreEqual(1, TAtlasTestProjectChoices.FormatOf(TAtlasTestProjectChoices.ToJson(Choices)));
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
  Folder, FileName: string;
  Choices: TArray<TAtlasTestProjectChoice>;
begin
  Folder := IncludeTrailingPathDelimiter(TPath.GetTempPath) + 'atlas-test-' + IntToStr(Random(MaxInt));
  FileName := IncludeTrailingPathDelimiter(Folder) + TAtlasTestProjectChoices.FileName;
  try
    Assert.AreEqual(0, Integer(Length(TAtlasTestProjectChoices.Load(FileName))), 'ohne Datei');
    Choices := nil;
    TAtlasTestProjectChoices.Remember(Choices, ['A', 'B'], 'B');
    Assert.IsTrue(TAtlasTestProjectChoices.Save(FileName, Choices), 'legt den Ordner an');
    Choices := TAtlasTestProjectChoices.Load(FileName);
    Assert.AreEqual(1, Integer(Length(Choices)));
    Assert.AreEqual('B', Choices[0].Project);
    TFile.WriteAllText(FileName, '{"format": 9, "choices": []}', TEncoding.UTF8);
    Assert.IsFalse(TAtlasTestProjectChoices.Save(FileName, Choices), 'neuere Fassung bleibt');
    Assert.AreEqual(9, TAtlasTestProjectChoices.FormatOf(TFile.ReadAllText(FileName, TEncoding.UTF8)));
  finally
    if FileExists(FileName) then
      System.SysUtils.DeleteFile(FileName);
    RemoveDir(Folder);
  end;
end;

procedure TAtlasTestProjectChoiceTests.BrokenFileSetAsideLockedFileKept;
var
  Folder, FileName: string;
  Choices: TArray<TAtlasTestProjectChoice>;
  Lock: TFileStream;
begin
  Folder := IncludeTrailingPathDelimiter(TPath.GetTempPath) + 'atlas-test-' + IntToStr(Random(MaxInt));
  FileName := IncludeTrailingPathDelimiter(Folder) + TAtlasTestProjectChoices.FileName;
  ForceDirectories(Folder);
  try
    TFile.WriteAllText(FileName, '{"choices": [');
    Assert.IsTrue(TAtlasTestProjectChoices.Load(FileName, Choices) = TAtlasDataLoad.Renewed);
    Assert.IsTrue(FileExists(FileName + TAtlasDataFile.DefectExtension), 'beiseitegelegt');
    TAtlasTestProjectChoices.Remember(Choices, ['A', 'B'], 'B');
    Assert.IsTrue(TAtlasTestProjectChoices.Save(FileName, Choices));
    Lock := TFileStream.Create(FileName, fmOpenRead or fmShareExclusive);
    try
      Assert.IsTrue(TAtlasTestProjectChoices.Load(FileName, Choices) = TAtlasDataLoad.Kept);
      Assert.AreEqual(0, Integer(Length(Choices)));
      Assert.IsFalse(TAtlasTestProjectChoices.Save(FileName, Choices), 'gerade nicht lesbar: nicht überschreiben');
    finally
      Lock.Free;
    end;
    Assert.AreEqual(1, Integer(Length(TAtlasTestProjectChoices.Load(FileName))));
  finally
    TDirectory.Delete(Folder, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTestProjectChoiceTests);

end.
