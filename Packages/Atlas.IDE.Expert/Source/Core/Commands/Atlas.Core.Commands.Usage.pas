unit Atlas.Core.Commands.Usage;

// Nutzung je Befehl (#600), ohne VCL und Open Tools API: wie oft ein Befehl
// der IDE oder von Atlas per Maus (Hauptmenü, Kontextmenü, Werkzeugleiste,
// Befehlspalette, Willkommensseite) und wie oft über sein Tastenkürzel
// aufgerufen wurde, dazu der letzte Aufruf, der letzte Tastenkürzel-Tipp und
// „Nicht mehr zeigen“. Die Tastenkürzel-Tipps (#600) entscheiden damit, die
// Tastenkürzel-Übersicht (#520) zeigt „selten per Tastatur genutzt“, und die
// Willkommensseite (#757 „Atlas entdecken“) kann dieselbe Zählung lesen
// (TAtlasCommandUsage.LoadFromFile, UseCount).
//
// Ablage: %LOCALAPPDATA%\Atlas\shortcut-tips.json, nur lokal. Nicht zu
// verwechseln mit %APPDATA%\Atlas\usage.json (lernende Gewichtung der
// Vervollständigung, #418); die bleibt unberührt.
//
// Format 1 (UTF-8 ohne BOM; Zeiten in Ortszeit als "2026-10-15T09:30:00"):
//   {
//     "format": 1,
//     "commands": {
//       "ecClassCompletion": {"mouse": 2, "keyboard": 1,
//         "lastUsed": "…", "lastTip": "…", "never": false},
//       "Atlas.CodeActions": {…}
//     }
//   }
// Schlüssel sind die Namen der Aktionen der IDE bzw. die Befehle der
// Befehlspalette von Atlas („Atlas.…“, TAtlasShortcutTips.AtlasCommandId);
// Groß- und Kleinschreibung zählt nicht. Fehlende Zeiten = nie.
// Erweitern: Neue Felder oberster Ebene bleiben beim Schreiben erhalten;
// "format" steigt nur bei einer inkompatiblen Änderung, eine Datei mit
// höherem "format" liest und überschreibt diese Fassung nicht (Writable).

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  {$SCOPEDENUMS ON}
  /// <summary>Wie ein Befehl aufgerufen wurde: Mouse = Menü, Kontextmenü, Werkzeugleiste, Palette;
  /// Keyboard = über sein Tastenkürzel.</summary>
  TAtlasCommandInput = (Mouse, Keyboard);
  {$SCOPEDENUMS OFF}

  /// <summary>Nutzung eines Befehls.</summary>
  TAtlasCommandUsageEntry = record
    /// <summary>Name der Aktion der IDE bzw. Befehl der Palette von Atlas.</summary>
    Id: string;
    /// <summary>Aufrufe per Maus (Menü, Kontextmenü, Werkzeugleiste, Befehlspalette).</summary>
    Mouse: Integer;
    /// <summary>Aufrufe über das Tastenkürzel.</summary>
    Keyboard: Integer;
    /// <summary>Letzter Aufruf (Ortszeit); 0 = nie.</summary>
    LastUsed: TDateTime;
    /// <summary>Letzter Tastenkürzel-Tipp (Ortszeit); 0 = nie.</summary>
    LastTip: TDateTime;
    /// <summary>„Nicht mehr zeigen“: für diesen Befehl kein Tipp mehr.</summary>
    Never: Boolean;
    class function Create(const AId: string): TAtlasCommandUsageEntry; static;
    /// <summary>Alle Aufrufe.</summary>
    function Total: Integer;
    /// <summary>Selten per Tastatur (#520): mindestens drei Aufrufe, davon weniger als ein Viertel über das
    /// Kürzel.</summary>
    function RarelyByKeyboard: Boolean;
  end;

  TAtlasCommandUsage = class
  public const
    FormatVersion = 1;
    FileName = 'shortcut-tips.json';
    /// <summary>Ab so vielen Aufrufen insgesamt gilt „selten per Tastatur“.</summary>
    RarelyMinUses = 3;
  private
    FEntries: TDictionary<string, TAtlasCommandUsageEntry>;
    /// <summary>Unbekannte Felder oberster Ebene als JSON-Text eines Objekts; '' ohne.</summary>
    FExtra: string;
    FWritable: Boolean;
    FChanged: Boolean;
    class function KeyOf(const AId: string): string; static;
  public
    /// <summary>Selten per Tastatur: mindestens RarelyMinUses Aufrufe, davon weniger als ein Viertel über das
    /// Kürzel.</summary>
    class function IsRarelyByKeyboard(AMouse, AKeyboard: Integer): Boolean; static;
    constructor Create;
    destructor Destroy; override;
    /// <summary>&lt;ALocalAppData&gt;\Atlas\shortcut-tips.json.</summary>
    class function DefaultFile(const ALocalAppData: string): string; static;
    /// <summary>Zeit als "yyyy-mm-ddThh:nn:ss"; '' für 0.</summary>
    class function TimeText(ATime: TDateTime): string; static;
    /// <summary>Zeit aus TimeText (auch mit Bruchteilen und "Z"); 0, wenn nicht lesbar.</summary>
    class function TimeOf(const AText: string): TDateTime; static;
    procedure Clear;
    /// <summary>Liest AJson; False bei kaputtem JSON (dann leer) oder höherem Format (dann leer und nicht
    /// beschreibbar).</summary>
    function Parse(const AJson: string): Boolean;
    function ToJson: string;
    /// <summary>Liest die Datei; fehlt sie oder ist sie kaputt, bleibt die Zählung leer.</summary>
    function LoadFromFile(const AFileName: string): Boolean;
    /// <summary>Schreibt über eine temporäre Datei; nicht, wenn eine neuere Fassung die Datei geschrieben hat.
    /// </summary>
    function SaveToFile(const AFileName: string): Boolean;
    function Find(const AId: string; out AEntry: TAtlasCommandUsageEntry): Boolean;
    /// <summary>Eintrag zu AId; ohne Eintrag ein leerer mit dieser Id.</summary>
    function Entry(const AId: string): TAtlasCommandUsageEntry;
    procedure Put(const AEntry: TAtlasCommandUsageEntry);
    /// <summary>Einen Aufruf zählen und den Zeitpunkt merken.</summary>
    procedure Count(const AId: string; AInput: TAtlasCommandInput; ANow: TDateTime);
    /// <summary>Aufrufe von AId insgesamt (für #757).</summary>
    function UseCount(const AId: string): Integer;
    /// <summary>Alle Einträge nach Id sortiert.</summary>
    function Entries: TArray<TAtlasCommandUsageEntry>;
    /// <summary>Etwas geändert seit dem letzten Lesen bzw. Schreiben.</summary>
    property Changed: Boolean read FChanged write FChanged;
    /// <summary>False, wenn die Datei ein höheres Format hat: dann nicht überschreiben.</summary>
    property Writable: Boolean read FWritable;
  end;

