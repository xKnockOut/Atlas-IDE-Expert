unit Atlas.Linux.Projects.DelphiInstallation;

// Platform-Feature "Projects" für Linux (#1109): Gegenstück zu
// Atlas.Windows.Projects.DelphiInstallation. Unter Linux gibt es kein RAD
// Studio und keine Registry; Versions ist leer, Latest nil, und Create meldet
// wie unter Windows für eine fehlende Version EProjectError. Der Server
// indiziert dann nur das Projekt selbst (ohne RTL und VCL der Installation).

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Projects.Contract;

type
  TDelphiInstallation = class(TInterfacedObject, ILibraryPathProvider)
  private
    FVersion: string;
  public
    /// <summary>Installierte Delphi-Versionen: unter Linux keine.</summary>
    class function Versions: TArray<string>; static;
    /// <summary>Neueste Installation: unter Linux nil.</summary>
    class function Latest: ILibraryPathProvider; static;
    /// <summary>Löst EProjectError aus: Unter Linux ist keine Version installiert.</summary>
    constructor Create(const AVersion: string);
    { ILibraryPathProvider }
    function LibraryPaths(const APlatform: string): TArray<string>;
    function BrowsingPaths(const APlatform: string): TArray<string>;
    function Variables: TArray<TPair<string, string>>;
    property Version: string read FVersion;
  end;

implementation

{ TDelphiInstallation }

class function TDelphiInstallation.Versions: TArray<string>;
begin
  Result := nil;
end;

class function TDelphiInstallation.Latest: ILibraryPathProvider;
begin
  Result := nil;
end;

constructor TDelphiInstallation.Create(const AVersion: string);
begin
  inherited Create;
  FVersion := AVersion;
  raise EProjectError.CreateFmt('Delphi-Version %s ist nicht installiert', [AVersion]);
end;

function TDelphiInstallation.LibraryPaths(const APlatform: string): TArray<string>;
begin
  Result := nil;
end;

function TDelphiInstallation.BrowsingPaths(const APlatform: string): TArray<string>;
begin
  Result := nil;
end;

function TDelphiInstallation.Variables: TArray<TPair<string, string>>;
begin
  Result := nil;
end;

end.
