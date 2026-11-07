unit Atlas.Core.Editor.MissingUnit;

// Argumente der Client-Befehle zu „Unit nicht gefunden“ (#550) und die neue
// Suchpfadliste, ohne IDE:
//   - atlas.addSearchPath [dproj, Ordner, Konfiguration]: Ordner relativ zur
//     .dproj in DCC_UnitSearchPath der Konfiguration; Konfiguration '' = Basis,
//     dann gilt er für alle Konfigurationen.
//   - atlas.addUnitToProject [dproj, Datei].
//   - atlas.showInfo [Text].
// Eine Konfiguration ohne eigenen Wert erbt den der Basis: Atlas schreibt dann
// „Ordner;$(DCC_UnitSearchPath)“, damit das Geerbte bleibt.

interface

uses
  System.SysUtils;

type
  TAtlasSearchPathRequest = record
    ProjectFile: string;
    Folder: string;
    /// <summary>Konfiguration, z. B. Debug; '' = Basis (alle Konfigurationen).</summary>
    Config: string;
    /// <summary>Liest die Argumente von atlas.addSearchPath; False bei unvollständigen.</summary>
    class function TryParse(const AArgumentsJson: string; out ARequest: TAtlasSearchPathRequest): Boolean; static;
  end;

  TAtlasAddUnitRequest = record
    ProjectFile: string;
    FileName: string;
    /// <summary>Liest die Argumente von atlas.addUnitToProject; False bei unvollständigen.</summary>
    class function TryParse(const AArgumentsJson: string; out ARequest: TAtlasAddUnitRequest): Boolean; static;
  end;

  TAtlasSearchPaths = class
  public const
    cOptionName = 'DCC_UnitSearchPath';
    cInherited_ = '$(DCC_UnitSearchPath)';
    cBaseConfig = 'Base';
  public
    /// <summary>Text des ersten Arguments von atlas.showInfo; False ohne.</summary>
    class function TryParseInfo(const AArgumentsJson: string; out AText: string): Boolean; static;
    /// <summary>Steht AFolder schon in der Liste AValue (; getrennt, ohne Groß-/Kleinschreibung, mit oder ohne
    /// \ am Ende)?</summary>
    class function Contains(const AValue, AFolder: string): Boolean; static;
    /// <summary>Neuer Wert der Konfiguration: AFolder vorn in ARaw (eigener Wert der Konfiguration). Eine
    /// Konfiguration außer der Basis ohne eigenen Wert erbt: dann „AFolder;$(DCC_UnitSearchPath)“.</summary>
    class function WithFolder(const ARaw, AFolder: string; ABase: Boolean): string; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.JSON;

function ArgumentsOf(const AJson: string): TJSONArray;
var
  mValue: TJSONValue;
begin
  Result := nil;
  mValue := TJSONObject.ParseJSONValue(AJson);
  if mValue is TJSONArray then
  begin
    Result := TJSONArray(mValue);
  end
  else
  begin
    mValue.Free;
  end;
end;

{ TAtlasSearchPathRequest }

class function TAtlasSearchPathRequest.TryParse(const AArgumentsJson: string;
  out ARequest: TAtlasSearchPathRequest): Boolean;
var
  mArguments: TJSONArray;
begin
  ARequest := Default(TAtlasSearchPathRequest);
  mArguments := ArgumentsOf(AArgumentsJson);
  try
    Result := (mArguments <> nil) and (mArguments.Count >= 2);
    if not Result then
    begin
      Exit;
    end;
    ARequest.ProjectFile := mArguments.Items[0].Value;
    ARequest.Folder := Trim(mArguments.Items[1].Value);
    if mArguments.Count > 2 then
    begin
      ARequest.Config := Trim(mArguments.Items[2].Value);
    end;
    if SameText(ARequest.Config, TAtlasSearchPaths.cBaseConfig) then
    begin
      ARequest.Config := '';
    end;
    Result := (ARequest.ProjectFile <> '') and (ARequest.Folder <> '') and (Pos(';', ARequest.Folder) = 0);
  finally
    mArguments.Free;
  end;
end;

{ TAtlasAddUnitRequest }

class function TAtlasAddUnitRequest.TryParse(const AArgumentsJson: string; out ARequest: TAtlasAddUnitRequest):
  Boolean;
var
  mArguments: TJSONArray;
begin
  ARequest := Default(TAtlasAddUnitRequest);
  mArguments := ArgumentsOf(AArgumentsJson);
  try
    Result := (mArguments <> nil) and (mArguments.Count >= 2);
    if not Result then
    begin
      Exit;
    end;
    ARequest.ProjectFile := mArguments.Items[0].Value;
    ARequest.FileName := mArguments.Items[1].Value;
    Result := (ARequest.ProjectFile <> '') and SameText(ExtractFileExt(ARequest.FileName), '.pas');
  finally
    mArguments.Free;
  end;
end;

{ TAtlasSearchPaths }

class function TAtlasSearchPaths.TryParseInfo(const AArgumentsJson: string; out AText: string): Boolean;
var
  mArguments: TJSONArray;
begin
  AText := '';
  mArguments := ArgumentsOf(AArgumentsJson);
  try
    if (mArguments <> nil) and (mArguments.Count > 0) then
    begin
      AText := mArguments.Items[0].Value;
    end;
  finally
    mArguments.Free;
  end;
  Result := AText <> '';
end;

function Normalized(const AFolder: string): string;
begin
  Result := Trim(AFolder);
  while (Length(Result) > 1) and CharInSet(Result[Length(Result)], ['\', '/']) do
  begin
    Delete(Result, Length(Result), 1);
  end;
end;

class function TAtlasSearchPaths.Contains(const AValue, AFolder: string): Boolean;
var
  mItem: string;
begin
  for mItem in AValue.Split([';']) do
  begin
    if SameText(Normalized(mItem), Normalized(AFolder)) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasSearchPaths.WithFolder(const ARaw, AFolder: string; ABase: Boolean): string;
begin
  if Trim(ARaw) <> '' then
  begin
    Result := AFolder + ';' + Trim(ARaw);
  end
  else if ABase then
  begin
    Result := AFolder;
  end
  else
  begin
    Result := AFolder + ';' + cInherited_;
  end;
end;

end.
