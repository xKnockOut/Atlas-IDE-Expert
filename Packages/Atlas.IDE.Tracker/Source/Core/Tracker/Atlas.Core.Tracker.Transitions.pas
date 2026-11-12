unit Atlas.Core.Tracker.Transitions;

// Übergänge einer Zustandsmaschine zuordnen (#1569, #2122), ohne VCL und
// Open Tools API; gemeinsam für Board, Beginnen, Beenden und Statusfeld.
// - Ein Übergang führt in einen Zustand, wenn seine Kennung oder sein Name
//   dem Zustand gleicht (ohne Groß- und Kleinschreibung, '-' und '_' wie
//   Leerzeichen). Benannte Ereignisse ("Beginnen") verraten ihr Ziel nicht.
// - Into: erster Übergang in einen von mehreren Werten (Spalte des Boards).
// - Preferred: Übergang in den ersten erreichbaren Wunschzustand
//   (issues.startState, issues.endStates; Reihenfolge = Vorliebe).
// - TargetOf: bekanntes Ziel eines Übergangs unter bekannten Zuständen
//   („Zur Prüfung geben → Zur Prüfung“).

interface

uses
  Atlas.Core.Tracker.Contract;

type
  TAtlasTrackerTransitions = class
  public
    /// <summary>Vergleichsform: klein, ohne Rand, '-' und '_' als Leerzeichen.</summary>
    class function Plain(const AText: string): string; static;
    /// <summary>ATransition führt nach Kennung oder Name in einen der Werte AValues.</summary>
    class function LeadsTo(const ATransition: TAtlasTrackerTransition; const AValues: TArray<string>): Boolean;
      static;
    /// <summary>Erster Übergang von ARules, der in einen der Werte AValues führt; -1 ohne.</summary>
    class function Into(const ARules: TAtlasTrackerStateRules; const AValues: TArray<string>): Integer; static;
    /// <summary>Übergang in den ersten Wunschzustand von AWanted, der erreichbar ist; -1 ohne.</summary>
    class function Preferred(const ARules: TAtlasTrackerStateRules; const AWanted: TArray<string>): Integer; static;
    /// <summary>Zustand aus AStates, in den ATransition nach Kennung oder Name führt; '' unbekannt.</summary>
    class function TargetOf(const ATransition: TAtlasTrackerTransition; const AStates: TArray<string>): string;
      static;
    /// <summary>Der aktuelle Wert von ARules ist AState (ohne Groß- und Kleinschreibung).</summary>
    class function IsAt(const ARules: TAtlasTrackerStateRules; const AState: string): Boolean; static;
    /// <summary>Eintrag einer Klappliste: Anzeigename, mit bekanntem Ziel aus AStates „Name → Ziel“ (das Ziel
    /// entfällt, wenn es dem Namen gleicht).</summary>
    class function ChoiceText(const ATransition: TAtlasTrackerTransition; const AStates: TArray<string>): string;
      static;
    /// <summary>Anzeigenamen der Übergänge von ARules.</summary>
    class function Captions(const ARules: TAtlasTrackerStateRules): TArray<string>; static;
    /// <summary>Anzeigenamen der Übergänge mit ", " verbunden; '' ohne.</summary>
    class function Names(const ARules: TAtlasTrackerStateRules): string; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasTrackerTransitions }

class function TAtlasTrackerTransitions.Plain(const AText: string): string;
begin
  Result := LowerCase(Trim(StringReplace(StringReplace(AText, '-', ' ', [rfReplaceAll]), '_', ' ',
    [rfReplaceAll])));
end;

class function TAtlasTrackerTransitions.LeadsTo(const ATransition: TAtlasTrackerTransition;
  const AValues: TArray<string>): Boolean;
var
  mValue, mPlain: string;
begin
  Result := False;
  for mValue in AValues do
  begin
    mPlain := Plain(mValue);
    if (mPlain <> '') and ((mPlain = Plain(ATransition.Name)) or (mPlain = Plain(ATransition.Id))) then
    begin
      Result := True;
    end;
  end;
end;

class function TAtlasTrackerTransitions.Into(const ARules: TAtlasTrackerStateRules;
  const AValues: TArray<string>): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := High(ARules.Transitions) downto 0 do
  begin
    if LeadsTo(ARules.Transitions[mIndex], AValues) then
    begin
      Result := mIndex;
    end;
  end;
end;

class function TAtlasTrackerTransitions.Preferred(const ARules: TAtlasTrackerStateRules;
  const AWanted: TArray<string>): Integer;
var
  mWanted: string;
begin
  Result := -1;
  for mWanted in AWanted do
  begin
    Result := Into(ARules, TArray<string>.Create(mWanted));
    if Result >= 0 then
    begin
      Exit;
    end;
  end;
end;

class function TAtlasTrackerTransitions.TargetOf(const ATransition: TAtlasTrackerTransition;
  const AStates: TArray<string>): string;
var
  mState: string;
begin
  Result := '';
  for mState in AStates do
  begin
    if LeadsTo(ATransition, TArray<string>.Create(mState)) then
    begin
      Exit(Trim(mState));
    end;
  end;
end;

class function TAtlasTrackerTransitions.ChoiceText(const ATransition: TAtlasTrackerTransition;
  const AStates: TArray<string>): string;
var
  mTarget: string;
begin
  Result := ATransition.Caption;
  mTarget := TargetOf(ATransition, AStates);
  if (mTarget <> '') and (Plain(mTarget) <> Plain(Result)) then
  begin
    Result := Result + ' → ' + mTarget;
  end;
end;

class function TAtlasTrackerTransitions.IsAt(const ARules: TAtlasTrackerStateRules; const AState: string): Boolean;
begin
  Result := (Trim(AState) <> '') and SameText(Trim(ARules.Current), Trim(AState));
end;

class function TAtlasTrackerTransitions.Captions(const ARules: TAtlasTrackerStateRules): TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(ARules.Transitions));
  for mIndex := 0 to High(ARules.Transitions) do
  begin
    Result[mIndex] := ARules.Transitions[mIndex].Caption;
  end;
end;

class function TAtlasTrackerTransitions.Names(const ARules: TAtlasTrackerStateRules): string;
begin
  Result := string.Join(', ', Captions(ARules));
end;

end.
