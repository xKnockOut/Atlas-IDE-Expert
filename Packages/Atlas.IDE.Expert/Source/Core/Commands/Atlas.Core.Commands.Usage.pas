unit Atlas.Core.Commands.Usage;

// Nutzung je Befehl (#600, #757), ohne VCL und Open Tools API: wie oft ein
// Befehl der IDE oder von Atlas per Maus (Hauptmenü, Kontextmenü,
// Werkzeugleiste, Befehlspalette, Willkommensseite) und wie oft über sein
// Tastenkürzel aufgerufen wurde und wann zuletzt, dazu der letzte
// Tastenkürzel-Tipp und „Nicht mehr zeigen“. Die Tastenkürzel-Tipps (#600)
// entscheiden damit, die Tastenkürzel-Übersicht (#520) zeigt „selten per
// Tastatur genutzt“, und die Karte „Atlas entdecken“ (#757) wählt danach
// ihren Tipp. Beide teilen sich diese eine Zählung.
//
// Zwei Dateien, nur lokal, nichts wird versendet:
// - %LOCALAPPDATA%\Atlas\usage.json (#757): die Zählung, nur Befehlskennung,
//   Zähler und Datum (CountsToJson, ParseCounts):
//     {"format": 1, "commands": {"Atlas.CodeActions":
//       {"mouse": 2, "keyboard": 1, "lastUsed": "2026-10-15T09:30:00"}}}
//   Mit tips.usageTracking aus (Tracking = False) zählt Count nichts.
// - %LOCALAPPDATA%\Atlas\shortcut-tips.json (#600): Zustand der Tipps je
//   Befehl (ToJson, Parse) und weitere Abschnitte oberster Ebene, z. B.
//   "discover" der Karte „Atlas entdecken“ (Section, SetSection):
//     {"format": 1, "commands": {"ecClassCompletion":
//       {"lastTip": "2026-10-15T09:31:00", "never": true}},
//      "discover": {"blocked": ["rename"], "last": "codeActions"}}
//   Ältere Fassungen von #600 schrieben die Zähler mit hinein: Parse liest
//   sie noch, LoadFromFiles übernimmt sie, solange es usage.json nicht gibt,
//   und der nächste Save schreibt sie nach usage.json.
// Nicht zu verwechseln mit %APPDATA%\Atlas\usage.json (lernende Gewichtung
// der Vervollständigung, #418, Roaming); die bleibt unberührt.
//
// UTF-8 ohne BOM; Zeiten in Ortszeit als "2026-10-15T09:30:00". Schlüssel
// sind die Namen der Aktionen der IDE bzw. die Befehle der Befehlspalette von
// Atlas („Atlas.…“, TAtlasShortcutTips.AtlasCommandId); Groß- und
// Kleinschreibung zählt nicht. Fehlende Zeiten = nie.
// Erweitern: "format" steigt nur bei einer inkompatiblen Änderung; eine Datei
// mit höherem "format" liest und überschreibt diese Fassung nicht. In
// shortcut-tips.json bleiben unbekannte Felder oberster Ebene erhalten; in
// usage.json schreibt Atlas bewusst nur Kennung, Zähler und Datum.

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
    /// <summary>Zähler oder letzter Aufruf gesetzt (gehört nach usage.json).</summary>
    function HasCounts: Boolean;
    /// <summary>Letzter Tipp oder „nie“ gesetzt (gehört nach shortcut-tips.json).</summary>
    function HasTipState: Boolean;
  end;

  TAtlasCommandUsage = class
  public const
    FormatVersion = 1;
    /// <summary>Zustand der Tipps (#600) und Abschnitte wie "discover" (#757).</summary>
    FileName = 'shortcut-tips.json';
    /// <summary>Zählung je Befehl (#757): nur Kennung, Zähler, Datum.</summary>
    UsageFileName = 'usage.json';
    /// <summary>Ab so vielen Aufrufen insgesamt gilt „selten per Tastatur“.</summary>
    RarelyMinUses = 3;
  private
    FEntries: TDictionary<string, TAtlasCommandUsageEntry>;
    /// <summary>Unbekannte Felder oberster Ebene von shortcut-tips.json als JSON-Text eines Objekts; '' ohne.
    /// </summary>
    FExtra: string;
    FWritable: Boolean;
    FCountsWritable: Boolean;
    FTipsChanged: Boolean;
    FCountsChanged: Boolean;
    FTracking: Boolean;
    class function KeyOf(const AId: string): string; static;
    function GetChanged: Boolean;
    procedure SetChanged(AValue: Boolean);
    procedure ClearCounts;
    function HasAnyCounts: Boolean;
  public
    /// <summary>Selten per Tastatur: mindestens RarelyMinUses Aufrufe, davon weniger als ein Viertel über das
    /// Kürzel.</summary>
    class function IsRarelyByKeyboard(AMouse, AKeyboard: Integer): Boolean; static;
    constructor Create;
    destructor Destroy; override;
    /// <summary>&lt;ALocalAppData&gt;\Atlas\shortcut-tips.json.</summary>
    class function DefaultFile(const ALocalAppData: string): string; static;
    /// <summary>&lt;ALocalAppData&gt;\Atlas\usage.json (#757).</summary>
    class function DefaultUsageFile(const ALocalAppData: string): string; static;
    /// <summary>Zeit als "yyyy-mm-ddThh:nn:ss"; '' für 0.</summary>
    class function TimeText(ATime: TDateTime): string; static;
    /// <summary>Zeit aus TimeText (auch mit Bruchteilen und "Z"); 0, wenn nicht lesbar.</summary>
    class function TimeOf(const AText: string): TDateTime; static;
    /// <summary>Alles leeren (Tracking bleibt).</summary>
    procedure Clear;
    /// <summary>Liest shortcut-tips.json (auch Zähler älterer Fassungen); False bei kaputtem JSON (dann leer) oder
    /// höherem Format (dann leer und nicht beschreibbar).</summary>
    function Parse(const AJson: string): Boolean;
    /// <summary>Inhalt von shortcut-tips.json: Tipp-Zustand je Befehl und unbekannte Abschnitte; keine Zähler.
    /// </summary>
    function ToJson: string;
    /// <summary>Liest usage.json und ersetzt alle Zähler; der Tipp-Zustand bleibt. False bei kaputtem JSON oder
    /// höherem Format (dann wird usage.json nicht überschrieben).</summary>
    function ParseCounts(const AJson: string): Boolean;
    /// <summary>Inhalt von usage.json: nur Befehlskennung, Zähler und letzter Aufruf.</summary>
    function CountsToJson: string;
    /// <summary>Liest shortcut-tips.json; fehlt sie oder ist sie kaputt, bleibt alles leer.</summary>
    function LoadFromFile(const AFileName: string): Boolean;
    /// <summary>Liest shortcut-tips.json und usage.json. Ohne usage.json gelten Zähler einer älteren
    /// shortcut-tips.json; der nächste Save legt usage.json damit an.</summary>
    procedure LoadFromFiles(const ATipsFile, AUsageFile: string);
    /// <summary>Schreibt shortcut-tips.json über eine temporäre Datei; nicht, wenn eine neuere Fassung die Datei
    /// geschrieben hat.</summary>
    function SaveToFile(const AFileName: string): Boolean;
    /// <summary>Schreibt usage.json über eine temporäre Datei; nicht bei höherem Format in der Datei.</summary>
    function SaveCountsToFile(const AFileName: string): Boolean;
    /// <summary>Schreibt, was sich geändert hat: Tipp-Zustand nach ATipsFile, Zähler nach AUsageFile.</summary>
    procedure SaveToFiles(const ATipsFile, AUsageFile: string);
    function Find(const AId: string; out AEntry: TAtlasCommandUsageEntry): Boolean;
    /// <summary>Eintrag zu AId; ohne Eintrag ein leerer mit dieser Id.</summary>
    function Entry(const AId: string): TAtlasCommandUsageEntry;
    procedure Put(const AEntry: TAtlasCommandUsageEntry);
    /// <summary>Einen Aufruf zählen und den Zeitpunkt merken; ohne Tracking nichts.</summary>
    procedure Count(const AId: string; AInput: TAtlasCommandInput; ANow: TDateTime);
    /// <summary>Aufrufe von AId insgesamt (#757).</summary>
    function UseCount(const AId: string): Integer;
    /// <summary>„Zählung zurücksetzen“ (#757): alle Zähler und letzten Aufrufe auf null; Tipp-Zustand bleibt.
    /// </summary>
    procedure ResetCounts;
    /// <summary>Alle Einträge nach Id sortiert.</summary>
    function Entries: TArray<TAtlasCommandUsageEntry>;
    /// <summary>Abschnitt AName oberster Ebene von shortcut-tips.json als JSON-Text; '' ohne.</summary>
    function Section(const AName: string): string;
    /// <summary>Abschnitt AName setzen (JSON-Text eines Werts); '' entfernt ihn. "format" und "commands" sind
    /// vergeben.</summary>
    procedure SetSection(const AName, AJson: string);
    /// <summary>Etwas geändert seit dem letzten Lesen bzw. Schreiben.</summary>
    property Changed: Boolean read GetChanged write SetChanged;
    /// <summary>Tipp-Zustand oder Abschnitte geändert (shortcut-tips.json).</summary>
    property TipsChanged: Boolean read FTipsChanged;
    /// <summary>Zähler geändert (usage.json).</summary>
    property CountsChanged: Boolean read FCountsChanged;
    /// <summary>False, wenn shortcut-tips.json ein höheres Format hat: dann nicht überschreiben.</summary>
    property Writable: Boolean read FWritable;
    /// <summary>False, wenn usage.json ein höheres Format hat: dann nicht überschreiben.</summary>
    property CountsWritable: Boolean read FCountsWritable;
    /// <summary>tips.usageTracking (#757): False = Count zählt nichts. Vorgabe True.</summary>
    property Tracking: Boolean read FTracking write FTracking;
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

