unit Atlas.Core.Tracker.Notify;

// Meldungen zu meinen Issues (#1271), ohne VCL und Open Tools API: Atlas
// fragt jede Tracker-Verbindung in einstellbarem Abstand nach Änderungen
// (IAtlasTrackerProvider.Changes) und meldet sie in der
// Benachrichtigungszentrale (#601, Quelle „Issues“). Ein selbst gehosteter
// Tracker kann die IDE nicht erreichen, daher fragt Atlas („Pull“).
// - Verbindung: Anbieter und Server (ConnectionId); jede Verbindung hat ihren
//   eigenen Stand, die Abfrage gilt allen Projekten des Servers.
// - Eigene Änderungen (Urheber = angemeldeter Benutzer) entfallen (Foreign).
// - Summarize fasst die Änderungen je Issue zu einer Meldung zusammen
//   (Kommentare mit ihren Urhebern, Zuweisung, letzter Zustand), neueste
//   zuerst; der erste neue Kommentar ist der Anker für die Vorschau.
// - TAtlasTrackerNotifySchedule: Abstand issues.notify.intervalMinutes
//   (kleinster Wert MinInterval, bei GitHub mindestens X-Poll-Interval);
//   nach einem Fehler verdoppelt er sich bis MaxBackoffMinutes und fällt
//   nach dem nächsten Erfolg zurück. Ein Fehler wird einmal gemeldet, dann
//   erst nach einem Erfolg wieder. Gefragt wird nur bei aktiver IDE
//   (UserActive); was beim Aussetzen fällig wurde, kommt beim Zurückkehren
//   mit einer Abfrage.
// - Stand je Verbindung in %LOCALAPPDATA%\Atlas\issues\notify.json (Ordner von
//   außen): seit wann, angemeldeter Benutzer, Last-Modified und die Issues
//   mit Punkt in „Meine Issues“ (Unseen), bis sie geöffnet wurden. Ohne Stand
//   oder nach dem Einschalten gilt „jetzt“ (Fresh), damit keine Flut alter
//   Änderungen kommt. Nie ein Token.
// Nur im Hauptthread benutzen; die Abfrage selbst läuft im Hintergrund.

interface

uses
  System.SysUtils,
  Atlas.Core.Tracker.Contract;

