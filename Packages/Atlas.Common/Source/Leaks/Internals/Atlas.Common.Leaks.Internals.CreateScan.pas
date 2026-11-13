unit Atlas.Common.Leaks.Internals.CreateScan;

// Stellen „TKlasse.Create…“ einer Unit für die Leck-Kandidaten (#1875), mit
// dem, was der Text um die Stelle hergibt: Zuweisung an wen, Argument,
// Rückgabe, Owner im Konstruktor; dazu je Routine die freigegebenen Namen
// (X.Free, X.DisposeOf, X.Destroy, FreeAndNil(X)) und die als Result
// zurückgegebenen, über alle Destruktoren der Unit die freigegebenen Felder.
// Eine Routine reicht von ihrer Kopfzeile bis zur nächsten benannten Routine.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract;

type
{$SCOPEDENUMS ON}
  /// <summary>Wohin das neue Objekt geht.</summary>
  TLeakCreateUse = (Statement, Assigned, Argument, Returned);
{$SCOPEDENUMS OFF}

  TLeakCreateSite = record
    Position: TTextPosition;
    ClassName: string;
    Use: TLeakCreateUse;
    /// <summary>Ziel der Zuweisung ohne Qualifizierung; '' ohne.</summary>
    Target: string;
    /// <summary>Ziel ist ein Feld (Self.X oder Name nach dem Muster FName).</summary>
    TargetIsField: Boolean;
    /// <summary>Erstes Argument des Konstruktors nennt einen Owner (Self, AOwner, Application …).</summary>
    Owned: Boolean;
    Routine: string;
    /// <summary>Die Routine gibt Target frei.</summary>
    RoutineFrees: Boolean;
    /// <summary>Die Routine gibt Target als Result zurück.</summary>
    RoutineReturns: Boolean;
  end;

  TLeakCreateScan = record
  private type
    TRoutine = record
      First: Integer;
      Name: string;
      IsDestructor: Boolean;
      Freed: TArray<string>;
      Returned: TArray<string>;
    end;
  private
    FText: string;
    FTokens: TArray<TPascalToken>;
    FRoutines: TArray<TRoutine>;
    function TokenIs(AIndex: Integer; const AText: string): Boolean;
    function IsName(AIndex: Integer): Boolean;
    function LowerAt(AIndex: Integer): string;
    procedure ReadRoutines;
    procedure ReadRoutineBody(var ARoutine: TRoutine; ALast: Integer);
    function RoutineAt(AIndex: Integer): Integer;
    function FirstOfChain(AIndex: Integer): Integer;
    function ReadSite(AIndex: Integer; out ASite: TLeakCreateSite): Boolean;
    procedure ReadUse(AFirst: Integer; var ASite: TLeakCreateSite);
    function OwnerArgument(AIndex: Integer): Boolean;
  public
    Sites: TArray<TLeakCreateSite>;
    /// <summary>Namen, die ein Destruktor der Unit freigibt, in Kleinbuchstaben.</summary>
    FreedInDestructors: TArray<string>;
    class function Run(const AText: string; const AClassNames: TArray<string>): TLeakCreateScan; static;
    /// <summary>Gibt ein Destruktor der Unit AName frei?</summary>
    function DestructorFrees(const AName: string): Boolean;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.Lexer;

const
  cRoutineWords: array[0..3] of string = ('procedure', 'function', 'constructor', 'destructor');
  cFreeMethods: array[0..2] of string = ('free', 'disposeof', 'destroy');
  cOwnerNames: array[0..2] of string = ('self', 'application', 'owner');
  cCreatePrefix = 'create';
  cFieldPrefix = 'F';
  // Abstände in Token: „TKlasse . Create (“, „FreeAndNil ( Self . X )“, „Result := X ;“.
  cCreateLength = 3;
  cFreeAndNilDot = 3;
  cFreeAndNilField = 4;
  cResultEnd = 3;

function Contains(const AList: array of string; const AName: string): Boolean;
begin
  Result := IndexText(AName, AList) >= 0;
end;

{ TLeakCreateScan }

function TLeakCreateScan.TokenIs(AIndex: Integer; const AText: string): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex < Length(FTokens)) and SameText(FTokens[AIndex].Text, AText);
end;

function TLeakCreateScan.IsName(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex < Length(FTokens)) and (FTokens[AIndex].Kind = TPascalTokenKind.Identifier);
end;

