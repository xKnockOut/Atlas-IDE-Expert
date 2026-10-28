unit Atlas.Core.Tracker.Workflow;

// Tracker-Zustand und Kommentar beim Beginnen und Beenden (#1266), ohne VCL
// und Open Tools API.
// - TAtlasTrackerSyncOptions: Einstellungen issues.syncState, .stateField,
//   .assigneeField, .startState, .assignOnStart, .startComment, .endStates
//   und .endComment; ForConnection setzt die Werte der Verbindung mit
//   demselben Server darüber (Liste issues.connections, #1260).
// - Platzhalter der Kommentarvorlagen: {branch}, {commits} (Kurz-Hash und
//   Betreff der Commits mit der Kennung, älteste zuerst), {pr} (Adresse des
//   Pull Requests), {time} (erfasste Zeit, #1267) und {kennung}; "\n" in
//   der Vorlage wird ein Zeilenumbruch (die Einstellung ist einzeilig).
// - StartChange bzw. EndChange bauen die Änderung (TAtlasTrackerChange), die
//   der Anbieter (IAtlasTrackerWriter) schreibt. Geschrieben wird nur nach
//   „Beginnen“ bzw. dem Klick auf „Senden“ im Beenden-Dialog.

interface

uses
  System.SysUtils,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Vcs.Contract;

type
  TAtlasTrackerSyncOptions = record
    /// <summary>issues.syncState: Zustand, Zuweisung und Kommentar beim Beginnen und Beenden anbieten.</summary>
    SyncState: Boolean;
    /// <summary>Zustandsfeld (YouTrack); nie leer.</summary>
    StateField: string;
    /// <summary>Benutzerfeld für die Zuständigkeit (YouTrack); nie leer.</summary>
    AssigneeField: string;
    /// <summary>Zustand beim Beginnen; '' = nicht ändern.</summary>
    StartState: string;
    AssignOnStart: Boolean;
    /// <summary>Kommentarvorlage beim Beginnen; '' = kein Kommentar.</summary>
    StartComment: string;
    /// <summary>Zielzustände im Beenden-Dialog.</summary>
    EndStates: TArray<string>;
    /// <summary>Kommentarvorlage beim Beenden.</summary>
    EndComment: string;
    /// <summary>Aus den Einstellungen; leere Feldnamen werden zu den Vorgaben, AEndStates ist eine Liste mit
    /// Komma, Semikolon oder Zeilenumbruch.</summary>
    class function Create(ASyncState: Boolean; const AStateField, AAssigneeField, AStartState: string;
      AAssignOnStart: Boolean; const AStartComment, AEndStates, AEndComment: string): TAtlasTrackerSyncOptions;
      static;
    /// <summary>Beim Beginnen gibt es etwas zu schreiben.</summary>
    function HasStartWork: Boolean;
  end;

  /// <summary>Werte der Platzhalter.</summary>
  TAtlasTrackerPlaceholders = record
    Key: string;
    Branch: string;
    /// <summary>Zeilen „abc1234 Betreff“; '' ohne.</summary>
    Commits: string;
    /// <summary>Adresse des Pull Requests; '' ohne.</summary>
    PullRequest: string;
    /// <summary>Erfasste Zeit („1 h 25 min“, #1267); '' ohne.</summary>
    Time: string;
    class function Create(const AKey, ABranch: string): TAtlasTrackerPlaceholders; static;
  end;

  TAtlasTrackerWorkflow = class
  public const
    DefaultStateField = 'State';
    DefaultAssigneeField = 'Assignee';
    /// <summary>Vorgabe von issues.endComment.</summary>
    DefaultEndComment = 'Erledigt in {branch}.\n{commits}';
    /// <summary>Zeitgrenze eines Schreibzugriffs und der Klapplisten.</summary>
    WriteTimeoutMs = 10000;
    /// <summary>Höchstens so viele Commits in {commits}.</summary>
    MaxCommits = 20;
    /// <summary>Höchstens so viele Commits werden je Branch gelesen.</summary>
    MaxLog = 200;
  public
    /// <summary>Liste aus Text (Komma, Semikolon oder Zeilenumbruch); leere und doppelte Einträge entfallen.
    /// </summary>
    class function ParseList(const AText: string): TArray<string>; static;
    /// <summary>Umkehrung von ParseList mit ", ".</summary>
    class function ListText(const AItems: TArray<string>): string; static;
    /// <summary>AOptions mit den Werten der Verbindung zum Server von ATarget (persönliche zuerst); leere Werte der
    /// Verbindung lassen die globalen.</summary>
    class function ForConnection(const AOptions: TAtlasTrackerSyncOptions;
      const AConnections: TArray<TAtlasTrackerConnection>; const ATarget: TAtlasTrackerTarget): TAtlasTrackerSyncOptions;
      static;
    /// <summary>Platzhalter in ATemplate ersetzen, "\n" wird #10; Leerzeilen am Ende entfallen.</summary>
    class function Fill(const ATemplate: string; const AValues: TAtlasTrackerPlaceholders): string; static;
    /// <summary>Betreff nennt AKey als eigenes Wort („ATL-123:“, „[#753]“), ohne Groß-/Kleinschreibung.</summary>
    class function MentionsKey(const ASummary, AKey: string): Boolean; static;
    /// <summary>{commits}: Commits (neueste zuerst, wie git log) mit AKey im Betreff, älteste zuerst, höchstens
    /// MaxCommits.</summary>
    class function CommitLines(const ACommits: TArray<TAtlasVcsCommit>; const AKey: string): string; static;
    /// <summary>Änderung beim Beginnen; leer ohne issues.syncState.</summary>
    class function StartChange(const AOptions: TAtlasTrackerSyncOptions;
      const AValues: TAtlasTrackerPlaceholders): TAtlasTrackerChange; static;
    /// <summary>Änderung beim Beenden: AState '' = Zustand nicht ändern; AHandOver mit AAssignee übergibt die
    /// Zuständigkeit.</summary>
    class function EndChange(const AOptions: TAtlasTrackerSyncOptions; const AState, AComment: string;
      AHandOver: Boolean; const AAssignee: string): TAtlasTrackerChange; static;
    /// <summary>Dauer für {time}: „1 h 25 min“, „25 min“; '' für 0.</summary>
    class function DurationText(AMinutes: Integer): string; static;
  end;