function TAtlasCommandUsageEntry.HasCounts: Boolean;
begin
  Result := (Mouse > 0) or (Keyboard > 0) or (LastUsed > 0);
end;

function TAtlasCommandUsageEntry.HasTipState: Boolean;
begin
  Result := (LastTip > 0) or Never;
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

/// <summary>JSON-Objekt aus AJson; nil bei kaputtem Text oder anderem Wert. Gehört dem Aufrufer.</summary>
function ParseObject(const AJson: string): TJSONObject;
var
  Value: TJSONValue;
begin
  Result := nil;
  Value := nil;
  // Kein Objekt: gar nicht erst parsen.
  if Copy(TrimLeft(AJson), 1, 1) <> '{' then
    Exit;
  try
    Value := TJSONObject.ParseJSONValue(AJson);
  except
    on Exception do
      Value := nil;
  end;
  if Value is TJSONObject then
    Result := TJSONObject(Value)
  else
    Value.Free;
end;

/// <summary>Über eine temporäre Datei schreiben (UTF-8 ohne BOM).</summary>
function WriteFile(const AFileName, AText: string): Boolean;
var
  Temp: string;
begin
  ForceDirectories(ExtractFileDir(AFileName));
  Temp := AFileName + '.tmp';
  TFile.WriteAllBytes(Temp, TEncoding.UTF8.GetBytes(AText));
  if FileExists(AFileName) then
    System.SysUtils.DeleteFile(AFileName);
  Result := RenameFile(Temp, AFileName);
