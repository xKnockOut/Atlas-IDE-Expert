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
    cSectionName = 'discover';
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
  begin
    Blocked := Blocked + [Trim(AId)];
  end;
end;

function TAtlasDiscoverState.ToJson: string;
var
  mRoot: TJSONObject;
  mList: TJSONArray;
  mId: string;
begin
  mRoot := TJSONObject.Create;
  try
    mList := TJSONArray.Create;
    mRoot.AddPair('blocked', mList);
    for mId in Blocked do
    begin
      mList.Add(mId);
    end;
    if Last <> '' then
    begin
      mRoot.AddPair('last', Last);
    end;
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasDiscoverState.Parse(const AJson: string): TAtlasDiscoverState;
var
  mRoot, mValue, mItem: TJSONValue;
begin
  Result := Default(TAtlasDiscoverState);
  if Copy(TrimLeft(AJson), 1, 1) <> '{' then
  begin
    Exit;
  end;
  try
    mRoot := TJSONObject.ParseJSONValue(AJson);
  except
    on Exception do
      mRoot := nil;
  end;
  try
    if not (mRoot is TJSONObject) then
    begin
      Exit;
    end;
    mValue := TJSONObject(mRoot).GetValue('blocked');
    if mValue is TJSONArray then
    begin
      for mItem in TJSONArray(mValue) do
      begin
        if mItem is TJSONString then
        begin
          Result.Block(TJSONString(mItem).Value);
        end;
      end;
    end;
    mValue := TJSONObject(mRoot).GetValue('last');
    if mValue is TJSONString then
    begin
      Result.Last := Trim(TJSONString(mValue).Value);
    end;
  finally
    mRoot.Free;
  end;
end;

{ TAtlasDiscover }

class function TAtlasDiscover.IndexIn(const AList: TArray<string>; const AId: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AList) do
  begin
    if SameText(AList[mIndex], Trim(AId)) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TAtlasDiscover.UsageOf(const ATip: TAtlasTip; AUsage: TAtlasCommandUsage;
  out ALastUsed: TDateTime): Integer;
var
  mId: string;
  mEntry: TAtlasCommandUsageEntry;
begin
  Result := 0;
  ALastUsed := 0;
  if AUsage = nil then
  begin
    Exit;
  end;
  for mId in ATip.UsageIds do
  begin
    mEntry := AUsage.Entry(mId);
    Inc(Result, mEntry.Total);
    if mEntry.LastUsed > ALastUsed then
    begin
      ALastUsed := mEntry.LastUsed;
    end;
  end;
end;

class function TAtlasDiscover.NeverUsed(const ATip: TAtlasTip; AUsage: TAtlasCommandUsage): Boolean;
var
  mLastUsed: TDateTime;
begin
  Result := (UsageOf(ATip, AUsage, mLastUsed) = 0) and (mLastUsed = 0);
end;

/// <summary>Indizes in Reihenfolge der Datei, beginnend nach AAfter (Index in ATips; -1 = von vorn).</summary>
function RotateAfter(const AIndexes: TArray<Integer>; AAfter: Integer): TArray<Integer>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex in AIndexes do
  begin
    if mIndex > AAfter then
    begin
      Result := Result + [mIndex];
    end;
  end;
  for mIndex in AIndexes do
  begin
    if mIndex <= AAfter then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

class function TAtlasDiscover.IsEnabled(const ATip: TAtlasTip; const ASettingOn,
  ACommandExists: TFunc<string, Boolean>): Boolean;
begin
  // Abgeschaltete Funktion: Einstellung aus (oder unbekannt) bzw. Befehl nicht in der Befehlspalette (#502).
  if (ATip.Setting <> '') and Assigned(ASettingOn) and not ASettingOn(ATip.Setting) then
  begin
    Exit(False);
  end;
  if (ATip.Command <> '') and Assigned(ACommandExists) and not ACommandExists(ATip.Command) then
  begin
    Exit(False);
  end;
  Result := True;
