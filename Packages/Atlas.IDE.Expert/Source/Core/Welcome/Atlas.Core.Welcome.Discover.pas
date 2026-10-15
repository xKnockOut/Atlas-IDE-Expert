unit Atlas.Core.Welcome.Discover;

// Karte „Atlas entdecken“ der Willkommensseite (#757), Teil ohne VCL und Open
// Tools API: welcher Tipp aus tips.json (Atlas.Core.Commands.Tips) als
// Nächstes kommt, „Zuletzt vor 3 Wochen“ und der Zustand der Karte.
// - Auswahl (Order): nur Tipps, deren Funktion eingeschaltet ist (AAllowed:
//   Einstellung an, Befehl vorhanden) und die nicht gesperrt sind. Mit
//   Nutzungszählung (tips.usageTracking) zuerst die noch nie benutzten, in
//   der Reihenfolge von tips.json, beginnend nach dem zuletzt gezeigten
//   Tipp (so kommt je Start ein anderer); dann die benutzten, am längsten
//   nicht benutzte zuerst. Ohne Zählung alle der Reihe nach, ebenfalls nach
//   dem zuletzt gezeigten. Genutzt heißt: ein Befehl aus TAtlasTip.UsageIds
//   hat Aufrufe oder einen letzten Aufruf in der Zählung (usage.json).
// - Je IDE-Start legt die IDE-Schicht die Reihenfolge einmal fest (Queue);
//   Effective, Pick und NextAfter halten sie gegen Änderungen der
//   Einstellungen und „Nicht mehr zeigen“ aktuell, ohne neu zu mischen.
// - Zustand (TAtlasDiscoverState) im Abschnitt "discover" von
//   %LOCALAPPDATA%\Atlas\shortcut-tips.json: gesperrte Tipps und der zuletzt
//   gezeigte; {"blocked": ["rename"], "last": "codeActions"}.

interface

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Commands.Usage,
  Atlas.Core.Commands.Tips;