type
  /// <summary>Eine Meldung: alle neuen Änderungen an einem Issue.</summary>
  TAtlasTrackerNotice = record
    Key: string;
    /// <summary>GitHub "owner/repo"; sonst ''.</summary>
    Project: string;
    Title: string;
    /// <summary>Anzahl neuer Kommentare.</summary>
    Comments: Integer;
    /// <summary>Urheber der Kommentare (Anzeigename), jeder einmal, in der Reihenfolge der Kommentare.</summary>
    CommentAuthors: TArray<string>;
    /// <summary>Mir zugewiesen.</summary>
    AssignedToMe: Boolean;
    /// <summary>Jemand anderem zugewiesen (letzter Zuständiger); '' ohne.</summary>
    AssignedTo: string;
    /// <summary>Letzter neuer Zustand; '' ohne Zustandswechsel.</summary>
    State: string;
    /// <summary>Nur allgemeine Änderungen ohne Einzelheit.</summary>
    Other: Boolean;
    /// <summary>Erster neuer Kommentar (UTC): dort öffnet die Vorschau; 0 ohne.</summary>
    Anchor: TDateTime;
    /// <summary>Letzte Änderung (UTC).</summary>
    Time: TDateTime;
    /// <summary>Gleiches Issue (Kennung und Projekt ohne Groß-/Kleinschreibung).</summary>
    function Matches(const AKey, AProject: string): Boolean;
  end;

  /// <summary>Issue mit Punkt in „Meine Issues“, bis es geöffnet wurde.</summary>
  TAtlasTrackerUnseen = record
    Key: string;
    Project: string;
    /// <summary>Erster ungesehener Kommentar (UTC); 0 ohne.</summary>
    Anchor: TDateTime;
  end;

  /// <summary>Gespeicherter Stand einer Verbindung.</summary>
  TAtlasTrackerNotifyConnection = record
    /// <summary>ConnectionId: "anbieter|server".</summary>
    Id: string;
    /// <summary>Änderungen danach sind neu (UTC).</summary>
    Since: TDateTime;
    /// <summary>Anmeldename des angemeldeten Benutzers; '' = noch unbekannt.</summary>
    Me: string;
    /// <summary>GitHub: Last-Modified der letzten Antwort.</summary>
    LastModified: string;
    Unseen: TArray<TAtlasTrackerUnseen>;
    class function Create(const AId: string; ASince: TDateTime): TAtlasTrackerNotifyConnection; static;
    function IndexOfUnseen(const AKey, AProject: string): Integer;
  end;

  /// <summary>Inhalt von notify.json.</summary>
  TAtlasTrackerNotifyFile = record
    /// <summary>issues.notify war beim letzten Speichern an; aus → beim Einschalten gilt „jetzt“.</summary>
    Enabled: Boolean;
    Connections: TArray<TAtlasTrackerNotifyConnection>;
    class function Empty: TAtlasTrackerNotifyFile; static;
    function IndexOf(const AId: string): Integer;
    function Find(const AId: string; out AConnection: TAtlasTrackerNotifyConnection): Boolean;
    procedure Put(const AConnection: TAtlasTrackerNotifyConnection);
  end;

  /// <summary>Takt einer Verbindung, in Millisekunden eines monotonen Zählers (GetTickCount64; Tests setzen
  /// eigene Werte ein).</summary>
  TAtlasTrackerNotifySchedule = record
    HasAttempt: Boolean;
    /// <summary>Beginn der letzten Abfrage.</summary>
    LastAttempt: UInt64;
    /// <summary>Fehlschläge in Folge.</summary>
    Failures: Integer;
    /// <summary>X-Poll-Interval (GitHub) in Sekunden; 0 ohne.</summary>
    PollSeconds: Integer;
    /// <summary>Der laufende Fehler wurde schon gemeldet.</summary>
    ErrorReported: Boolean;
    /// <summary>Abstand bis zur nächsten Abfrage: der eingestellte (mindestens MinInterval und PollSeconds), nach
    /// Fehlern verdoppelt bis MaxBackoffMinutes (nie unter dem eingestellten).</summary>
    function DelayMs(AIntervalMinutes: Integer): UInt64;
    /// <summary>Fällig: IDE aktiv und noch keine Abfrage bzw. der Abstand ist um.</summary>
    function Due(ANowMs: UInt64; AActive: Boolean; AIntervalMinutes: Integer): Boolean;
    /// <summary>Beim Öffnen von „Meine Issues“: ohne laufende Fehler und frühestens OnDemandMs (bzw. PollSeconds)
    /// nach der letzten Abfrage.</summary>
    function DueOnDemand(ANowMs: UInt64): Boolean;
    procedure Started(ANowMs: UInt64);
    /// <summary>Erfolg: Abstand zurück auf den eingestellten, Fehler wieder meldbar.</summary>
    procedure Succeeded(APollSeconds: Integer);
    /// <summary>Fehlschlag: Abstand verdoppeln. True, wenn der Fehler gemeldet werden soll (der erste seit dem
    /// letzten Erfolg).</summary>
    function Failed: Boolean;
  end;

  TAtlasTrackerNotify = class
  public const
    FileName = 'notify.json';
    Version = 1;
    /// <summary>Kleinster und vorgegebener Abstand in Minuten (issues.notify.intervalMinutes).</summary>
    MinInterval = 2;
    DefaultInterval = 10;
    /// <summary>Größter Abstand nach Fehlern.</summary>
    MaxBackoffMinutes = 60;
    /// <summary>Ohne Eingabe so lange setzt die Abfrage aus.</summary>
    IdleMinutes = 30;
    /// <summary>Beim Öffnen von „Meine Issues“ frühestens so lange nach der letzten Abfrage.</summary>
    OnDemandMs = 60000;
    /// <summary>Zeitgrenze einer Abfrage je Verbindung.</summary>
    TimeoutMs = 15000;
    /// <summary>Höchstens so viele Meldungen je Abfrage; der Rest kommt als eine Sammelmeldung.</summary>
    MaxNotices = 10;
    /// <summary>Höchstens so viele Issues mit Punkt je Verbindung (die ältesten fallen heraus).</summary>
    MaxUnseen = 50;
    ScopeAssigned = 'assigned';
    ScopeAssignedOrCreated = 'assignedOrCreated';
    ScopeWatched = 'watched';
  public
    /// <summary>"anbieter|server" (klein); '' ohne Anbieter oder Server.</summary>
    class function ConnectionId(const ATarget: TAtlasTrackerTarget): string; static;
    /// <summary>Projekt, unter dem die Issues von ATarget Punkte tragen: GitHub "owner/repo" (Kennungen "#12"
    /// gelten je Repository), sonst '' (YouTrack-Kennungen enthalten das Projekt).</summary>
    class function UnseenProject(const ATarget: TAtlasTrackerTarget): string; static;
    class function ScopeName(AScope: TAtlasTrackerNotifyScope): string; static;
    /// <summary>Umkehrung von ScopeName (ohne Groß-/Kleinschreibung); AssignedOrCreated für fremde Texte.</summary>
    class function ScopeOf(const AName: string): TAtlasTrackerNotifyScope; static;
    /// <summary>Abstand in Minuten, mindestens MinInterval.</summary>
    class function Interval(AMinutes: Integer): Integer; static;
    /// <summary>IDE aktiv: nicht minimiert und eine Eingabe in den letzten IdleMinutes.</summary>
    class function UserActive(AMinimized: Boolean; AIdleMs: UInt64): Boolean; static;
    /// <summary>Ohne eigene Änderungen (Urheber = AMe, ohne Groß-/Kleinschreibung); AMe '' lässt alle.</summary>
    class function Foreign(const AChanges: TArray<TAtlasTrackerChange>;
      const AMe: string): TArray<TAtlasTrackerChange>; static;
    /// <summary>Eine Meldung je Issue, neueste zuerst; höchstens AMax, ARest zählt die übrigen.</summary>
    class function Summarize(const AChanges: TArray<TAtlasTrackerChange>; AMax: Integer;
      out ARest: Integer): TArray<TAtlasTrackerNotice>; static;
    /// <summary>Nächster Stand: der neueste gesehene Zeitpunkt, nie zurück.</summary>
    class function NextSince(ASince, ALatest: TDateTime): TDateTime; static;
    /// <summary>Issues der Meldungen bekommen einen Punkt (ein vorhandener Anker bleibt der ältere).</summary>
    class procedure MarkUnseen(var AConnection: TAtlasTrackerNotifyConnection;
      const ANotices: TArray<TAtlasTrackerNotice>); static;
    /// <summary>Punkt von AKey entfernen; True, wenn es einen gab.</summary>
    class function Seen(var AConnection: TAtlasTrackerNotifyConnection; const AKey, AProject: string): Boolean;
      static;
    /// <summary>Stand für eine Verbindung ohne gespeicherten Stand bzw. nach dem Einschalten: jetzt.</summary>
    class function Fresh(const AId: string; ANowUtc: TDateTime): TAtlasTrackerNotifyConnection; static;
    /// <summary>Anmeldename aus der Antwort der Prüfadresse (YouTrack /api/users/me, GitHub /user); '' ohne.
    /// </summary>
    class function LoginOf(const AJson: string): string; static;
    class function ToJson(const AFile: TAtlasTrackerNotifyFile): string; static;
    /// <summary>False bei ungültigem JSON oder anderer Version (dann gilt Empty).</summary>
    class function FromJson(const AJson: string; out AFile: TAtlasTrackerNotifyFile): Boolean; static;
    /// <summary>notify.json in AFolder lesen; Empty ohne Datei oder bei ungültigem Inhalt.</summary>
    class function Load(const AFolder: string): TAtlasTrackerNotifyFile; static;
    /// <summary>notify.json in AFolder schreiben (Ordner wird angelegt); False bei Fehler.</summary>
    class function Save(const AFolder: string; const AFile: TAtlasTrackerNotifyFile): Boolean; static;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.DateUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.JSON;

