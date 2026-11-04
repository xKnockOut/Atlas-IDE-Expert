unit Atlas.Core.Architecture.Commands;

// Fenster „Atlas-Architektur“ (#1118): TAtlasArchitectureCommands baut die
// Argumente der Befehle atlas.architecture (mit "compareWith" bzw.
// "compare": false, #1121) und atlas.architecture.saveReport (.json: Stand
// speichern); TAtlasArchitectureOptions trägt Umfang, Vergleich, Feinheit
// (#1366) und „Teilsysteme neu benennen“ (#1367). Ohne VCL und OTA.

interface

type
  /// <summary>Optionen der Befehle atlas.architecture und atlas.architecture.saveReport.</summary>
  TAtlasArchitectureOptions = record
    /// <summary>"projectGroup" oder "project".</summary>
    Scope: string;
    IncludeLibrary: Boolean;
    /// <summary>Pfad eines gespeicherten Stands (#1121); '' = architecture.baseline bzw. keiner.</summary>
    CompareWith: string;
    /// <summary>False: auch nicht mit architecture.baseline vergleichen.</summary>
    Compare: Boolean;
    /// <summary>Feinheit γ für diesen Aufruf (#1366); 0 = architecture.grouping.resolution des Servers.</summary>
    Resolution: Double;
    /// <summary>Einmal ohne Angleichung an den vorigen Stand rechnen (#1367, „Teilsysteme neu benennen“).</summary>
    RenameSubsystems: Boolean;
    /// <summary>Umfang und Bibliotheks-Units, Vergleich mit architecture.baseline, Feinheit des Servers.</summary>
    class function Create(const AScope: string; AIncludeLibrary: Boolean): TAtlasArchitectureOptions; static;
  end;

  TAtlasArchitectureCommands = class
  public const
    Command = 'atlas.architecture';
    SaveCommand = 'atlas.architecture.saveReport';
  public
    /// <summary>[uri, {"scope", "includeLibraryUnits", "format": "json"}] für atlas.architecture.</summary>
    class function Arguments(const AProjectUri, AScope: string; AIncludeLibrary: Boolean): string; overload; static;
    /// <summary>Wie oben mit Vergleich (#1121): ACompareWith (Pfad eines gespeicherten Stands) als "compareWith";
    /// leer und ohne ACompare "compare": false (auch nicht mit architecture.baseline vergleichen).</summary>
    class function Arguments(const AProjectUri, AScope: string; AIncludeLibrary: Boolean; const ACompareWith: string;
      ACompare: Boolean): string; overload; static;
    /// <summary>[uri, {"scope", "includeLibraryUnits", "format": "json", Vergleich, "resolution"}] (#1366).
    /// </summary>
    class function Arguments(const AProjectUri: string; const AOptions: TAtlasArchitectureOptions): string;
      overload; static;
    /// <summary>[uri, Datei, Optionen wie Arguments ohne "format"] für atlas.architecture.saveReport.</summary>
    class function SaveArguments(const AProjectUri, AFileName: string;
      const AOptions: TAtlasArchitectureOptions): string; overload; static;
    /// <summary>[uri, Datei, {"scope", "includeLibraryUnits"}] für atlas.architecture.saveReport; Datei .json
    /// speichert den Stand für den Vergleich.</summary>
    class function SaveArguments(const AProjectUri, AFileName, AScope: string;
      AIncludeLibrary: Boolean): string; overload; static;
    /// <summary>Wie oben mit Vergleich wie Arguments (Berichte bekommen den Abschnitt „Vergleich“).</summary>
    class function SaveArguments(const AProjectUri, AFileName, AScope: string; AIncludeLibrary: Boolean;
      const ACompareWith: string; ACompare: Boolean): string; overload; static;
    /// <summary>Gespeicherte Datei aus der Antwort von saveReport ({"file", "units"}); '' bei Fehler.</summary>
    class function SavedFile(const AAnswer: string): string; static;
  end;

implementation

uses
  System.JSON,
  Atlas.Core.Architecture.Model;

{ TAtlasArchitectureOptions }

class function TAtlasArchitectureOptions.Create(const AScope: string;
  AIncludeLibrary: Boolean): TAtlasArchitectureOptions;
