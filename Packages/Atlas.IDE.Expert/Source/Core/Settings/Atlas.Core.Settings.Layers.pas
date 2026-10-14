unit Atlas.Core.Settings.Layers;

// Ebenen der Einstellungen im Dialog (#227): Standard aus dem Schema, globale
// Datei %APPDATA%\Atlas\settings.json und atlas.json des Projekts. Vorrang wie
// im Server: Projekt vor global vor Standard. Bearbeitet wird genau eine Datei
// (global oder Projekt); im Projekt zeigt das Modell, was global gilt, und
// „Auf global zurücksetzen“ entfernt den Schlüssel aus atlas.json.
// Geschrieben wird als Textersetzung (TAtlasJsonText): Kommentare, Reihenfolge,
// Einrückung und unbekannte Schlüssel bleiben; ohne Änderung bleibt der Text
// gleich.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Core.Settings.Schema;

type
{$SCOPEDENUMS ON}
  /// <summary>Woher der wirksame Wert einer Einstellung kommt.</summary>
  TAtlasSettingOrigin = (Default_, Global, Project);
{$SCOPEDENUMS OFF}

  TAtlasSettingsModel = class
  private
    FFields: TArray<TAtlasSettingField>;
    FText: string;
    FGlobal: Boolean;
    FOriginal: TArray<string>;
    FCurrent: TArray<string>;
    FInherited: TArray<string>;
    // Änderungen unterhalb eines Felds (einzelne Regel in "rules"), in Reihenfolge; die letzte gilt.
    FPaths: TArray<TPair<string, string>>;
    function GetCount: Integer;
    function GetField(AIndex: Integer): TAtlasSettingField;
  public
    /// <summary>AText: Inhalt der bearbeiteten Datei ('' wenn es sie nicht gibt). AGlobalText: Inhalt der
    /// globalen Datei; nur im Projektmodus (AGlobal = False) bedeutsam.</summary>
    constructor Create(const AFields: TArray<TAtlasSettingField>; const AText, AGlobalText: string;
      AGlobal: Boolean);
    /// <summary>Feld mit APath; -1 ohne.</summary>
    function IndexOf(const APath: string): Integer;
    /// <summary>Wert in der bearbeiteten Datei beim Öffnen bzw. jetzt; '' = nicht gesetzt.</summary>
    function Original(AIndex: Integer): string;
    function Current(AIndex: Integer): string;
    /// <summary>Wert der globalen Datei (Projektmodus); '' im globalen Modus.</summary>
    function Inherited_(AIndex: Integer): string;
    /// <summary>Was ohne Wert in der bearbeiteten Datei gilt: global, sonst Standard; '' ohne beides.</summary>
    function Fallback(AIndex: Integer): string;
    /// <summary>Wirksamer Wert: eigener, sonst Fallback.</summary>
    function Effective(AIndex: Integer): string;
    function Origin(AIndex: Integer): TAtlasSettingOrigin;
    /// <summary>Bedienelement nach der Art des Felds (Kontrollkästchen, Zahl, Auswahl, Liste); False für
    /// Complex und für Werte, die nicht zur Art passen (z. B. profile als Objekt): Die bearbeitet der Dialog
    /// als JSON-Text.</summary>
    function Typed(AIndex: Integer): Boolean;
    /// <summary>Setzt den eigenen Wert (JSON-Text); '' entfernt ihn.</summary>
    procedure SetValue(AIndex: Integer; const AJson: string);
    /// <summary>Eigenen Wert entfernen: im Projekt „Auf global zurücksetzen“, global „Auf Standard“.</summary>
    procedure Reset(AIndex: Integer);
    /// <summary>Ändert einen Pfad unterhalb eines Felds, z. B. "rules.no-with", ohne den übrigen Wert neu zu
    /// schreiben; '' entfernt ihn.</summary>
    procedure SetPath(const APath, AJson: string);
    /// <summary>Geänderte Pfade mit JSON-Text, '' = entfernen.</summary>
    function Changes: TArray<TPair<string, string>>;
    function Modified: Boolean;
    /// <summary>Neuer Inhalt der Datei; ohne Änderung genau der alte Text.</summary>
    function ResultText: string;
    property Count: Integer read GetCount;
    property Fields[AIndex: Integer]: TAtlasSettingField read GetField;
    property AllFields: TArray<TAtlasSettingField> read FFields;
    property Global: Boolean read FGlobal;
    property Text: string read FText;
  end;

  TAtlasSettingsFiles = class
  public const
    GlobalFolder = 'Atlas';
    GlobalName = 'settings.json';
    ProjectName = 'atlas.json';
  public
    /// <summary>Globale Datei unter AAppData (%APPDATA%); '' ohne AAppData. Wie der Server.</summary>
    class function GlobalFile(const AAppData: string): string; static;
  end;

implementation

uses
  System.IOUtils,
  Atlas.Core.Settings.JsonText;

