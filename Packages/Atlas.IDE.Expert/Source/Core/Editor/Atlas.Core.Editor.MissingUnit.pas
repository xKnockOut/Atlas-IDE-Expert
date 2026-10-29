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
    OptionName = 'DCC_UnitSearchPath';
    Inherited_ = '$(DCC_UnitSearchPath)';
    BaseConfig = 'Base';
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
  Value: TJSONValue;
begin
  Result := nil;
  Value := TJSONObject.ParseJSONValue(AJson);
  if Value is TJSONArray then
    Result := TJSONArray(Value)
  else
    Value.Free;
end;

{ TAtlasSearchPathRequest }

class function TAtlasSearchPathRequest.TryParse(const AArgumentsJson: string;
  out ARequest: TAtlasSearchPathRequest): Boolean;
var
  Arguments: TJSONArray;
begin
  ARequest := Default(TAtlasSearchPathRequest);
  Arguments := ArgumentsOf(AArgumentsJson);
  try
    Result := (Arguments <> nil) and (Arguments.Count >= 2);
    if not Result then
      Exit;
    ARequest.ProjectFile := Arguments.Items[0].Value;
    ARequest.Folder := Trim(Arguments.Items[1].Value);
    if Arguments.Count > 2 then
      ARequest.Config := Trim(Arguments.Items[2].Value);
    if SameText(ARequest.Config, TAtlasSearchPaths.BaseConfig) then
      ARequest.Config := '';
    Result := (ARequest.ProjectFile <> '') and (ARequest.Folder <> '') and (Pos(';', ARequest.Folder) = 0);
  finally
    Arguments.Free;
  end;
end;

{ TAtlasAddUnitRequest }

class function TAtlasAddUnitRequest.TryParse(const AArgumentsJson: string; out ARequest: TAtlasAddUnitRequest):
  Boolean;
var
  Arguments: TJSONArray;
begin
  ARequest := Default(TAtlasAddUnitRequest);
  Arguments := ArgumentsOf(AArgumentsJson);
  try
    Result := (Arguments <> nil) and (Arguments.Count >= 2);
    if not Result then
      Exit;
    ARequest.ProjectFile := Arguments.Items[0].Value;
    ARequest.FileName := Arguments.Items[1].Value;
    Result := (ARequest.ProjectFile <> '') and SameText(ExtractFileExt(ARequest.FileName), '.pas');
  finally
    Arguments.Free;
  end;
end;

{ TAtlasSearchPaths }

class function TAtlasSearchPaths.TryParseInfo(const AArgumentsJson: string; out AText: string): Boolean;
var
  Arguments: TJSONArray;
begin
  AText := '';
  Arguments := ArgumentsOf(AArgumentsJson);
  try
    if (Arguments <> nil) and (Arguments.Count > 0) then
      AText := Arguments.Items[0].Value;
  finally
    Arguments.Free;
  end;
  Result := AText <> '';
end;

function Normalized(const AFolder: string): string;
begin
  Result := Trim(AFolder);
  while (Length(Result) > 1) and CharInSet(Result[Length(Result)], ['\', '/']) do
    Delete(Result, Length(Result), 1);
end;

class function TAtlasSearchPaths.Contains(const AValue, AFolder: string): Boolean;
var
  Item: string;
begin
  for Item in AValue.Split([';']) do
    if SameText(Normalized(Item), Normalized(AFolder)) then
      Exit(True);
  Result := False;
end;

class function TAtlasSearchPaths.WithFolder(const ARaw, AFolder: string; ABase: Boolean): string;
begin
  if Trim(ARaw) <> '' then
    Result := AFolder + ';' + Trim(ARaw)
  else if ABase then
    Result := AFolder
  else
    Result := AFolder + ';' + Inherited_;
end;

end.