end;

class function TAtlasDiscover.SettingOn(const ASettings: TAtlasPluginSettings; const AName: string): Boolean;
var
  mStore: IAtlasMemorySettingsStore;
  mValue: string;
begin
  if Trim(AName) = '' then
  begin
    Exit(False);
  end;
  // Über Save statt eines Falls je Feld: jede Einstellung ist ohne Änderung hier erreichbar.
  mStore := TAtlasMemorySettingsStore.FromSettings(ASettings);
  if mStore.HasInteger(AName) then
  begin
    Exit(mStore.ReadInteger(AName, 0) <> 0);
  end;
  mValue := Trim(mStore.Text(AName));
  Result := (mValue <> '') and not SameText(mValue, 'off');
end;

/// <summary>Kennungen der Tipps AIndexes aus ATips.</summary>
function IdsOf(const ATips: TAtlasTips; const AIndexes: TArray<Integer>): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex in AIndexes do
  begin
    Result := Result + [ATips[mIndex].Id];
  end;
end;

/// <summary>Indizes der Tipps, die kommen dürfen: Abgeschaltete Funktionen und gesperrte Tipps kommen nie.
/// </summary>
function AllowedTips(const ATips: TAtlasTips; const AState: TAtlasDiscoverState;
  const AAllowed: TFunc<TAtlasTip, Boolean>): TArray<Integer>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(ATips) do
  begin
    if not AState.IsBlocked(ATips[mIndex].Id) and (not Assigned(AAllowed) or AAllowed(ATips[mIndex])) then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

/// <summary>Am längsten nicht benutzt zuerst (ALastUsed je Tipp), bei Gleichstand wie in der Datei.</summary>
function OldestFirst(const ALastUsed: TArray<TDateTime>): IComparer<Integer>;
begin
  Result := TComparer<Integer>.Construct(
    function(const A, B: Integer): Integer
    begin
      if ALastUsed[A] < ALastUsed[B] then
      begin
        Result := -1;
      end
      else if ALastUsed[A] > ALastUsed[B] then
      begin
        Result := 1;
      end
      else
      begin
        Result := A - B;
      end;
    end);
end;

class function TAtlasDiscover.Order(const ATips: TAtlasTips; AUsage: TAtlasCommandUsage;
  const AState: TAtlasDiscoverState; const AAllowed: TFunc<TAtlasTip, Boolean>; ATracking: Boolean): TArray<string>;
var
  mIndex, mAfter: Integer;
  mFresh, mAll: TArray<Integer>;
  mUsed: TList<Integer>;
  mLastUsed: TArray<TDateTime>;
  mMoment: TDateTime;
begin
  mAll := AllowedTips(ATips, AState, AAllowed);
  mAfter := TAtlasTipCatalog.IndexOf(ATips, AState.Last);
  if not ATracking or (AUsage = nil) then
  begin
    // Ohne Zählung der Reihe nach.
    Exit(IdsOf(ATips, RotateAfter(mAll, mAfter)));
  end;
  mFresh := nil;
  SetLength(mLastUsed, Length(ATips));
  mUsed := TList<Integer>.Create;
  try
    for mIndex in mAll do
    begin
      UsageOf(ATips[mIndex], AUsage, mMoment);
      mLastUsed[mIndex] := mMoment;
      if NeverUsed(ATips[mIndex], AUsage) then
      begin
        mFresh := mFresh + [mIndex];
      end
      else
      begin
        mUsed.Add(mIndex);
      end;
    end;
    // Zuerst nie benutzte, dann die benutzten.
    mUsed.Sort(OldestFirst(mLastUsed));
    Result := IdsOf(ATips, RotateAfter(mFresh, mAfter)) + IdsOf(ATips, mUsed.ToArray);
  finally
    mUsed.Free;
  end;
end;

class function TAtlasDiscover.AgeOf(ALastUsed, ANow: TDateTime): TAtlasDiscoverAge;
var
  mDays: Integer;
