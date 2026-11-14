unit Atlas.Common.Logging.RotatingFileStream.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRotatingFileStreamTests = class
  private
    FFileName: string;
    procedure DeleteFiles;
  public
    [SetupFixture]
    procedure SetupFixture;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure AppendsToExistingFile;
    [Test]
    procedure StartsNewFileWithoutAppend;
    [Test]
    procedure RotatesWhenLimitIsExceeded;
    [Test]
    procedure FallsBackWhenFileIsLocked;
    [Test]
    procedure RaisesWhenLockedWithoutFallback;
    [Test]
    procedure FallbackNameInsertsTagBeforeExtension;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Atlas.Common.Logging.RotatingFileStream;

procedure WriteText(AStream: TStream; const AText: string);
var
  mBytes: TBytes;
begin
  mBytes := TEncoding.UTF8.GetBytes(AText);
  AStream.WriteBuffer(mBytes[0], Length(mBytes));
end;

function ReadText(const AFileName: string): string;
begin
  Result := TEncoding.UTF8.GetString(TFile.ReadAllBytes(AFileName));
end;

{ TRotatingFileStreamTests }

procedure TRotatingFileStreamTests.DeleteFiles;
var
  mName: string;
begin
  for mName in [FFileName, FFileName + '.1', TRotatingFileStream.FallbackName(FFileName, '42')] do
  begin
    if TFile.Exists(mName) then
    begin
      TFile.Delete(mName);
    end;
  end;
end;

procedure TRotatingFileStreamTests.SetupFixture;
var
  mFileName: string;
  mFirst: TStream;
begin
  // Die RTL legt beim ersten EFOpenError Daten an, die bis Programmende bleiben (vgl.
  // EFCreateError in den Cache-Tests). Einmal vorab auslösen, damit der Leck-Monitor in
  // den Tests nur deren eigenen Speicher sieht.
  mFileName := TPath.Combine(TPath.GetTempPath, 'Atlas.Tests.' + TGUID.NewGuid.ToString + '.log');
  mFirst := TFileStream.Create(mFileName, fmCreate or fmShareExclusive);
  try
    try
      TFileStream.Create(mFileName, fmOpenWrite or fmShareDenyWrite).Free;
    except
      on EFOpenError do
        ;
    end;
  finally
    mFirst.Free;
  end;
  TFile.Delete(mFileName);
end;

procedure TRotatingFileStreamTests.Setup;
begin
  FFileName := TPath.Combine(TPath.GetTempPath, 'Atlas.Tests.' + TGUID.NewGuid.ToString + '.log');
end;

procedure TRotatingFileStreamTests.TearDown;
begin
  DeleteFiles;
  // Sonst gibt erst das nächste Setup den Pfad frei (Leck-Monitor).
  FFileName := '';
end;

procedure TRotatingFileStreamTests.AppendsToExistingFile;
var
  mStream: TStream;
begin
  TFile.WriteAllText(FFileName, 'alt', TEncoding.ASCII);
  mStream := TRotatingFileStream.Create(FFileName, True, '');
  try
    WriteText(mStream, 'neu');
  finally
    mStream.Free;
  end;
  Assert.AreEqual('altneu', ReadText(FFileName));
end;

procedure TRotatingFileStreamTests.StartsNewFileWithoutAppend;
var
  mStream: TStream;
begin
  TFile.WriteAllText(FFileName, 'alt', TEncoding.ASCII);
  mStream := TRotatingFileStream.Create(FFileName, False, '');
  try
    WriteText(mStream, 'neu');
  finally
    mStream.Free;
  end;
  Assert.AreEqual('neu', ReadText(FFileName));
end;

procedure TRotatingFileStreamTests.RotatesWhenLimitIsExceeded;
var
  mStream: TStream;
begin
  mStream := TRotatingFileStream.Create(FFileName, False, '', 10);
  try
    WriteText(mStream, 'erste-');
    WriteText(mStream, 'zweite');
  finally
    mStream.Free;
  end;
  Assert.AreEqual('erste-', ReadText(FFileName + '.1'));
  Assert.AreEqual('zweite', ReadText(FFileName));
end;

procedure TRotatingFileStreamTests.FallsBackWhenFileIsLocked;
var
  mFirst, mSecond: TRotatingFileStream;
begin
  mFirst := TRotatingFileStream.Create(FFileName, False, '41');
  try
    mSecond := TRotatingFileStream.Create(FFileName, True, '42');
    try
      Assert.AreEqual(TRotatingFileStream.FallbackName(FFileName, '42'), mSecond.FileName);
      WriteText(mSecond, 'zweiter');
    finally
      mSecond.Free;
    end;
    WriteText(mFirst, 'erster');
  finally
    mFirst.Free;
  end;
  Assert.AreEqual('erster', ReadText(FFileName));
  Assert.AreEqual('zweiter', ReadText(TRotatingFileStream.FallbackName(FFileName, '42')));
end;

procedure TRotatingFileStreamTests.RaisesWhenLockedWithoutFallback;
var
  mFirst: TStream;
begin
  mFirst := TRotatingFileStream.Create(FFileName, False, '');
  try
    // Belegt meldet die RTL EFOpenError bzw. EFCreateError, beides Unterklassen von EStreamError.
    Assert.WillRaiseDescendant(
      procedure
      begin
        TRotatingFileStream.Create(FFileName, True, '').Free;
      end, EStreamError);
  finally
    mFirst.Free;
  end;
end;

procedure TRotatingFileStreamTests.FallbackNameInsertsTagBeforeExtension;
begin
  Assert.AreEqual('C:\Logs\server.42.log', TRotatingFileStream.FallbackName('C:\Logs\server.log', '42'));
end;

initialization
  TDUnitX.RegisterTestFixture(TRotatingFileStreamTests);

end.
