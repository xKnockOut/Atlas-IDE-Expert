unit Atlas.Core.Debug.ThreadsInSourceFlow;

// Entscheidungen von „Threads im Quelltext“ (#852) außerhalb der Marken, ohne IDE prüfbar (#1967): wann die Stapel
// gelesen sind, für welche Threads ein Befehl gilt, ob eine Auswahlliste nötig ist und was ein Eintrag darin trifft.
// Atlas.IDE.Debug.ThreadsInSource fragt Debugger, Editor und Rinne.

interface

uses
  Atlas.Core.Debug.ThreadMarks;

type
  {$SCOPEDENUMS ON}
  /// <summary>Was ein Eintrag der Auswahlliste mit dem gewählten Thread tut.</summary>
  TAtlasThreadAction = (Switch, Flag, Freeze, Thaw);
  /// <summary>Wie ein Befehl seine Threads bekommt: Programm steht nicht, kein Thread, genau einer, Auswahlliste.
  /// </summary>
  TAtlasThreadPick = (NotStopped, Nothing, Direct, Menu);
  {$SCOPEDENUMS OFF}

  TAtlasThreadsInSourceFlow = class
  public const
    /// <summary>Tag des Eintrags „Alle Threads dieser Zeile“.</summary>
    cAllTag = -1;
  public
    /// <summary>Stapel fertig gelesen: nichts steht aus (APending False) oder mehr als AMax Versuche (ARetries).
    /// </summary>
    class function ReadDone(APending: Boolean; ARetries, AMax: Integer): Boolean; static;
    /// <summary>Threads der Marke an Zeile ALine (1-basiert) von AFileName; nil ohne Marke oder ohne Editor
    /// (AFileName '').</summary>
    class function ThreadsAt(const AMarks: TAtlasDebugThreadMarks; const AFileName: string;
      ALine: Integer): TArray<Integer>; static;
    /// <summary>Kein anderer Thread an der Zeile: der aktuelle (ACurrent, -1 ohne).</summary>
    class function CurrentOnly(ACurrent: Integer): TArray<Integer>; static;
    class function PickOf(AHasStacks, AStopped: Boolean; ACount: Integer): TAtlasThreadPick; static;
    /// <summary>„Alle Threads dieser Zeile“ anbieten? Wechseln geht nur zu einem.</summary>
    class function OffersAll(AAction: TAtlasThreadAction): Boolean; static;
    /// <summary>Threads, die der Eintrag mit ATag trifft: alle bei cAllTag, sonst der eine.</summary>
    class function Targets(ATag: Integer; const AThreads: TArray<Integer>): TArray<Integer>; static;
    /// <summary>Gibt es den Thread AThread unter ACount Stapeln?</summary>
    class function ValidThread(AThread, ACount: Integer): Boolean; static;
  end;

implementation

{ TAtlasThreadsInSourceFlow }

class function TAtlasThreadsInSourceFlow.ReadDone(APending: Boolean; ARetries, AMax: Integer): Boolean;
begin
  Result := not APending or (ARetries > AMax);
end;

class function TAtlasThreadsInSourceFlow.ThreadsAt(const AMarks: TAtlasDebugThreadMarks; const AFileName: string;
  ALine: Integer): TArray<Integer>;
var
  mMark: Integer;
begin
  Result := nil;
  if AFileName = '' then
  begin
    Exit;
  end;
  mMark := AMarks.IndexAt(AFileName, ALine);
  if mMark >= 0 then
  begin
    Result := AMarks.Marks[mMark].Threads;
  end;
end;

class function TAtlasThreadsInSourceFlow.CurrentOnly(ACurrent: Integer): TArray<Integer>;
begin
  Result := nil;
  if ACurrent >= 0 then
  begin
    Result := [ACurrent];
  end;
end;

class function TAtlasThreadsInSourceFlow.PickOf(AHasStacks, AStopped: Boolean; ACount: Integer): TAtlasThreadPick;
begin
  if not AHasStacks or not AStopped then
  begin
    Result := TAtlasThreadPick.NotStopped;
  end
  else if ACount = 0 then
  begin
    Result := TAtlasThreadPick.Nothing;
  end
  else if ACount = 1 then
  begin
    Result := TAtlasThreadPick.Direct;
  end
  else
  begin
    Result := TAtlasThreadPick.Menu;
  end;
end;

class function TAtlasThreadsInSourceFlow.OffersAll(AAction: TAtlasThreadAction): Boolean;
begin
  Result := AAction <> TAtlasThreadAction.Switch;
end;

class function TAtlasThreadsInSourceFlow.Targets(ATag: Integer; const AThreads: TArray<Integer>): TArray<Integer>;
begin
  Result := AThreads;
  if ATag <> cAllTag then
  begin
    Result := [ATag];
  end;
end;

class function TAtlasThreadsInSourceFlow.ValidThread(AThread, ACount: Integer): Boolean;
begin
  Result := (AThread >= 0) and (AThread < ACount);
end;

end.
