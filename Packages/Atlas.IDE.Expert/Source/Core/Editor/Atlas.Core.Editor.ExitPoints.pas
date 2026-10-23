unit Atlas.Core.Editor.ExitPoints;

// Austrittspunkte hervorheben (#698), ohne VCL und Open Tools API:
// - FromJson liest die Antwort von atlas.server.exitPoints (siehe
//   Atlas.Common.Lsp.ExitPoints; Zeilen und Zeichen ab 0).
// - Triggers: Lohnt eine Anfrage an der Cursorstelle? Auf Exit, raise, Abort,
//   Halt, RunError, Result, except, on, Break, Continue, auf einem Namen vor
//   := (Funktionsname als Ergebnis) und auf dem Namen im Routinenkopf. Was der
//   Server daraus macht, entscheidet er; der Filter spart nur Anfragen.
// - Holds: Steht der Cursor auf einer der markierten Stellen oder auf dem
//   Routinennamen, gilt die Antwort weiter (F3 springt von Stelle zu Stelle,
//   auch auf das end, das selbst keine Anfrage auslöst).
// - Next: nächste bzw. vorherige Stelle reihum (F3/Umschalt+F3).
// - Role: Farbe je Stelle (Austritt, Zuweisung, Ergebnis fehlt, Quelle einer
//   Exception, Schleife).
// - BadgeText: „1 Austritt“, „3 Austritte“, mit fehlendem Ergebnis
//   „… · Result fehlt auf einem Weg“.

interface

uses
  System.SysUtils,
  System.JSON;

{$SCOPEDENUMS ON}

type
  TAtlasExitPointKind = (ExitCall, RaiseStatement, Terminate, RaisingCall, FallThrough, ResultAssign,
    ExceptionSource, Handler, LoopPart, LoopJump);

  /// <summary>Farbe einer Stelle: Leave = Austritt, Assign = Zuweisung an Result, Missing = Austritt ohne
  /// Ergebnis, Source = löst die Exception aus, Loop = Schleife und ihre Sprünge.</summary>
  TAtlasExitPointRole = (Leave, Assign, Missing, Source, Loop);

  TAtlasExitPointQuery = (None, Routine, ResultValue, Exceptions, Loop);

  TAtlasExitPoint = record
    Kind: TAtlasExitPointKind;
    /// <summary>0-basiert.</summary>
    Line: Integer;
    Character: Integer;
    EndCharacter: Integer;
    /// <summary>Austritt, an dem das Ergebnis fehlen kann (Hinweis wie W1035).</summary>
    ResultMissing: Boolean;
    /// <summary>Name des auslösenden Aufrufs bzw. der Klasse hinter raise.</summary>
    Detail: string;
    /// <summary>Exception-Klasse laut XMLDoc bzw. raise.</summary>
    ExceptionClass: string;
    function Role: TAtlasExitPointRole;
    /// <summary>Liegt ALine/ACharacter auf der Stelle (Ende eingeschlossen)?</summary>
    function Contains(ALine, ACharacter: Integer): Boolean;
  end;

  TAtlasExitPointSet = record
    Query: TAtlasExitPointQuery;
    HasRoutine: Boolean;
    RoutineName: string;
    /// <summary>Name im Kopf, 0-basiert.</summary>
    RoutineLine: Integer;
    RoutineCharacter: Integer;
    RoutineEnd: Integer;
    IsFunction: Boolean;
    Exits: Integer;
    ResultMissing: Boolean;
    /// <summary>In Dateireihenfolge.</summary>
    Points: TArray<TAtlasExitPoint>;
    /// <summary>Antwort von atlas.server.exitPoints; leer bei unbekanntem Format.</summary>
    class function FromJson(AValue: TJSONValue): TAtlasExitPointSet; static;
    function Found: Boolean;
    /// <summary>Stellen in ALine (0-basiert), von links nach rechts.</summary>
    function PointsAt(ALine: Integer): TArray<TAtlasExitPoint>;
    /// <summary>Index der Stelle unter ALine/ACharacter, sonst -1.</summary>
    function IndexAt(ALine, ACharacter: Integer): Integer;
    /// <summary>Steht der Cursor auf einer Stelle oder auf dem Routinennamen im Kopf?</summary>
    function Holds(ALine, ACharacter: Integer): Boolean;
    /// <summary>Nächste (ABackward: vorherige) Stelle nach bzw. vor ALine/ACharacter, über das Ende hinweg
    /// reihum. False ohne Stellen.</summary>
    function Next(ALine, ACharacter: Integer; ABackward: Boolean; out APoint: TAtlasExitPoint): Boolean;
    /// <summary>Marke am Routinenkopf: nur für Abfragen auf Routine und Result.</summary>
    function HasBadge: Boolean;
  end;

  TAtlasExitPoints = class
  public
    /// <summary>Wort an oder vor ACharacter (0-basiert) in ALine; False, wenn dort keins steht.</summary>
    class function WordAt(const ALine: string; ACharacter: Integer; out AStart, AStop: Integer): Boolean; static;
    /// <summary>Lohnt eine Anfrage an dieser Stelle (siehe Kopf der Unit)?</summary>
    class function Triggers(const ALine: string; ACharacter: Integer): Boolean; static;
    /// <summary>Text der Marke; AOne für einen Austritt, AMany mit %d, AMissing wird mit " · " angehängt.
    /// </summary>
    class function BadgeText(const ASet: TAtlasExitPointSet; const AOne, AMany, AMissing: string): string; static;
  end;

