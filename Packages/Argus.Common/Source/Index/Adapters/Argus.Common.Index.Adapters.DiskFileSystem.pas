unit Argus.Common.Index.Adapters.DiskFileSystem;

// IIndexFileSystem auf der echten Platte. Lesen erkennt die Kodierung wie
// beim Öffnen im Editor; Schreiben (Cache) geht über eine temporäre Datei,
// die die alte in einem Schritt ersetzt (TFile.Replace). So sieht ein Leser
// nie einen halben Cache, auch nicht nach einem Abbruch (#184).

interface

uses
  System.SysUtils,
  Argus.Common.Index.Contract;

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
  Argus.Common.Documents.FileEncoding;

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
  Temp, Backup: string;
begin
  // Eindeutige Namen: zwei Schreiber kommen sich nicht in die Quere.
  Temp := Format('%s.%d.tmp', [AFileName, TThread.CurrentThread.ThreadID]);
  // TFile.Replace braucht eine Sicherungsdatei: Mit '' scheitert es an
  // TPath.GetFullPath('') ("Pfad ist leer"), sobald die Zieldatei existiert.
  Backup := Format('%s.%d.bak', [AFileName, TThread.CurrentThread.ThreadID]);
  try
    ForceDirectories(ExtractFileDir(AFileName));
    TFile.WriteAllText(Temp, AText, TEncoding.UTF8);
    if FileExists(AFileName) then
    begin
      TFile.Replace(Temp, AFileName, Backup);
      System.SysUtils.DeleteFile(Backup);
      Result := True;
    end
    else
      Result := RenameFile(Temp, AFileName);
  except
    on EInOutError do
      Result := False;
    on EFCreateError do
      Result := False;
    on EArgumentException do
      Result := False;
  end;
  if not Result and FileExists(Temp) then
    System.SysUtils.DeleteFile(Temp);
end;

end.
