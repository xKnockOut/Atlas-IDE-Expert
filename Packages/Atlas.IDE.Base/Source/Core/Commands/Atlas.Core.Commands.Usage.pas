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
// Lesen und Schreiben über TAtlasDataFile (Bericht N3): atomar ersetzt (früher
// Löschen und Umbenennen), eine unbrauchbare Datei liegt danach als .defekt
// daneben, eine gesperrte bleibt unverändert und wird nicht überschrieben.
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
  /// <summary>Hörer der Zählung (#757, #1455), etwa die Karte „Atlas entdecken“ eines Moduls; ein Modul stellt ihn
  /// über seinen Scope bereit. Hauptthread.</summary>
  IAtlasCommandUsageListener = interface
    ['{F66EA46F-1AE5-4CD7-94C5-3BACEC4433D8}']
    /// <summary>„Zählung zurücksetzen“ (Einstellungen): Zähler sind leer.</summary>
    procedure UsageReset;
  end;

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

  /// <summary>Dateinamen, Format und Hilfen der Befehlsnutzung; Grundlage von TAtlasCommandUsage.</summary>
  TAtlasCommandUsageFormat = class
  public const
    cFormatVersion = 1;
    /// <summary>Zustand der Tipps (#600) und Abschnitte wie "discover" (#757).</summary>
    cFileName = 'shortcut-tips.json';
    /// <summary>Zählung je Befehl (#757): nur Kennung, Zähler, Datum.</summary>
    cUsageFileName = 'usage.json';
    /// <summary>Ab so vielen Aufrufen insgesamt gilt „selten per Tastatur“.</summary>
    cRarelyMinUses = 3;
  public
    /// <summary>Selten per Tastatur: mindestens RarelyMinUses Aufrufe, davon weniger als ein Viertel über das
    /// Kürzel.</summary>
    class function IsRarelyByKeyboard(AMouse, AKeyboard: Integer): Boolean; static;
    /// <summary>&lt;ALocalAppData&gt;\Atlas\shortcut-tips.json.</summary>
    class function DefaultFile(const ALocalAppData: string): string; static;
    /// <summary>&lt;ALocalAppData&gt;\Atlas\usage.json (#757).</summary>
    class function DefaultUsageFile(const ALocalAppData: string): string; static;
    /// <summary>Zeit als "yyyy-mm-ddThh:nn:ss"; '' für 0.</summary>
    class function TimeText(ATime: TDateTime): string; static;
    /// <summary>Zeit aus TimeText (auch mit Bruchteilen und "Z"); 0, wenn nicht lesbar.</summary>
    class function TimeOf(const AText: string): TDateTime; static;
  end;

  TAtlasCommandUsage = class(TAtlasCommandUsageFormat)
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
    function GetChanged: Boolean;
    procedure SetChanged(AValue: Boolean);
    procedure ClearCounts;
    function HasAnyCounts: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
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
    /// <summary>Liest shortcut-tips.json über TAtlasDataFile.Load; fehlt sie oder ist sie unbrauchbar (dann als
    /// .defekt beiseitegelegt), bleibt alles leer. Ist sie gesperrt, bleibt sie unverändert (Writable False).
    /// True, wenn sie gelesen wurde und geschrieben werden darf.</summary>
    function LoadFromFile(const AFileName: string): Boolean;
    /// <summary>Liest shortcut-tips.json und usage.json. Ohne usage.json gelten Zähler einer älteren
    /// shortcut-tips.json; der nächste Save legt usage.json damit an.</summary>
    procedure LoadFromFiles(const ATipsFile, AUsageFile: string);
    /// <summary>Ersetzt shortcut-tips.json atomar; nicht, wenn eine neuere Fassung die Datei geschrieben hat oder
    /// sie beim Lesen gesperrt war.</summary>
    function SaveToFile(const AFileName: string): Boolean;
    /// <summary>Ersetzt usage.json atomar; nicht bei höherem Format in der Datei oder wenn sie beim Lesen gesperrt
    /// war.</summary>
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
    /// <summary>False, wenn shortcut-tips.json ein höheres Format hat oder beim Lesen gesperrt war: dann nicht
    /// überschreiben.</summary>
    property Writable: Boolean read FWritable;
    /// <summary>False, wenn usage.json ein höheres Format hat oder beim Lesen gesperrt war: dann nicht
    /// überschreiben.</summary>
    property CountsWritable: Boolean read FCountsWritable;
    /// <summary>tips.usageTracking (#757): False = Count zählt nichts. Vorgabe True.</summary>
    property Tracking: Boolean read FTracking write FTracking;
  end;