{$SCOPEDENUMS OFF}

implementation

uses
  Atlas.Text.Chars;

const
  KindNames: array[TAtlasExitPointKind] of string = ('exit', 'raise', 'halt', 'call', 'end', 'result', 'source',
    'handler', 'loop', 'jump');
  QueryNames: array[TAtlasExitPointQuery] of string = ('', 'routine', 'result', 'exceptions', 'loop');
  TriggerWords: array[0..9] of string = ('exit', 'raise', 'abort', 'halt', 'runerror', 'result', 'except', 'on',
    'break', 'continue');
  HeaderWords: array[0..4] of string = ('procedure', 'function', 'constructor', 'destructor', 'operator');

function KindOf(const AName: string; out AKind: TAtlasExitPointKind): Boolean;
var
  Kind: TAtlasExitPointKind;
begin
  for Kind := Low(TAtlasExitPointKind) to High(TAtlasExitPointKind) do
    if KindNames[Kind] = AName then
    begin
      AKind := Kind;
      Exit(True);
    end;
  Result := False;
end;

function QueryOf(const AName: string): TAtlasExitPointQuery;
var
  Query: TAtlasExitPointQuery;
begin
  for Query := Low(TAtlasExitPointQuery) to High(TAtlasExitPointQuery) do
    if QueryNames[Query] = AName then
      Exit(Query);
  Result := TAtlasExitPointQuery.None;
end;

function Before(ALine, ACharacter, BLine, BCharacter: Integer): Boolean;
begin
  Result := (ALine < BLine) or ((ALine = BLine) and (ACharacter < BCharacter));
end;

{ TAtlasExitPoint }

function TAtlasExitPoint.Role: TAtlasExitPointRole;
begin
  case Kind of
    TAtlasExitPointKind.ResultAssign:
      Result := TAtlasExitPointRole.Assign;
    TAtlasExitPointKind.ExceptionSource:
      Result := TAtlasExitPointRole.Source;
    TAtlasExitPointKind.LoopPart, TAtlasExitPointKind.LoopJump:
      Result := TAtlasExitPointRole.Loop;
  else
    if ResultMissing then
      Result := TAtlasExitPointRole.Missing
    else
      Result := TAtlasExitPointRole.Leave;
  end;
end;

function TAtlasExitPoint.Contains(ALine, ACharacter: Integer): Boolean;
begin
  Result := (ALine = Line) and (ACharacter >= Character) and (ACharacter <= EndCharacter);
end;

{ TAtlasExitPointSet }

class function TAtlasExitPointSet.FromJson(AValue: TJSONValue): TAtlasExitPointSet;
var
  Root, Routine, Item: TJSONObject;
  Value: TJSONValue;
  Point: TAtlasExitPoint;
  Kind: TAtlasExitPointKind;
begin
  Result := Default(TAtlasExitPointSet);
  Result.RoutineLine := -1;
  if not (AValue is TJSONObject) then
    Exit;
  Root := TJSONObject(AValue);
  Result.Query := QueryOf(Root.GetValue<string>('query', ''));
  if Root.GetValue('routine') is TJSONObject then
  begin
    Routine := TJSONObject(Root.GetValue('routine'));
    Result.RoutineName := Routine.GetValue<string>('name', '');
    Result.RoutineLine := Routine.GetValue<Integer>('line', -1);
    Result.RoutineCharacter := Routine.GetValue<Integer>('character', 0);
    Result.RoutineEnd := Routine.GetValue<Integer>('endCharacter', Result.RoutineCharacter);
    Result.HasRoutine := Result.RoutineLine >= 0;
  end;
  Result.IsFunction := Root.GetValue<Boolean>('function', False);
  Result.Exits := Root.GetValue<Integer>('exits', 0);
  Result.ResultMissing := Root.GetValue<Boolean>('resultMissing', False);
  // Typen selbst prüfen: GetValue<TJSONArray> wandelt eine Zahl ungeprüft um.
  if not (Root.GetValue('points') is TJSONArray) then
    Exit;
  for Value in TJSONArray(Root.GetValue('points')) do
  begin
    if not (Value is TJSONObject) then
      Continue;
    Item := TJSONObject(Value);
    if not KindOf(Item.GetValue<string>('kind', ''), Kind) then
      Continue;
    Point := Default(TAtlasExitPoint);
    Point.Kind := Kind;
    Point.Line := Item.GetValue<Integer>('line', -1);
    Point.Character := Item.GetValue<Integer>('character', 0);
    Point.EndCharacter := Item.GetValue<Integer>('endCharacter', Point.Character);
    Point.ResultMissing := Item.GetValue<Boolean>('resultMissing', False);
    Point.Detail := Item.GetValue<string>('detail', '');
    Point.ExceptionClass := Item.GetValue<string>('exception', '');
    if Point.Line >= 0 then
      Result.Points := Result.Points + [Point];
  end;