function TLeakCreateScan.LowerAt(AIndex: Integer): string;
begin
  Result := '';
  if (AIndex >= 0) and (AIndex < Length(FTokens)) then
  begin
    Result := LowerCase(TPascalLexer.PlainName(FTokens[AIndex].Text));
  end;
end;

/// <summary>Benannte Routinen: Schlüsselwort, dann Name mit Punkten; anonyme Methoden zählen nicht.</summary>
procedure TLeakCreateScan.ReadRoutines;
var
  mIndex, mAt: Integer;
  mRoutine: TRoutine;
begin
  FRoutines := nil;
  for mIndex := 0 to High(FTokens) - 1 do
  begin
    if (FTokens[mIndex].Kind <> TPascalTokenKind.Keyword) or not Contains(cRoutineWords, LowerAt(mIndex)) or
      not IsName(mIndex + 1) then
    begin
      Continue;
    end;
    mRoutine := Default(TRoutine);
    mRoutine.First := mIndex;
    mRoutine.IsDestructor := LowerAt(mIndex) = 'destructor';
    mAt := mIndex + 1;
    while TokenIs(mAt + 1, '.') and IsName(mAt + 2) do
    begin
      Inc(mAt, 2);
    end;
    // Name samt Punkten aus dem Text, ohne Zeichenkette in der Schleife zu verlängern.
    mRoutine.Name := Copy(FText, FTokens[mIndex + 1].Offset + 1,
      FTokens[mAt].Offset + Length(FTokens[mAt].Text) - FTokens[mIndex + 1].Offset);
    FRoutines := FRoutines + [mRoutine];
  end;
  for mIndex := 0 to High(FRoutines) do
  begin
    if mIndex < High(FRoutines) then
    begin
      mAt := FRoutines[mIndex + 1].First - 1;
    end
    else
    begin
      mAt := High(FTokens);
    end;
    ReadRoutineBody(FRoutines[mIndex], mAt);
    if FRoutines[mIndex].IsDestructor then
    begin
      FreedInDestructors := FreedInDestructors + FRoutines[mIndex].Freed;
    end;
  end;
end;

/// <summary>Freigaben und Rückgaben zwischen Kopfzeile und ALast.</summary>
procedure TLeakCreateScan.ReadRoutineBody(var ARoutine: TRoutine; ALast: Integer);
var
  mIndex: Integer;
begin
  for mIndex := ARoutine.First to ALast do
  begin
    // X.Free, X.DisposeOf, X.Destroy
    if IsName(mIndex) and TokenIs(mIndex + 1, '.') and Contains(cFreeMethods, LowerAt(mIndex + 2)) then
    begin
      ARoutine.Freed := ARoutine.Freed + [LowerAt(mIndex)];
    end
    // FreeAndNil(X) bzw. FreeAndNil(Self.X)
    else if (LowerAt(mIndex) = 'freeandnil') and TokenIs(mIndex + 1, '(') then
    begin
      if TokenIs(mIndex + cFreeAndNilDot, '.') then
      begin
        ARoutine.Freed := ARoutine.Freed + [LowerAt(mIndex + cFreeAndNilField)];
      end
      else
      begin
        ARoutine.Freed := ARoutine.Freed + [LowerAt(mIndex + 2)];
      end;
    end
    // Result := X;
    else if (LowerAt(mIndex) = 'result') and TokenIs(mIndex + 1, ':=') and IsName(mIndex + 2) and
      (TokenIs(mIndex + cResultEnd, ';') or TokenIs(mIndex + cResultEnd, 'end')) then
    begin
      ARoutine.Returned := ARoutine.Returned + [LowerAt(mIndex + 2)];
    end;
  end;
end;