implementation

uses
  System.JSON,
  System.Generics.Defaults,
  System.Math,
  Atlas.Core.Files.DataFile,
  Atlas.Text.Json;

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

class function TAtlasCommandUsageFormat.IsRarelyByKeyboard(AMouse, AKeyboard: Integer): Boolean;
var
  mTotal: Integer;
begin
  mTotal := AMouse + AKeyboard;
  Result := (mTotal >= cRarelyMinUses) and (AKeyboard * 4 < mTotal);
end;

{ JSON-Helfer }

/// <summary>Text einer vorhandenen Datei, ohne das atomare Ersetzen durch eine zweite IDE zu blockieren;
/// EInOutError, wenn sie nicht lesbar ist.</summary>
function ReadText(const AFileName: string): string;
begin
  if not TAtlasDataFile.TryRead(AFileName, Result) then
  begin
    raise EInOutError.Create('Datendatei nicht lesbar');
  end;
end;

/// <summary>JSON-Objekt aus AJson; nil bei kaputtem Text oder anderem Wert. Gehört dem Aufrufer.</summary>
function ParseObject(const AJson: string): TJSONObject;
var
  mValue: TJSONValue;
begin
  Result := nil;
  // Kein Objekt: gar nicht erst parsen.
  if Copy(TrimLeft(AJson), 1, 1) <> '{' then
  begin
    Exit;
  end;
  try
    mValue := TJSONObject.ParseJSONValue(AJson);
  except
    on Exception do
      mValue := nil;
  end;
  if mValue is TJSONObject then
  begin
    Result := TJSONObject(mValue);
  end
  else
  begin
    mValue.Free;
  end;
end;

/// <summary>Format in einer vorhandenen Datei ist höher als diese Fassung kennt.</summary>
function NewerFormat(const AFileName: string): Boolean;
var
  mRoot: TJSONObject;
begin
  Result := False;
  if not FileExists(AFileName) then
  begin
    Exit;
  end;
  mRoot := ParseObject(ReadText(AFileName));
  try
    Result := (mRoot <> nil) and (Max(0, TJsonRead.Int(mRoot, 'format')) > TAtlasCommandUsage.cFormatVersion);
  finally
    mRoot.Free;
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

/// <summary>Schlüssel im Wörterbuch: Kennung ohne Rand, groß.</summary>
function KeyOf(const AId: string): string;
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

class function TAtlasCommandUsageFormat.DefaultFile(const ALocalAppData: string): string;
begin
  Result := IncludeTrailingPathDelimiter(IncludeTrailingPathDelimiter(ALocalAppData) + 'Atlas') + cFileName;
end;

class function TAtlasCommandUsageFormat.DefaultUsageFile(const ALocalAppData: string): string;
begin
  Result := IncludeTrailingPathDelimiter(IncludeTrailingPathDelimiter(ALocalAppData) + 'Atlas') + cUsageFileName;
end;

class function TAtlasCommandUsageFormat.TimeText(ATime: TDateTime): string;
var
  mYear, mMonth, mDay, mHour, mMinute, mSecond, mMSec: Word;
begin
  Result := '';
  if ATime <= 0 then
  begin
    Exit;
  end;
  DecodeDate(ATime, mYear, mMonth, mDay);
  DecodeTime(ATime, mHour, mMinute, mSecond, mMSec);
  Result := Format('%.4d-%.2d-%.2dT%.2d:%.2d:%.2d', [mYear, mMonth, mDay, mHour, mMinute, mSecond]);
end;

/// <summary>Hat AText die Form "yyyy-mm-ddThh:nn:ss" (auch mit Leerzeichen statt T, Rest danach erlaubt)?</summary>
function HasTimeShape(const AText: string): Boolean;
begin
  Result := (Length(AText) >= 19) and (AText[5] + AText[8] = '--') and CharInSet(AText[11], ['T', 't', ' ']) and
    (AText[14] + AText[17] = '::');
end;

class function TAtlasCommandUsageFormat.TimeOf(const AText: string): TDateTime;
var
  mText: string;
  mYear, mMonth, mDay, mHour, mMinute, mSecond: Integer;
  mDatePart, mTimePart: TDateTime;
