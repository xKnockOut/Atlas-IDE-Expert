unit Atlas.Core.Files.DataFile.Tests;

// Datendateien des Plugins: Lesen mit und ohne BOM, unbrauchbarer Inhalt wird als .defekt
// beiseitegelegt und protokolliert (ohne Pfad), eine gesperrte oder nicht lesbare Datei bleibt unverändert,
// Schreiben ersetzt atomar und legt den Ordner an.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasDataFileTests = class
  private
    FFolder: string;
    FLogFolder: string;
    FOldLogFolder: string;
    function DataFile(const AName: string): string;
    function LogText: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure MissingFileIsMissing;
    [Test]
    procedure ReadsWithAndWithoutBom;
    /// <summary>Unbrauchbarer Inhalt: als .defekt beiseitegelegt, die Ablage beginnt neu und darf schreiben.
    /// </summary>
    [Test]
    procedure SetsAsideUnusableContent;
    [Test]
    procedure EmptyFileIsSetAsideAsEmpty;
    [Test]
    procedure NewerDefectReplacesOlder;
    /// <summary>Eine Ausnahme im Leser lässt die Datei, wie sie ist; ihre Meldung (Inhalt) kommt nicht ins
    /// Protokoll, die Zeile steht einmal je Art.</summary>
    [Test]
    procedure ParserExceptionKeepsFile;
    /// <summary>Exklusiv gesperrt: nicht gelesen, nicht überschreiben (früher: leer begonnen und beim nächsten
    /// Speichern überschrieben).</summary>
    [Test]
    procedure LockedFileIsKept;
    /// <summary>Lässt sich die unbrauchbare Datei nicht umbenennen, bleibt sie und wird nicht überschrieben.
    /// </summary>
    [Test]
    procedure KeepsFileThatCannotBeSetAside;
    [Test]
    procedure WritesAtomicallyWithoutBom;
    [Test]
    procedure ReportsNotWrittenOncePerKind;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Diagnostics.Guard;

function Occurrences(const ASub, AText: string): Integer;
var
  mPosition: Integer;
begin
  Result := 0;
  mPosition := Pos(ASub, AText);
  while mPosition > 0 do
  begin
    Inc(Result);
    mPosition := Pos(ASub, AText, mPosition + Length(ASub));
  end;
end;

{ TAtlasDataFileTests }

procedure TAtlasDataFileTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'AtlasDataFileTests' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FFolder);
  FLogFolder := TPath.Combine(TPath.GetTempPath, 'AtlasDataFileLog' + TGUID.NewGuid.ToString);
  FOldLogFolder := TAtlasGuard.RotatingLog.Folder;
  TAtlasGuard.RotatingLog.Folder := FLogFolder;
  TAtlasDataFile.ForgetReports;
end;

procedure TAtlasDataFileTests.TearDown;
begin
  TAtlasDataFile.ForgetReports;
  TAtlasGuard.RotatingLog.Folder := FOldLogFolder;
  if TDirectory.Exists(FFolder) then
  begin
    TDirectory.Delete(FFolder, True);
  end;
  if TDirectory.Exists(FLogFolder) then
  begin
    TDirectory.Delete(FLogFolder, True);
  end;
  FFolder := '';
  FLogFolder := '';
  FOldLogFolder := '';
end;

function TAtlasDataFileTests.DataFile(const AName: string): string;
begin
  Result := TPath.Combine(FFolder, AName);
end;

function TAtlasDataFileTests.LogText: string;
var
  mFileName: string;
begin
  Result := '';
  mFileName := TPath.Combine(FLogFolder, 'atlas.log');
  if TFile.Exists(mFileName) then
  begin
    Result := TFile.ReadAllText(mFileName, TEncoding.UTF8);
  end;
end;

procedure TAtlasDataFileTests.MissingFileIsMissing;
var
  mCalled: Boolean;
begin
  mCalled := False;
  Assert.AreEqual<TAtlasDataLoad>(TAtlasDataLoad.Missing, TAtlasDataFile.Load(DataFile('favoriten.json'), 'Favoriten',
    function(const AText: string): Boolean
    begin
      mCalled := True;
      Result := True;
    end));
  Assert.IsFalse(mCalled, 'ohne Datei wird nichts gelesen');
  Assert.IsTrue(TAtlasDataFile.Writable(TAtlasDataLoad.Missing));
  Assert.AreEqual(0, Occurrences('Datendatei', LogText));
end;

procedure TAtlasDataFileTests.ReadsWithAndWithoutBom;
var
  mText, mSeen: string;
