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
  System.Generics.Collections,
  Atlas.Text.Chars;

const
  cKindNames: array[TAtlasExitPointKind] of string = ('exit', 'raise', 'halt', 'call', 'end', 'result', 'source',
    'handler', 'loop', 'jump');
  cQueryNames: array[TAtlasExitPointQuery] of string = ('', 'routine', 'result', 'exceptions', 'loop');
  cTriggerWords: array[0..9] of string = ('exit', 'raise', 'abort', 'halt', 'runerror', 'result', 'except', 'on',
    'break', 'continue');
  cHeaderWords: array[0..4] of string = ('procedure', 'function', 'constructor', 'destructor', 'operator');

function KindOf(const AName: string; out AKind: TAtlasExitPointKind): Boolean;
var
  mKind: TAtlasExitPointKind;
begin
  for mKind := Low(TAtlasExitPointKind) to High(TAtlasExitPointKind) do
  begin
    if cKindNames[mKind] = AName then
    begin
      AKind := mKind;
      Exit(True);
    end;
  end;
  Result := False;
end;

function QueryOf(const AName: string): TAtlasExitPointQuery;
var
  mQuery: TAtlasExitPointQuery;
begin
  for mQuery := Low(TAtlasExitPointQuery) to High(TAtlasExitPointQuery) do
  begin
    if cQueryNames[mQuery] = AName then
    begin
      Exit(mQuery);
    end;
  end;
  Result := TAtlasExitPointQuery.None;
end;

function Before(ALine, ACharacter, ABLine, ABCharacter: Integer): Boolean;
begin
  Result := (ALine < ABLine) or ((ALine = ABLine) and (ACharacter < ABCharacter));
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
    begin
      Result := TAtlasExitPointRole.Missing;
    end
    else
    begin
      Result := TAtlasExitPointRole.Leave;
    end;
  end;
end;

function TAtlasExitPoint.Contains(ALine, ACharacter: Integer): Boolean;
begin
  Result := (ALine = Line) and (ACharacter >= Character) and (ACharacter <= EndCharacter);
end;

{ TAtlasExitPointSet }

class function TAtlasExitPointSet.FromJson(AValue: TJSONValue): TAtlasExitPointSet;
var
  mRoot, mRoutine, mItem: TJSONObject;
  mValue: TJSONValue;
  mPoint: TAtlasExitPoint;
  mKind: TAtlasExitPointKind;
begin
  Result := Default(TAtlasExitPointSet);
  Result.RoutineLine := -1;
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  mRoot := TJSONObject(AValue);
  Result.Query := QueryOf(mRoot.GetValue<string>('query', ''));
  if mRoot.GetValue('routine') is TJSONObject then
  begin
    mRoutine := TJSONObject(mRoot.GetValue('routine'));
    Result.RoutineName := mRoutine.GetValue<string>('name', '');
    Result.RoutineLine := mRoutine.GetValue<Integer>('line', -1);
    Result.RoutineCharacter := mRoutine.GetValue<Integer>('character', 0);
    Result.RoutineEnd := mRoutine.GetValue<Integer>('endCharacter', Result.RoutineCharacter);
    Result.HasRoutine := Result.RoutineLine >= 0;
  end;
  Result.IsFunction := mRoot.GetValue<Boolean>('function', False);
  Result.Exits := mRoot.GetValue<Integer>('exits', 0);
  Result.ResultMissing := mRoot.GetValue<Boolean>('resultMissing', False);
  // Typen selbst prüfen: GetValue<TJSONArray> wandelt eine Zahl ungeprüft um.
  if not (mRoot.GetValue('points') is TJSONArray) then
  begin
    Exit;
  end;
  for mValue in TJSONArray(mRoot.GetValue('points')) do
  begin
    if not (mValue is TJSONObject) then
    begin
      Continue;
    end;
    mItem := TJSONObject(mValue);
    if not KindOf(mItem.GetValue<string>('kind', ''), mKind) then
    begin
      Continue;
    end;
    mPoint := Default(TAtlasExitPoint);
    mPoint.Kind := mKind;
    mPoint.Line := mItem.GetValue<Integer>('line', -1);
    mPoint.Character := mItem.GetValue<Integer>('character', 0);
    mPoint.EndCharacter := mItem.GetValue<Integer>('endCharacter', mPoint.Character);
    mPoint.ResultMissing := mItem.GetValue<Boolean>('resultMissing', False);
    mPoint.Detail := mItem.GetValue<string>('detail', '');
    mPoint.ExceptionClass := mItem.GetValue<string>('exception', '');
    if mPoint.Line >= 0 then
    begin
      Result.Points := Result.Points + [mPoint];
    end;
  end;
