unit Atlas.Core.Tracker.Files;

// Anmeldung des Datei- und Shellzugriffs des Trackers (#1455 Paket 2d), ohne
// VCL und Open Tools API. Atlas.IDE.Tracker.Composition meldet beim Anmelden
// des Moduls die echten Umsetzungen an (Install) und beim Abmelden wieder ab
// (Uninstall); die Tests melden die lokale Umsetzung bzw. eine Attrappe an.
// Ohne Anmeldung (vor dem Start, nach dem Abmelden) liefern Files und Shell
// leere Umsetzungen: Nichts wird gelesen, geschrieben oder geöffnet, damit
// nach dem Abmelden nichts mehr Platte oder Shell im Namen des Moduls
// erreicht (Regel 3). Zugriff aus Hintergrund-Threads ist erlaubt;
// Files und Shell geben einen eigenen Verweis zurück.

interface

uses
  System.SysUtils,
  Atlas.Core.Tracker.Contract.Files;

type
  TAtlasTrackerFiles = class
  public
    /// <summary>Umsetzungen anmelden; ersetzt frühere.</summary>
    class procedure Install(const AFiles: IAtlasTrackerFiles; const AShell: IAtlasTrackerShell); static;
    /// <summary>Wieder abmelden; danach liefern Files und Shell die leeren Umsetzungen.</summary>
    class procedure Uninstall; static;
    class function Files: IAtlasTrackerFiles; static;
    class function Shell: IAtlasTrackerShell; static;
    /// <summary>AName in AFolder (nur Text, ohne Plattenzugriff); ohne AFolder AName.</summary>
    class function Join(const AFolder, AName: string): string; static;
  end;

implementation

uses
  System.SyncObjs;

type
  /// <summary>Leere Umsetzung ohne Anmeldung: findet nichts, schreibt nichts.</summary>
  TAtlasTrackerNoFiles = class(TInterfacedObject, IAtlasTrackerFiles)
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

  /// <summary>Leere Umsetzung ohne Anmeldung: öffnet nichts.</summary>
  TAtlasTrackerNoShell = class(TInterfacedObject, IAtlasTrackerShell)
  public
    function Open(const ATarget: string): Boolean;
    function OpenFile(const AFileName: string): Boolean;
    function Reveal(const AFileName: string): Boolean;
  end;

var
  GLock: TCriticalSection;
  GFiles: IAtlasTrackerFiles;
  GShell: IAtlasTrackerShell;

{ TAtlasTrackerNoFiles }

function TAtlasTrackerNoFiles.FileExists(const AFileName: string): Boolean;
begin
  Result := False;
end;

function TAtlasTrackerNoFiles.FolderExists(const AFolder: string): Boolean;
begin
  Result := False;
end;

function TAtlasTrackerNoFiles.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := False;
end;

function TAtlasTrackerNoFiles.ReadHead(const AFileName: string; AMaxBytes: Integer; out AData: TBytes): Boolean;
begin
  AData := nil;
  Result := False;
end;

function TAtlasTrackerNoFiles.ReadTail(const AFileName: string; AMaxBytes: Integer; out AData: TBytes;
  out ACut: Boolean): Boolean;
begin
  AData := nil;
  ACut := False;
  Result := False;
end;

function TAtlasTrackerNoFiles.WriteText(const AFileName, AText: string): Boolean;
begin
  Result := False;
end;

function TAtlasTrackerNoFiles.ReplaceText(const AFileName, AText: string): Boolean;
begin
  Result := False;
end;

function TAtlasTrackerNoFiles.WriteBytes(const AFileName: string; const AData: TBytes): Boolean;
begin
  Result := False;
end;

function TAtlasTrackerNoFiles.DeleteFile(const AFileName: string): Boolean;
begin
  Result := False;
end;

function TAtlasTrackerNoFiles.DeleteFolder(const AFolder: string): Boolean;
begin
  Result := False;
end;

function TAtlasTrackerNoFiles.RemoveEmptyFolder(const AFolder: string): Boolean;
begin
  Result := False;
end;

function TAtlasTrackerNoFiles.ForceFolder(const AFolder: string): Boolean;
begin
  Result := False;
end;

function TAtlasTrackerNoFiles.Files(const AFolder, AMask: string): TArray<string>;
begin
  Result := nil;
end;

function TAtlasTrackerNoFiles.Folders(const AFolder: string): TArray<string>;
begin
  Result := nil;
end;

function TAtlasTrackerNoFiles.WriteTime(const APath: string): TDateTime;
begin
  Result := 0;
end;

function TAtlasTrackerNoFiles.Lock(const AFileName: string; AWaitMs: Integer): IInterface;
begin
  Result := nil;
end;

function TAtlasTrackerNoFiles.Environment(const AName: string): string;
begin
  Result := '';
end;

function TAtlasTrackerNoFiles.TempFolder: string;
begin
  Result := '';
end;

{ TAtlasTrackerNoShell }

function TAtlasTrackerNoShell.Open(const ATarget: string): Boolean;
begin
  Result := False;
end;

function TAtlasTrackerNoShell.OpenFile(const AFileName: string): Boolean;
begin
  Result := False;
end;

function TAtlasTrackerNoShell.Reveal(const AFileName: string): Boolean;
begin
  Result := False;
end;

{ TAtlasTrackerFiles }

class procedure TAtlasTrackerFiles.Install(const AFiles: IAtlasTrackerFiles; const AShell: IAtlasTrackerShell);
begin
  GLock.Enter;
  try
    GFiles := AFiles;
    GShell := AShell;
  finally
    GLock.Leave;
  end;
end;

class procedure TAtlasTrackerFiles.Uninstall;
begin
  Install(nil, nil);
end;

class function TAtlasTrackerFiles.Files: IAtlasTrackerFiles;
begin
  GLock.Enter;
  try
    Result := GFiles;
  finally
    GLock.Leave;
  end;
  if Result = nil then
  begin
    Result := TAtlasTrackerNoFiles.Create;
  end;
end;

class function TAtlasTrackerFiles.Shell: IAtlasTrackerShell;
begin
  GLock.Enter;
  try
    Result := GShell;
  finally
    GLock.Leave;
  end;
  if Result = nil then
  begin
    Result := TAtlasTrackerNoShell.Create;
  end;
end;

class function TAtlasTrackerFiles.Join(const AFolder, AName: string): string;
begin
  if AFolder = '' then
  begin
    Exit(AName);
  end;
  Result := IncludeTrailingPathDelimiter(AFolder) + AName;
end;

initialization
  GLock := TCriticalSection.Create;

finalization
  TAtlasTrackerFiles.Uninstall;
  FreeAndNil(GLock);

end.
