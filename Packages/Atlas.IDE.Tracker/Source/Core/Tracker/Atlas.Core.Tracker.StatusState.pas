unit Atlas.Core.Tracker.StatusState;

// Zustand des aktuellen Issues im Statusfeld (#2124, issues.statusState),
// ohne VCL und Open Tools API:
// - Feldtext „ATL-2052 · In Bearbeitung · 1:25“ (Text): Teile ohne Wert
//   entfallen; lange Zustände kürzt Short auf cMaxState Zeichen mit „…“, der
//   volle Name steht im Hinweis.
// - Einträge des Menüs (Entries): unter einer Zustandsmaschine die erlaubten
//   Übergänge („Zur Prüfung geben → Zur Prüfung“, wenn das Ziel unter den
//   Werten des Feldes bekannt ist), sonst die Werte des Zustandsfeldes außer
//   dem aktuellen.
// - Einträge der Befehlspalette (Matching, RowCaption): „ATL-2052: Zur
//   Prüfung geben“, sobald jedes Wort der Eingabe im Eintrag vorkommt;
//   Kennung „atlas.issueState:<n>“ (RowId, IndexOf). Leere Eingabe zeigt
//   nichts, damit die Befehle vorn bleiben.
// - Änderung zu einem Eintrag (Change) mit optionalem Kommentar und der
//   danach bekannte Zustand (After).

interface

uses
  Atlas.Core.Tracker.Contract;

type
  /// <summary>Eintrag des Menüs: ein Übergang (Transition.Id gesetzt) oder ein Wert des Zustandsfeldes (State).
  /// </summary>
  TAtlasIssueStateEntry = record
    Caption: string;
    Transition: TAtlasTrackerTransition;
    State: string;
    class function ForTransition(const ATransition: TAtlasTrackerTransition;
      const AStates: TArray<string>): TAtlasIssueStateEntry; static;
    class function ForState(const AState: string): TAtlasIssueStateEntry; static;
  end;

  TAtlasIssueStatus = class
  public const
    /// <summary>Längere Zustände kürzt das Statusfeld.</summary>
    cMaxState = 24;
    cSeparator = ' · ';
    /// <summary>Anfang der Kennung eines Eintrags in der Befehlspalette.</summary>
    cRowPrefix = 'atlas.issueState:';
  public
    /// <summary>AState höchstens cMaxState Zeichen, sonst gekürzt mit „…“.</summary>
    class function Short(const AState: string): string; static;
    /// <summary>„Kennung · Zustand · Zeit“; leere Teile entfallen, der Zustand gekürzt.</summary>
    class function Text(const AKey, AState, AClock: string): string; static;
    /// <summary>Unter einer Zustandsmaschine die Übergänge von ARules, sonst die Werte AStates außer ACurrent.
    /// </summary>
    class function Entries(const ARules: TAtlasTrackerStateRules; const AStates: TArray<string>;
      const ACurrent: string): TArray<TAtlasIssueStateEntry>; static;
    /// <summary>Text der Zeile in der Befehlspalette: „Kennung: Eintrag“.</summary>
    class function RowCaption(const AKey: string; const AEntry: TAtlasIssueStateEntry): string; static;
    /// <summary>Kennung der Zeile zum Eintrag AIndex.</summary>
    class function RowId(AIndex: Integer): string; static;
    /// <summary>Nummern der Einträge, deren Zeile für AKey alle Wörter von APattern enthält; nil bei leerer Eingabe
    /// oder ohne Issue.</summary>
    class function Matching(const AKey: string; const AEntries: TArray<TAtlasIssueStateEntry>;
      const APattern: string): TArray<Integer>; static;
    /// <summary>Nummer des Eintrags zur Kennung einer Zeile; -1, wenn sie nicht von Rows stammt.</summary>
    class function IndexOf(const AId: string): Integer; static;
    /// <summary>Änderung für AEntry: Übergang (mit AFieldId) bzw. Wert im Feld AStateField, dazu AComment.</summary>
    class function Change(const AEntry: TAtlasIssueStateEntry; const AStateField, AFieldId,
      AComment: string): TAtlasTrackerWrite; static;
    /// <summary>Zustand nach AEntry: der Wert bzw. das bekannte Ziel des Übergangs unter AStates; '' unbekannt.
    /// </summary>
    class function After(const AEntry: TAtlasIssueStateEntry; const AStates: TArray<string>): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Tracker.Transitions;

{ TAtlasIssueStateEntry }

class function TAtlasIssueStateEntry.ForTransition(const ATransition: TAtlasTrackerTransition;
  const AStates: TArray<string>): TAtlasIssueStateEntry;