end;

/// <summary>Format in einer vorhandenen Datei ist höher als diese Fassung kennt.</summary>
function NewerFormat(const AFileName: string): Boolean;
var
  Root: TJSONObject;
begin
  Result := False;
  if not FileExists(AFileName) then
    Exit;
  Root := ParseObject(ReadText(AFileName));
  try
    Result := (Root <> nil) and (NumberOf(Root, 'format') > TAtlasCommandUsage.FormatVersion);
  finally
    Root.Free;
  end;
end;

{ TAtlasCommandUsage }

constructor TAtlasCommandUsage.Create;
begin
  inherited Create;
  FEntries := TDictionary<string, TAtlasCommandUsageEntry>.Create;
  FWritable := True;
  FCountsWritable := True;
  FTracking := True;
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

function TAtlasCommandUsage.GetChanged: Boolean;
begin
  Result := FTipsChanged or FCountsChanged;
end;

procedure TAtlasCommandUsage.SetChanged(AValue: Boolean);
begin
  FTipsChanged := AValue;
  FCountsChanged := AValue;
end;

class function TAtlasCommandUsage.DefaultFile(const ALocalAppData: string): string;
begin
  Result := IncludeTrailingPathDelimiter(IncludeTrailingPathDelimiter(ALocalAppData) + 'Atlas') + FileName;
end;

class function TAtlasCommandUsage.DefaultUsageFile(const ALocalAppData: string): string;
begin
  Result := IncludeTrailingPathDelimiter(IncludeTrailingPathDelimiter(ALocalAppData) + 'Atlas') + UsageFileName;
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
  FCountsWritable := True;
  FTipsChanged := False;
  FCountsChanged := False;
end;

procedure TAtlasCommandUsage.ClearCounts;
var
  Keys: TArray<string>;
  Key: string;
  Entry: TAtlasCommandUsageEntry;
