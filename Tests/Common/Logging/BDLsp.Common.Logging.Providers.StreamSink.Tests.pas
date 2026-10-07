unit BDLsp.Common.Logging.Providers.StreamSink.Tests;

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
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  BDLsp.Common.Logging.Contract,
  BDLsp.Common.Logging.Providers.StreamSink;

{ TStreamLogSinkTests }

procedure TStreamLogSinkTests.WritesOneUtf8LinePerEntry;
var
  Stream: TBytesStream;
  Sink: ILogSink;
  Lines: TArray<string>;
begin
  Stream := TBytesStream.Create;
  try
    Sink := TStreamLogSink.Create(Stream, False);
    Sink.Write(TLogEntry.Create(Now, TLogLevel.Info, 'Größe'));
    Sink.Write(TLogEntry.Create(Now, TLogLevel.Error, 'zweite'));
    Sink := nil;

    Lines := TEncoding.UTF8.GetString(Stream.Bytes, 0, Integer(Stream.Size)).Split([sLineBreak]);
    Assert.AreEqual<NativeInt>(3, Length(Lines), 'zwei Zeilen und ein leerer Rest');
    Assert.IsTrue(Lines[0].EndsWith('[INFO] Größe'), Lines[0]);
    Assert.IsTrue(Lines[1].EndsWith('[ERROR] zweite'), Lines[1]);
    Assert.AreEqual('', Lines[2]);
  finally
    Stream.Free;
  end;
end;

procedure TStreamLogSinkTests.FileSinkAppendsToExistingFile;
var
  FileName: string;
  Sink: ILogSink;
  Content: string;
begin
  FileName := TPath.Combine(TPath.GetTempPath, 'BDLsp.Tests.' + TGUID.NewGuid.ToString + '.log');
  try
    TFile.WriteAllText(FileName, 'alt' + sLineBreak, TEncoding.UTF8);

    Sink := TStreamLogSink.CreateForFile(FileName);
    Sink.Write(TLogEntry.Create(Now, TLogLevel.Info, 'neu'));
    Sink := nil;

    Content := TFile.ReadAllText(FileName, TEncoding.UTF8);
    Assert.IsTrue(Content.Contains('alt'), Content);
    Assert.IsTrue(Content.Contains('[INFO] neu'), Content);
    Assert.IsTrue(Content.IndexOf('alt') < Content.IndexOf('neu'), Content);
  finally
    if TFile.Exists(FileName) then
      TFile.Delete(FileName);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TStreamLogSinkTests);

end.
