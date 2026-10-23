unit Atlas.Common.Pascal.PureRoutines;

// Standardroutinen ohne Seiteneffekte (#1109): Sie ändern weder Parameter noch Zustand und greifen auf kein
// Objekt zu. Eine gemeinsame Liste für Inline-Variable (Editing.Inlining), doppelte Bedingungen
// (duplicate-condition) und IfThen mit Aufrufen in den Zweigen (ifthen-side-effect); vorher führte jede Stelle
// eine eigene, unvollständige Liste.

interface

type
  TPureRoutines = record
  public
    /// <summary>Alle Namen; Klassenmethoden des String-Helfers als "string.Join".</summary>
    class function Names: TArray<string>; static;
    /// <summary>Ist AName (ohne Groß-/Kleinschreibung) eine Standardroutine ohne Seiteneffekte?</summary>
    class function IsPure(const AName: string): Boolean; static;
  end;

implementation

uses
  System.StrUtils;

const
  PureNames: array[0..62] of string = ('Abs', 'Assigned', 'Chr', 'Copy', 'Frac', 'High', 'Int', 'Length', 'Low',
    'Max', 'Min', 'Odd', 'Ord', 'Pred', 'Round', 'SizeOf', 'Sqr', 'Sqrt', 'Succ', 'Trunc',
    'IntToStr', 'IntToHex', 'FloatToStr', 'BoolToStr', 'Format', 'QuotedStr', 'Trim', 'TrimLeft', 'TrimRight',
    'LowerCase', 'UpperCase', 'AnsiLowerCase', 'AnsiUpperCase', 'StringReplace', 'StringOfChar', 'Pos', 'PosEx',
    'SameText', 'SameStr', 'CompareText', 'CompareStr', 'ContainsText', 'ContainsStr', 'StartsText', 'StartsStr',
    'EndsText', 'EndsStr', 'MatchText', 'MatchStr', 'LeftStr', 'RightStr', 'MidStr', 'ReplaceStr', 'ReplaceText',
    'ExtractFileName', 'ExtractFileExt', 'ExtractFilePath', 'ExtractFileDir', 'ChangeFileExt',
    'IncludeTrailingPathDelimiter', 'ExcludeTrailingPathDelimiter', 'string.Join', 'string.Create');

class function TPureRoutines.Names: TArray<string>;
var
  Index: Integer;
begin
  SetLength(Result, Length(PureNames));
  for Index := 0 to High(PureNames) do
    Result[Index] := PureNames[Index];
end;

class function TPureRoutines.IsPure(const AName: string): Boolean;
begin
  Result := MatchText(AName, PureNames);
end;

end.