type
{$SCOPEDENUMS ON}
  /// <summary>Hinweis zur Nutzung: None = keiner (Zählung aus), Never = „Noch nie benutzt“, sonst „Zuletzt …“.
  /// </summary>
  TAtlasDiscoverAgeKind = (None, Never, Today, Yesterday, Days, Weeks, Months, Years);
{$SCOPEDENUMS OFF}

  TAtlasDiscoverAge = record
    Kind: TAtlasDiscoverAgeKind;
    /// <summary>Anzahl Tage, Wochen, Monate bzw. Jahre.</summary>
    Count: Integer;
    class function Create(AKind: TAtlasDiscoverAgeKind; ACount: Integer): TAtlasDiscoverAge; static;
  end;

  /// <summary>Gesperrte Tipps und der zuletzt gezeigte.</summary>
  TAtlasDiscoverState = record
    Blocked: TArray<string>;
    Last: string;
    function IsBlocked(const AId: string): Boolean;
    procedure Block(const AId: string);
    /// <summary>JSON-Text des Abschnitts "discover".</summary>
    function ToJson: string;
    /// <summary>Aus dem Abschnitt; leer bei ungültigem Inhalt.</summary>
    class function Parse(const AJson: string): TAtlasDiscoverState; static;
  end;

  /// <summary>Was die Karte zeigt.</summary>
  TAtlasDiscoverCard = record
    Id: string;
    Title: string;
    Text: string;
    /// <summary>Tatsächliche Belegung des Befehls; '' ohne.</summary>
    KeyText: string;
    /// <summary>Vollständiger Pfad des Bilds; '' ohne (oder Datei fehlt).</summary>
    ImageFile: string;
    Age: TAtlasDiscoverAge;
    /// <summary>„Ausprobieren“ möglich (Beispieldatei vorhanden oder Befehl vorhanden).</summary>
    CanTry: Boolean;
    /// <summary>Stelle (ab 1) und Zahl der Tipps, die gerade in Frage kommen.</summary>
    Position: Integer;
    Count: Integer;
  end;

  TAtlasDiscover = class
  public const
    /// <summary>Abschnitt in shortcut-tips.json (TAtlasCommandUsage.Section).</summary>
    SectionName = 'discover';
  public
    /// <summary>Summe der Aufrufe und letzter Aufruf über alle Befehle des Tipps; AUsage darf nil sein.</summary>
    class function UsageOf(const ATip: TAtlasTip; AUsage: TAtlasCommandUsage; out ALastUsed: TDateTime): Integer;
      static;
    /// <summary>Funktion des Tipps eingeschaltet: Einstellung (wenn angegeben) vorhanden und an, Befehl (wenn
    /// angegeben) vorhanden; ASettingOn liefert False auch für unbekannte Namen. nil-Prüfungen lassen
    /// alles zu.</summary>
    class function IsEnabled(const ATip: TAtlasTip; const ASettingOn, ACommandExists: TFunc<string, Boolean>): Boolean;
      static;
    /// <summary>Einstellung AName (Registry-Name wie in TAtlasPluginSettings.Save) eingeschaltet: Schalter an;
    /// bei einer Auswahl wie WelcomePageWhatsNew jeder Wert außer „off“. Unbekannter Name: False.</summary>
    class function SettingOn(const ASettings: TAtlasPluginSettings; const AName: string): Boolean; static;
    /// <summary>Noch nie benutzt: keine Aufrufe und kein letzter Aufruf.</summary>
    class function NeverUsed(const ATip: TAtlasTip; AUsage: TAtlasCommandUsage): Boolean; static;
    /// <summary>Kennungen der Tipps in der Reihenfolge, in der die Karte sie vorschlägt. AAllowed: Funktion
    /// eingeschaltet (nil = alle); ATracking: Nutzung zählt (sonst der Reihe nach).</summary>
    class function Order(const ATips: TAtlasTips; AUsage: TAtlasCommandUsage; const AState: TAtlasDiscoverState;
      const AAllowed: TFunc<TAtlasTip, Boolean>; ATracking: Boolean): TArray<string>; static;
    /// <summary>„Zuletzt vor …“ nach Kalendertagen; ALastUsed = 0 heißt nie.</summary>
    class function AgeOf(ALastUsed, ANow: TDateTime): TAtlasDiscoverAge; static;
    /// <summary>Hinweis der Karte: ohne Zählung None, sonst AgeOf des letzten Aufrufs.</summary>
    class function UsageAge(const ATip: TAtlasTip; AUsage: TAtlasCommandUsage; ATracking: Boolean;
      ANow: TDateTime): TAtlasDiscoverAge; static;
    /// <summary>Die Reihenfolge des Starts (AQueue), gefiltert auf AAllowed; neu erlaubte Tipps hinten an.
    /// </summary>
    class function Effective(const AQueue, AAllowed: TArray<string>): TArray<string>; static;
    /// <summary>Der zu zeigende Tipp: ACurrent, solange erlaubt; sonst der nächste erlaubte nach ihm in AQueue;
    /// sonst der erste; '' ohne.</summary>
    class function Pick(const AQueue, AAllowed: TArray<string>; const ACurrent: string): string; static;
    /// <summary>„Nächster Tipp“: der erlaubte nach ACurrent, am Ende wieder vorn.</summary>
    class function NextAfter(const AQueue, AAllowed: TArray<string>; const ACurrent: string): string; static;
    /// <summary>Stelle von AId in AList ab 0; -1 ohne (Groß/klein egal).</summary>
    class function IndexIn(const AList: TArray<string>; const AId: string): Integer; static;
  end;

implementation

uses
  System.JSON,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Core.Settings.History;

{ TAtlasDiscoverAge }

class function TAtlasDiscoverAge.Create(AKind: TAtlasDiscoverAgeKind; ACount: Integer): TAtlasDiscoverAge;
begin
  Result.Kind := AKind;
  Result.Count := ACount;
end;

{ TAtlasDiscoverState }

function TAtlasDiscoverState.IsBlocked(const AId: string): Boolean;
begin
  Result := TAtlasDiscover.IndexIn(Blocked, AId) >= 0;
end;

procedure TAtlasDiscoverState.Block(const AId: string);
begin
  if (Trim(AId) <> '') and not IsBlocked(AId) then
    Blocked := Blocked + [Trim(AId)];
end;

function TAtlasDiscoverState.ToJson: string;
var
  Root: TJSONObject;
  List: TJSONArray;
  Id: string;
begin
  Root := TJSONObject.Create;
  try
    List := TJSONArray.Create;
    Root.AddPair('blocked', List);
    for Id in Blocked do
      List.Add(Id);
    if Last <> '' then
      Root.AddPair('last', Last);
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

class function TAtlasDiscoverState.Parse(const AJson: string): TAtlasDiscoverState;
var
  Root, Value, Item: TJSONValue;
