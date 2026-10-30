unit Atlas.Core.Files.DataFile.Tests;

// Datendateien des Plugins (Bericht N3): Lesen mit und ohne BOM, unbrauchbarer Inhalt wird als .defekt
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
  Position: Integer;
begin
  Result := 0;
  Position := Pos(ASub, AText);
  while Position > 0 do
  begin
    Inc(Result);
    Position := Pos(ASub, AText, Position + Length(ASub));
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
    TDirectory.Delete(FFolder, True);
  if TDirectory.Exists(FLogFolder) then
    TDirectory.Delete(FLogFolder, True);
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
  FileName: string;
begin
  Result := '';
  FileName := TPath.Combine(FLogFolder, 'atlas.log');
  if TFile.Exists(FileName) then
    Result := TFile.ReadAllText(FileName, TEncoding.UTF8);
end;

procedure TAtlasDataFileTests.MissingFileIsMissing;
var
  Called: Boolean;
begin
  Called := False;
  Assert.IsTrue(TAtlasDataFile.Load(DataFile('favoriten.json'), 'Favoriten',
    function(const AText: string): Boolean
    begin
      Called := True;
      Result := True;
    end) = TAtlasDataLoad.Missing);
  Assert.IsFalse(Called, 'ohne Datei wird nichts gelesen');
  Assert.IsTrue(TAtlasDataFile.Writable(TAtlasDataLoad.Missing));
  Assert.AreEqual(0, Occurrences('Datendatei', LogText));
end;

procedure TAtlasDataFileTests.ReadsWithAndWithoutBom;
var
  Text, Seen: string;
begin
  TFile.WriteAllBytes(DataFile('a.json'), TBytes.Create($EF, $BB, $BF, Ord('['), $C3, $A4, Ord(']')));
  TFile.WriteAllBytes(DataFile('b.json'), TBytes.Create(Ord('['), $C3, $A4, Ord(']')));
  Assert.IsTrue(TAtlasDataFile.TryRead(DataFile('a.json'), Text));
  Assert.AreEqual('[ä]', Text);
  Assert.IsTrue(TAtlasDataFile.TryRead(DataFile('b.json'), Text));
  Assert.AreEqual('[ä]', Text);
  Assert.IsFalse(TAtlasDataFile.TryRead(DataFile('fehlt.json'), Text));
  Assert.AreEqual('', Text);
  Assert.IsTrue(TAtlasDataFile.Load(DataFile('a.json'), 'Favoriten',
    function(const AText: string): Boolean
    begin
      Seen := AText;
      Result := True;
    end) = TAtlasDataLoad.Loaded);
  Assert.AreEqual('[ä]', Seen);
  Assert.IsTrue(TAtlasDataFile.Writable(TAtlasDataLoad.Loaded));
  Seen := '';
end;

procedure TAtlasDataFileTests.SetsAsideUnusableContent;
var
  Log: string;
  Load: TAtlasDataLoad;
begin
  TFile.WriteAllText(DataFile('favoriten.json'), '{kaputt');
  Load := TAtlasDataFile.Load(DataFile('favoriten.json'), 'Favoriten',
    function(const AText: string): Boolean
    begin
      Result := False;
    end);
  Assert.IsTrue(Load = TAtlasDataLoad.Renewed);
  Assert.IsTrue(TAtlasDataFile.Writable(Load));
  Assert.IsFalse(TFile.Exists(DataFile('favoriten.json')));
  Assert.AreEqual('{kaputt', TFile.ReadAllText(DataFile('favoriten.json.defekt'), TEncoding.UTF8));
  Log := LogText;
  Assert.Contains(Log, 'Datendatei Favoriten: kein gültiger Inhalt; beiseitegelegt als *.defekt');
  Assert.DoesNotContain(Log, ExtractFileName(FFolder), 'kein Pfad im Protokoll');
end;

procedure TAtlasDataFileTests.EmptyFileIsSetAsideAsEmpty;
begin
  TFile.WriteAllBytes(DataFile('notizen.json'), nil);
  Assert.IsTrue(TAtlasDataFile.Load(DataFile('notizen.json'), 'Notizen',
    function(const AText: string): Boolean
    begin
      Result := False;
    end) = TAtlasDataLoad.Renewed);
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
  Parse: TAtlasDataParse;
  Log: string;
begin
  TFile.WriteAllText(DataFile('lesezeichen.json'), '{"geheimer Inhalt": 1}');
  Parse :=
    function(const AText: string): Boolean
    begin
      if AText <> '' then
        raise EConvertError.Create('geheimer Inhalt');
      Result := True;
    end;
  Assert.IsTrue(TAtlasDataFile.Load(DataFile('lesezeichen.json'), 'Lesezeichen', Parse) = TAtlasDataLoad.Kept);
  Assert.IsFalse(TAtlasDataFile.Writable(TAtlasDataLoad.Kept));
  Assert.IsTrue(TAtlasDataFile.Load(DataFile('lesezeichen.json'), 'Lesezeichen', Parse) = TAtlasDataLoad.Kept);
  Assert.AreEqual('{"geheimer Inhalt": 1}', TFile.ReadAllText(DataFile('lesezeichen.json'), TEncoding.UTF8));
  Assert.IsFalse(TFile.Exists(DataFile('lesezeichen.json.defekt')));
  Log := LogText;
  Assert.AreEqual(1, Occurrences('Datendatei Lesezeichen: Fehler beim Lesen (EConvertError)', Log));
  Assert.DoesNotContain(Log, 'geheim');
  Parse := nil;
