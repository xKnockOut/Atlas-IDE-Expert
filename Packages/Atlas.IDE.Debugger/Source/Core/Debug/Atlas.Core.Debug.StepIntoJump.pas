unit Atlas.Core.Debug.StepIntoJump;

// Ablauf von „Gezielt hineinspringen“ (#836) nach der Liste, ohne IDE prüfbar (#1967): was nach der Antwort des
// Servers geschieht, welche Taste die Liste bedient, welche Haltepunkte der Sprung braucht und was ein Halt danach
// bedeutet. Atlas.IDE.Debug.StepInto fragt Debugger, Server und Tastatur.

interface

uses
  Atlas.Core.Debug.StepInto;

{$SCOPEDENUMS ON}

type
  /// <summary>Nach der Antwort: wie F7 (höchstens ein Aufruf), nichts wählbar (Meldung, dann wie F7), Liste.
  /// </summary>
  TAtlasStepOffer = (StepInto, Nothing, List);

  /// <summary>Taste in der offenen Liste; None: Die Liste kennt sie nicht und schließt.</summary>
  TAtlasStepKey = (None, Accept, Cancel, Up, Down, Digit);

  /// <summary>Halt nach dem Sprung: noch am Start (Run nicht angekommen), am Ziel, an der Folgeanweisung (nicht
  /// aufgerufen), anderswo angehalten, sonst (Exception, ohne Meldung).</summary>
  TAtlasStepArrival = (NotYet, AtTarget, NotCalled, Elsewhere, Other);

  /// <summary>Laufender Sprung auf ein gewähltes Ziel.</summary>
  TAtlasStepJump = record
    Running: Boolean;
    SeenRunning: Boolean;
    StartFile: string;
    StartLine: Integer;
    Caption: string;
    Target: TAtlasStepTarget;
    /// <summary>Folgeanweisung (ab 0) in der Datei des Starts; -1 ohne.</summary>
    FollowLine: Integer;
    /// <summary>Zweiter Haltepunkt auf der Folgeanweisung von AFileName nötig: Es gibt sie, und sie ist nicht
    /// selbst das Ziel.</summary>
    function NeedsFollowBreak(const AFileName: string): Boolean;
    /// <summary>Halt an AFileName/ALine; AStartFile: Datei der Liste, AStopped: gewöhnlicher Halt (nicht
    /// Exception).</summary>
    function Arrival(const AFileName: string; ALine: Integer; const AStartFile: string;
      AStopped: Boolean): TAtlasStepArrival;
  end;

  TAtlasStepIntoJump = class
  public const
    // Tasten wie in Winapi.Windows (VK_*), hier ohne Windows.
    cKeyReturn = $0D;
    cKeyEscape = $1B;
    cKeyUp = $26;
    cKeyDown = $28;
    cKeyNumpad0 = $60;
    cKeyNumpad1 = $61;
    cKeyNumpad9 = $69;
  public
    class function Offer(const ARows: TArray<TAtlasStepRow>): TAtlasStepOffer; static;
    /// <summary>Taste AKey (virtueller Code) in der Liste; bei Digit die Ziffer 1 bis 9 in ADigit.</summary>
    class function KeyOf(AKey: Word; out ADigit: Integer): TAtlasStepKey; static;
    /// <summary>Gewählte Zeile AIndex lässt sich anspringen.</summary>
    class function CanAccept(const ARows: TArray<TAtlasStepRow>; AIndex: Integer): Boolean; static;
    /// <summary>Wert von DCC_DebugDCUs: Haltepunkte in RTL, VCL und FMX greifen.</summary>
    class function DebugDcus(const AValue: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

function SamePlace(const AFileName: string; ALine: Integer; const AOtherFile: string; AOtherLine: Integer): Boolean;
begin
  Result := SameText(AFileName, AOtherFile) and (ALine = AOtherLine);
end;

{ TAtlasStepJump }

function TAtlasStepJump.NeedsFollowBreak(const AFileName: string): Boolean;
begin
  Result := (FollowLine >= 0) and not SamePlace(Target.FileName, Target.Line, AFileName, FollowLine);
end;

function TAtlasStepJump.Arrival(const AFileName: string; ALine: Integer; const AStartFile: string;
  AStopped: Boolean): TAtlasStepArrival;
begin
  if not SeenRunning and SamePlace(AFileName, ALine, StartFile, StartLine) then
  begin
    Result := TAtlasStepArrival.NotYet;
  end
  else if SamePlace(AFileName, ALine, Target.FileName, Target.Line) then
  begin
    Result := TAtlasStepArrival.AtTarget;
  end
  else if SamePlace(AFileName, ALine, AStartFile, FollowLine) then
  begin
    Result := TAtlasStepArrival.NotCalled;
  end
  else if AStopped then
  begin
    Result := TAtlasStepArrival.Elsewhere;
  end
  else
  begin
    Result := TAtlasStepArrival.Other;
  end;
end;

{ TAtlasStepIntoJump }

class function TAtlasStepIntoJump.Offer(const ARows: TArray<TAtlasStepRow>): TAtlasStepOffer;
begin
  if TAtlasStepInto.ActsLikeStepInto(ARows) then
  begin
    Result := TAtlasStepOffer.StepInto;
  end
  else if TAtlasStepInto.NextAvailable(ARows, 0, 1) < 0 then
  begin
    Result := TAtlasStepOffer.Nothing;
  end
  else
  begin
    Result := TAtlasStepOffer.List;
  end;
end;

class function TAtlasStepIntoJump.KeyOf(AKey: Word; out ADigit: Integer): TAtlasStepKey;
begin
  ADigit := 0;
  case AKey of
    cKeyReturn:
      Result := TAtlasStepKey.Accept;
    cKeyEscape:
      Result := TAtlasStepKey.Cancel;
    cKeyUp:
      Result := TAtlasStepKey.Up;
    cKeyDown:
      Result := TAtlasStepKey.Down;
    Ord('1')..Ord('9'):
      begin
        ADigit := AKey - Ord('0');
        Result := TAtlasStepKey.Digit;
      end;
    cKeyNumpad1..cKeyNumpad9:
      begin
        ADigit := AKey - cKeyNumpad0;
        Result := TAtlasStepKey.Digit;
      end;
  else
    Result := TAtlasStepKey.None;
  end;
end;

class function TAtlasStepIntoJump.CanAccept(const ARows: TArray<TAtlasStepRow>; AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(ARows)) and ARows[AIndex].Available;
end;

class function TAtlasStepIntoJump.DebugDcus(const AValue: string): Boolean;
begin
  Result := SameText(Trim(AValue), 'true');
end;

end.
