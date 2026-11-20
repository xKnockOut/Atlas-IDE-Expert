unit Atlas.Core.Assistants.LinkLock;

// Assistenten-Kopplung (#2377): Anmeldung der IDE beim Kommandozeilen-Assistenten. Die IDE legt eine Lock-Datei
// <Port>.lock in den Ordner, den der Client durchsucht, mit Prozess, Arbeitsordnern, Name der IDE, Transport und
// Token. Nur hier stehen die Namen, die der Client technisch erwartet (Ordner der Lock-Dateien, Umgebungsvariable
// des Konfigurationsordners, Kopf mit dem Token); ändert der Client sie, betrifft das nur diese Unit.
// Ohne Dateisystem: Pfad, Inhalt und Token sind reine Funktionen, das Schreiben macht die IDE.

interface

uses
  System.SysUtils;

type
  TAtlasLinkLock = class
  public const
    /// <summary>Kopf, in dem der Client das Token schickt.</summary>
    cTokenHeader = 'x-claude-code-ide-authorization';
    /// <summary>Umgebungsvariable mit dem Konfigurationsordner des Clients; leer = Ordner im Benutzerprofil.
    /// </summary>
    cConfigVariable = 'CLAUDE_CONFIG_DIR';
    /// <summary>Konfigurationsordner des Clients im Benutzerprofil.</summary>
    cConfigFolder = '.claude';
    /// <summary>Unterordner mit den Lock-Dateien.</summary>
    cLockFolder = 'ide';
    cLockExtension = '.lock';
    /// <summary>Bereich der Ports, den der Client erwartet.</summary>
    cMinPort = 10000;
    cMaxPort = 65535;
    /// <summary>Bytes des Tokens (128 Bit, als 32 Hexziffern).</summary>
    cTokenBytes = 16;
    /// <summary>Name der IDE vor der Version.</summary>
    cProduct = 'RAD Studio';
  public
    /// <summary>Ordner der Lock-Dateien: AConfigDir (Wert von cConfigVariable), sonst AHome\.claude, dazu \ide.
    /// </summary>
    class function Folder(const AHome, AConfigDir: string): string; static;
    /// <summary>Lock-Datei für APort in AFolder.</summary>
    class function FileName(const AFolder: string; APort: Integer): string; static;
    /// <summary>Inhalt der Lock-Datei (JSON).</summary>
    class function Content(APid: Cardinal; const AFolders: TArray<string>; const AIdeName, AToken: string): string;
      static;
    /// <summary>Token aus ABytes (Zufall aus dem Betriebssystem) als Hexziffern in Kleinbuchstaben.</summary>
    class function TokenOf(const ABytes: TBytes): string; static;
    /// <summary>Port aus AValue (Zufall) im Bereich cMinPort bis cMaxPort.</summary>
    class function PortOf(AValue: Cardinal): Integer; static;
    /// <summary>Name der IDE für den Client: „RAD Studio“ mit Version, etwa „RAD Studio 13 (Atlas)“.</summary>
    class function IdeName(const AVersion: string): string; static;
  end;

implementation

uses
  System.JSON,
  // Inline-Funktionen von TJSONObject (H2443).
  System.Generics.Collections;

class function TAtlasLinkLock.Folder(const AHome, AConfigDir: string): string;
begin
  if AConfigDir <> '' then
  begin
    Result := IncludeTrailingPathDelimiter(AConfigDir) + cLockFolder;
  end
  else
  begin
    Result := IncludeTrailingPathDelimiter(AHome) + cConfigFolder + PathDelim + cLockFolder;
  end;
end;

class function TAtlasLinkLock.FileName(const AFolder: string; APort: Integer): string;
begin
  Result := IncludeTrailingPathDelimiter(AFolder) + IntToStr(APort) + cLockExtension;
end;

class function TAtlasLinkLock.Content(APid: Cardinal; const AFolders: TArray<string>; const AIdeName, AToken: string):
  string;
var
  mRoot: TJSONObject;
  mFolders: TJSONArray;
  mFolder: string;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('pid', TJSONNumber.Create(APid));
    mFolders := TJSONArray.Create;
    for mFolder in AFolders do
    begin
      mFolders.Add(mFolder);
    end;
    mRoot.AddPair('workspaceFolders', mFolders);
    mRoot.AddPair('ideName', AIdeName);
    mRoot.AddPair('transport', 'ws');
    mRoot.AddPair('authToken', AToken);
    Result := mRoot.ToJSON([]);
  finally
    mRoot.Free;
  end;
end;

class function TAtlasLinkLock.TokenOf(const ABytes: TBytes): string;
var
  mByte: Byte;
begin
  Result := '';
  for mByte in ABytes do
  begin
    Result := Result + LowerCase(IntToHex(mByte, 2));
  end;
end;

class function TAtlasLinkLock.PortOf(AValue: Cardinal): Integer;
begin
  Result := cMinPort + Integer(AValue mod Cardinal(cMaxPort - cMinPort + 1));
end;

class function TAtlasLinkLock.IdeName(const AVersion: string): string;
begin
  Result := cProduct;
  if AVersion <> '' then
  begin
    Result := Result + ' ' + AVersion;
  end;
  Result := Result + ' (Atlas)';
end;

end.