end;

procedure TAtlasDataFileTests.LockedFileIsKept;
var
  Handle: THandle;
  Called: Boolean;
  Parse: TAtlasDataParse;
begin
  TFile.WriteAllText(DataFile('startprofile.json'), '{}');
  Called := False;
  Parse :=
    function(const AText: string): Boolean
    begin
      Called := True;
      Result := True;
    end;
  Handle := CreateFile(PChar(DataFile('startprofile.json')), GENERIC_READ, 0, nil, OPEN_EXISTING,
    FILE_ATTRIBUTE_NORMAL, 0);
  Assert.IsTrue(Handle <> INVALID_HANDLE_VALUE);
  try
    Assert.IsTrue(TAtlasDataFile.Load(DataFile('startprofile.json'), 'Startprofile', Parse) = TAtlasDataLoad.Kept);
    Assert.IsTrue(TAtlasDataFile.Load(DataFile('startprofile.json'), 'Startprofile', Parse) = TAtlasDataLoad.Kept);
  finally
    CloseHandle(Handle);
  end;
  Assert.IsFalse(Called);
  Assert.IsFalse(TFile.Exists(DataFile('startprofile.json.defekt')));
  Assert.AreEqual(1, Occurrences('Datendatei Startprofile: gesperrt oder nicht lesbar', LogText));
  Parse := nil;
end;

procedure TAtlasDataFileTests.KeepsFileThatCannotBeSetAside;
var
  Handle: THandle;
begin
  TFile.WriteAllText(DataFile('wahl.json'), 'kaputt');
  // Lesen geteilt, Löschen nicht: TryRead liest, Umbenennen scheitert.
  Handle := CreateFile(PChar(DataFile('wahl.json')), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING,
    FILE_ATTRIBUTE_NORMAL, 0);
  Assert.IsTrue(Handle <> INVALID_HANDLE_VALUE);
  try
    Assert.IsTrue(TAtlasDataFile.Load(DataFile('wahl.json'), 'Wahl des Testprojekts',
      function(const AText: string): Boolean
      begin
        Result := False;
      end) = TAtlasDataLoad.Kept);
  finally
    CloseHandle(Handle);
  end;
  Assert.AreEqual('kaputt', TFile.ReadAllText(DataFile('wahl.json'), TEncoding.UTF8));
  Assert.IsFalse(TFile.Exists(DataFile('wahl.json.defekt')));
  Assert.Contains(LogText, 'Datendatei Wahl des Testprojekts: kein gültiger Inhalt, lässt sich nicht beiseitelegen');
end;

procedure TAtlasDataFileTests.WritesAtomicallyWithoutBom;
var
  FileName, Text: string;
  Bytes: TBytes;
begin
  FileName := TPath.Combine(TPath.Combine(FFolder, 'neu'), 'daten.json');
  TAtlasDataFile.Write(FileName, '{"a": "ä"}');
  Bytes := TFile.ReadAllBytes(FileName);
  Assert.AreEqual(Integer(Ord('{')), Integer(Bytes[0]), 'ohne BOM');
  Assert.IsTrue(TAtlasDataFile.TryRead(FileName, Text));
  Assert.AreEqual('{"a": "ä"}', Text);
  TAtlasDataFile.Write(FileName, '[]');
  Assert.IsTrue(TAtlasDataFile.TryRead(FileName, Text));
  Assert.AreEqual('[]', Text);
  Assert.IsFalse(TFile.Exists(FileName + '.atlas-tmp'), 'keine Nachbardatei übrig');
end;

procedure TAtlasDataFileTests.ReportsNotWrittenOncePerKind;
var
  Locked: EAtlasTextFileError;
  Open: EFOpenError;
  Log: string;
begin
  Locked := EAtlasTextFileError.Create('Ziel von einem anderen Programm gesperrt');
  // CreateFmt: Delphis EFOpenError.Create erwartet einen Ressourcen-String.
  Open := EFOpenError.CreateFmt('%s lässt sich nicht öffnen', ['C:\Benutzer\Geheim\notizen.json']);
  try
    TAtlasDataFile.ReportNotWritten('Favoriten', Locked);
    TAtlasDataFile.ReportNotWritten('Favoriten', Locked);
    TAtlasDataFile.ReportNotWritten('Notizen', Open);
    Log := LogText;
    Assert.AreEqual(1, Occurrences('Datendatei Favoriten nicht gespeichert', Log));
    Assert.Contains(Log, 'EAtlasTextFileError: Ziel von einem anderen Programm gesperrt');
    Assert.Contains(Log, 'Datendatei Notizen nicht gespeichert (EFOpenError)');
    Assert.DoesNotContain(Log, 'Geheim', 'Meldungen mit Pfad nicht ins Protokoll');
    TAtlasDataFile.ForgetReports;
    TAtlasDataFile.ReportNotWritten('Favoriten', Locked);
    Assert.AreEqual(2, Occurrences('Datendatei Favoriten nicht gespeichert', LogText));
  finally
    Open.Free;
    Locked.Free;
  end;
end;

end.
