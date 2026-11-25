unit Atlas.Common.Documents.FileBatch.Tests;

// Tests für TFileBatch: alle Dateien oder keine.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFileBatchTests = class
  public
    [Test]
    procedure WritesAllFiles;
    [Test]
    procedure RollsBackOnError;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.FileBatch;

{ TFileBatchTests }

procedure TFileBatchTests.WritesAllFiles;
var
  mNames: string;
begin
  mNames := '';
  Assert.AreEqual(2, TFileBatch.WriteAll(TArray<string>.Create('A.pas', 'B.pas'),
    TArray<string>.Create('alt A', 'alt B'), TArray<string>.Create('neu A', 'neu B'),
    procedure(const AFileName, AText: string)
    begin
      mNames := mNames + AFileName + '=' + AText + ';';
    end));
  Assert.AreEqual('A.pas=neu A;B.pas=neu B;', mNames);
end;

procedure TFileBatchTests.RollsBackOnError;
var
  mLog: TList<string>;
begin
  mLog := TList<string>.Create;
  try
    Assert.WillRaise(
      procedure
      begin
        TFileBatch.WriteAll(TArray<string>.Create('A.pas', 'B.pas'), TArray<string>.Create('alt A', 'alt B'),
          TArray<string>.Create('neu A', 'neu B'),
          procedure(const AFileName, AText: string)
          begin
            if AFileName = 'B.pas' then
            begin
              raise EInOutError.Create('gesperrt');
            end;
            mLog.Add(AFileName + '=' + AText);
          end);
      end, EFileBatchWrite);
    Assert.AreEqual('A.pas=neu A|A.pas=alt A', string.Join('|', mLog.ToArray));
  finally
    mLog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TFileBatchTests);

end.