{ TAtlasTrackerNotice }

function TAtlasTrackerNotice.Matches(const AKey, AProject: string): Boolean;
begin
  Result := SameText(Key, AKey) and SameText(Project, AProject);
end;

{ TAtlasTrackerNotifyConnection }

class function TAtlasTrackerNotifyConnection.Create(const AId: string;
  ASince: TDateTime): TAtlasTrackerNotifyConnection;
begin
  Result := Default(TAtlasTrackerNotifyConnection);
  Result.Id := AId;
  Result.Since := ASince;
  Result.Unseen := nil;
end;

function TAtlasTrackerNotifyConnection.IndexOfUnseen(const AKey, AProject: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Unseen) do
    if SameText(Unseen[mIndex].Key, AKey) and SameText(Unseen[mIndex].Project, AProject) then
      Exit(mIndex);
  Result := -1;
end;

{ TAtlasTrackerNotifyFile }

class function TAtlasTrackerNotifyFile.Empty: TAtlasTrackerNotifyFile;
begin
  Result.Enabled := False;
  Result.Connections := nil;
end;

function TAtlasTrackerNotifyFile.IndexOf(const AId: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Connections) do
    if SameText(Connections[mIndex].Id, AId) then
      Exit(mIndex);
  Result := -1;
end;

function TAtlasTrackerNotifyFile.Find(const AId: string; out AConnection: TAtlasTrackerNotifyConnection): Boolean;
var
  mIndex: Integer;