begin
  Keys := FEntries.Keys.ToArray;
  for Key in Keys do
  begin
    Entry := FEntries[Key];
    Entry.Mouse := 0;
    Entry.Keyboard := 0;
    Entry.LastUsed := 0;
    if Entry.HasTipState then
      FEntries[Key] := Entry
    else
      FEntries.Remove(Key);
  end;
end;

function TAtlasCommandUsage.HasAnyCounts: Boolean;
var
  Entry: TAtlasCommandUsageEntry;
begin
  Result := False;
  for Entry in FEntries.Values do
    if Entry.HasCounts then
      Exit(True);
end;

function TAtlasCommandUsage.Parse(const AJson: string): Boolean;
var
  Root, Commands, Item, Extra: TJSONObject;
  Index: Integer;
  Pair: TJSONPair;
  Entry: TAtlasCommandUsageEntry;
begin
  Clear;
  Result := False;
  Root := ParseObject(AJson);
  try
    if Root = nil then
      Exit;
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
        // Zähler nur aus älteren Fassungen von #600; heute stehen sie in usage.json.
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
    Root.Free;
  end;
end;

function TAtlasCommandUsage.ToJson: string;
var
  Root, Commands, Item: TJSONObject;
  Extra: TJSONObject;
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
      // Zähler gehören nach usage.json.
      if not Entry.HasTipState then
        Continue;
      Item := TJSONObject.Create;
      Commands.AddPair(Entry.Id, Item);
      if Entry.LastTip > 0 then
        Item.AddPair('lastTip', TimeText(Entry.LastTip));
      if Entry.Never then
        Item.AddPair('never', TJSONBool.Create(True));
    end;
    // Unbekannte Felder oberster Ebene behalten (Erweiterungen, z. B. "discover" von #757).
    if FExtra <> '' then
    begin
      Extra := ParseObject(FExtra);
      try
        if Extra <> nil then
          for Index := 0 to Extra.Count - 1 do
          begin
            Pair := Extra.Pairs[Index];
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

function TAtlasCommandUsage.ParseCounts(const AJson: string): Boolean;
var
  Root, Commands, Item: TJSONObject;
  Index: Integer;
  Pair: TJSONPair;
  Entry: TAtlasCommandUsageEntry;
begin
  Result := False;
  Root := ParseObject(AJson);
  try
    if Root = nil then
      Exit;
    if NumberOf(Root, 'format') > FormatVersion then
    begin
      // Neuere Fassung: Zähler nicht lesen und usage.json nicht überschreiben.
      FCountsWritable := False;
      Exit;
    end;
    // usage.json gilt: Zähler älterer shortcut-tips.json fallen weg.
    ClearCounts;
    if Root.GetValue('commands') is TJSONObject then
    begin
      Commands := TJSONObject(Root.GetValue('commands'));
      for Index := 0 to Commands.Count - 1 do
      begin
        Pair := Commands.Pairs[Index];
        if (Trim(Pair.JsonString.Value) = '') or not (Pair.JsonValue is TJSONObject) then
          Continue;
        Item := TJSONObject(Pair.JsonValue);
        if not FEntries.TryGetValue(KeyOf(Pair.JsonString.Value), Entry) then
          Entry := TAtlasCommandUsageEntry.Create(Trim(Pair.JsonString.Value));
        Entry.Mouse := NumberOf(Item, 'mouse');
        Entry.Keyboard := NumberOf(Item, 'keyboard');
        Entry.LastUsed := TimeOf(TextOf(Item, 'lastUsed'));
        FEntries.AddOrSetValue(KeyOf(Entry.Id), Entry);
      end;
    end;
    Result := True;
  finally
    Root.Free;
  end;
end;

function TAtlasCommandUsage.CountsToJson: string;
var
  Root, Commands, Item: TJSONObject;
  Entry: TAtlasCommandUsageEntry;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('format', TJSONNumber.Create(FormatVersion));
    Commands := TJSONObject.Create;
    Root.AddPair('commands', Commands);
    // Nur Befehlskennung, Zähler und Datum (#757): keine Dateinamen, kein Code.
    for Entry in Entries do
    begin
      if not Entry.HasCounts then
        Continue;
      Item := TJSONObject.Create;
      Commands.AddPair(Entry.Id, Item);
      Item.AddPair('mouse', TJSONNumber.Create(Entry.Mouse));
      Item.AddPair('keyboard', TJSONNumber.Create(Entry.Keyboard));
      if Entry.LastUsed > 0 then
        Item.AddPair('lastUsed', TimeText(Entry.LastUsed));
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

