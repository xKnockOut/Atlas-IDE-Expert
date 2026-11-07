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
  mValue: TJSONValue;
begin
  Result := '';
  mValue := AObject.GetValue(AName);
  if mValue is TJSONString then
  begin
    Result := Trim(TJSONString(mValue).Value);
  end;
end;

function NumberOf(AObject: TJSONObject; const AName: string): Integer;
var
  mValue: TJSONValue;
begin
  Result := 0;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONNumber then
  begin
    Result := TJSONNumber(mValue).AsInt;
  end
  else if mValue is TJSONString then
  begin
    Result := StrToIntDef(TJSONString(mValue).Value, 0);
  end;
  if Result < 0 then
  begin
    Result := 0;
  end;
end;

function ListOf(AObject: TJSONObject; const AName: string): TArray<string>;
var
  mValue, mItem: TJSONValue;
begin
  Result := nil;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONString then
  begin
    if Trim(TJSONString(mValue).Value) <> '' then
    begin
      Result := [Trim(TJSONString(mValue).Value)];
    end;
    Exit;
  end;
  if not (mValue is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(mValue) do
  begin
    if (mItem is TJSONString) and (Trim(TJSONString(mItem).Value) <> '') then
    begin
      Result := Result + [Trim(TJSONString(mItem).Value)];
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
  mRoot, mTips, mValue: TJSONValue;
  mTip: TAtlasTip;
begin
  Result := nil;
  // Kein Objekt: gar nicht erst parsen.
  if Copy(TrimLeft(AJson), 1, 1) <> '{' then
  begin
    Exit;
  end;
  try
    mRoot := TJSONObject.ParseJSONValue(AJson);
  except
    // Kaputte Datei: keine Tipps, kein Fehler in der IDE.
    on Exception do
      mRoot := nil;
  end;
  try
    if not (mRoot is TJSONObject) then
    begin
      Exit;
    end;
    mTips := TJSONObject(mRoot).GetValue('tips');
    if not (mTips is TJSONArray) then
    begin
      Exit;
    end;
    for mValue in TJSONArray(mTips) do
    begin
      if not (mValue is TJSONObject) then
      begin
        Continue;
      end;
      mTip := TipOf(TJSONObject(mValue));
      if (mTip.Id = '') or (mTip.Title = '') or (IndexOf(Result, mTip.Id) >= 0) then
      begin
        Continue;
      end;
      Result := Result + [mTip];
    end;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasTipCatalog.IndexOf(const ATips: TAtlasTips; const AId: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ATips) do
  begin
    if SameText(ATips[mIndex].Id, Trim(AId)) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TAtlasTipCatalog.FindByCommand(const ATips: TAtlasTips; const ACommand: string;
  out ATip: TAtlasTip): Boolean;
var
  mTip: TAtlasTip;
begin
  ATip := Default(TAtlasTip);
  if Trim(ACommand) = '' then
  begin
    Exit(False);
  end;
  for mTip in ATips do
  begin
    if SameText(mTip.Command, Trim(ACommand)) then
    begin
      ATip := mTip;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasTipCatalog.FileIn(const AFolder, ARelative: string): string;
var
  mRelative: string;
begin
  Result := '';
  mRelative := Trim(ARelative);
  if (Trim(AFolder) = '') or (mRelative = '') or (Pos('..', mRelative) > 0) or (Pos(':', mRelative) > 0) or
    CharInSet(mRelative[1], ['\', '/']) then
  begin
    Exit;
  end;
  mRelative := StringReplace(mRelative, '/', PathDelim, [rfReplaceAll]);
  mRelative := StringReplace(mRelative, '\', PathDelim, [rfReplaceAll]);
  Result := IncludeTrailingPathDelimiter(AFolder) + mRelative;
end;

class function TAtlasTipCatalog.HighDpiName(const AFileName: string): string;
var
  mExtension: string;
begin
  Result := '';
  if Trim(AFileName) = '' then
  begin
    Exit;
  end;
  mExtension := ExtractFileExt(AFileName);
  Result := Copy(AFileName, 1, Length(AFileName) - Length(mExtension)) + HighDpiSuffix + mExtension;
end;

class function TAtlasTipCatalog.ImageFor(const AFileName: string; AShownWidth: Integer): string;
var
  mLarge: string;
begin
  Result := AFileName;
  if (AFileName = '') or (AShownWidth <= ImageWidth) then
  begin
    Exit;
  end;
  mLarge := HighDpiName(AFileName);
  if FileExists(mLarge) then
  begin
    Result := mLarge;
  end;
end;

end.