begin
  mIndex := IndexOf(AId);
  Result := mIndex >= 0;
  if Result then
    AConnection := Connections[mIndex]
  else
    AConnection := TAtlasTrackerNotifyConnection.Create(AId, 0);
end;

procedure TAtlasTrackerNotifyFile.Put(const AConnection: TAtlasTrackerNotifyConnection);
var
  mIndex: Integer;
begin
  mIndex := IndexOf(AConnection.Id);
  if mIndex >= 0 then
    Connections[mIndex] := AConnection
  else
    Connections := Connections + [AConnection];
end;

{ TAtlasTrackerNotifySchedule }

function TAtlasTrackerNotifySchedule.DelayMs(AIntervalMinutes: Integer): UInt64;
var
  mBase, mCap: UInt64;
  mStep: Integer;
begin
  mBase := UInt64(TAtlasTrackerNotify.Interval(AIntervalMinutes)) * 60000;
  if UInt64(PollSeconds) * 1000 > mBase then
    mBase := UInt64(PollSeconds) * 1000;
  Result := mBase;
  if Failures <= 0 then
    Exit;
  mCap := UInt64(TAtlasTrackerNotify.MaxBackoffMinutes) * 60000;
  if mBase >= mCap then
    Exit;
  // Verdoppeln je Fehlschlag (ohne Überlauf), höchstens bis zur Grenze.
  for mStep := 1 to Failures do
  begin
    Result := Result * 2;
    if Result >= mCap then
      Exit(mCap);
  end;
end;

function TAtlasTrackerNotifySchedule.Due(ANowMs: UInt64; AActive: Boolean; AIntervalMinutes: Integer): Boolean;
begin
  Result := AActive and (not HasAttempt or (ANowMs < LastAttempt) or
    (ANowMs - LastAttempt >= DelayMs(AIntervalMinutes)));
end;

function TAtlasTrackerNotifySchedule.DueOnDemand(ANowMs: UInt64): Boolean;
var
  mWait: UInt64;