begin
  Result := 0;
  mText := Trim(AText);
  if not HasTimeShape(mText) then
  begin
    Exit;
  end;
  mYear := StrToIntDef(Copy(mText, 1, 4), -1);
  mMonth := StrToIntDef(Copy(mText, 6, 2), -1);
  mDay := StrToIntDef(Copy(mText, 9, 2), -1);
  mHour := StrToIntDef(Copy(mText, 12, 2), -1);
  mMinute := StrToIntDef(Copy(mText, 15, 2), -1);
  mSecond := StrToIntDef(Copy(mText, 18, 2), -1);
  // Ungültige Teile (-1) lehnen TryEncodeDate und TryEncodeTime ab.
  if not TryEncodeDate(mYear, mMonth, mDay, mDatePart) or not TryEncodeTime(mHour, mMinute, mSecond, 0, mTimePart) then
  begin
    Exit;
  end;
  Result := mDatePart + mTimePart;
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
  mKeys: TArray<string>;
  mKey: string;
  mEntry: TAtlasCommandUsageEntry;
begin
  mKeys := FEntries.Keys.ToArray;
  for mKey in mKeys do
  begin
    mEntry := FEntries[mKey];
    mEntry.Mouse := 0;
    mEntry.Keyboard := 0;
    mEntry.LastUsed := 0;
    if mEntry.HasTipState then
    begin
      FEntries[mKey] := mEntry;
    end
    else
    begin
      FEntries.Remove(mKey);
    end;
  end;
end;

function TAtlasCommandUsage.HasAnyCounts: Boolean;
var
  mEntry: TAtlasCommandUsageEntry;
begin
  Result := False;
  for mEntry in FEntries.Values do
  begin
    if mEntry.HasCounts then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Felder oberster Ebene außer "format" und "commands" als JSON-Text eines Objekts; '' ohne.</summary>
function ExtraOf(ARoot: TJSONObject): string;
var
  mExtra: TJSONObject;
  mIndex: Integer;
  mPair: TJSONPair;
begin
  Result := '';
  mExtra := TJSONObject.Create;
  try
    for mIndex := 0 to ARoot.Count - 1 do
    begin
      mPair := ARoot.Pairs[mIndex];
      if (mPair.JsonString.Value <> 'format') and (mPair.JsonString.Value <> 'commands') then
      begin
        mExtra.AddPair(mPair.JsonString.Value, TJSONValue(mPair.JsonValue.Clone));
      end;
    end;
    if mExtra.Count > 0 then
    begin
      Result := mExtra.ToJSON;
    end;
  finally
    mExtra.Free;
  end;
end;

/// <summary>Einträge aus "commands" von shortcut-tips.json nach AEntries.</summary>
procedure ReadTipEntries(ACommands: TJSONObject; AEntries: TDictionary<string, TAtlasCommandUsageEntry>);
var
  mIndex: Integer;
  mPair: TJSONPair;
  mItem: TJSONObject;
  mEntry: TAtlasCommandUsageEntry;
begin
  for mIndex := 0 to ACommands.Count - 1 do
  begin
    mPair := ACommands.Pairs[mIndex];
    if (Trim(mPair.JsonString.Value) = '') or not (mPair.JsonValue is TJSONObject) then
    begin
      Continue;
    end;
    mItem := TJSONObject(mPair.JsonValue);
    mEntry := TAtlasCommandUsageEntry.Create(Trim(mPair.JsonString.Value));
    // Zähler nur aus älteren Fassungen von #600; heute stehen sie in usage.json.
    mEntry.Mouse := Max(0, TJsonRead.Int(mItem, 'mouse'));
    mEntry.Keyboard := Max(0, TJsonRead.Int(mItem, 'keyboard'));
    mEntry.LastUsed := TAtlasCommandUsage.TimeOf(TJsonRead.Text(mItem, 'lastUsed'));
    mEntry.LastTip := TAtlasCommandUsage.TimeOf(TJsonRead.Text(mItem, 'lastTip'));
    mEntry.Never := TJsonRead.Flag(mItem, 'never');
    AEntries.AddOrSetValue(KeyOf(mEntry.Id), mEntry);
  end;
end;

function TAtlasCommandUsage.Parse(const AJson: string): Boolean;
var
  mRoot: TJSONObject;
