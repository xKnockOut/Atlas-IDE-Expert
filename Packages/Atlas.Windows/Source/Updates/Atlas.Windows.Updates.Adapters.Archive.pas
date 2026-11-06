unit Atlas.Windows.Updates.Adapters.Archive;

// Platform-Feature "Updates" (#1519), Adapter: ZIP über System.Zip. Ob ein
// Eintrag sicher ist, prüft die Logik (TUpdateArchives) vor dem Entpacken.

interface

uses
  System.SysUtils,
  Atlas.Common.Updates.Contract;

type
  TUpdateWindowsArchive = class(TInterfacedObject, IUpdateArchive)
  public
    function Entries(const AZipFile: string): TArray<string>;
    procedure Extract(const AZipFile, AEntry, ATargetFile: string);
  end;

implementation

uses
  System.Classes,
  System.Zip;

{ TUpdateWindowsArchive }

function TUpdateWindowsArchive.Entries(const AZipFile: string): TArray<string>;
var
  mZip: TZipFile;
begin
  mZip := TZipFile.Create;
  try
    mZip.Open(AZipFile, zmRead);
    Result := mZip.FileNames;
    mZip.Close;
  finally
    mZip.Free;
  end;
end;

procedure TUpdateWindowsArchive.Extract(const AZipFile, AEntry, ATargetFile: string);
var
  mZip: TZipFile;
  mBytes: TBytes;
  mStream: TFileStream;
begin
  mZip := TZipFile.Create;
  try
    mZip.Open(AZipFile, zmRead);
    mZip.Read(AEntry, mBytes);
    mZip.Close;
  finally
    mZip.Free;
  end;
  ForceDirectories(ExtractFileDir(ATargetFile));
  mStream := TFileStream.Create(ATargetFile, fmCreate);
  try
    if Length(mBytes) > 0 then
    begin
      mStream.WriteBuffer(mBytes[0], Length(mBytes));
    end;
  finally
    mStream.Free;
  end;
end;

end.