begin
  TFile.WriteAllBytes(DataFile('a.json'), TBytes.Create($EF, $BB, $BF, Ord('['), $C3, $A4, Ord(']')));
  TFile.WriteAllBytes(DataFile('b.json'), TBytes.Create(Ord('['), $C3, $A4, Ord(']')));
  Assert.IsTrue(TAtlasDataFile.TryRead(DataFile('a.json'), mText));
  Assert.AreEqual('[ä]', mText);
  Assert.IsTrue(TAtlasDataFile.TryRead(DataFile('b.json'), mText));
  Assert.AreEqual('[ä]', mText);
  Assert.IsFalse(TAtlasDataFile.TryRead(DataFile('fehlt.json'), mText));
  Assert.AreEqual('', mText);
  Assert.AreEqual<TAtlasDataLoad>(TAtlasDataLoad.Loaded, TAtlasDataFile.Load(DataFile('a.json'), 'Favoriten',
    function(const AText: string): Boolean
    begin
      mSeen := AText;
      Result := True;
    end));
  Assert.AreEqual('[ä]', mSeen);
  Assert.IsTrue(TAtlasDataFile.Writable(TAtlasDataLoad.Loaded));
  mSeen := '';
end;

procedure TAtlasDataFileTests.SetsAsideUnusableContent;
var
  mLog: string;
  mLoad: TAtlasDataLoad;
begin
  TFile.WriteAllText(DataFile('favoriten.json'), '{kaputt');
  mLoad := TAtlasDataFile.Load(DataFile('favoriten.json'), 'Favoriten',
    function(const AText: string): Boolean
    begin
      Result := False;
    end);
  Assert.AreEqual<TAtlasDataLoad>(TAtlasDataLoad.Renewed, mLoad);
  Assert.IsTrue(TAtlasDataFile.Writable(mLoad));
  Assert.IsFalse(TFile.Exists(DataFile('favoriten.json')));
  Assert.AreEqual('{kaputt', TFile.ReadAllText(DataFile('favoriten.json.defekt'), TEncoding.UTF8));
  mLog := LogText;
  Assert.Contains(mLog, 'Datendatei Favoriten: kein gültiger Inhalt; beiseitegelegt als *.defekt');
  Assert.DoesNotContain(mLog, ExtractFileName(FFolder), 'kein Pfad im Protokoll');
end;

procedure TAtlasDataFileTests.EmptyFileIsSetAsideAsEmpty;
begin
  TFile.WriteAllBytes(DataFile('notizen.json'), nil);
  Assert.AreEqual<TAtlasDataLoad>(TAtlasDataLoad.Renewed, TAtlasDataFile.Load(DataFile('notizen.json'), 'Notizen',
    function(const AText: string): Boolean
    begin
      Result := False;
    end));
  Assert.IsTrue(TFile.Exists(DataFile('notizen.json.defekt')));
  Assert.Contains(LogText, 'Datendatei Notizen: leer; beiseitegelegt');
end;

procedure TAtlasDataFileTests.NewerDefectReplacesOlder;
begin
  TFile.WriteAllText(DataFile('verlauf.json'), 'alt');
  TAtlasDataFile.SetAside(DataFile('verlauf.json'), 'Verlauf', 'Test');
  TFile.WriteAllText(DataFile('verlauf.json'), 'neu');
  Assert.IsTrue(TAtlasDataFile.SetAside(DataFile('verlauf.json'), 'Verlauf', 'Test'));
  Assert.AreEqual('neu', TFile.ReadAllText(DataFile('verlauf.json.defekt'), TEncoding.UTF8));
  Assert.IsFalse(TFile.Exists(DataFile('verlauf.json')));
end;

procedure TAtlasDataFileTests.ParserExceptionKeepsFile;
var
  mParse: TAtlasDataParse;
  mLog: string;
begin
  TFile.WriteAllText(DataFile('lesezeichen.json'), '{"geheimer Inhalt": 1}');
  mParse :=
    function(const AText: string): Boolean
    begin
      if AText <> '' then
      begin
        raise EConvertError.Create('geheimer Inhalt');
      end;
      Result := True;
    end;
  Assert.AreEqual<TAtlasDataLoad>(TAtlasDataLoad.Kept,
    TAtlasDataFile.Load(DataFile('lesezeichen.json'), 'Lesezeichen', mParse));
  Assert.IsFalse(TAtlasDataFile.Writable(TAtlasDataLoad.Kept));
  Assert.AreEqual<TAtlasDataLoad>(TAtlasDataLoad.Kept,
    TAtlasDataFile.Load(DataFile('lesezeichen.json'), 'Lesezeichen', mParse));
  Assert.AreEqual('{"geheimer Inhalt": 1}', TFile.ReadAllText(DataFile('lesezeichen.json'), TEncoding.UTF8));
  Assert.IsFalse(TFile.Exists(DataFile('lesezeichen.json.defekt')));
  mLog := LogText;
  Assert.AreEqual(1, Occurrences('Datendatei Lesezeichen: Fehler beim Lesen (EConvertError)', mLog));
  Assert.DoesNotContain(mLog, 'geheim');
  mParse := nil;
end;

procedure TAtlasDataFileTests.LockedFileIsKept;
var
  mHandle: THandle;
  mCalled: Boolean;
  mParse: TAtlasDataParse;
