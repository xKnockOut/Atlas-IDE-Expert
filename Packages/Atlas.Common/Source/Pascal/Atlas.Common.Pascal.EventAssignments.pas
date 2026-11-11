unit Atlas.Common.Pascal.EventAssignments;

// Methoden, die der Code einem Ereignis zuweist: "OnClose := FormClose;", "FEvents.OnEditorPaintLine :=
// PaintLine;", "Timer.OnTimer := Later.Tick;". Solche Methoden brauchen ein Objekt (method-without-self) und
// behalten die Parameternamen ihres Ereignistyps (naming-prefix), wie die Ereignisse der Formulardatei. Erkannt
// wird eine Zuweisung an eine Property OnXyz, rechts eine Kette von Namen ohne Aufruf.

interface

uses
  Atlas.Common.Pascal.Contract;

type
  TEventAssignments = record
  public
    /// <summary>Heißt AName wie eine Ereignis-Property (On + Großbuchstabe: OnClose, OnTimer)?</summary>
    class function IsEventName(const AName: string): Boolean; static;
    /// <summary>Namen der Methoden (letztes Glied rechts, ohne Objekt davor), die ATokens einer Property OnXyz
    /// zuweisen; jeder Name einmal.</summary>
    class function Names(const ATokens: TArray<TPascalToken>): TArray<string>; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.TokenCursor;

/// <summary>Index hinter der schließenden Klammer zur "(" an AIndex; Length(ATokens) ohne.</summary>
function AfterParens(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
var
  mDepth: Integer;
begin
  mDepth := 0;
  Result := AIndex;
  while Result <= High(ATokens) do
  begin
    if ATokens[Result].IsSymbol('(') then
    begin
      Inc(mDepth);
    end
    else if ATokens[Result].IsSymbol(')') then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit(NextCode(ATokens, Result + 1));
      end;
    end;
    Inc(Result);
  end;
end;

/// <summary>Rechte Seite ab AIndex: @? Name(.Name)* und danach ";", end oder else; AName = letztes Glied. Ein Glied
/// darf eine Typumwandlung sein, wenn ein Punkt folgt (TStopTicker(FTicker).Tick).</summary>
function MethodReference(const ATokens: TArray<TPascalToken>; AIndex: Integer; out AName: string): Boolean;
var
  mIndex: Integer;
begin
  AName := '';
  mIndex := AIndex;
  if (mIndex <= High(ATokens)) and ATokens[mIndex].IsSymbol('@') then
  begin
    mIndex := NextCode(ATokens, mIndex + 1);
  end;
  while (mIndex <= High(ATokens)) and (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) do
  begin
    AName := ATokens[mIndex].Text;
    mIndex := NextCode(ATokens, mIndex + 1);
    if (mIndex <= High(ATokens)) and ATokens[mIndex].IsSymbol('(') then
    begin
      // Typumwandlung nur mit folgendem Glied; Name(…) am Ende wäre ein Aufruf.
      mIndex := AfterParens(ATokens, mIndex);
      if (mIndex > High(ATokens)) or not ATokens[mIndex].IsSymbol('.') then
      begin
        AName := '';
        Break;
      end;
    end;
    if (mIndex > High(ATokens)) or not ATokens[mIndex].IsSymbol('.') then
    begin
      Break;
    end;
    mIndex := NextCode(ATokens, mIndex + 1);
  end;
  Result := (AName <> '') and ((mIndex > High(ATokens)) or ATokens[mIndex].IsSymbol(';') or
    ATokens[mIndex].IsKeyword('end') or ATokens[mIndex].IsKeyword('else'));
end;

class function TEventAssignments.IsEventName(const AName: string): Boolean;
begin
  Result := (Length(AName) > 2) and StartsText('On', AName) and CharInSet(AName[3], ['A'..'Z']);
end;

class function TEventAssignments.Names(const ATokens: TArray<TPascalToken>): TArray<string>;
var
  mIndex, mLeft: Integer;
  mName: string;
begin
  Result := nil;
  for mIndex := 0 to High(ATokens) do
  begin
    if not ATokens[mIndex].IsSymbol(':=') then
    begin
      Continue;
    end;
    mLeft := PreviousCode(ATokens, mIndex);
    if (mLeft >= 0) and (ATokens[mLeft].Kind = TPascalTokenKind.Identifier) and IsEventName(ATokens[mLeft].Text) and
      MethodReference(ATokens, NextCode(ATokens, mIndex + 1), mName) and (IndexText(mName, Result) < 0) then
    begin
      Result := Result + [mName];
    end;
  end;
end;

end.