begin
  Result := Default(TAtlasDiscoverState);
  if Copy(TrimLeft(AJson), 1, 1) <> '{' then
    Exit;
  try
    Root := TJSONObject.ParseJSONValue(AJson);
  except
    on Exception do
      Root := nil;
  end;
  try
    if not (Root is TJSONObject) then
      Exit;
    Value := TJSONObject(Root).GetValue('blocked');
    if Value is TJSONArray then
      for Item in TJSONArray(Value) do
        if Item is TJSONString then
          Result.Block(TJSONString(Item).Value);
    Value := TJSONObject(Root).GetValue('last');
    if Value is TJSONString then
      Result.Last := Trim(TJSONString(Value).Value);
  finally
    Root.Free;
  end;
end;

{ TAtlasDiscover }

class function TAtlasDiscover.IndexIn(const AList: TArray<string>; const AId: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(AList) do
    if SameText(AList[Index], Trim(AId)) then
      Exit(Index);
  Result := -1;
end;

class function TAtlasDiscover.UsageOf(const ATip: TAtlasTip; AUsage: TAtlasCommandUsage;
  out ALastUsed: TDateTime): Integer;
var
  Id: string;
  Entry: TAtlasCommandUsageEntry;
begin
  Result := 0;
  ALastUsed := 0;
  if AUsage = nil then
    Exit;
  for Id in ATip.UsageIds do
  begin
    Entry := AUsage.Entry(Id);
    Inc(Result, Entry.Total);
    if Entry.LastUsed > ALastUsed then
      ALastUsed := Entry.LastUsed;
  end;
end;

class function TAtlasDiscover.NeverUsed(const ATip: TAtlasTip; AUsage: TAtlasCommandUsage): Boolean;
var
  LastUsed: TDateTime;
begin
  Result := (UsageOf(ATip, AUsage, LastUsed) = 0) and (LastUsed = 0);
end;

/// <summary>Indizes in Reihenfolge der Datei, beginnend nach AAfter (Index in ATips; -1 = von vorn).</summary>
function RotateAfter(const AIndexes: TArray<Integer>; AAfter: Integer): TArray<Integer>;
var
  Index: Integer;
begin
  Result := nil;
  for Index in AIndexes do
    if Index > AAfter then
      Result := Result + [Index];
  for Index in AIndexes do
    if Index <= AAfter then
      Result := Result + [Index];
end;

class function TAtlasDiscover.IsEnabled(const ATip: TAtlasTip; const ASettingOn,
  ACommandExists: TFunc<string, Boolean>): Boolean;
begin
  // Abgeschaltete Funktion: Einstellung aus (oder unbekannt) bzw. Befehl nicht in der Befehlspalette (#502).
  if (ATip.Setting <> '') and Assigned(ASettingOn) and not ASettingOn(ATip.Setting) then
    Exit(False);
  if (ATip.Command <> '') and Assigned(ACommandExists) and not ACommandExists(ATip.Command) then
    Exit(False);
  Result := True;
end;

class function TAtlasDiscover.SettingOn(const ASettings: TAtlasPluginSettings; const AName: string): Boolean;
var
  Store: IAtlasMemorySettingsStore;
  Value: string;
begin
  if Trim(AName) = '' then
    Exit(False);
  // Über Save statt eines Falls je Feld: jede Einstellung ist ohne Änderung hier erreichbar.
  Store := TAtlasMemorySettingsStore.FromSettings(ASettings);
  if Store.HasInteger(AName) then
    Exit(Store.ReadInteger(AName, 0) <> 0);
  Value := Trim(Store.Text(AName));
  Result := (Value <> '') and not SameText(Value, 'off');
end;

class function TAtlasDiscover.Order(const ATips: TAtlasTips; AUsage: TAtlasCommandUsage;
  const AState: TAtlasDiscoverState; const AAllowed: TFunc<TAtlasTip, Boolean>; ATracking: Boolean): TArray<string>;
var
  Index, After: Integer;
  Fresh, Known, All: TArray<Integer>;
  Used: TList<Integer>;
  Tracking: Boolean;
  LastUsed: TArray<TDateTime>;
  Moment: TDateTime;
begin
  Result := nil;
  Fresh := nil;
  All := nil;
  Tracking := ATracking and (AUsage <> nil);
  SetLength(LastUsed, Length(ATips));
  Used := TList<Integer>.Create;
  try
    for Index := 0 to High(ATips) do
    begin
      // Abgeschaltete Funktionen und gesperrte Tipps kommen nie.
      if AState.IsBlocked(ATips[Index].Id) then
        Continue;
      if Assigned(AAllowed) and not AAllowed(ATips[Index]) then
        Continue;
      All := All + [Index];
      if not Tracking then
        Continue;
      UsageOf(ATips[Index], AUsage, Moment);
      LastUsed[Index] := Moment;
      if NeverUsed(ATips[Index], AUsage) then
        Fresh := Fresh + [Index]
      else
        Used.Add(Index);
    end;
    After := TAtlasTipCatalog.IndexOf(ATips, AState.Last);
    if not Tracking then
    begin
      // Ohne Zählung der Reihe nach.
      for Index in RotateAfter(All, After) do
        Result := Result + [ATips[Index].Id];
      Exit;
    end;
    for Index in RotateAfter(Fresh, After) do
      Result := Result + [ATips[Index].Id];
    // Dann die benutzten: am längsten nicht benutzt zuerst, bei Gleichstand wie in der Datei.
    Used.Sort(TComparer<Integer>.Construct(
      function(const A, B: Integer): Integer
      begin
        if LastUsed[A] < LastUsed[B] then
          Result := -1
        else if LastUsed[A] > LastUsed[B] then
          Result := 1
        else
          Result := A - B;
      end));
    Known := Used.ToArray;
    for Index in Known do
      Result := Result + [ATips[Index].Id];
  finally
    Used.Free;
  end;
end;

class function TAtlasDiscover.AgeOf(ALastUsed, ANow: TDateTime): TAtlasDiscoverAge;
var
  Days: Integer;
begin
  if ALastUsed <= 0 then
    Exit(TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.Never, 0));
  // Kalendertage: gestern 23 Uhr ist „gestern“, auch wenn erst eine Stunde vergangen ist.
  Days := Trunc(ANow) - Trunc(ALastUsed);
  if Days <= 0 then
    Result := TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.Today, 0)
  else if Days = 1 then
    Result := TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.Yesterday, 1)
  else if Days < 14 then
    Result := TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.Days, Days)
  else if Days < 60 then
    Result := TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.Weeks, Days div 7)
  else if Days < 365 then
    Result := TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.Months, Days div 30)
  else
    Result := TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.Years, Days div 365);