begin
  TFile.WriteAllText(DataFile('startprofile.json'), '{}');
  mCalled := False;
  mParse :=
    function(const AText: string): Boolean
    begin
      mCalled := True;
      Result := True;
    end;
  mHandle := CreateFile(PChar(DataFile('startprofile.json')), GENERIC_READ, 0, nil, OPEN_EXISTING,
    FILE_ATTRIBUTE_NORMAL, 0);
  Assert.AreNotEqual<THandle>(INVALID_HANDLE_VALUE, mHandle);
  try
    Assert.AreEqual<TAtlasDataLoad>(TAtlasDataLoad.Kept,
      TAtlasDataFile.Load(DataFile('startprofile.json'), 'Startprofile', mParse));
    Assert.AreEqual<TAtlasDataLoad>(TAtlasDataLoad.Kept,
      TAtlasDataFile.Load(DataFile('startprofile.json'), 'Startprofile', mParse));
  finally
    CloseHandle(mHandle);
  end;
  Assert.IsFalse(mCalled);
  Assert.IsFalse(TFile.Exists(DataFile('startprofile.json.defekt')));
  Assert.AreEqual(1, Occurrences('Datendatei Startprofile: gesperrt oder nicht lesbar', LogText));
  mParse := nil;
end;

procedure TAtlasDataFileTests.KeepsFileThatCannotBeSetAside;
var
  mHandle: THandle;
begin
  TFile.WriteAllText(DataFile('wahl.json'), 'kaputt');
  // Lesen geteilt, Löschen nicht: TryRead liest, Umbenennen scheitert.
  mHandle := CreateFile(PChar(DataFile('wahl.json')), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING,
    FILE_ATTRIBUTE_NORMAL, 0);
  Assert.AreNotEqual<THandle>(INVALID_HANDLE_VALUE, mHandle);
  try
    Assert.AreEqual<TAtlasDataLoad>(TAtlasDataLoad.Kept,
      TAtlasDataFile.Load(DataFile('wahl.json'), 'Wahl des Testprojekts',
      function(const AText: string): Boolean
      begin
        Result := False;
      end));
  finally
    CloseHandle(mHandle);
  end;
  Assert.AreEqual('kaputt', TFile.ReadAllText(DataFile('wahl.json'), TEncoding.UTF8));
  Assert.IsFalse(TFile.Exists(DataFile('wahl.json.defekt')));
  Assert.Contains(LogText, 'Datendatei Wahl des Testprojekts: kein gültiger Inhalt, lässt sich nicht beiseitelegen');
end;

procedure TAtlasDataFileTests.WritesAtomicallyWithoutBom;
var
  mFileName, mText: string;
  mBytes: TBytes;
begin
  mFileName := TPath.Combine(TPath.Combine(FFolder, 'neu'), 'daten.json');
  TAtlasDataFile.Write(mFileName, '{"a": "ä"}');
  mBytes := TFile.ReadAllBytes(mFileName);
  Assert.AreEqual(Integer(Ord('{')), Integer(mBytes[0]), 'ohne BOM');
  Assert.IsTrue(TAtlasDataFile.TryRead(mFileName, mText));
  Assert.AreEqual('{"a": "ä"}', mText);
  TAtlasDataFile.Write(mFileName, '[]');
  Assert.IsTrue(TAtlasDataFile.TryRead(mFileName, mText));
  Assert.AreEqual('[]', mText);
  Assert.IsFalse(TFile.Exists(mFileName + '.atlas-tmp'), 'keine Nachbardatei übrig');
end;

procedure TAtlasDataFileTests.ReportsNotWrittenOncePerKind;
var
  mLocked: EAtlasTextFileError;
  mOpen: EFOpenError;
  mLog: string;
begin
  mLocked := EAtlasTextFileError.Create('Ziel von einem anderen Programm gesperrt');
  // CreateFmt: Delphis EFOpenError.Create erwartet einen Ressourcen-String.
  mOpen := EFOpenError.CreateFmt('%s lässt sich nicht öffnen', ['C:\Benutzer\Geheim\notizen.json']);
  try
    TAtlasDataFile.ReportNotWritten('Favoriten', mLocked);
    TAtlasDataFile.ReportNotWritten('Favoriten', mLocked);
    TAtlasDataFile.ReportNotWritten('Notizen', mOpen);
    mLog := LogText;
    Assert.AreEqual(1, Occurrences('Datendatei Favoriten nicht gespeichert', mLog));
    Assert.Contains(mLog, 'EAtlasTextFileError: Ziel von einem anderen Programm gesperrt');
    Assert.Contains(mLog, 'Datendatei Notizen nicht gespeichert (EFOpenError)');
    Assert.DoesNotContain(mLog, 'Geheim', 'Meldungen mit Pfad nicht ins Protokoll');
    TAtlasDataFile.ForgetReports;
    TAtlasDataFile.ReportNotWritten('Favoriten', mLocked);
    Assert.AreEqual(2, Occurrences('Datendatei Favoriten nicht gespeichert', LogText));
  finally
    mOpen.Free;
    mLocked.Free;
  end;
end;

end.