implementation

uses
  System.StrUtils;

{ TAtlasTrackerSyncOptions }

class function TAtlasTrackerSyncOptions.Create(ASyncState: Boolean; const AStateField, AAssigneeField,
  AStartState: string; AAssignOnStart: Boolean; const AStartComment, AEndStates,
  AEndComment: string): TAtlasTrackerSyncOptions;
begin
  Result.SyncState := ASyncState;
  Result.StateField := Trim(AStateField);
  if Result.StateField = '' then
    Result.StateField := TAtlasTrackerWorkflow.DefaultStateField;
  Result.AssigneeField := Trim(AAssigneeField);
  if Result.AssigneeField = '' then
    Result.AssigneeField := TAtlasTrackerWorkflow.DefaultAssigneeField;
  Result.StartState := Trim(AStartState);
  Result.AssignOnStart := AAssignOnStart;
  Result.StartComment := AStartComment;
  Result.EndStates := TAtlasTrackerWorkflow.ParseList(AEndStates);
  Result.EndComment := AEndComment;
end;

function TAtlasTrackerSyncOptions.HasStartWork: Boolean;
begin
  Result := SyncState and ((StartState <> '') or AssignOnStart or (Trim(StartComment) <> ''));
end;

{ TAtlasTrackerPlaceholders }

class function TAtlasTrackerPlaceholders.Create(const AKey, ABranch: string): TAtlasTrackerPlaceholders;
begin
  Result.Key := AKey;
  Result.Branch := ABranch;
  Result.Commits := '';
  Result.PullRequest := '';
  Result.Time := '';
end;

{ TAtlasTrackerWorkflow }

class function TAtlasTrackerWorkflow.ParseList(const AText: string): TArray<string>;
var
  mPart, mItem: string;
  mFound: Boolean;
