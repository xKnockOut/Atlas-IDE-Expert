unit BDLsp.Common.Index.Adapters.DiskFileSystem;

// IIndexFileSystem auf der echten Platte. Lesen erkennt die Kodierung wie
// beim Öffnen im Editor; Schreiben (Cache) geht über eine temporäre Datei,
// damit ein Abbruch keinen halben Cache hinterlässt.

interface

uses
  System.SysUtils,
  BDLsp.Common.Index.Contract;

type
  TDiskIndexFileSystem = class(TInterfacedObject, IIndexFileSystem)
  public
    function FileStamp(const AFileName: string; out AStamp: Int64): Boolean;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function WriteText(const AFileName, AText: string): Boolean;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  BDLsp.Common.Documents.FileEncoding;

{ TDiskIndexFileSystem }

function TDiskIndexFileSystem.FileStamp(const AFileName: string; out AStamp: Int64): Boolean;
var
  Age: TDateTime;
begin
  Result := FileAge(AFileName, Age);
  if Result then
    AStamp := Round(Age * MSecsPerDay)
  else
    AStamp := 0;
end;

function TDiskIndexFileSystem.ReadText(const AFileName: string; out AText: string): Boolean;
var
  Format: TFileFormat;
begin
  try
    AText := TFileEncoding.LoadFromFile(AFileName, Format);
    Result := True;
  except
    on EInOutError do
      Result := False;
    on EFOpenError do
      Result := False;
  end;
  if not Result then
    AText := '';
end;

function TDiskIndexFileSystem.WriteText(const AFileName, AText: string): Boolean;
var
  Temp: string;
begin
  Temp := AFileName + '.tmp';
  try
    ForceDirectories(ExtractFileDir(AFileName));
    TFile.WriteAllText(Temp, AText, TEncoding.UTF8);
    if FileExists(AFileName) then
      System.SysUtils.DeleteFile(AFileName);
    Result := RenameFile(Temp, AFileName);
  except
    on EInOutError do
      Result := False;
    on EFCreateError do
      Result := False;
  end;
end;

end.
