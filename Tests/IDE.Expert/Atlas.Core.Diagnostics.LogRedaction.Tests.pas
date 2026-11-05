unit Atlas.Core.Diagnostics.LogRedaction.Tests;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Anonymes Plugin-Protokoll atlas.log (#1478): gekennzeichnete Werte werden beim Schreiben ersetzt.
  /// </summary>
  [TestFixture]
  TAtlasLogRedactorTests = class
  private
    FFolder: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure MarkedValuesBecomeNumberedLabels;
    [Test]
    procedure SameValueKeepsItsNumber;
    [Test]
    procedure NamesWritesPlainText;
    [Test]
    procedure IdentityAndPathsWithoutMarksAreReplaced;
    [Test]
    procedure LabelsStopGrowingAtLimit;
    /// <summary>Wächter: Eine Zeile mit Markernamen kommt ohne diese Namen in die Datei.</summary>
    [Test]
    procedure RotatingLogWritesNoMarkerNames;
    /// <summary>Wächter: Die Meldung einer Exception landet über TAtlasGuard nie im Klartext in atlas.log.</summary>
    [Test]
    procedure GuardErrorLineHidesMessage;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Text.LogMarks,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.LogRedaction;

const
  cMarkerProject = 'MarkerProjektKunde';
  cMarkerFile = 'C:\MarkerOrdner\MarkerUnit.pas';
  cMarkerCode = 'procedure TMarkerForm.Geheim;';
  cMarkerUser = 'MarkerBenutzer';

procedure TAtlasLogRedactorTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'AtlasLogRedactionTests' + TGUID.NewGuid.ToString);
end;

procedure TAtlasLogRedactorTests.TearDown;
begin
  if TDirectory.Exists(FFolder) then
  begin
    TDirectory.Delete(FFolder, True);
  end;
  FFolder := '';
end;

procedure TAtlasLogRedactorTests.MarkedValuesBecomeNumberedLabels;
var
  mRedactor: TAtlasLogRedactor;
begin
  mRedactor := TAtlasLogRedactor.Create(nil);
  try
    Assert.AreEqual('Projekt name#1 in datei#2.pas: text#3',
      mRedactor.Redact('Projekt ' + TLogMarks.Name(cMarkerProject) + ' in ' + TLogMarks.Path(cMarkerFile) + ': ' +
      TLogMarks.Text(cMarkerCode)));
  finally
    mRedactor.Free;
  end;
end;

procedure TAtlasLogRedactorTests.SameValueKeepsItsNumber;
var
  mRedactor: TAtlasLogRedactor;
begin
  mRedactor := TAtlasLogRedactor.Create(nil);
  try
    Assert.AreEqual('name#1', mRedactor.Redact(TLogMarks.Name('Kunden')));
    Assert.AreEqual('name#2', mRedactor.Redact(TLogMarks.Name('Lager')));
    // Groß-/Kleinschreibung und Leerraum zählen nicht; derselbe Wert als Pfad ist ein anderer Eintrag.
    Assert.AreEqual('name#1', mRedactor.Redact(TLogMarks.Name(' kunden ')));
    Assert.AreEqual('datei#3', mRedactor.Redact(TLogMarks.Path('Kunden')));
  finally
    mRedactor.Free;
  end;
end;

procedure TAtlasLogRedactorTests.NamesWritesPlainText;
var
  mRedactor: TAtlasLogRedactor;
begin
  mRedactor := TAtlasLogRedactor.Create(nil);
  try
    mRedactor.Names := True;
    Assert.IsTrue(mRedactor.Names);
    Assert.AreEqual('Projekt ' + cMarkerProject + ' in ' + cMarkerFile,
      mRedactor.Redact('Projekt ' + TLogMarks.Name(cMarkerProject) + ' in ' + TLogMarks.Path(cMarkerFile)));
  finally
    mRedactor.Free;
  end;
end;

procedure TAtlasLogRedactorTests.IdentityAndPathsWithoutMarksAreReplaced;
var
  mRedactor: TAtlasLogRedactor;
  mText: string;
begin
  // Netz für Zeilen ohne Kennzeichen; Einträge unter drei Zeichen zählen nicht als Name.
  mRedactor := TAtlasLogRedactor.Create([cMarkerUser, 'ab', '']);
  try
    mText := mRedactor.Redact('Angemeldet als ' + cMarkerUser + ', Datei ' + cMarkerFile + ', ab hier');
    Assert.IsFalse(mText.Contains(cMarkerUser), mText);
    Assert.IsFalse(mText.Contains('MarkerOrdner'), mText);
    Assert.IsTrue(mText.Contains('<benutzer>'), mText);
    Assert.IsTrue(mText.Contains('ab hier'), mText);
  finally
    mRedactor.Free;
  end;
end;

procedure TAtlasLogRedactorTests.LabelsStopGrowingAtLimit;
var
  mRedactor: TAtlasLogRedactor;
  mIndex: Integer;
begin
  mRedactor := TAtlasLogRedactor.Create(nil);
  try
    for mIndex := 1 to TAtlasLogRedactor.MaxLabels do
    begin
      mRedactor.Redact(TLogMarks.Name('N' + IntToStr(mIndex)));
    end;
    Assert.AreEqual('<name>', mRedactor.Redact(TLogMarks.Name('NeuerName')));
    Assert.AreEqual('<datei>.pas', mRedactor.Redact(TLogMarks.Path('Neu.pas')));
    Assert.AreEqual('name#1', mRedactor.Redact(TLogMarks.Name('N1')), 'bekannte Werte behalten ihre Nummer');
  finally
    mRedactor.Free;
  end;
end;

procedure TAtlasLogRedactorTests.RotatingLogWritesNoMarkerNames;
var
  mLog: TAtlasRotatingLog;
  mText: string;
begin
  mLog := TAtlasRotatingLog.Create(FFolder);
  try
    mLog.Add('Projekt ' + TLogMarks.Name(cMarkerProject) + ' geladen aus ' + TLogMarks.Path(cMarkerFile) +
      ', Fehler ' + TLogMarks.Text(cMarkerCode));
    mText := TFile.ReadAllText(mLog.FileName, TEncoding.UTF8);
  finally
    mLog.Free;
  end;
  Assert.IsFalse(mText.Contains(cMarkerProject), mText);
  Assert.IsFalse(mText.Contains('MarkerUnit'), mText);
  Assert.IsFalse(mText.Contains('Geheim'), mText);
  Assert.IsFalse(TLogMarks.HasMarks(mText), 'keine Kennzeichen in der Datei');
  Assert.IsTrue(mText.Contains('Projekt name#1 geladen aus datei#2.pas, Fehler text#3'), mText);
end;

procedure TAtlasLogRedactorTests.GuardErrorLineHidesMessage;
var
  mOldFolder, mText: string;
begin
  mOldFolder := TAtlasGuard.RotatingLog.Folder;
  TAtlasGuard.RotatingLog.Folder := FFolder;
  try
    TAtlasGuard.SetLogNames(False);
    TAtlasGuard.Run(TAtlasFeature.Hover,
      procedure
      begin
        raise EInvalidOpException.Create('Zugriff in ' + cMarkerCode);
      end);
    mText := TFile.ReadAllText(TPath.Combine(FFolder, 'atlas.log'), TEncoding.UTF8);
  finally
    TAtlasGuard.RotatingLog.Folder := mOldFolder;
    TAtlasGuard.Fuse.ResetAll;
  end;
  Assert.IsFalse(mText.Contains('Geheim'), mText);
  Assert.IsTrue(mText.Contains('EInvalidOpException: text#'), mText);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasLogRedactorTests);

end.