begin
  Clear;
  Result := False;
  mRoot := ParseObject(AJson);
  try
    if mRoot = nil then
    begin
      Exit;
    end;
    if Max(0, TJsonRead.Int(mRoot, 'format')) > cFormatVersion then
    begin
      // Eine neuere Fassung hat geschrieben: nichts lesen, nichts überschreiben.
      FWritable := False;
      Exit;
    end;
    FExtra := ExtraOf(mRoot);
    if mRoot.GetValue('commands') is TJSONObject then
    begin
      ReadTipEntries(TJSONObject(mRoot.GetValue('commands')), FEntries);
    end;
    Result := True;
  finally
    mRoot.Free;
  end;
end;

/// <summary>Felder des JSON-Objekts AExtra (Text, '' = keine) an ARoot anhängen.</summary>
procedure AddExtra(ARoot: TJSONObject; const AExtra: string);
var
  mExtra: TJSONObject;
  mIndex: Integer;
  mPair: TJSONPair;
begin
  // Leer oder kein Objekt: nichts anzuhängen.
  mExtra := ParseObject(AExtra);
  if mExtra = nil then
  begin
    Exit;
  end;
  try
    for mIndex := 0 to mExtra.Count - 1 do
    begin
      mPair := mExtra.Pairs[mIndex];
      ARoot.AddPair(mPair.JsonString.Value, TJSONValue(mPair.JsonValue.Clone));
    end;
  finally
    mExtra.Free;
  end;
end;

function TAtlasCommandUsage.ToJson: string;
var
  mRoot, mCommands, mItem: TJSONObject;
  mEntry: TAtlasCommandUsageEntry;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('format', TJSONNumber.Create(cFormatVersion));
    mCommands := TJSONObject.Create;
    mRoot.AddPair('commands', mCommands);
    for mEntry in Entries do
    begin
      // Zähler gehören nach usage.json.
      if not mEntry.HasTipState then
      begin
        Continue;
      end;
      mItem := TJSONObject.Create;
      mCommands.AddPair(mEntry.Id, mItem);
      if mEntry.LastTip > 0 then
      begin
        mItem.AddPair('lastTip', TimeText(mEntry.LastTip));
      end;
      if mEntry.Never then
      begin
        mItem.AddPair('never', TJSONBool.Create(True));
      end;
    end;
    // Unbekannte Felder oberster Ebene behalten (Erweiterungen, z. B. "discover" von #757).
    AddExtra(mRoot, FExtra);
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

function TAtlasCommandUsage.ParseCounts(const AJson: string): Boolean;
var
  mRoot, mCommands, mItem: TJSONObject;
  mIndex: Integer;
  mPair: TJSONPair;
  mEntry: TAtlasCommandUsageEntry;
begin
  Result := False;
  mRoot := ParseObject(AJson);
  try
    if mRoot = nil then
    begin
      Exit;
    end;
    if Max(0, TJsonRead.Int(mRoot, 'format')) > cFormatVersion then
    begin
      // Neuere Fassung: Zähler nicht lesen und usage.json nicht überschreiben.
      FCountsWritable := False;
      Exit;
    end;
    // usage.json gilt: Zähler älterer shortcut-tips.json fallen weg.
    ClearCounts;
    if mRoot.GetValue('commands') is TJSONObject then
    begin
      mCommands := TJSONObject(mRoot.GetValue('commands'));
      for mIndex := 0 to mCommands.Count - 1 do
      begin
        mPair := mCommands.Pairs[mIndex];
        if (Trim(mPair.JsonString.Value) = '') or not (mPair.JsonValue is TJSONObject) then
        begin
          Continue;
        end;
        mItem := TJSONObject(mPair.JsonValue);
        if not FEntries.TryGetValue(KeyOf(mPair.JsonString.Value), mEntry) then
        begin
          mEntry := TAtlasCommandUsageEntry.Create(Trim(mPair.JsonString.Value));
        end;
        mEntry.Mouse := Max(0, TJsonRead.Int(mItem, 'mouse'));
        mEntry.Keyboard := Max(0, TJsonRead.Int(mItem, 'keyboard'));
        mEntry.LastUsed := TimeOf(TJsonRead.Text(mItem, 'lastUsed'));
        FEntries.AddOrSetValue(KeyOf(mEntry.Id), mEntry);
      end;
    end;
    Result := True;
  finally
    mRoot.Free;
  end;
end;

