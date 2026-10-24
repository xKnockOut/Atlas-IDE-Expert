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
  UncountedWords: array[0..34] of string = (
    'abstract', 'assembler', 'cdecl', 'deprecated', 'dispid', 'dynamic', 'experimental',
    'export', 'external', 'far', 'final', 'forward', 'inline', 'library', 'local',
    'near', 'noreturn', 'overload', 'override', 'pascal', 'platform',
    'register', 'reintroduce', 'safecall', 'static', 'stdcall', 'unsafe', 'varargs',
    'virtual', 'winapi', 'delayed', 'sealed', 'nodefault', 'self', 'result');

{ TIndexUsages }

class function TIndexUsages.Has(const AUsages: TArray<TIndexUsage>; const AName: string): Boolean;
var
  Low, High_, Middle, Order: Integer;
  Key: string;
begin
  // Sortiert nach UpperCase(Name), ordinal (TIndexExtractor.CollectUsages).
  Key := UpperCase(AName);
  Low := 0;
  High_ := High(AUsages);
  while Low <= High_ do
  begin
    Middle := (Low + High_) div 2;
    Order := CompareStr(UpperCase(AUsages[Middle].Name), Key);
    if Order = 0 then
      Exit(True);
    if Order < 0 then
      Low := Middle + 1
    else
      High_ := Middle - 1;
  end;
  Result := False;
end;

class function TIndexUsages.Counted(const AName: string): Boolean;
begin
  Result := IndexText(AName, UncountedWords) < 0;
end;

class function TIndexUsages.Lookup(const AUnit: TUnitIndex; const AName: string): TIndexUsageAnswer;
begin
  if not AUnit.UsagesIndexed or AUnit.UsagesOffloaded or (AUnit.Includes <> nil) or not Counted(AName) then
    Exit(TIndexUsageAnswer.Unknown);
  if Has(AUnit.Usages, AName) then
    Result := TIndexUsageAnswer.Present
  else
    Result := TIndexUsageAnswer.Absent;
end;

class function TIndexUsages.Lookup(const AIndex: ISymbolIndex; const AFileName, AName: string): TIndexUsageAnswer;
var
  Indexed: TUnitIndex;
begin
  if (AIndex = nil) or not AIndex.FindFile(AFileName, Indexed) then
    Exit(TIndexUsageAnswer.Unknown);
  Result := Lookup(Indexed, AName);
end;

end.