function TLeakCreateScan.RoutineAt(AIndex: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(FRoutines) do
  begin
    if FRoutines[mIndex].First < AIndex then
    begin
      Result := mIndex;
    end;
  end;
end;

/// <summary>Anfang einer Kette „Unit.TKlasse“ vor AIndex.</summary>
function TLeakCreateScan.FirstOfChain(AIndex: Integer): Integer;
begin
  Result := AIndex;
  while TokenIs(Result - 1, '.') and IsName(Result - 2) do
  begin
    Dec(Result, 2);
  end;
end;

function TLeakCreateScan.OwnerArgument(AIndex: Integer): Boolean;
var
  mName: string;
begin
  Result := TokenIs(AIndex, '(') and IsName(AIndex + 1);
  if Result then
  begin
    mName := LowerAt(AIndex + 1);
    Result := Contains(cOwnerNames, mName) or (Pos('owner', mName) > 0);
  end;
end;

/// <summary>Was vor der Stelle steht: Zuweisung, Argument, Exit(…) oder Anweisung.</summary>
procedure TLeakCreateScan.ReadUse(AFirst: Integer; var ASite: TLeakCreateSite);
var
  mTarget: Integer;
begin
  ASite.Use := TLeakCreateUse.Statement;
  if TokenIs(AFirst - 1, ':=') and IsName(AFirst - 2) then
  begin
    mTarget := AFirst - 2;
    ASite.Target := FTokens[mTarget].Text;
    ASite.TargetIsField := (TokenIs(mTarget - 1, '.') and TokenIs(mTarget - 2, 'self')) or
      ((Length(ASite.Target) > 1) and (ASite.Target[1] = cFieldPrefix) and CharInSet(ASite.Target[2], ['A'..'Z']));
    if SameText(ASite.Target, 'result') then
    begin
      ASite.Use := TLeakCreateUse.Returned;
    end
    else
    begin
      ASite.Use := TLeakCreateUse.Assigned;
    end;
  end
  else if TokenIs(AFirst - 1, '(') and TokenIs(AFirst - 2, 'exit') then
  begin
    ASite.Use := TLeakCreateUse.Returned;
  end
  else if TokenIs(AFirst - 1, '(') or TokenIs(AFirst - 1, ',') then
  begin
    ASite.Use := TLeakCreateUse.Argument;
  end;
end;

function TLeakCreateScan.ReadSite(AIndex: Integer; out ASite: TLeakCreateSite): Boolean;
var
  mFirst, mRoutine: Integer;
begin
  ASite := Default(TLeakCreateSite);
  mFirst := FirstOfChain(AIndex);
  // Kopfzeile „constructor TKlasse.Create“ und Exceptions („raise EFehler.Create“) sind keine Kandidaten.
  Result := not ((mFirst > 0) and (FTokens[mFirst - 1].Kind = TPascalTokenKind.Keyword) and
    (Contains(cRoutineWords, LowerAt(mFirst - 1)) or (LowerAt(mFirst - 1) = 'raise')));
  if not Result then
  begin
    Exit;
  end;
  ASite.Position := FTokens[AIndex].StartPos;
  ASite.ClassName := FTokens[AIndex].Text;
  ASite.Owned := OwnerArgument(AIndex + cCreateLength);
  ReadUse(mFirst, ASite);
  mRoutine := RoutineAt(AIndex);
  if mRoutine >= 0 then
  begin
    ASite.Routine := FRoutines[mRoutine].Name;
    ASite.RoutineFrees := Contains(FRoutines[mRoutine].Freed, ASite.Target);
    ASite.RoutineReturns := Contains(FRoutines[mRoutine].Returned, ASite.Target);
  end;
end;

function TLeakCreateScan.DestructorFrees(const AName: string): Boolean;
begin
  Result := Contains(FreedInDestructors, AName);
end;

class function TLeakCreateScan.Run(const AText: string; const AClassNames: TArray<string>): TLeakCreateScan;
var
  mAll: TArray<TPascalToken>;
  mToken: TPascalToken;
  mIndex, mCount: Integer;
  mSite: TLeakCreateSite;
begin
  Result := Default(TLeakCreateScan);
  Result.FText := AText;
  mAll := TPascalLexer.Tokenize(AText);
  SetLength(Result.FTokens, Length(mAll));
  mCount := 0;
  for mToken in mAll do
  begin
    if not (mToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      Result.FTokens[mCount] := mToken;
      Inc(mCount);
    end;
  end;
  SetLength(Result.FTokens, mCount);
  Result.ReadRoutines;
  for mIndex := 0 to mCount - cCreateLength do
  begin
    if Result.IsName(mIndex) and Contains(AClassNames, Result.FTokens[mIndex].Text) and
      Result.TokenIs(mIndex + 1, '.') and StartsText(cCreatePrefix, Result.LowerAt(mIndex + 2)) and
      Result.ReadSite(mIndex, mSite) then
    begin
      Result.Sites := Result.Sites + [mSite];
    end;
  end;
end;

end.