function TAtlasCommandUsage.CountsToJson: string;
var
  mRoot, mCommands, mItem: TJSONObject;
  mEntry: TAtlasCommandUsageEntry;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('format', TJSONNumber.Create(cFormatVersion));
    mCommands := TJSONObject.Create;
    mRoot.AddPair('commands', mCommands);
    // Nur Befehlskennung, Zähler und Datum (#757): keine Dateinamen, kein Code.
    for mEntry in Entries do
    begin
      if not mEntry.HasCounts then
      begin
        Continue;
      end;
      mItem := TJSONObject.Create;
      mCommands.AddPair(mEntry.Id, mItem);
      mItem.AddPair('mouse', TJSONNumber.Create(mEntry.Mouse));
      mItem.AddPair('keyboard', TJSONNumber.Create(mEntry.Keyboard));
      if mEntry.LastUsed > 0 then
      begin
        mItem.AddPair('lastUsed', TimeText(mEntry.LastUsed));
      end;
    end;
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

function TAtlasCommandUsage.LoadFromFile(const AFileName: string): Boolean;
var
  mLoad: TAtlasDataLoad;
begin
  Clear;
  Result := False;
  if AFileName = '' then
  begin
    Exit;
  end;
  mLoad := TAtlasDataFile.Load(AFileName, 'Tastenkürzel-Tipps',
    function(const AText: string): Boolean
    begin
      // Höheres Format ist nicht unbrauchbar, nur nicht zu überschreiben (Parse setzt Writable).
      Result := Parse(AText) or not FWritable;
    end);
  if mLoad = TAtlasDataLoad.Kept then
  begin
    Clear;
    FWritable := False;
  end;
  Result := (mLoad = TAtlasDataLoad.Loaded) and FWritable;
end;

procedure TAtlasCommandUsage.LoadFromFiles(const ATipsFile, AUsageFile: string);
var
  mCounts: TAtlasDataLoad;
begin
  LoadFromFile(ATipsFile);
  mCounts := TAtlasDataLoad.Missing;
  if AUsageFile <> '' then
  begin
    mCounts := TAtlasDataFile.Load(AUsageFile, 'Befehlsnutzung',
      function(const AText: string): Boolean
      begin
        // Höheres Format ist nicht unbrauchbar, nur nicht zu überschreiben (ParseCounts setzt CountsWritable).
        Result := ParseCounts(AText) or not FCountsWritable;
      end);
  end;
  if mCounts = TAtlasDataLoad.Kept then
  begin
    FCountsWritable := False;
  end
  else if (mCounts <> TAtlasDataLoad.Loaded) and HasAnyCounts then
  begin
    // Ältere shortcut-tips.json mit Zählern: beim nächsten Speichern nach usage.json umziehen.
    FCountsChanged := True;
    FTipsChanged := True;
  end;
end;

function TAtlasCommandUsage.SaveToFile(const AFileName: string): Boolean;
var
  mProbe: TAtlasCommandUsage;
begin
  Result := False;
  if (AFileName = '') or not FWritable then
  begin
    Exit;
  end;
  try
    // Eine neuere Fassung hat die Datei inzwischen geschrieben: nicht überschreiben.
    if FileExists(AFileName) then
    begin
      mProbe := TAtlasCommandUsage.Create;
      try
        mProbe.Parse(ReadText(AFileName));
        if not mProbe.Writable then
        begin
          FWritable := False;
          Exit;
        end;
      finally
        mProbe.Free;
      end;
    end;
    TAtlasDataFile.Write(AFileName, ToJson);
    Result := True;
    FTipsChanged := False;
  except
    // Gesperrt, kein Platz o. Ä.: Changed bleibt gesetzt, der Grund steht einmal im Protokoll.
    on E: Exception do
      TAtlasDataFile.ReportNotWritten('Tastenkürzel-Tipps', E);
  end;
end;

function TAtlasCommandUsage.SaveCountsToFile(const AFileName: string): Boolean;
begin
  Result := False;
  if (AFileName = '') or not FCountsWritable then
  begin
    Exit;
  end;
  try
    if NewerFormat(AFileName) then
    begin
      FCountsWritable := False;
      Exit;
    end;
    TAtlasDataFile.Write(AFileName, CountsToJson);
    Result := True;
    FCountsChanged := False;
  except
    // Gesperrt, kein Platz o. Ä.: Changed bleibt gesetzt, der Grund steht einmal im Protokoll.
    on E: Exception do
      TAtlasDataFile.ReportNotWritten('Befehlsnutzung', E);
  end;
end;

procedure TAtlasCommandUsage.SaveToFiles(const ATipsFile, AUsageFile: string);
begin
  if FCountsChanged then
  begin
    SaveCountsToFile(AUsageFile);
  end;
  if FTipsChanged then
  begin
    SaveToFile(ATipsFile);
  end;