begin
  Result := Default(TAtlasIssueStateEntry);
  Result.Transition := ATransition;
  Result.Caption := TAtlasTrackerTransitions.ChoiceText(ATransition, AStates);
end;

class function TAtlasIssueStateEntry.ForState(const AState: string): TAtlasIssueStateEntry;
begin
  Result := Default(TAtlasIssueStateEntry);
  Result.State := AState;
  Result.Caption := AState;
end;

{ TAtlasIssueStatus }

class function TAtlasIssueStatus.Short(const AState: string): string;
begin
  Result := Trim(AState);
  if Length(Result) > cMaxState then
  begin
    Result := TrimRight(Copy(Result, 1, cMaxState - 1)) + '…';
  end;
end;

class function TAtlasIssueStatus.Text(const AKey, AState, AClock: string): string;
var
  mParts: TArray<string>;
begin
  mParts := nil;
  if Trim(AKey) <> '' then
  begin
    mParts := mParts + [Trim(AKey)];
  end;
  if Short(AState) <> '' then
  begin
    mParts := mParts + [Short(AState)];
  end;
  if Trim(AClock) <> '' then
  begin
    mParts := mParts + [Trim(AClock)];
  end;
  Result := string.Join(cSeparator, mParts);
end;

class function TAtlasIssueStatus.Entries(const ARules: TAtlasTrackerStateRules; const AStates: TArray<string>;
  const ACurrent: string): TArray<TAtlasIssueStateEntry>;
var
  mTransition: TAtlasTrackerTransition;
  mState: string;
begin
  Result := nil;
  if ARules.StateMachine then
  begin
    for mTransition in ARules.Transitions do
    begin
      Result := Result + [TAtlasIssueStateEntry.ForTransition(mTransition, AStates)];
    end;
    Exit;
  end;
  for mState in AStates do
  begin
    if (Trim(mState) <> '') and not SameText(Trim(mState), Trim(ACurrent)) then
    begin
      Result := Result + [TAtlasIssueStateEntry.ForState(Trim(mState))];
    end;
  end;
end;

/// <summary>Jedes Wort von APattern kommt in AText vor (ohne Groß- und Kleinschreibung); False bei leerem Muster.
/// </summary>
function MatchesAll(const AText, APattern: string): Boolean;
var
  mWord, mText: string;
  mAny: Boolean;
begin
  mText := LowerCase(AText);
  mAny := False;
  for mWord in LowerCase(APattern).Split([' '], TStringSplitOptions.ExcludeEmpty) do
  begin
    if Pos(mWord, mText) = 0 then
    begin
      Exit(False);
    end;
    mAny := True;
  end;
  Result := mAny;
end;

class function TAtlasIssueStatus.RowCaption(const AKey: string; const AEntry: TAtlasIssueStateEntry): string;
begin
  Result := Trim(AKey) + ': ' + AEntry.Caption;
end;

class function TAtlasIssueStatus.RowId(AIndex: Integer): string;
begin
  Result := cRowPrefix + IntToStr(AIndex);
end;

class function TAtlasIssueStatus.Matching(const AKey: string; const AEntries: TArray<TAtlasIssueStateEntry>;
  const APattern: string): TArray<Integer>;
var
  mIndex: Integer;
begin
  Result := nil;
  if Trim(AKey) = '' then
  begin
    Exit;
  end;
  for mIndex := 0 to High(AEntries) do
  begin
    if MatchesAll(RowCaption(AKey, AEntries[mIndex]), APattern) then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

class function TAtlasIssueStatus.IndexOf(const AId: string): Integer;
begin
  Result := -1;
  if AId.StartsWith(cRowPrefix) then
  begin
    Result := StrToIntDef(Copy(AId, Length(cRowPrefix) + 1, MaxInt), -1);
  end;
end;

class function TAtlasIssueStatus.Change(const AEntry: TAtlasIssueStateEntry; const AStateField, AFieldId,
  AComment: string): TAtlasTrackerWrite;
begin
  Result := TAtlasTrackerWrite.CommentOnly(Trim(AComment));
  Result.StateField := AStateField;
  if AEntry.Transition.Id <> '' then
  begin
    Result.Transition := AEntry.Transition;
    Result.FieldId := AFieldId;
  end
  else
  begin
    Result.State := AEntry.State;
  end;
end;

class function TAtlasIssueStatus.After(const AEntry: TAtlasIssueStateEntry; const AStates: TArray<string>): string;
begin
  Result := AEntry.State;
  if AEntry.Transition.Id <> '' then
  begin
    Result := TAtlasTrackerTransitions.TargetOf(AEntry.Transition, AStates);
  end;
end;

end.