end;

function TAtlasExitPointSet.Found: Boolean;
begin
  Result := (Query <> TAtlasExitPointQuery.None) and (Length(Points) > 0);
end;

function TAtlasExitPointSet.PointsAt(ALine: Integer): TArray<TAtlasExitPoint>;
var
  Point: TAtlasExitPoint;
begin
  Result := nil;
  for Point in Points do
    if Point.Line = ALine then
      Result := Result + [Point];
end;

function TAtlasExitPointSet.IndexAt(ALine, ACharacter: Integer): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Points) do
    if Points[Index].Contains(ALine, ACharacter) then
      Exit(Index);
  Result := -1;
end;

function TAtlasExitPointSet.Holds(ALine, ACharacter: Integer): Boolean;
begin
  Result := Found and ((IndexAt(ALine, ACharacter) >= 0) or (HasRoutine and (ALine = RoutineLine) and
    (ACharacter >= RoutineCharacter) and (ACharacter <= RoutineEnd)));
end;

function TAtlasExitPointSet.Next(ALine, ACharacter: Integer; ABackward: Boolean;
  out APoint: TAtlasExitPoint): Boolean;
var
  Index, Current: Integer;
begin
  Result := Length(Points) > 0;
  if not Result then
    Exit;
  // Auf einer Stelle zählt ihr Anfang, damit der Sprung nicht auf derselben Stelle landet.
  Current := IndexAt(ALine, ACharacter);
  if Current >= 0 then
    ACharacter := Points[Current].Character;
  if ABackward then
  begin
    APoint := Points[High(Points)];
    for Index := High(Points) downto 0 do
      if Before(Points[Index].Line, Points[Index].Character, ALine, ACharacter) then
      begin
        APoint := Points[Index];
        Exit;
      end;
  end
  else
  begin
    APoint := Points[0];
    for Index := 0 to High(Points) do
      if Before(ALine, ACharacter, Points[Index].Line, Points[Index].Character) then
      begin
        APoint := Points[Index];
        Exit;
      end;
  end;
end;

function TAtlasExitPointSet.HasBadge: Boolean;
begin
  Result := HasRoutine and ((Query = TAtlasExitPointQuery.Routine) or (Query = TAtlasExitPointQuery.ResultValue));
end;

{ TAtlasExitPoints }

class function TAtlasExitPoints.WordAt(const ALine: string; ACharacter: Integer; out AStart, AStop: Integer): Boolean;
begin
  AStart := ACharacter;
  if (AStart >= Length(ALine)) or not TTextChars.IsIdentChar(ALine[AStart + 1]) then
    Dec(AStart);
  Result := (AStart >= 0) and (AStart < Length(ALine)) and TTextChars.IsIdentChar(ALine[AStart + 1]);
  if not Result then
    Exit;
  while (AStart > 0) and TTextChars.IsIdentChar(ALine[AStart]) do
    Dec(AStart);
  AStop := AStart;
  while (AStop < Length(ALine)) and TTextChars.IsIdentChar(ALine[AStop + 1]) do
    Inc(AStop);
end;

class function TAtlasExitPoints.Triggers(const ALine: string; ACharacter: Integer): Boolean;
var
  Start, Stop, Index: Integer;
  Word, Head, Rest: string;
begin
  Result := WordAt(ALine, ACharacter, Start, Stop);
  if not Result then
    Exit;
  Word := LowerCase(Copy(ALine, Start + 1, Stop - Start));
  for Head in TriggerWords do
    if Word = Head then
      Exit(True);
  // Funktionsname als Ziel einer Zuweisung.
  Rest := TrimLeft(Copy(ALine, Stop + 1, MaxInt));
  if Rest.StartsWith(':=') then
    Exit(True);
  // Name im Routinenkopf: vor dem Wort steht (class) procedure, function … und sonst nur Namen mit Punkten.
  Head := LowerCase(Trim(Copy(ALine, 1, Start)));
  for Index := 1 to Length(Head) do
    if not TTextChars.IsIdentChar(Head[Index]) and not CharInSet(Head[Index], ['.', ' ', '<', '>', ',']) then
      Exit(False);
  if Head.StartsWith('class ') then
    Head := TrimLeft(Copy(Head, 7, MaxInt));
  for Word in HeaderWords do
    if (Head = Word) or Head.StartsWith(Word + ' ') then
      Exit(True);
  Result := False;
end;

class function TAtlasExitPoints.BadgeText(const ASet: TAtlasExitPointSet; const AOne, AMany,
  AMissing: string): string;
begin
  if ASet.Exits = 1 then
    Result := AOne
  else
    Result := Format(AMany, [ASet.Exits]);
  if ASet.ResultMissing then
    Result := Result + ' ' + #$00B7 + ' ' + AMissing;
end;

end.
