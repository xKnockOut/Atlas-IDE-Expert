unit Atlas.Core.Commands.Tips;

// Tippquelle von Atlas (#757), ohne VCL und Open Tools API: tips.json aus dem
// Installationsordner (Quelle im Repository: Setup/tips.json, Bilder in
// Setup/Tipps). Die Karte „Atlas entdecken“ (#757) schlägt daraus je Start
// eine Funktion vor; die Tastenkürzel-Tipps im Editor (#600) nehmen von dort
// den Titel eines Befehls. Kein Netzabruf.
//
//   {"format": 1, "tips": [{
//     "id": "codeActions",              Kennung („Nicht mehr zeigen“); sonst command
//     "command": "Atlas.CodeActions",   Befehl der Befehlspalette: Kürzel, Ausprobieren
//     "usage": ["Atlas.CodeActions"],   Befehle, deren Nutzung zählt; sonst [command]
//     "setting": "UndoMultiFile",       Plugin-Einstellung (Registry-Name); aus = Tipp aus
//     "try": "Atlas.ChangeList",        Befehl für „Ausprobieren“ ohne Beispiel; sonst command
//     "title": "…", "titleEn": "…",     Titel deutsch und englisch
//     "text": "…", "textEn": "…",       ein bis zwei Sätze
//     "image": "Tipps\\code-aktionen.png",   PNG relativ zum Installationsordner (320 × 180,
//                                             daneben code-aktionen@2x.png mit 640 × 360)
//     "sample": "Beispiele\\Entdecken.pas",  Beispieldatei für „Ausprobieren“
//     "line": 12, "column": 5}]}              Stelle darin ab 1
// Pflicht sind title und command oder id. Unbekannte Felder werden
// übergangen; doppelte Kennungen zählen einmal (die erste).
// Bilder: Die Karte zeigt sie in ImageWidth × ImageHeight (logische Pixel);
// breiter als ImageWidth Pixel (ab 125 % Skalierung) nimmt sie die Datei mit
// @2x, wenn es sie gibt (ImageFor). Erzeugt werden beide aus HTML-Vorlagen
// mit Tools/Tipps/Render-Tips.mjs.

interface

uses
  System.SysUtils;

type
  TAtlasTip = record
    Id: string;
    Command: string;
    /// <summary>Befehle, deren Nutzung für den Tipp zählt; leer = nur Command.</summary>
    Usage: TArray<string>;
    /// <summary>Name der Plugin-Einstellung wie in der Registry; '' = immer an.</summary>
    Setting: string;
    /// <summary>Befehl für „Ausprobieren“ ohne Beispieldatei, wenn Command dafür nicht taugt (etwa
    /// „Zurücknehmen“: die Liste der Änderungen statt sofort zurückzunehmen); '' = Command.</summary>
    TryCommand: string;
    Title: string;
    TitleEn: string;
    Text: string;
    TextEn: string;
    /// <summary>Bild (PNG) relativ zum Installationsordner; '' ohne.</summary>
    Image: string;
    /// <summary>Beispieldatei relativ zum Installationsordner; '' ohne.</summary>
    Sample: string;
    /// <summary>Zeile und Spalte in Sample ab 1; 0 = Anfang.</summary>
    Line: Integer;
    Column: Integer;
    /// <summary>Usage, sonst [Command]; ohne beides leer.</summary>
    function UsageIds: TArray<string>;
    /// <summary>Befehl für „Ausprobieren“: TryCommand, sonst Command.</summary>
    function TryId: string;
    /// <summary>Titel in der Sprache; ohne englischen der deutsche.</summary>
    function TitleIn(AEnglish: Boolean): string;
    function TextIn(AEnglish: Boolean): string;
  end;

  TAtlasTips = TArray<TAtlasTip>;

  TAtlasTipCatalog = class
  public const
    FileName = 'tips.json';
    /// <summary>Ordner der Bilder im Installationsordner.</summary>
    ImageFolder = 'Tipps';
    FormatVersion = 1;
    /// <summary>Anzeigegröße der Bilder in logischen Pixeln (bei 100 %) und Pixelgröße der einfachen Datei.
    /// </summary>
    ImageWidth = 320;
    ImageHeight = 180;
    /// <summary>Zusatz der Datei mit doppelter Auflösung: code-aktionen@2x.png.</summary>
    HighDpiSuffix = '@2x';
  public
    /// <summary>Tipps aus tips.json in der Reihenfolge der Datei; leer bei ungültigem Inhalt.</summary>
    class function Parse(const AJson: string): TAtlasTips; static;
    /// <summary>Index des Tipps mit Kennung AId (Groß/klein egal); -1 ohne.</summary>
    class function IndexOf(const ATips: TAtlasTips; const AId: string): Integer; static;
    /// <summary>Erster Tipp zum Befehl ACommand (Groß/klein egal).</summary>
    class function FindByCommand(const ATips: TAtlasTips; const ACommand: string; out ATip: TAtlasTip): Boolean;
      static;
    /// <summary>Datei ARelative im Ordner AFolder; '' bei absolutem Pfad, Laufwerk, „..“ oder leerem Teil.
    /// tips.json ist Teil der Installation, aber kein Ort für fremde Pfade.</summary>
    class function FileIn(const AFolder, ARelative: string): string; static;
    /// <summary>Name der Datei mit doppelter Auflösung: „…\a.png“ → „…\a@2x.png“; '' bei leerem Namen.
    /// </summary>
    class function HighDpiName(const AFileName: string): string; static;
    /// <summary>Bild für eine Anzeigebreite von AShownWidth Pixeln: breiter als ImageWidth die Datei mit @2x,
    /// wenn es sie gibt, sonst AFileName.</summary>
    class function ImageFor(const AFileName: string; AShownWidth: Integer): string; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.JSON;