implementation

uses
  System.IOUtils,
  System.JSON,
  System.Generics.Defaults;

{ TAtlasCommandUsageEntry }

class function TAtlasCommandUsageEntry.Create(const AId: string): TAtlasCommandUsageEntry;
begin
  Result := Default(TAtlasCommandUsageEntry);
  Result.Id := AId;
end;

function TAtlasCommandUsageEntry.Total: Integer;
begin
  Result := Mouse + Keyboard;
end;

function TAtlasCommandUsageEntry.RarelyByKeyboard: Boolean;
begin
  Result := TAtlasCommandUsage.IsRarelyByKeyboard(Mouse, Keyboard);
end;

class function TAtlasCommandUsage.IsRarelyByKeyboard(AMouse, AKeyboard: Integer): Boolean;
var
  Total: Integer;
begin
  Total := AMouse + AKeyboard;
  Result := (Total >= RarelyMinUses) and (AKeyboard * 4 < Total);
end;

{ JSON-Helfer }

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

function TextOf(AObject: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  Value := AObject.GetValue(AName);
  if Value is TJSONString then
    Result := TJSONString(Value).Value;
end;

function FlagOf(AObject: TJSONObject; const AName: string): Boolean;
var
  Value: TJSONValue;
begin
  Result := False;
  Value := AObject.GetValue(AName);
  if Value is TJSONBool then
    Result := SameText(Value.Value, 'true');
end;

function ReadText(const AFileName: string): string;
var
  Bytes: TBytes;
begin
  Bytes := TFile.ReadAllBytes(AFileName);
  // Mit oder ohne BOM.
  if (Length(Bytes) >= 3) and (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF) then
    Result := TEncoding.UTF8.GetString(Bytes, 3, Length(Bytes) - 3)
  else
    Result := TEncoding.UTF8.GetString(Bytes);
end;

{ TAtlasCommandUsage }

constructor TAtlasCommandUsage.Create;
begin
  inherited Create;
  FEntries := TDictionary<string, TAtlasCommandUsageEntry>.Create;
  FWritable := True;
end;

destructor TAtlasCommandUsage.Destroy;
begin
  FEntries.Free;
  inherited;
end;

class function TAtlasCommandUsage.KeyOf(const AId: string): string;
begin
  Result := UpperCase(Trim(AId));
end;

class function TAtlasCommandUsage.DefaultFile(const ALocalAppData: string): string;
begin
  Result := IncludeTrailingPathDelimiter(IncludeTrailingPathDelimiter(ALocalAppData) + 'Atlas') + FileName;
end;

class function TAtlasCommandUsage.TimeText(ATime: TDateTime): string;
var
  Year, Month, Day, Hour, Minute, Second, MSec: Word;
begin
  Result := '';
  if ATime <= 0 then
    Exit;
  DecodeDate(ATime, Year, Month, Day);
  DecodeTime(ATime, Hour, Minute, Second, MSec);
  Result := Format('%.4d-%.2d-%.2dT%.2d:%.2d:%.2d', [Year, Month, Day, Hour, Minute, Second]);
end;

class function TAtlasCommandUsage.TimeOf(const AText: string): TDateTime;
var
  Text: string;
  Year, Month, Day, Hour, Minute, Second: Integer;
  DatePart, TimePart: TDateTime;
begin
  Result := 0;
  Text := Trim(AText);
  if (Length(Text) < 19) or (Text[5] <> '-') or (Text[8] <> '-') or not CharInSet(Text[11], ['T', 't', ' ']) or
    (Text[14] <> ':') or (Text[17] <> ':') then
    Exit;
  Year := StrToIntDef(Copy(Text, 1, 4), -1);
  Month := StrToIntDef(Copy(Text, 6, 2), -1);
  Day := StrToIntDef(Copy(Text, 9, 2), -1);
  Hour := StrToIntDef(Copy(Text, 12, 2), -1);
  Minute := StrToIntDef(Copy(Text, 15, 2), -1);
  Second := StrToIntDef(Copy(Text, 18, 2), -1);
  if (Year < 1) or (Month < 1) or (Day < 1) or (Hour < 0) or (Minute < 0) or (Second < 0) then
    Exit;
  if not TryEncodeDate(Year, Month, Day, DatePart) or not TryEncodeTime(Hour, Minute, Second, 0, TimePart) then
    Exit;
  Result := DatePart + TimePart;
end;

procedure TAtlasCommandUsage.Clear;
begin
  FEntries.Clear;
  FExtra := '';
  FWritable := True;
  FChanged := False;
end;

function TAtlasCommandUsage.Parse(const AJson: string): Boolean;
var
  Value: TJSONValue;
  Root, Commands, Item, Extra: TJSONObject;
  Index: Integer;
  Pair: TJSONPair;
  Entry: TAtlasCommandUsageEntry;
begin
  Clear;
  Result := False;
  Value := nil;
  try
    Value := TJSONObject.ParseJSONValue(AJson);
  except
    on Exception do
      Value := nil;
  end;
  try
    if not (Value is TJSONObject) then
      Exit;
    Root := TJSONObject(Value);
    if NumberOf(Root, 'format') > FormatVersion then
    begin
      // Eine neuere Fassung hat geschrieben: nichts lesen, nichts überschreiben.
      FWritable := False;
      Exit;
    end;
    Extra := TJSONObject.Create;
    try
      for Index := 0 to Root.Count - 1 do
      begin
        Pair := Root.Pairs[Index];
        if (Pair.JsonString.Value <> 'format') and (Pair.JsonString.Value <> 'commands') then
          Extra.AddPair(Pair.JsonString.Value, TJSONValue(Pair.JsonValue.Clone));
      end;
      if Extra.Count > 0 then
        FExtra := Extra.ToJSON;
    finally
      Extra.Free;
    end;
    if Root.GetValue('commands') is TJSONObject then
    begin
      Commands := TJSONObject(Root.GetValue('commands'));
      for Index := 0 to Commands.Count - 1 do
      begin
        Pair := Commands.Pairs[Index];
        if (Trim(Pair.JsonString.Value) = '') or not (Pair.JsonValue is TJSONObject) then
          Continue;
        Item := TJSONObject(Pair.JsonValue);
        Entry := TAtlasCommandUsageEntry.Create(Trim(Pair.JsonString.Value));
        Entry.Mouse := NumberOf(Item, 'mouse');
        Entry.Keyboard := NumberOf(Item, 'keyboard');
        Entry.LastUsed := TimeOf(TextOf(Item, 'lastUsed'));
        Entry.LastTip := TimeOf(TextOf(Item, 'lastTip'));
        Entry.Never := FlagOf(Item, 'never');
        FEntries.AddOrSetValue(KeyOf(Entry.Id), Entry);
      end;
    end;
    Result := True;
  finally
    Value.Free;
  end;
end;

function TAtlasCommandUsage.ToJson: string;
var
  Root, Commands, Item: TJSONObject;
  Extra: TJSONValue;
  Entry: TAtlasCommandUsageEntry;
  Index: Integer;
  Pair: TJSONPair;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('format', TJSONNumber.Create(FormatVersion));
    Commands := TJSONObject.Create;
    Root.AddPair('commands', Commands);
    for Entry in Entries do
    begin
      Item := TJSONObject.Create;
      Commands.AddPair(Entry.Id, Item);
      Item.AddPair('mouse', TJSONNumber.Create(Entry.Mouse));
      Item.AddPair('keyboard', TJSONNumber.Create(Entry.Keyboard));
      if Entry.LastUsed > 0 then
        Item.AddPair('lastUsed', TimeText(Entry.LastUsed));
      if Entry.LastTip > 0 then
        Item.AddPair('lastTip', TimeText(Entry.LastTip));
      if Entry.Never then
        Item.AddPair('never', TJSONBool.Create(True));
    end;
    // Unbekannte Felder oberster Ebene behalten (Erweiterungen, z. B. #757).
    if FExtra <> '' then
    begin
      Extra := TJSONObject.ParseJSONValue(FExtra);
      try
        if Extra is TJSONObject then
          for Index := 0 to TJSONObject(Extra).Count - 1 do
          begin
            Pair := TJSONObject(Extra).Pairs[Index];
            Root.AddPair(Pair.JsonString.Value, TJSONValue(Pair.JsonValue.Clone));
          end;
      finally
        Extra.Free;
      end;
    end;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function TAtlasCommandUsage.LoadFromFile(const AFileName: string): Boolean;
var
  Text: string;
begin
  Clear;
  Result := False;
  if (AFileName = '') or not FileExists(AFileName) then
    Exit;
  try
    Text := ReadText(AFileName);
  except
    // Gesperrt oder unlesbar: wie ohne Datei.
    on Exception do
      Exit;
  end;
  Result := Parse(Text);
end;

function TAtlasCommandUsage.SaveToFile(const AFileName: string): Boolean;
var
  Temp: string;
  Probe: TAtlasCommandUsage;
begin
  Result := False;
  if (AFileName = '') or not FWritable then
    Exit;
  try
    // Eine neuere Fassung hat die Datei inzwischen geschrieben: nicht überschreiben.
    if FileExists(AFileName) then
    begin
      Probe := TAtlasCommandUsage.Create;
      try
        Probe.Parse(ReadText(AFileName));
        if not Probe.Writable then
        begin
          FWritable := False;
          Exit;
        end;
      finally
        Probe.Free;
      end;
    end;
    ForceDirectories(ExtractFileDir(AFileName));
    Temp := AFileName + '.tmp';
    // Ohne BOM: UTF-8 wie JSON üblich.
    TFile.WriteAllBytes(Temp, TEncoding.UTF8.GetBytes(ToJson));
    if FileExists(AFileName) then
      System.SysUtils.DeleteFile(AFileName);
    Result := RenameFile(Temp, AFileName);
    if Result then
      FChanged := False;
  except
    on Exception do
      Result := False;
  end;
end;

function TAtlasCommandUsage.Find(const AId: string; out AEntry: TAtlasCommandUsageEntry): Boolean;
begin
  Result := FEntries.TryGetValue(KeyOf(AId), AEntry);
  if not Result then
    AEntry := TAtlasCommandUsageEntry.Create(Trim(AId));
end;

function TAtlasCommandUsage.Entry(const AId: string): TAtlasCommandUsageEntry;
begin
  Find(AId, Result);
end;

procedure TAtlasCommandUsage.Put(const AEntry: TAtlasCommandUsageEntry);
var
  Entry: TAtlasCommandUsageEntry;
begin
  if Trim(AEntry.Id) = '' then
    Exit;
  Entry := AEntry;
  Entry.Id := Trim(Entry.Id);
  FEntries.AddOrSetValue(KeyOf(Entry.Id), Entry);
  FChanged := True;
end;

procedure TAtlasCommandUsage.Count(const AId: string; AInput: TAtlasCommandInput; ANow: TDateTime);
var
  Entry: TAtlasCommandUsageEntry;
begin
  if Trim(AId) = '' then
    Exit;
  Find(AId, Entry);
  if AInput = TAtlasCommandInput.Keyboard then
    Inc(Entry.Keyboard)
  else
    Inc(Entry.Mouse);
  Entry.LastUsed := ANow;
  Put(Entry);
end;

function TAtlasCommandUsage.UseCount(const AId: string): Integer;
begin
  Result := Entry(AId).Total;
end;

function TAtlasCommandUsage.Entries: TArray<TAtlasCommandUsageEntry>;
var
  List: TList<TAtlasCommandUsageEntry>;
  Entry: TAtlasCommandUsageEntry;
begin
  List := TList<TAtlasCommandUsageEntry>.Create;
  try
    for Entry in FEntries.Values do
      List.Add(Entry);
    List.Sort(TComparer<TAtlasCommandUsageEntry>.Construct(
      function(const A, B: TAtlasCommandUsageEntry): Integer
      begin
        Result := CompareText(A.Id, B.Id);
        if Result = 0 then
          Result := CompareStr(A.Id, B.Id);
      end));
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

end.