begin
  if not HasAttempt then
    Exit(True);
  if (Failures > 0) or (ANowMs < LastAttempt) then
    Exit(False);
  mWait := TAtlasTrackerNotify.OnDemandMs;
  if UInt64(PollSeconds) * 1000 > mWait then
    mWait := UInt64(PollSeconds) * 1000;
  Result := ANowMs - LastAttempt >= mWait;
end;

procedure TAtlasTrackerNotifySchedule.Started(ANowMs: UInt64);
begin
  HasAttempt := True;
  LastAttempt := ANowMs;
end;

procedure TAtlasTrackerNotifySchedule.Succeeded(APollSeconds: Integer);
begin
  Failures := 0;
  ErrorReported := False;
  if APollSeconds > 0 then
    PollSeconds := APollSeconds;
end;

function TAtlasTrackerNotifySchedule.Failed: Boolean;
begin
  // Obergrenze genügt: ab hier gilt ohnehin MaxBackoffMinutes.
  if Failures < 16 then
    Inc(Failures);
  Result := not ErrorReported;
  ErrorReported := True;
end;

{ TAtlasTrackerNotify }

class function TAtlasTrackerNotify.ConnectionId(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := '';
  if (ATarget.Provider <> '') and (ATarget.Server <> '') then
    Result := LowerCase(ATarget.Provider + '|' + ATarget.Server);
end;

class function TAtlasTrackerNotify.UnseenProject(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := '';
  if SameText(ATarget.Provider, TAtlasTrackerTarget.GitHub) then
    Result := ATarget.Project;
end;

class function TAtlasTrackerNotify.ScopeName(AScope: TAtlasTrackerNotifyScope): string;
begin
  case AScope of
    TAtlasTrackerNotifyScope.Assigned:
      Result := ScopeAssigned;
    TAtlasTrackerNotifyScope.Watched:
      Result := ScopeWatched;
  else
    Result := ScopeAssignedOrCreated;
  end;
end;

class function TAtlasTrackerNotify.ScopeOf(const AName: string): TAtlasTrackerNotifyScope;
begin
  if SameText(Trim(AName), ScopeAssigned) then
    Result := TAtlasTrackerNotifyScope.Assigned
  else if SameText(Trim(AName), ScopeWatched) then
    Result := TAtlasTrackerNotifyScope.Watched
  else
    Result := TAtlasTrackerNotifyScope.AssignedOrCreated;
end;

class function TAtlasTrackerNotify.Interval(AMinutes: Integer): Integer;
begin
  Result := AMinutes;
  if Result < MinInterval then
    Result := MinInterval;
end;

class function TAtlasTrackerNotify.UserActive(AMinimized: Boolean; AIdleMs: UInt64): Boolean;
begin
  Result := not AMinimized and (AIdleMs < UInt64(IdleMinutes) * 60000);
end;

class function TAtlasTrackerNotify.Foreign(const AChanges: TArray<TAtlasTrackerChange>;
  const AMe: string): TArray<TAtlasTrackerChange>;
var
  mChange: TAtlasTrackerChange;
begin
  Result := nil;
  for mChange in AChanges do
    if (AMe = '') or not SameText(mChange.Author, AMe) then
      Result := Result + [mChange];
end;

class function TAtlasTrackerNotify.Summarize(const AChanges: TArray<TAtlasTrackerChange>; AMax: Integer;
  out ARest: Integer): TArray<TAtlasTrackerNotice>;
var
  mSorted: TArray<TAtlasTrackerChange>;
  mChange: TAtlasTrackerChange;
  mAll: TArray<TAtlasTrackerNotice>;
  mNotice: TAtlasTrackerNotice;
  mIndex, mFound: Integer;
  mWho: string;
  mKnown: Boolean;
begin
  // Älteste zuerst, damit Zustand und Zuständiger am Ende der letzte Stand sind; bei Gleichstand nach Kennung
  // und Art (TArray.Sort ist nicht stabil).
  mSorted := Copy(AChanges);
  TArray.Sort<TAtlasTrackerChange>(mSorted, TComparer<TAtlasTrackerChange>.Construct(
    function(const ALeft, ARight: TAtlasTrackerChange): Integer
    begin
      if ALeft.Time < ARight.Time then
        Exit(-1);
      if ALeft.Time > ARight.Time then
        Exit(1);
      Result := CompareText(ALeft.Project + '#' + ALeft.Key, ARight.Project + '#' + ARight.Key);
      if Result = 0 then
        Result := Ord(ALeft.Kind) - Ord(ARight.Kind);
    end));
  mAll := nil;
  for mChange in mSorted do
  begin
    mFound := -1;
    for mIndex := 0 to High(mAll) do
      if mAll[mIndex].Matches(mChange.Key, mChange.Project) then
        mFound := mIndex;
    if mFound < 0 then
    begin
      mNotice := Default(TAtlasTrackerNotice);
      mNotice.Key := mChange.Key;
      mNotice.Project := mChange.Project;
      mNotice.CommentAuthors := nil;
      mNotice.Other := True;
      mAll := mAll + [mNotice];
      mFound := High(mAll);
    end;
    if mChange.Title <> '' then
      mAll[mFound].Title := mChange.Title;
    if mChange.Time > mAll[mFound].Time then
      mAll[mFound].Time := mChange.Time;
    if mChange.Kind <> TAtlasTrackerChangeKind.Other then
      mAll[mFound].Other := False;
    case mChange.Kind of
      TAtlasTrackerChangeKind.Comment:
        begin
          Inc(mAll[mFound].Comments);
          if mAll[mFound].Anchor = 0 then
            mAll[mFound].Anchor := mChange.Time;
          mWho := mChange.Who;
          mKnown := mWho = '';
          for mIndex := 0 to High(mAll[mFound].CommentAuthors) do
            if SameText(mAll[mFound].CommentAuthors[mIndex], mWho) then
              mKnown := True;
          if not mKnown then
            mAll[mFound].CommentAuthors := mAll[mFound].CommentAuthors + [mWho];
        end;
      TAtlasTrackerChangeKind.Assigned:
        if mChange.ToMe then
        begin
          mAll[mFound].AssignedToMe := True;
          mAll[mFound].AssignedTo := '';
        end
        else
        begin
          mAll[mFound].AssignedToMe := False;
          mAll[mFound].AssignedTo := mChange.Value;
        end;
      TAtlasTrackerChangeKind.State:
        mAll[mFound].State := mChange.Value;
    end;
  end;
  // Neueste Meldung zuerst; bei Gleichstand nach Kennung.
  TArray.Sort<TAtlasTrackerNotice>(mAll, TComparer<TAtlasTrackerNotice>.Construct(
    function(const ALeft, ARight: TAtlasTrackerNotice): Integer
    begin
      if ALeft.Time > ARight.Time then
        Exit(-1);
      if ALeft.Time < ARight.Time then
        Exit(1);
      Result := CompareText(ALeft.Project + '#' + ALeft.Key, ARight.Project + '#' + ARight.Key);
    end));
  ARest := 0;
  if (AMax >= 0) and (Length(mAll) > AMax) then
  begin
    ARest := Length(mAll) - AMax;
    mAll := Copy(mAll, 0, AMax);
  end;
  Result := mAll;
end;

class function TAtlasTrackerNotify.NextSince(ASince, ALatest: TDateTime): TDateTime;
begin
  Result := ASince;
  if ALatest > Result then
    Result := ALatest;
end;

class procedure TAtlasTrackerNotify.MarkUnseen(var AConnection: TAtlasTrackerNotifyConnection;
  const ANotices: TArray<TAtlasTrackerNotice>);
var
  mNotice: TAtlasTrackerNotice;
  mIndex: Integer;
  mItem: TAtlasTrackerUnseen;
begin
  for mNotice in ANotices do
  begin
    mIndex := AConnection.IndexOfUnseen(mNotice.Key, mNotice.Project);
    if mIndex >= 0 then
    begin
      // Der älteste ungesehene Kommentar bleibt der Anker.
      if AConnection.Unseen[mIndex].Anchor = 0 then
        AConnection.Unseen[mIndex].Anchor := mNotice.Anchor;
      Continue;
    end;
    mItem.Key := mNotice.Key;
    mItem.Project := mNotice.Project;
    mItem.Anchor := mNotice.Anchor;
    AConnection.Unseen := AConnection.Unseen + [mItem];
  end;
  if Length(AConnection.Unseen) > MaxUnseen then
    AConnection.Unseen := Copy(AConnection.Unseen, Length(AConnection.Unseen) - MaxUnseen, MaxUnseen);
end;

class function TAtlasTrackerNotify.Seen(var AConnection: TAtlasTrackerNotifyConnection;
  const AKey, AProject: string): Boolean;
var
  mIndex: Integer;
begin
  mIndex := AConnection.IndexOfUnseen(AKey, AProject);
  Result := mIndex >= 0;
  if Result then
    Delete(AConnection.Unseen, mIndex, 1);
end;

class function TAtlasTrackerNotify.Fresh(const AId: string; ANowUtc: TDateTime): TAtlasTrackerNotifyConnection;
begin
  Result := TAtlasTrackerNotifyConnection.Create(AId, ANowUtc);
end;

class function TAtlasTrackerNotify.LoginOf(const AJson: string): string;
var
  mValue, mLogin: TJSONValue;
begin
  Result := '';
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONObject) then
      Exit;
    mLogin := TJSONObject(mValue).Values['login'];
    if mLogin is TJSONString then
      Result := Trim(TJSONString(mLogin).Value);
  finally
    mValue.Free;
  end;
end;

function IsoOf(AValue: TDateTime): string;
begin
  Result := '';
  if AValue > 0 then
    Result := DateToISO8601(AValue, True);
end;

function TimeOf(AObject: TJSONObject; const AName: string): TDateTime;
var
  mValue: TJSONValue;
begin
  Result := 0;
  mValue := AObject.Values[AName];
  if not (mValue is TJSONString) or (TJSONString(mValue).Value = '') or
    not TryISO8601ToDate(TJSONString(mValue).Value, Result, True) then
    Result := 0;
end;

function TextOf(AObject: TJSONObject; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  mValue := AObject.Values[AName];
  if mValue is TJSONString then
    Result := TJSONString(mValue).Value;
end;

class function TAtlasTrackerNotify.ToJson(const AFile: TAtlasTrackerNotifyFile): string;
var
  mRoot, mObject, mEntry: TJSONObject;
  mList, mUnseen: TJSONArray;
  mConnection: TAtlasTrackerNotifyConnection;
  mItem: TAtlasTrackerUnseen;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('version', TJSONNumber.Create(Version));
    mRoot.AddPair('enabled', TJSONBool.Create(AFile.Enabled));
    mList := TJSONArray.Create;
    mRoot.AddPair('connections', mList);
    for mConnection in AFile.Connections do
    begin
      mObject := TJSONObject.Create;
      mList.AddElement(mObject);
      mObject.AddPair('id', mConnection.Id);
      mObject.AddPair('since', IsoOf(mConnection.Since));
      mObject.AddPair('me', mConnection.Me);
      mObject.AddPair('lastModified', mConnection.LastModified);
      mUnseen := TJSONArray.Create;
      mObject.AddPair('unseen', mUnseen);
      for mItem in mConnection.Unseen do
      begin
        mEntry := TJSONObject.Create;
        mUnseen.AddElement(mEntry);
        mEntry.AddPair('key', mItem.Key);
        mEntry.AddPair('project', mItem.Project);
        mEntry.AddPair('anchor', IsoOf(mItem.Anchor));
      end;
    end;
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasTrackerNotify.FromJson(const AJson: string; out AFile: TAtlasTrackerNotifyFile): Boolean;
var
  mValue, mItem, mEntry, mList: TJSONValue;
  mRoot, mObject: TJSONObject;
  mConnection: TAtlasTrackerNotifyConnection;
  mUnseen: TAtlasTrackerUnseen;
  mVersion: Integer;
begin
  AFile := TAtlasTrackerNotifyFile.Empty;
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONObject) then
      Exit;
    mRoot := TJSONObject(mValue);
    if not (mRoot.Values['version'] is TJSONNumber) or
      not TryStrToInt(TJSONNumber(mRoot.Values['version']).Value, mVersion) or (mVersion <> Version) then
      Exit;
    AFile.Enabled := (mRoot.Values['enabled'] is TJSONBool) and TJSONBool(mRoot.Values['enabled']).AsBoolean;
    mList := mRoot.Values['connections'];
    if mList is TJSONArray then
      for mItem in TJSONArray(mList) do
      begin
        if not (mItem is TJSONObject) then
          Continue;
        mObject := TJSONObject(mItem);
        mConnection := TAtlasTrackerNotifyConnection.Create(Trim(TextOf(mObject, 'id')), TimeOf(mObject, 'since'));
        if (mConnection.Id = '') or (mConnection.Since = 0) or (AFile.IndexOf(mConnection.Id) >= 0) then
          Continue;
        mConnection.Me := TextOf(mObject, 'me');
        mConnection.LastModified := TextOf(mObject, 'lastModified');
        if mObject.Values['unseen'] is TJSONArray then
          for mEntry in TJSONArray(mObject.Values['unseen']) do
          begin
            if not (mEntry is TJSONObject) then
              Continue;
            mUnseen.Key := Trim(TextOf(TJSONObject(mEntry), 'key'));
            mUnseen.Project := Trim(TextOf(TJSONObject(mEntry), 'project'));
            mUnseen.Anchor := TimeOf(TJSONObject(mEntry), 'anchor');
            if (mUnseen.Key <> '') and (mConnection.IndexOfUnseen(mUnseen.Key, mUnseen.Project) < 0) then
              mConnection.Unseen := mConnection.Unseen + [mUnseen];
          end;
        AFile.Connections := AFile.Connections + [mConnection];
      end;
    Result := True;
  finally
    mValue.Free;
  end;
end;

class function TAtlasTrackerNotify.Load(const AFolder: string): TAtlasTrackerNotifyFile;
var
  mFileName: string;
begin
  Result := TAtlasTrackerNotifyFile.Empty;
  if AFolder = '' then
    Exit;
  mFileName := TPath.Combine(AFolder, FileName);
  try
    if TFile.Exists(mFileName) and not FromJson(TFile.ReadAllText(mFileName, TEncoding.UTF8), Result) then
      Result := TAtlasTrackerNotifyFile.Empty;
  except
    // Nicht lesbar (gesperrt, kaputt): wie ohne Datei, also „jetzt“.
    on Exception do
      Result := TAtlasTrackerNotifyFile.Empty;
  end;
end;

class function TAtlasTrackerNotify.Save(const AFolder: string; const AFile: TAtlasTrackerNotifyFile): Boolean;
var
  mFileName, mTemp: string;
begin
  Result := False;
  if AFolder = '' then
    Exit;
  mFileName := TPath.Combine(AFolder, FileName);
  mTemp := mFileName + '.tmp';
  try
    TDirectory.CreateDirectory(AFolder);
    // Erst daneben schreiben, dann ersetzen: Ein Abbruch lässt nie eine halbe Datei zurück.
    TFile.WriteAllText(mTemp, ToJson(AFile), TEncoding.UTF8);
    if TFile.Exists(mFileName) then
      TFile.Delete(mFileName);
    TFile.Move(mTemp, mFileName);
    Result := True;
  except
    // Kein Platz, keine Rechte: Der Stand bleibt im Speicher und wird beim nächsten Mal wieder geschrieben.
    on Exception do
      Result := False;
  end;
end;

end.