begin
  Result.Scope := AScope;
  Result.IncludeLibrary := AIncludeLibrary;
  Result.CompareWith := '';
  Result.Compare := True;
  Result.Resolution := 0;
  Result.RenameSubsystems := False;
end;

{ TAtlasArchitectureCommands }

function Options(const AOptions: TAtlasArchitectureOptions): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('scope', AOptions.Scope);
  Result.AddPair('includeLibraryUnits', TJSONBool.Create(AOptions.IncludeLibrary));
  if AOptions.CompareWith <> '' then
  begin
    Result.AddPair('compareWith', AOptions.CompareWith);
  end
  else if not AOptions.Compare then
  begin
    Result.AddPair('compare', TJSONBool.Create(False));
  end;
  if AOptions.Resolution > 0 then
  begin
    Result.AddPair('resolution', TJSONNumber.Create(TAtlasArchResolution.Clamp(AOptions.Resolution)));
  end;
  if AOptions.RenameSubsystems then
  begin
    Result.AddPair('renameSubsystems', TJSONBool.Create(True));
  end;
end;

function ComparedOptions(const AScope: string; AIncludeLibrary: Boolean; const ACompareWith: string;
  ACompare: Boolean): TAtlasArchitectureOptions;
begin
  Result := TAtlasArchitectureOptions.Create(AScope, AIncludeLibrary);
  Result.CompareWith := ACompareWith;
  Result.Compare := ACompare;
end;

class function TAtlasArchitectureCommands.Arguments(const AProjectUri, AScope: string;
  AIncludeLibrary: Boolean): string;
begin
  Result := Arguments(AProjectUri, TAtlasArchitectureOptions.Create(AScope, AIncludeLibrary));
end;

class function TAtlasArchitectureCommands.Arguments(const AProjectUri, AScope: string; AIncludeLibrary: Boolean;
  const ACompareWith: string; ACompare: Boolean): string;
begin
  Result := Arguments(AProjectUri, ComparedOptions(AScope, AIncludeLibrary, ACompareWith, ACompare));
end;

class function TAtlasArchitectureCommands.Arguments(const AProjectUri: string;
  const AOptions: TAtlasArchitectureOptions): string;
var
  Items: TJSONArray;
  Option: TJSONObject;
begin
  Items := TJSONArray.Create;
  try
    Items.Add(AProjectUri);
    Option := Options(AOptions);
    Option.AddPair('format', 'json');
    Items.AddElement(Option);
    Result := Items.ToJSON;
  finally
    Items.Free;
  end;
end;

class function TAtlasArchitectureCommands.SaveArguments(const AProjectUri, AFileName, AScope: string;
  AIncludeLibrary: Boolean): string;
begin
  Result := SaveArguments(AProjectUri, AFileName, TAtlasArchitectureOptions.Create(AScope, AIncludeLibrary));
end;

class function TAtlasArchitectureCommands.SaveArguments(const AProjectUri, AFileName, AScope: string;
  AIncludeLibrary: Boolean; const ACompareWith: string; ACompare: Boolean): string;
begin
  Result := SaveArguments(AProjectUri, AFileName, ComparedOptions(AScope, AIncludeLibrary, ACompareWith, ACompare));
end;

class function TAtlasArchitectureCommands.SaveArguments(const AProjectUri, AFileName: string;
  const AOptions: TAtlasArchitectureOptions): string;
var
  Items: TJSONArray;
begin
  Items := TJSONArray.Create;
  try
    Items.Add(AProjectUri);
    Items.Add(AFileName);
    Items.AddElement(Options(AOptions));
    Result := Items.ToJSON;
  finally
    Items.Free;
  end;
end;

class function TAtlasArchitectureCommands.SavedFile(const AAnswer: string): string;
var
  Root: TJSONValue;
begin
  Result := '';
  Root := TJSONObject.ParseJSONValue(AAnswer);
  try
    if (Root is TJSONObject) and (TJSONObject(Root).GetValue('file') is TJSONString) then
    begin
      Result := TJSONObject(Root).GetValue('file').Value;
    end;
  finally
    Root.Free;
  end;
end;

end.