end;

class function TAtlasDiscover.UsageAge(const ATip: TAtlasTip; AUsage: TAtlasCommandUsage; ATracking: Boolean;
  ANow: TDateTime): TAtlasDiscoverAge;
var
  LastUsed: TDateTime;
  Total: Integer;
begin
  // Ohne Zählung weiß Atlas nichts über die Nutzung: kein Hinweis.
  if not ATracking or (AUsage = nil) then
    Exit(TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.None, 0));
  Total := UsageOf(ATip, AUsage, LastUsed);
  if (Total = 0) and (LastUsed = 0) then
    Exit(TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.Never, 0));
  if LastUsed = 0 then
    // Gezählt, aber ohne Datum (ältere Datei): benutzt, Zeitpunkt unbekannt.
    Exit(TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.None, 0));
  Result := AgeOf(LastUsed, ANow);
end;

class function TAtlasDiscover.Effective(const AQueue, AAllowed: TArray<string>): TArray<string>;
var
  Id: string;
begin
  Result := nil;
  for Id in AQueue do
    if (IndexIn(AAllowed, Id) >= 0) and (IndexIn(Result, Id) < 0) then
      Result := Result + [Id];
  for Id in AAllowed do
    if IndexIn(Result, Id) < 0 then
      Result := Result + [Id];
end;

class function TAtlasDiscover.Pick(const AQueue, AAllowed: TArray<string>; const ACurrent: string): string;
var
  List: TArray<string>;
  Index, Step: Integer;
  Candidate: string;
begin
  Result := '';
  List := Effective(AQueue, AAllowed);
  if Length(List) = 0 then
    Exit;
  if IndexIn(List, ACurrent) >= 0 then
    Exit(List[IndexIn(List, ACurrent)]);
  // Der bisherige Tipp ist weg (gesperrt, Funktion aus): der nächste nach ihm.
  Index := IndexIn(AQueue, ACurrent);
  if Index >= 0 then
    for Step := 1 to Length(AQueue) do
    begin
      Candidate := AQueue[(Index + Step) mod Length(AQueue)];
      if IndexIn(List, Candidate) >= 0 then
        Exit(List[IndexIn(List, Candidate)]);
    end;
  Result := List[0];
end;

class function TAtlasDiscover.NextAfter(const AQueue, AAllowed: TArray<string>; const ACurrent: string): string;
var
  List: TArray<string>;
  Index: Integer;
begin
  Result := '';
  List := Effective(AQueue, AAllowed);
  if Length(List) = 0 then
    Exit;
  Index := IndexIn(List, ACurrent);
  if Index < 0 then
    Exit(Pick(AQueue, AAllowed, ACurrent));
  Result := List[(Index + 1) mod Length(List)];
end;

end.
