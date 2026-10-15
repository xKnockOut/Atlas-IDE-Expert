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
//     "title": "…", "titleEn": "…",     Titel deutsch und englisch
//     "text": "…", "textEn": "…",       ein bis zwei Sätze
//     "image": "Tipps\\code-aktionen.png",   PNG relativ zum Installationsordner
//     "sample": "Beispiele\\Entdecken.pas",  Beispieldatei für „Ausprobieren“
//     "line": 12, "column": 5}]}              Stelle darin ab 1
// Pflicht sind title und command oder id. Unbekannte Felder werden
// übergangen; doppelte Kennungen zählen einmal (die erste).

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
  end;

implementation

uses
  System.JSON;

{ TAtlasTip }

function TAtlasTip.UsageIds: TArray<string>;
begin
  Result := Usage;
  if (Length(Result) = 0) and (Command <> '') then
    Result := [Command];
end;

function TAtlasTip.TitleIn(AEnglish: Boolean): string;
begin
  Result := Title;
  if AEnglish and (TitleEn <> '') then
    Result := TitleEn;
end;

function TAtlasTip.TextIn(AEnglish: Boolean): string;
begin
  Result := Text;
  if AEnglish and (TextEn <> '') then
    Result := TextEn;
end;

{ JSON-Helfer }

function TextOf(AObject: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  Value := AObject.GetValue(AName);
  if Value is TJSONString then
    Result := Trim(TJSONString(Value).Value);
end;

function NumberOf(AObject: TJSONObject; const AName: string): Integer;
var
  Value: TJSONValue;
begin
  Result := 0;
  Value := AObject.GetValue(AName);
  if Value is TJSONNumber then
    Result := TJSONNumber(Value).AsInt
  else if Value is TJSONString then
    Result := StrToIntDef(TJSONString(Value).Value, 0);
  if Result < 0 then
    Result := 0;
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
      Result := [Trim(TJSONString(Value).Value)];
    Exit;
  end;
  if not (Value is TJSONArray) then
    Exit;
  for Item in TJSONArray(Value) do
    if (Item is TJSONString) and (Trim(TJSONString(Item).Value) <> '') then
      Result := Result + [Trim(TJSONString(Item).Value)];
end;

{ TAtlasTipCatalog }

class function TAtlasTipCatalog.Parse(const AJson: string): TAtlasTips;
var
  Root, Tips, Value: TJSONValue;
  Item: TJSONObject;
  Tip: TAtlasTip;
begin
  Result := nil;
  // Kein Objekt: gar nicht erst parsen.
  if Copy(TrimLeft(AJson), 1, 1) <> '{' then
    Exit;
  try
    Root := TJSONObject.ParseJSONValue(AJson);
  except
    // Kaputte Datei: keine Tipps, kein Fehler in der IDE.
    on Exception do
      Root := nil;
  end;
  try
    if not (Root is TJSONObject) then
      Exit;
    Tips := TJSONObject(Root).GetValue('tips');
    if not (Tips is TJSONArray) then
      Exit;
    for Value in TJSONArray(Tips) do
    begin
      if not (Value is TJSONObject) then
        Continue;
      Item := TJSONObject(Value);
      Tip := Default(TAtlasTip);
      Tip.Command := TextOf(Item, 'command');
      Tip.Id := TextOf(Item, 'id');
      if Tip.Id = '' then
        Tip.Id := Tip.Command;
      Tip.Usage := ListOf(Item, 'usage');
      Tip.Setting := TextOf(Item, 'setting');
      Tip.Title := TextOf(Item, 'title');
      Tip.TitleEn := TextOf(Item, 'titleEn');
      Tip.Text := TextOf(Item, 'text');
      Tip.TextEn := TextOf(Item, 'textEn');
      Tip.Image := TextOf(Item, 'image');
      Tip.Sample := TextOf(Item, 'sample');
      Tip.Line := NumberOf(Item, 'line');
      Tip.Column := NumberOf(Item, 'column');
      if (Tip.Id = '') or (Tip.Title = '') or (IndexOf(Result, Tip.Id) >= 0) then
        Continue;
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
    if SameText(ATips[Index].Id, Trim(AId)) then
      Exit(Index);
  Result := -1;
end;

class function TAtlasTipCatalog.FindByCommand(const ATips: TAtlasTips; const ACommand: string;
  out ATip: TAtlasTip): Boolean;
var
  Tip: TAtlasTip;
begin
  ATip := Default(TAtlasTip);
  if Trim(ACommand) = '' then
    Exit(False);
  for Tip in ATips do
    if SameText(Tip.Command, Trim(ACommand)) then
    begin
      ATip := Tip;
      Exit(True);
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
    Exit;
  Relative := StringReplace(Relative, '/', PathDelim, [rfReplaceAll]);
  Relative := StringReplace(Relative, '\', PathDelim, [rfReplaceAll]);
  Result := IncludeTrailingPathDelimiter(AFolder) + Relative;
end;

end.