procedure TAtlasCommandUsage.LoadFromFiles(const ATipsFile, AUsageFile: string);
var
  Text: string;
begin
  LoadFromFile(ATipsFile);
  if (AUsageFile <> '') and FileExists(AUsageFile) then
  begin
    try
      Text := ReadText(AUsageFile);
    except
      on Exception do
        Text := '';
    end;
    ParseCounts(Text);
  end
  else if HasAnyCounts then
  begin
    // Ältere shortcut-tips.json mit Zählern: beim nächsten Speichern nach usage.json umziehen.
    FCountsChanged := True;
    FTipsChanged := True;
  end;
end;

function TAtlasCommandUsage.SaveToFile(const AFileName: string): Boolean;
var
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
    Result := WriteFile(AFileName, ToJson);
    if Result then
      FTipsChanged := False;
  except
    on Exception do
      Result := False;
  end;
end;

function TAtlasCommandUsage.SaveCountsToFile(const AFileName: string): Boolean;
begin
  Result := False;
  if (AFileName = '') or not FCountsWritable then
    Exit;
  try
    if NewerFormat(AFileName) then
    begin
      FCountsWritable := False;
      Exit;
    end;
    Result := WriteFile(AFileName, CountsToJson);
    if Result then
      FCountsChanged := False;
  except
    on Exception do
      Result := False;
  end;
end;

procedure TAtlasCommandUsage.SaveToFiles(const ATipsFile, AUsageFile: string);
begin
  if FCountsChanged then
    SaveCountsToFile(AUsageFile);
  if FTipsChanged then
    SaveToFile(ATipsFile);
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
  Entry, Old: TAtlasCommandUsageEntry;
begin
  if Trim(AEntry.Id) = '' then
    Exit;
  Entry := AEntry;
  Entry.Id := Trim(Entry.Id);
  Find(Entry.Id, Old);
  if (Old.Mouse <> Entry.Mouse) or (Old.Keyboard <> Entry.Keyboard) or (Old.LastUsed <> Entry.LastUsed) then
    FCountsChanged := True;
  if (Old.LastTip <> Entry.LastTip) or (Old.Never <> Entry.Never) then
    FTipsChanged := True;
  FEntries.AddOrSetValue(KeyOf(Entry.Id), Entry);
end;

procedure TAtlasCommandUsage.Count(const AId: string; AInput: TAtlasCommandInput; ANow: TDateTime);
var
  Entry: TAtlasCommandUsageEntry;
begin
  // tips.usageTracking aus: nichts zählen (#757).
  if not FTracking or (Trim(AId) = '') then
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

procedure TAtlasCommandUsage.ResetCounts;
begin
  if HasAnyCounts then
  begin
    ClearCounts;
    FCountsChanged := True;
    // Auch ältere shortcut-tips.json mit Zählern neu schreiben.
    FTipsChanged := True;
  end;
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

function TAtlasCommandUsage.Section(const AName: string): string;
var
  Extra: TJSONObject;
  Value: TJSONValue;
begin
  Result := '';
  if FExtra = '' then
    Exit;
  Extra := ParseObject(FExtra);
  try
    if Extra = nil then
      Exit;
    Value := Extra.GetValue(AName);
    if Value <> nil then
      Result := Value.ToJSON;
  finally
    Extra.Free;
  end;
end;

procedure TAtlasCommandUsage.SetSection(const AName, AJson: string);
var
  Extra: TJSONObject;
  Value: TJSONValue;
  Pair: TJSONPair;
begin
  if (Trim(AName) = '') or (AName = 'format') or (AName = 'commands') then
    Exit;
  Value := nil;
  if AJson <> '' then
  begin
    try
      Value := TJSONObject.ParseJSONValue(AJson);
    except
      on Exception do
        Value := nil;
    end;
    // Kaputter Text: nichts ändern.
    if Value = nil then
      Exit;
  end;
  Extra := nil;
  if FExtra <> '' then
    Extra := ParseObject(FExtra);
  if Extra = nil then
    Extra := TJSONObject.Create;
  try
    Pair := Extra.RemovePair(AName);
    Pair.Free;
    if Value <> nil then
    begin
      Extra.AddPair(AName, Value);
      Value := nil;
    end;
    if Extra.Count > 0 then
      FExtra := Extra.ToJSON
    else
      FExtra := '';
    FTipsChanged := True;
  finally
    Value.Free;
    Extra.Free;
  end;
end;

end.
