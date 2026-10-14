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
  FileName := TPath.Combine(TPath.GetTempPath, 'Atlas.Tests.' + TGUID.NewGuid.ToString + '.log');
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

procedure TStreamLogSinkTests.TransformSinkRewritesText;
var
  Stream: TBytesStream;
  Sink: ILogSink;
  Text: string;
begin
  Stream := TBytesStream.Create;
  try
    Sink := TTransformLogSink.Create(TStreamLogSink.Create(Stream, False),
      function(const AText: string): string
      begin
        Result := StringReplace(AText, 'geheim', 'name#1', [rfReplaceAll]);
      end);
    Sink.Write(TLogEntry.Create(Now, TLogLevel.Warning, 'Projekt geheim'));
    Sink := nil;
    Text := TEncoding.UTF8.GetString(Stream.Bytes, 0, Stream.Size);
  finally
    Stream.Free;
  end;
  Assert.Contains(Text, 'Projekt name#1');
  Assert.DoesNotContain(Text, 'geheim');
  Assert.Contains(Text, '[WARN');
end;

initialization
  TDUnitX.RegisterTestFixture(TStreamLogSinkTests);

end.
