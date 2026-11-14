unit Atlas.Common.Logging.Providers.StreamSink.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TStreamLogSinkTests = class
  public
    [Test]
    procedure WritesOneUtf8LinePerEntry;
    [Test]
    procedure FileSinkAppendsToExistingFile;
    [Test]
    procedure TransformSinkRewritesText;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Logging.Providers.StreamSink,
  Atlas.Common.Logging.Providers.TransformSink;

{ TStreamLogSinkTests }

procedure TStreamLogSinkTests.WritesOneUtf8LinePerEntry;
var
  mStream: TBytesStream;
  mSink: ILogSink;
  mLines: TArray<string>;
begin
  mStream := TBytesStream.Create;
  try
    mSink := TStreamLogSink.Create(mStream, False);
    mSink.Write(TLogEntry.Create(Now, TLogLevel.Info, 'Größe'));
    mSink.Write(TLogEntry.Create(Now, TLogLevel.Error, 'zweite'));
    mSink := nil;

    mLines := TEncoding.UTF8.GetString(mStream.Bytes, 0, Integer(mStream.Size)).Split([sLineBreak]);
    Assert.AreEqual<NativeInt>(3, Length(mLines), 'zwei Zeilen und ein leerer Rest');
    Assert.IsTrue(mLines[0].EndsWith('[INFO] Größe'), mLines[0]);
    Assert.IsTrue(mLines[1].EndsWith('[ERROR] zweite'), mLines[1]);
    Assert.AreEqual('', mLines[2]);
  finally
    mStream.Free;
  end;
end;

procedure TStreamLogSinkTests.FileSinkAppendsToExistingFile;
var
  mFileName: string;
  mSink: ILogSink;
  mContent: string;
begin
  mFileName := TPath.Combine(TPath.GetTempPath, 'Atlas.Tests.' + TGUID.NewGuid.ToString + '.log');
  try
    TFile.WriteAllText(mFileName, 'alt' + sLineBreak, TEncoding.UTF8);

    mSink := TStreamLogSink.CreateForFile(mFileName);
    mSink.Write(TLogEntry.Create(Now, TLogLevel.Info, 'neu'));
    mSink := nil;

    mContent := TFile.ReadAllText(mFileName, TEncoding.UTF8);
    Assert.IsTrue(mContent.Contains('alt'), mContent);
    Assert.IsTrue(mContent.Contains('[INFO] neu'), mContent);
    Assert.IsTrue(mContent.IndexOf('alt') < mContent.IndexOf('neu'), mContent);
  finally
    if TFile.Exists(mFileName) then
    begin
      TFile.Delete(mFileName);
    end;
  end;
end;

procedure TStreamLogSinkTests.TransformSinkRewritesText;
var
  mStream: TBytesStream;
  mSink: ILogSink;
  mText: string;
begin
  mStream := TBytesStream.Create;
  try
    mSink := TTransformLogSink.Create(TStreamLogSink.Create(mStream, False),
      function(const AText: string): string
      begin
        Result := StringReplace(AText, 'geheim', 'name#1', [rfReplaceAll]);
      end);
    mSink.Write(TLogEntry.Create(Now, TLogLevel.Warning, 'Projekt geheim'));
    mSink := nil;
    mText := TEncoding.UTF8.GetString(mStream.Bytes, 0, mStream.Size);
  finally
    mStream.Free;
  end;
  Assert.Contains(mText, 'Projekt name#1');
  Assert.DoesNotContain(mText, 'geheim');
  Assert.Contains(mText, '[WARN');
end;

initialization
  TDUnitX.RegisterTestFixture(TStreamLogSinkTests);

end.