{ TAtlasTip }

function TAtlasTip.UsageIds: TArray<string>;
begin
  Result := Usage;
  if (Length(Result) = 0) and (Command <> '') then
  begin
    Result := [Command];
  end;
end;

function TAtlasTip.TryId: string;
begin
  Result := TryCommand;
  if Result = '' then
  begin
    Result := Command;
  end;
end;

function TAtlasTip.TitleIn(AEnglish: Boolean): string;
begin
  Result := Title;
  if AEnglish and (TitleEn <> '') then
  begin
    Result := TitleEn;
  end;
end;

function TAtlasTip.TextIn(AEnglish: Boolean): string;
begin
  Result := Text;
  if AEnglish and (TextEn <> '') then
  begin
    Result := TextEn;
  end;
end;

{ JSON-Helfer }

function TextOf(AObject: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  Value := AObject.GetValue(AName);
  if Value is TJSONString then
  begin
    Result := Trim(TJSONString(Value).Value);
  end;
end;

function NumberOf(AObject: TJSONObject; const AName: string): Integer;
var
  Value: TJSONValue;
begin
  Result := 0;
  Value := AObject.GetValue(AName);
  if Value is TJSONNumber then
  begin
    Result := TJSONNumber(Value).AsInt;
  end
  else if Value is TJSONString then
  begin
    Result := StrToIntDef(TJSONString(Value).Value, 0);
  end;
  if Result < 0 then
  begin
    Result := 0;
  end;
end;

function ListOf(AObject: TJSONObject; const AName: string): TArray<string>;
var
  Value, Item: TJSONValue;
begin
  Result := nil;
  Value := AObject.GetValue(AName);
  if Value is TJSONString then
  begin
    if Trim(TJSONString(Value).Value) <> '' then
    begin
      Result := [Trim(TJSONString(Value).Value)];
    end;
    Exit;
  end;
  if not (Value is TJSONArray) then
  begin
    Exit;
  end;
  for Item in TJSONArray(Value) do
  begin
    if (Item is TJSONString) and (Trim(TJSONString(Item).Value) <> '') then
    begin
      Result := Result + [Trim(TJSONString(Item).Value)];
    end;
  end;
end;

{ TAtlasTipCatalog }

/// <summary>Tipp aus einem Eintrag von "tips"; ohne "id" gilt "command".</summary>
function TipOf(AItem: TJSONObject): TAtlasTip;
begin
  Result := Default(TAtlasTip);
  Result.Command := TextOf(AItem, 'command');
  Result.Id := TextOf(AItem, 'id');
  if Result.Id = '' then
  begin
    Result.Id := Result.Command;
  end;
  Result.Usage := ListOf(AItem, 'usage');
  Result.Setting := TextOf(AItem, 'setting');
  Result.TryCommand := TextOf(AItem, 'try');
  Result.Title := TextOf(AItem, 'title');
  Result.TitleEn := TextOf(AItem, 'titleEn');
  Result.Text := TextOf(AItem, 'text');
  Result.TextEn := TextOf(AItem, 'textEn');
  Result.Image := TextOf(AItem, 'image');
  Result.Sample := TextOf(AItem, 'sample');
  Result.Line := NumberOf(AItem, 'line');
  Result.Column := NumberOf(AItem, 'column');
end;

class function TAtlasTipCatalog.Parse(const AJson: string): TAtlasTips;
var
  Root, Tips, Value: TJSONValue;
  Tip: TAtlasTip;
begin
  Result := nil;
  // Kein Objekt: gar nicht erst parsen.
  if Copy(TrimLeft(AJson), 1, 1) <> '{' then
  begin
    Exit;
  end;
  try
    Root := TJSONObject.ParseJSONValue(AJson);
  except
    // Kaputte Datei: keine Tipps, kein Fehler in der IDE.
    on Exception do
      Root := nil;
  end;
  try
    if not (Root is TJSONObject) then
    begin
      Exit;
    end;
    Tips := TJSONObject(Root).GetValue('tips');
    if not (Tips is TJSONArray) then
    begin
      Exit;
    end;
    for Value in TJSONArray(Tips) do
    begin
      if not (Value is TJSONObject) then
      begin
        Continue;
      end;
      Tip := TipOf(TJSONObject(Value));
      if (Tip.Id = '') or (Tip.Title = '') or (IndexOf(Result, Tip.Id) >= 0) then
      begin
        Continue;
      end;
      Result := Result + [Tip];
    end;
  finally
    Root.Free;
  end;
end;

class function TAtlasTipCatalog.IndexOf(const ATips: TAtlasTips; const AId: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(ATips) do
  begin
    if SameText(ATips[Index].Id, Trim(AId)) then
    begin
      Exit(Index);
    end;
  end;
  Result := -1;
end;

class function TAtlasTipCatalog.FindByCommand(const ATips: TAtlasTips; const ACommand: string;
  out ATip: TAtlasTip): Boolean;
var
  Tip: TAtlasTip;
begin
  ATip := Default(TAtlasTip);
  if Trim(ACommand) = '' then
  begin
    Exit(False);
  end;
  for Tip in ATips do
  begin
    if SameText(Tip.Command, Trim(ACommand)) then
    begin
      ATip := Tip;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasTipCatalog.FileIn(const AFolder, ARelative: string): string;
var
  Relative: string;
begin
  Result := '';
  Relative := Trim(ARelative);
  if (Trim(AFolder) = '') or (Relative = '') or (Pos('..', Relative) > 0) or (Pos(':', Relative) > 0) or
    CharInSet(Relative[1], ['\', '/']) then
  begin
    Exit;
  end;
  Relative := StringReplace(Relative, '/', PathDelim, [rfReplaceAll]);
  Relative := StringReplace(Relative, '\', PathDelim, [rfReplaceAll]);
  Result := IncludeTrailingPathDelimiter(AFolder) + Relative;
end;

class function TAtlasTipCatalog.HighDpiName(const AFileName: string): string;
var
  Extension: string;
begin
  Result := '';
  if Trim(AFileName) = '' then
  begin
    Exit;
  end;
  Extension := ExtractFileExt(AFileName);
  Result := Copy(AFileName, 1, Length(AFileName) - Length(Extension)) + HighDpiSuffix + Extension;
end;

class function TAtlasTipCatalog.ImageFor(const AFileName: string; AShownWidth: Integer): string;
var
  Large: string;
begin
  Result := AFileName;
  if (AFileName = '') or (AShownWidth <= ImageWidth) then
  begin
    Exit;
  end;
  Large := HighDpiName(AFileName);
  if FileExists(Large) then
  begin
    Result := Large;
  end;
end;

end.