end;

function TAtlasExitPointSet.Found: Boolean;
begin
  Result := (Query <> TAtlasExitPointQuery.None) and (Length(Points) > 0);
end;

function TAtlasExitPointSet.PointsAt(ALine: Integer): TArray<TAtlasExitPoint>;
var
  mPoint: TAtlasExitPoint;
begin
  Result := nil;
  for mPoint in Points do
  begin
    if mPoint.Line = ALine then
    begin
      Result := Result + [mPoint];
    end;
  end;
end;

function TAtlasExitPointSet.IndexAt(ALine, ACharacter: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Points) do
  begin
    if Points[mIndex].Contains(ALine, ACharacter) then
    begin
      Exit(mIndex);
    end;
  end;
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
  mIndex, mCurrent: Integer;
begin
  Result := Length(Points) > 0;
  if not Result then
  begin
    Exit;
  end;
  // Auf einer Stelle zählt ihr Anfang, damit der Sprung nicht auf derselben Stelle landet.
  mCurrent := IndexAt(ALine, ACharacter);
  if mCurrent >= 0 then
  begin
    ACharacter := Points[mCurrent].Character;
  end;
  if ABackward then
  begin
    APoint := Points[High(Points)];
    for mIndex := High(Points) downto 0 do
    begin
      if Before(Points[mIndex].Line, Points[mIndex].Character, ALine, ACharacter) then
      begin
        APoint := Points[mIndex];
        Exit;
      end;
    end;
  end
  else
  begin
    APoint := Points[0];
    for mIndex := 0 to High(Points) do
    begin
      if Before(ALine, ACharacter, Points[mIndex].Line, Points[mIndex].Character) then
      begin
        APoint := Points[mIndex];
        Exit;
      end;
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
  begin
    Dec(AStart);
  end;
  Result := (AStart >= 0) and (AStart < Length(ALine)) and TTextChars.IsIdentChar(ALine[AStart + 1]);
  if not Result then
  begin
    Exit;
  end;
  while (AStart > 0) and TTextChars.IsIdentChar(ALine[AStart]) do
  begin
    Dec(AStart);
  end;
  AStop := AStart;
  while (AStop < Length(ALine)) and TTextChars.IsIdentChar(ALine[AStop + 1]) do
  begin
    Inc(AStop);
  end;
end;

/// <summary>AWord (klein) ist ein Schlüsselwort, das die Austrittspunkte zeigt.</summary>
function IsTriggerWord(const AWord: string): Boolean;
var
  mHead: string;
begin
  Result := False;
  for mHead in cTriggerWords do
  begin
    Result := Result or (AWord = mHead);
  end;
end;

/// <summary>Vor dem Wort steht (class) procedure, function … und sonst nur Namen mit Punkten.</summary>
function IsRoutineHead(const ABefore: string): Boolean;
var
  mHead, mWord: string;
  mIndex: Integer;
begin
  mHead := LowerCase(Trim(ABefore));
  Result := True;
  for mIndex := 1 to Length(mHead) do
  begin
    Result := Result and (TTextChars.IsIdentChar(mHead[mIndex]) or CharInSet(mHead[mIndex], ['.', ' ', '<', '>', ',']));
  end;
  if Result then
  begin
    if mHead.StartsWith('class ') then
    begin
      mHead := TrimLeft(Copy(mHead, 7, MaxInt));
    end;
    Result := False;
    for mWord in cHeaderWords do
    begin
      Result := Result or (mHead = mWord) or mHead.StartsWith(mWord + ' ');
    end;
  end;
end;

class function TAtlasExitPoints.Triggers(const ALine: string; ACharacter: Integer): Boolean;
var
  mStart, mStop: Integer;
begin
  Result := WordAt(ALine, ACharacter, mStart, mStop);
  // Schlüsselwort, Funktionsname als Ziel einer Zuweisung oder Name im Routinenkopf.
  Result := Result and (IsTriggerWord(LowerCase(Copy(ALine, mStart + 1, mStop - mStart))) or
    TrimLeft(Copy(ALine, mStop + 1, MaxInt)).StartsWith(':=') or IsRoutineHead(Copy(ALine, 1, mStart)));
end;

class function TAtlasExitPoints.BadgeText(const ASet: TAtlasExitPointSet; const AOne, AMany,
  AMissing: string): string;
begin
  if ASet.Exits = 1 then
  begin
    Result := AOne;
  end
  else
  begin
    Result := Format(AMany, [ASet.Exits]);
  end;
  if ASet.ResultMissing then
  begin
    Result := Result + ' ' + #$00B7 + ' ' + AMissing;
  end;
end;

end.
