unit BDLsp.Common.Logging.Providers.RotatingFileStream.Tests;

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
  BDLsp.Common.Logging.Providers.RotatingFileStream;

procedure WriteText(AStream: TStream; const AText: string);
var
  Bytes: TBytes;
begin
  Bytes := TEncoding.UTF8.GetBytes(AText);
  AStream.WriteBuffer(Bytes[0], Length(Bytes));
end;

function ReadText(const AFileName: string): string;
begin
  Result := TEncoding.UTF8.GetString(TFile.ReadAllBytes(AFileName));
end;

{ TRotatingFileStreamTests }

procedure TRotatingFileStreamTests.DeleteFiles;
var
  Name: string;
begin
  for Name in [FFileName, FFileName + '.1', TRotatingFileStream.FallbackName(FFileName, '42')] do
    if TFile.Exists(Name) then
      TFile.Delete(Name);
end;

procedure TRotatingFileStreamTests.Setup;
begin
  FFileName := TPath.Combine(TPath.GetTempPath, 'BDLsp.Tests.' + TGUID.NewGuid.ToString + '.log');
end;

procedure TRotatingFileStreamTests.TearDown;
begin
  DeleteFiles;
end;

procedure TRotatingFileStreamTests.AppendsToExistingFile;
var
  Stream: TStream;
begin
  TFile.WriteAllText(FFileName, 'alt', TEncoding.ASCII);
  Stream := TRotatingFileStream.Create(FFileName, True, '');
  try
    WriteText(Stream, 'neu');
  finally
    Stream.Free;
  end;
  Assert.AreEqual('altneu', ReadText(FFileName));
end;

procedure TRotatingFileStreamTests.StartsNewFileWithoutAppend;
var
  Stream: TStream;
begin
  TFile.WriteAllText(FFileName, 'alt', TEncoding.ASCII);
  Stream := TRotatingFileStream.Create(FFileName, False, '');
  try
    WriteText(Stream, 'neu');
  finally
    Stream.Free;
  end;
  Assert.AreEqual('neu', ReadText(FFileName));
end;

procedure TRotatingFileStreamTests.RotatesWhenLimitIsExceeded;
var
  Stream: TStream;
begin
  Stream := TRotatingFileStream.Create(FFileName, False, '', 10);
  try
    WriteText(Stream, 'erste-');
    WriteText(Stream, 'zweite');
  finally
    Stream.Free;
  end;
  Assert.AreEqual('erste-', ReadText(FFileName + '.1'));
  Assert.AreEqual('zweite', ReadText(FFileName));
end;

procedure TRotatingFileStreamTests.FallsBackWhenFileIsLocked;
var
  First, Second: TRotatingFileStream;
begin
  First := TRotatingFileStream.Create(FFileName, False, '41');
  try
    Second := TRotatingFileStream.Create(FFileName, True, '42');
    try
      Assert.AreEqual(TRotatingFileStream.FallbackName(FFileName, '42'), Second.FileName);
      WriteText(Second, 'zweiter');
    finally
      Second.Free;
    end;
    WriteText(First, 'erster');
  finally
    First.Free;
  end;
  Assert.AreEqual('erster', ReadText(FFileName));
  Assert.AreEqual('zweiter', ReadText(TRotatingFileStream.FallbackName(FFileName, '42')));
end;

procedure TRotatingFileStreamTests.RaisesWhenLockedWithoutFallback;
var
  First: TStream;
begin
  First := TRotatingFileStream.Create(FFileName, False, '');
  try
    Assert.WillRaise(
      procedure
      begin
        TRotatingFileStream.Create(FFileName, True, '').Free;
      end, EStreamError);
  finally
    First.Free;
  end;
end;

procedure TRotatingFileStreamTests.FallbackNameInsertsTagBeforeExtension;
begin
  Assert.AreEqual('C:\Logs\server.42.log', TRotatingFileStream.FallbackName('C:\Logs\server.log', '42'));
end;

initialization
  TDUnitX.RegisterTestFixture(TRotatingFileStreamTests);

end.