{ TAtlasSettingsModel }

constructor TAtlasSettingsModel.Create(const AFields: TArray<TAtlasSettingField>; const AText, AGlobalText: string;
  AGlobal: Boolean);
var
  Root, GlobalRoot: TJSONObject;
  Index: Integer;
begin
  inherited Create;
  FFields := AFields;
  FText := AText;
  FGlobal := AGlobal;
  SetLength(FOriginal, Length(FFields));
  SetLength(FCurrent, Length(FFields));
  SetLength(FInherited, Length(FFields));
  Root := TAtlasJsonText.Parse(AText);
  GlobalRoot := nil;
  if not AGlobal then
    GlobalRoot := TAtlasJsonText.Parse(AGlobalText);
  try
    for Index := 0 to High(FFields) do
    begin
      if Root <> nil then
        FOriginal[Index] := TAtlasJsonText.ValueAt(Root, FFields[Index].Path);
      FCurrent[Index] := FOriginal[Index];
      if GlobalRoot <> nil then
        FInherited[Index] := TAtlasJsonText.ValueAt(GlobalRoot, FFields[Index].Path);
    end;
  finally
    GlobalRoot.Free;
    Root.Free;
  end;
end;

function TAtlasSettingsModel.GetCount: Integer;
begin
  Result := Length(FFields);
end;

function TAtlasSettingsModel.GetField(AIndex: Integer): TAtlasSettingField;
begin
  Result := FFields[AIndex];
end;

function TAtlasSettingsModel.IndexOf(const APath: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(FFields) do
    if SameText(FFields[Index].Path, APath) then
      Exit(Index);
  Result := -1;
end;

function TAtlasSettingsModel.Original(AIndex: Integer): string;
begin
  Result := FOriginal[AIndex];
end;

function TAtlasSettingsModel.Current(AIndex: Integer): string;
begin
  Result := FCurrent[AIndex];
end;

function TAtlasSettingsModel.Inherited_(AIndex: Integer): string;
begin
  Result := FInherited[AIndex];
end;

function TAtlasSettingsModel.Fallback(AIndex: Integer): string;
begin
  Result := FInherited[AIndex];
  if Result = '' then
    Result := FFields[AIndex].DefaultJson;
end;

function TAtlasSettingsModel.Effective(AIndex: Integer): string;
begin
  Result := FCurrent[AIndex];
  if Result = '' then
    Result := Fallback(AIndex);
end;

function TAtlasSettingsModel.Origin(AIndex: Integer): TAtlasSettingOrigin;
begin
  if FCurrent[AIndex] <> '' then
  begin
    if FGlobal then
      Result := TAtlasSettingOrigin.Global
    else
      Result := TAtlasSettingOrigin.Project;
  end
  else if FInherited[AIndex] <> '' then
    Result := TAtlasSettingOrigin.Global
  else
    Result := TAtlasSettingOrigin.Default_;
end;

function TAtlasSettingsModel.Typed(AIndex: Integer): Boolean;
begin
  Result := (FFields[AIndex].Kind <> TAtlasSettingKind.Complex) and FFields[AIndex].Accepts(FOriginal[AIndex]) and
    FFields[AIndex].Accepts(Fallback(AIndex));
end;

procedure TAtlasSettingsModel.SetValue(AIndex: Integer; const AJson: string);
begin
  FCurrent[AIndex] := AJson;
end;

procedure TAtlasSettingsModel.Reset(AIndex: Integer);
begin
  FCurrent[AIndex] := '';
end;

function TAtlasSettingsModel.Changes: TArray<TPair<string, string>>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to High(FFields) do
    if FCurrent[Index] <> FOriginal[Index] then
      Result := Result + [TPair<string, string>.Create(FFields[Index].Path, FCurrent[Index])];
  Result := Result + FPaths;
end;

procedure TAtlasSettingsModel.SetPath(const APath, AJson: string);
var
  Index: Integer;
begin
  for Index := 0 to High(FPaths) do
    if SameText(FPaths[Index].Key, APath) then
    begin
      FPaths[Index].Value := AJson;
      Exit;
    end;
  FPaths := FPaths + [TPair<string, string>.Create(APath, AJson)];
end;

function TAtlasSettingsModel.Modified: Boolean;
begin
  Result := Length(Changes) > 0;
end;

function TAtlasSettingsModel.ResultText: string;
var
  Pending: TArray<TPair<string, string>>;
begin
  Pending := Changes;
  if Length(Pending) = 0 then
    Exit(FText);
  Result := TAtlasJsonText.ApplyChanges(FText, Pending);
end;

{ TAtlasSettingsFiles }

class function TAtlasSettingsFiles.GlobalFile(const AAppData: string): string;
begin
  Result := '';
  if AAppData <> '' then
    Result := TPath.Combine(TPath.Combine(AAppData, GlobalFolder), GlobalName);
end;

end.
