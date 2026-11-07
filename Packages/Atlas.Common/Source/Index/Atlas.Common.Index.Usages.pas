unit Atlas.Common.Index.Usages;

// Kommt ein Name in einer Projekt-Unit vor? Antwort aus den Verwendungen des
// Index (#492, index.usages), ohne die Datei zu lesen. Gemeinsam für die
// projektweiten Prüfregeln (TRuleProjectFiles.NameIn, #1102) und die
// Vorfilterung der Auswirkungsanalyse (#1120).
//
// Je Projekt-Unit liegen im Index alle Bezeichner außer Deklarationen,
// sortiert nach dem Namen in Großbuchstaben. Unknown heißt: Der Index kann es
// nicht sagen, der Aufrufer muss die Datei lesen. Das gilt, wenn die Unit nicht
// im Index steht, ihre Verwendungen fehlen oder ausgelagert sind, sie
// Include-Dateien hat (deren Bezeichner zählen nicht zur Unit) oder der Name
// ein Wort ist, das der Index nicht als Verwendung zählt (Direktiven, Self,
// Result). Deklarationen zählen nicht als Verwendung: Absent schließt nicht
// aus, dass der Name in der Datei deklariert wird.

interface

uses
  Atlas.Common.Index.Contract;

type
{$SCOPEDENUMS ON}
  TIndexUsageAnswer = (Present, Absent, Unknown);
{$SCOPEDENUMS OFF}

  TIndexUsages = class
  public
    /// <summary>Steht AName in AUsages (sortiert nach UpperCase(Name), ordinal)?</summary>
    class function Has(const AUsages: TArray<TIndexUsage>; const AName: string): Boolean; static;
    /// <summary>Zählt der Index AName überhaupt als Verwendung?</summary>
    class function Counted(const AName: string): Boolean; static;
    /// <summary>Antwort des Index für die Unit AUnit; Unknown, wenn er es nicht sagen kann.</summary>
    class function Lookup(const AUnit: TUnitIndex; const AName: string): TIndexUsageAnswer; overload; static;
    /// <summary>Wie oben für die Datei AFileName; Unknown ohne Index oder ohne die Unit darin.</summary>
    class function Lookup(const AIndex: ISymbolIndex; const AFileName, AName: string): TIndexUsageAnswer;
      overload; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

const
  // Wörter, die der Index nicht als Verwendung erfasst (Atlas.Common.Index.Extractor, CollectUsages):
  // Direktiven nach Routinenköpfen sowie Self und Result.
  cUncountedWords: array[0..34] of string = (
    'abstract', 'assembler', 'cdecl', 'deprecated', 'dispid', 'dynamic', 'experimental',
    'export', 'external', 'far', 'final', 'forward', 'inline', 'library', 'local',
    'near', 'noreturn', 'overload', 'override', 'pascal', 'platform',
    'register', 'reintroduce', 'safecall', 'static', 'stdcall', 'unsafe', 'varargs',
    'virtual', 'winapi', 'delayed', 'sealed', 'nodefault', 'self', 'result');

{ TIndexUsages }

class function TIndexUsages.Has(const AUsages: TArray<TIndexUsage>; const AName: string): Boolean;
var
  mLow, mHigh_, mMiddle, mOrder: Integer;
  mKey: string;
begin
  // Sortiert nach UpperCase(Name), ordinal (TIndexExtractor.CollectUsages).
  mKey := UpperCase(AName);
  mLow := 0;
  mHigh_ := High(AUsages);
  while mLow <= mHigh_ do
  begin
    mMiddle := (mLow + mHigh_) div 2;
    mOrder := CompareStr(UpperCase(AUsages[mMiddle].Name), mKey);
    if mOrder = 0 then
    begin
      Exit(True);
    end;
    if mOrder < 0 then
    begin
      mLow := mMiddle + 1;
    end
    else
    begin
      mHigh_ := mMiddle - 1;
    end;
  end;
  Result := False;
end;

class function TIndexUsages.Counted(const AName: string): Boolean;
begin
  Result := IndexText(AName, cUncountedWords) < 0;
end;

class function TIndexUsages.Lookup(const AUnit: TUnitIndex; const AName: string): TIndexUsageAnswer;
begin
  if not AUnit.UsagesIndexed or AUnit.UsagesOffloaded or (AUnit.Includes <> nil) or not Counted(AName) then
  begin
    Exit(TIndexUsageAnswer.Unknown);
  end;
  if Has(AUnit.Usages, AName) then
  begin
    Result := TIndexUsageAnswer.Present;
  end
  else
  begin
    Result := TIndexUsageAnswer.Absent;
  end;
end;

class function TIndexUsages.Lookup(const AIndex: ISymbolIndex; const AFileName, AName: string): TIndexUsageAnswer;
var
  mIndexed: TUnitIndex;
begin
  if (AIndex = nil) or not AIndex.FindFile(AFileName, mIndexed) then
  begin
    Exit(TIndexUsageAnswer.Unknown);
  end;
  Result := Lookup(mIndexed, AName);
end;

end.