end;

function TAtlasCommandUsage.Find(const AId: string; out AEntry: TAtlasCommandUsageEntry): Boolean;
begin
  Result := FEntries.TryGetValue(KeyOf(AId), AEntry);
  if not Result then
  begin
    AEntry := TAtlasCommandUsageEntry.Create(Trim(AId));
  end;
end;

function TAtlasCommandUsage.Entry(const AId: string): TAtlasCommandUsageEntry;
begin
  Find(AId, Result);
end;

procedure TAtlasCommandUsage.Put(const AEntry: TAtlasCommandUsageEntry);
var
  mEntry, mOld: TAtlasCommandUsageEntry;
begin
  if Trim(AEntry.Id) = '' then
  begin
    Exit;
  end;
  mEntry := AEntry;
  mEntry.Id := Trim(mEntry.Id);
  Find(mEntry.Id, mOld);
  if (mOld.Mouse <> mEntry.Mouse) or (mOld.Keyboard <> mEntry.Keyboard) or (mOld.LastUsed <> mEntry.LastUsed) then
  begin
    FCountsChanged := True;
  end;
  if (mOld.LastTip <> mEntry.LastTip) or (mOld.Never <> mEntry.Never) then
  begin
    FTipsChanged := True;
  end;
  FEntries.AddOrSetValue(KeyOf(mEntry.Id), mEntry);
end;

procedure TAtlasCommandUsage.Count(const AId: string; AInput: TAtlasCommandInput; ANow: TDateTime);
var
  mEntry: TAtlasCommandUsageEntry;
begin
  // tips.usageTracking aus: nichts zählen (#757).
  if not FTracking or (Trim(AId) = '') then
  begin
    Exit;
  end;
  Find(AId, mEntry);
  if AInput = TAtlasCommandInput.Keyboard then
  begin
    Inc(mEntry.Keyboard);
  end
  else
  begin
    Inc(mEntry.Mouse);
  end;
  mEntry.LastUsed := ANow;
  Put(mEntry);
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
  mList: TList<TAtlasCommandUsageEntry>;
  mEntry: TAtlasCommandUsageEntry;
begin
  mList := TList<TAtlasCommandUsageEntry>.Create;
  try
    for mEntry in FEntries.Values do
    begin
      mList.Add(mEntry);
    end;
    mList.Sort(TComparer<TAtlasCommandUsageEntry>.Construct(
      function(const A, B: TAtlasCommandUsageEntry): Integer
      begin
        Result := CompareText(A.Id, B.Id);
        if Result = 0 then
        begin
          Result := CompareStr(A.Id, B.Id);
        end;
      end));
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

function TAtlasCommandUsage.Section(const AName: string): string;
var
  mExtra: TJSONObject;
  mValue: TJSONValue;
begin
  Result := '';
  if FExtra = '' then
  begin
    Exit;
  end;
  mExtra := ParseObject(FExtra);
  try
    if mExtra = nil then
    begin
      Exit;
    end;
    mValue := mExtra.GetValue(AName);
    if mValue <> nil then
    begin
      Result := mValue.ToJSON;
    end;
  finally
    mExtra.Free;
  end;
end;

procedure TAtlasCommandUsage.SetSection(const AName, AJson: string);
var
  mExtra: TJSONObject;
  mValue: TJSONValue;
  mPair: TJSONPair;
begin
  if (Trim(AName) = '') or (AName = 'format') or (AName = 'commands') then
  begin
    Exit;
  end;
  mValue := nil;
  if AJson <> '' then
  begin
    try
      mValue := TJSONObject.ParseJSONValue(AJson);
    except
      on Exception do
        mValue := nil;
    end;
    // Kaputter Text: nichts ändern.
    if mValue = nil then
    begin
      Exit;
    end;
  end;
  mExtra := nil;
  if FExtra <> '' then
  begin
    mExtra := ParseObject(FExtra);
  end;
  if mExtra = nil then
  begin
    mExtra := TJSONObject.Create;
  end;
  try
    mPair := mExtra.RemovePair(AName);
    mPair.Free;
    if mValue <> nil then
    begin
      mExtra.AddPair(AName, mValue);
      mValue := nil;
    end;
    if mExtra.Count > 0 then
    begin
      FExtra := mExtra.ToJSON;
    end
    else
    begin
      FExtra := '';
    end;
    FTipsChanged := True;
  finally
    mValue.Free;
    mExtra.Free;
  end;
end;

end.
