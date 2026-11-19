unit Atlas.Core.Tracker.Files.TestSupport;

// Dateizugriff des Trackers für Tests, die auch unter FPC laufen (Tools/Linux/FpcTests.txt): Die Umsetzung des
// Plugins (Atlas.Core.Tracker.Adapters.LocalFiles) ersetzt Dateien über Atlas.Core.Files.TextFile und braucht
// Windows. Diese hier liest und schreibt über System.IOUtils (UTF-8, ReplaceText ohne Zwischendatei); Sperre,
// Umgebung und Änderungszeit braucht kein Test, sie tun nichts.

interface

uses
  System.SysUtils,
  Atlas.Core.Tracker.Contract.Files;

type
  TAtlasTrackerTestFiles = class(TInterfacedObject, IAtlasTrackerFiles)
  public
    function FileExists(const AFileName: string): Boolean;
    function FolderExists(const AFolder: string): Boolean;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function ReadHead(const AFileName: string; AMaxBytes: Integer; out AData: TBytes): Boolean;
    function ReadTail(const AFileName: string; AMaxBytes: Integer; out AData: TBytes; out ACut: Boolean): Boolean;
    function WriteText(const AFileName, AText: string): Boolean;
    function ReplaceText(const AFileName, AText: string): Boolean;
    function WriteBytes(const AFileName: string; const AData: TBytes): Boolean;
    function DeleteFile(const AFileName: string): Boolean;
    function DeleteFolder(const AFolder: string): Boolean;
    function RemoveEmptyFolder(const AFolder: string): Boolean;
    function ForceFolder(const AFolder: string): Boolean;
    function Files(const AFolder, AMask: string): TArray<string>;
    function Folders(const AFolder: string): TArray<string>;
    function WriteTime(const APath: string): TDateTime;
    function Lock(const AFileName: string; AWaitMs: Integer): IInterface;
    function Environment(const AName: string): string;
    function TempFolder: string;
  end;

implementation

uses
  System.IOUtils;

{ TAtlasTrackerTestFiles }

function TAtlasTrackerTestFiles.FileExists(const AFileName: string): Boolean;
begin
  Result := TFile.Exists(AFileName);
end;

function TAtlasTrackerTestFiles.FolderExists(const AFolder: string): Boolean;
begin
  Result := TDirectory.Exists(AFolder);
end;

function TAtlasTrackerTestFiles.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := TFile.Exists(AFileName);
  if Result then
  begin
    AText := TFile.ReadAllText(AFileName, TEncoding.UTF8);
  end;
end;

function TAtlasTrackerTestFiles.ReadHead(const AFileName: string; AMaxBytes: Integer; out AData: TBytes): Boolean;
begin
  AData := nil;
  Result := TFile.Exists(AFileName);
  if Result then
  begin
    AData := Copy(TFile.ReadAllBytes(AFileName), 0, AMaxBytes);
  end;
end;

function TAtlasTrackerTestFiles.ReadTail(const AFileName: string; AMaxBytes: Integer; out AData: TBytes;
  out ACut: Boolean): Boolean;
begin
  AData := nil;
  ACut := False;
  Result := TFile.Exists(AFileName);
  if Result then
  begin
    AData := TFile.ReadAllBytes(AFileName);
  end;
end;

function TAtlasTrackerTestFiles.WriteText(const AFileName, AText: string): Boolean;
begin
  Result := ForceFolder(ExtractFileDir(AFileName));
  if Result then
  begin
    TFile.WriteAllText(AFileName, AText, TEncoding.UTF8);
  end;
end;

function TAtlasTrackerTestFiles.ReplaceText(const AFileName, AText: string): Boolean;
begin
  Result := WriteText(AFileName, AText);
end;

function TAtlasTrackerTestFiles.WriteBytes(const AFileName: string; const AData: TBytes): Boolean;
begin
  Result := ForceFolder(ExtractFileDir(AFileName));
  if Result then
  begin
    TFile.WriteAllBytes(AFileName, AData);
  end;
end;

function TAtlasTrackerTestFiles.DeleteFile(const AFileName: string): Boolean;
begin
  if TFile.Exists(AFileName) then
  begin
    TFile.Delete(AFileName);
  end;
  Result := not TFile.Exists(AFileName);
end;

function TAtlasTrackerTestFiles.DeleteFolder(const AFolder: string): Boolean;
begin
  if TDirectory.Exists(AFolder) then
  begin
    TDirectory.Delete(AFolder, True);
  end;
  Result := not TDirectory.Exists(AFolder);
end;

function TAtlasTrackerTestFiles.RemoveEmptyFolder(const AFolder: string): Boolean;
begin
  Result := TDirectory.Exists(AFolder) and TDirectory.IsEmpty(AFolder);
  if Result then
  begin
    TDirectory.Delete(AFolder);
  end;
end;

function TAtlasTrackerTestFiles.ForceFolder(const AFolder: string): Boolean;
begin
  Result := (AFolder = '') or ForceDirectories(AFolder);
end;

function TAtlasTrackerTestFiles.Files(const AFolder, AMask: string): TArray<string>;
var
  mName: string;
begin
  Result := nil;
  for mName in TDirectory.GetFiles(AFolder) do
  begin
    Result := Result + [mName];
  end;
end;

function TAtlasTrackerTestFiles.Folders(const AFolder: string): TArray<string>;
var
  mName: string;
begin
  Result := nil;
  for mName in TDirectory.GetDirectories(AFolder) do
  begin
    Result := Result + [mName];
  end;
end;

function TAtlasTrackerTestFiles.WriteTime(const APath: string): TDateTime;
begin
  Result := 0;
end;

function TAtlasTrackerTestFiles.Lock(const AFileName: string; AWaitMs: Integer): IInterface;
begin
  Result := nil;
end;

function TAtlasTrackerTestFiles.Environment(const AName: string): string;
begin
  Result := '';
end;

function TAtlasTrackerTestFiles.TempFolder: string;
begin
  Result := TPath.GetTempPath;
end;

end.