begin
  if ALastUsed <= 0 then
  begin
    Exit(TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.Never, 0));
  end;
  // Kalendertage: gestern 23 Uhr ist „gestern“, auch wenn erst eine Stunde vergangen ist.
  mDays := Trunc(ANow) - Trunc(ALastUsed);
  if mDays <= 0 then
  begin
    Result := TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.Today, 0);
  end
  else if mDays = 1 then
  begin
    Result := TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.Yesterday, 1);
  end
  else if mDays < 14 then
  begin
    Result := TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.Days, mDays);
  end
  else if mDays < 60 then
  begin
    Result := TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.Weeks, mDays div 7);
  end
  else if mDays < 365 then
  begin
    Result := TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.Months, mDays div 30);
  end
  else
  begin
    Result := TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.Years, mDays div 365);
  end;
end;

class function TAtlasDiscover.UsageAge(const ATip: TAtlasTip; AUsage: TAtlasCommandUsage; ATracking: Boolean;
  ANow: TDateTime): TAtlasDiscoverAge;
var
  mLastUsed: TDateTime;
  mTotal: Integer;
begin
  // Ohne Zählung weiß Atlas nichts über die Nutzung: kein Hinweis.
  if not ATracking or (AUsage = nil) then
  begin
    Exit(TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.None, 0));
  end;
  mTotal := UsageOf(ATip, AUsage, mLastUsed);
  if (mTotal = 0) and (mLastUsed = 0) then
  begin
    Exit(TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.Never, 0));
  end;
  if mLastUsed = 0 then
  begin
    // Gezählt, aber ohne Datum (ältere Datei): benutzt, Zeitpunkt unbekannt.
    Exit(TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.None, 0));
  end;
  Result := AgeOf(mLastUsed, ANow);
end;

class function TAtlasDiscover.Effective(const AQueue, AAllowed: TArray<string>): TArray<string>;
var
  mId: string;
begin
  Result := nil;
  for mId in AQueue do
  begin
    if (IndexIn(AAllowed, mId) >= 0) and (IndexIn(Result, mId) < 0) then
    begin
      Result := Result + [mId];
    end;
  end;
  for mId in AAllowed do
  begin
    if IndexIn(Result, mId) < 0 then
    begin
      Result := Result + [mId];
    end;
  end;
end;

class function TAtlasDiscover.Pick(const AQueue, AAllowed: TArray<string>; const ACurrent: string): string;
var
  mList: TArray<string>;
  mIndex, mStep: Integer;
  mCandidate: string;
begin
  Result := '';
  mList := Effective(AQueue, AAllowed);
  if Length(mList) = 0 then
  begin
    Exit;
  end;
  if IndexIn(mList, ACurrent) >= 0 then
  begin
    Exit(mList[IndexIn(mList, ACurrent)]);
  end;
  // Der bisherige Tipp ist weg (gesperrt, Funktion aus): der nächste nach ihm.
  mIndex := IndexIn(AQueue, ACurrent);
  if mIndex >= 0 then
  begin
    for mStep := 1 to Length(AQueue) do
    begin
      mCandidate := AQueue[(mIndex + mStep) mod Length(AQueue)];
      if IndexIn(mList, mCandidate) >= 0 then
      begin
        Exit(mList[IndexIn(mList, mCandidate)]);
      end;
    end;
  end;
  Result := mList[0];
end;

class function TAtlasDiscover.NextAfter(const AQueue, AAllowed: TArray<string>; const ACurrent: string): string;
var
  mList: TArray<string>;
  mIndex: Integer;
begin
  Result := '';
  mList := Effective(AQueue, AAllowed);
  if Length(mList) = 0 then
  begin
    Exit;
  end;
  mIndex := IndexIn(mList, ACurrent);
  if mIndex < 0 then
  begin
    Exit(Pick(AQueue, AAllowed, ACurrent));
  end;
  Result := mList[(mIndex + 1) mod Length(mList)];
end;

end.