begin
  Result := nil;
  for mPart in StringReplace(StringReplace(StringReplace(AText, ';', ',', [rfReplaceAll]), #13, ',',
    [rfReplaceAll]), #10, ',', [rfReplaceAll]).Split([',']) do
  begin
    if Trim(mPart) = '' then
      Continue;
    mFound := False;
    for mItem in Result do
      if SameText(mItem, Trim(mPart)) then
        mFound := True;
    if not mFound then
      Result := Result + [Trim(mPart)];
  end;
end;

class function TAtlasTrackerWorkflow.ListText(const AItems: TArray<string>): string;
begin
  Result := string.Join(', ', AItems);
end;

class function TAtlasTrackerWorkflow.ForConnection(const AOptions: TAtlasTrackerSyncOptions;
  const AConnections: TArray<TAtlasTrackerConnection>; const ATarget: TAtlasTrackerTarget): TAtlasTrackerSyncOptions;
var
  mConnection: TAtlasTrackerConnection;
  mServer: string;
begin
  Result := AOptions;
  mServer := ATarget.Server;
  if mServer = '' then
    Exit;
  for mConnection in AConnections do
  begin
    if not SameText(mConnection.Provider, ATarget.Provider) or
      not SameText(mConnection.Target.Server, mServer) then
      Continue;
    if mConnection.StateField <> '' then
      Result.StateField := mConnection.StateField;
    if mConnection.AssigneeField <> '' then
      Result.AssigneeField := mConnection.AssigneeField;
    if mConnection.StartState <> '' then
      Result.StartState := mConnection.StartState;
    if Length(mConnection.EndStates) > 0 then
      Result.EndStates := Copy(mConnection.EndStates);
    Exit;
  end;
end;

class function TAtlasTrackerWorkflow.Fill(const ATemplate: string; const AValues: TAtlasTrackerPlaceholders): string;
var
  mCommits: string;
begin
  mCommits := StringReplace(AValues.Commits, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(ATemplate, '\n', #10, [rfReplaceAll]);
  Result := StringReplace(Result, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, '{branch}', AValues.Branch, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '{commits}', mCommits, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '{pr}', AValues.PullRequest, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '{time}', AValues.Time, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '{kennung}', AValues.Key, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '{key}', AValues.Key, [rfReplaceAll, rfIgnoreCase]);
  // Leere Platzhalter am Ende lassen keine Leerzeilen zurück.
  while (Result <> '') and CharInSet(Result[Length(Result)], [#10, ' ', #9]) do
    Delete(Result, Length(Result), 1);
end;

function IsKeyChar(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['A'..'Z', 'a'..'z', '0'..'9', '_', '-']);
end;

class function TAtlasTrackerWorkflow.MentionsKey(const ASummary, AKey: string): Boolean;
var
  mKey, mText: string;
  mPos, mEnd: Integer;
begin
  Result := False;
  mKey := UpperCase(Trim(AKey));
  if mKey = '' then
    Exit;
  mText := UpperCase(ASummary);
  mPos := Pos(mKey, mText);
  while mPos > 0 do
  begin
    mEnd := mPos + Length(mKey);
    // Eigenes Wort: davor und danach kein Buchstabe, keine Ziffer ("ATL-12" nicht in "ATL-123").
    if ((mPos = 1) or not IsKeyChar(mText[mPos - 1]) or (mKey[1] = '#')) and
      ((mEnd > Length(mText)) or not IsKeyChar(mText[mEnd])) then
      Exit(True);
    mPos := PosEx(mKey, mText, mPos + 1);
  end;
end;

class function TAtlasTrackerWorkflow.CommitLines(const ACommits: TArray<TAtlasVcsCommit>; const AKey: string): string;
var
  mIndex, mCount: Integer;
  mLines: TArray<string>;
begin
  mLines := nil;
  mCount := 0;
  for mIndex := High(ACommits) downto 0 do
  begin
    if not MentionsKey(ACommits[mIndex].Summary, AKey) then
      Continue;
    mLines := mLines + [ACommits[mIndex].ShortHash + ' ' + Trim(ACommits[mIndex].Summary)];
    Inc(mCount);
    if mCount >= MaxCommits then
      Break;
  end;
  Result := string.Join(#10, mLines);
end;

class function TAtlasTrackerWorkflow.StartChange(const AOptions: TAtlasTrackerSyncOptions;
  const AValues: TAtlasTrackerPlaceholders): TAtlasTrackerChange;
begin
  Result := TAtlasTrackerChange.Empty;
  if not AOptions.SyncState then
    Exit;
  Result.StateField := AOptions.StateField;
  Result.AssigneeField := AOptions.AssigneeField;
  Result.State := AOptions.StartState;
  if AOptions.AssignOnStart then
    Result.Assign := TAtlasTrackerAssign.Me;
  if Trim(AOptions.StartComment) <> '' then
    Result.Comment := Fill(AOptions.StartComment, AValues);
end;

class function TAtlasTrackerWorkflow.EndChange(const AOptions: TAtlasTrackerSyncOptions; const AState,
  AComment: string; AHandOver: Boolean; const AAssignee: string): TAtlasTrackerChange;
begin
  Result := TAtlasTrackerChange.Empty;
  Result.StateField := AOptions.StateField;
  Result.AssigneeField := AOptions.AssigneeField;
  Result.State := Trim(AState);
  Result.PreviousState := AOptions.StartState;
  Result.Comment := Trim(AComment);
  if AHandOver and (Trim(AAssignee) <> '') then
  begin
    Result.Assign := TAtlasTrackerAssign.User;
    Result.Assignee := Trim(AAssignee);
  end;
end;

class function TAtlasTrackerWorkflow.DurationText(AMinutes: Integer): string;
begin
  Result := '';
  if AMinutes <= 0 then
    Exit;
  if AMinutes < 60 then
    Exit(Format('%d min', [AMinutes]));
  if AMinutes mod 60 = 0 then
    Exit(Format('%d h', [AMinutes div 60]));
  Result := Format('%d h %d min', [AMinutes div 60, AMinutes mod 60]);
end;

end.
