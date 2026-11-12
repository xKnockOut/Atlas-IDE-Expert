unit Atlas.Common.Pascal.PureRoutines;

// Standardroutinen ohne Seiteneffekte (#1109): Sie ändern weder Parameter noch Zustand und greifen auf kein
// Objekt zu. Eine gemeinsame Liste für Inline-Variable (Editing.Inlining), doppelte Bedingungen
// (duplicate-condition), IfThen mit Aufrufen in den Zweigen (ifthen-side-effect) und verworfene Ergebnisse
// (ignored-result, #624); vorher führte jede Stelle eine eigene, unvollständige Liste. Die Namen stehen je
// RTL-Unit, damit der Regelkatalog sie so zeigen und ignored-result eine eigene Routine gleichen Namens von der
// RTL unterscheiden kann. Keine Routine mit var- oder out-Parameter und keine, die bei falscher Eingabe
// absichtlich eine Exception wirft (StrToInt als Prüfung), steht in der Liste.

interface

type
  /// <summary>Namen einer RTL-Unit, mit Komma getrennt.</summary>
  TPureRoutineGroup = record
    UnitName: string;
    Names: string;
  end;

  TPureRoutines = record
  public
    /// <summary>Alle Namen; Klassenmethoden als "string.Join" bzw. "TPath.Combine".</summary>
    class function Names: TArray<string>; static;
    /// <summary>Die Namen je Unit in der Reihenfolge der Liste (Regelkatalog).</summary>
    class function Groups: TArray<TPureRoutineGroup>; static;
    /// <summary>Ist AName (ohne Groß-/Kleinschreibung) eine Standardroutine ohne Seiteneffekte?</summary>
    class function IsPure(const AName: string): Boolean; static;
    /// <summary>Unit der Standardroutine AName ("System.SysUtils"), '' wenn sie nicht in der Liste steht.
    /// </summary>
    class function UnitOf(const AName: string): string; static;
    /// <summary>Gehört die Unit AUnitName zur RTL (System, System.*, auch ohne Namensraum wie SysUtils)?</summary>
    class function IsRtlUnit(const AUnitName: string): Boolean; static;
    /// <summary>Methode von TStringHelper ohne Seiteneffekte (S.Trim, S.Replace(…)); sie liefert ein neues
    /// Ergebnis und lässt den String unverändert.</summary>
    class function IsPureStringMember(const AName: string): Boolean; static;
    /// <summary>Alle Methoden aus IsPureStringMember.</summary>
    class function StringMembers: TArray<string>; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections;

const
  cGroups: array[0..4] of TPureRoutineGroup = (
    (UnitName: 'System'; Names: 'Abs,Assigned,Chr,Concat,Copy,Frac,High,Int,Length,Low,Odd,Ord,Pos,Pred,Round,' +
      'SizeOf,Sqr,Sqrt,StringOfChar,Succ,Trunc,UpCase'),
    (UnitName: 'System.SysUtils'; Names: 'IntToStr,IntToHex,FloatToStr,CurrToStr,BoolToStr,Format,FormatFloat,' +
      'QuotedStr,AnsiQuotedStr,Trim,TrimLeft,TrimRight,LowerCase,UpperCase,AnsiLowerCase,AnsiUpperCase,' +
      'StringReplace,SameText,SameStr,CompareText,CompareStr,AnsiSameText,AnsiSameStr,AnsiCompareText,' +
      'AnsiCompareStr,AnsiPos,StrToIntDef,StrToInt64Def,StrToFloatDef,StrToBoolDef,ExtractFileName,ExtractFileExt,' +
      'ExtractFilePath,ExtractFileDir,ExtractFileDrive,ChangeFileExt,ChangeFilePath,IncludeTrailingPathDelimiter,' +
      'ExcludeTrailingPathDelimiter,IncludeTrailingBackslash,ExcludeTrailingBackslash,AdjustLineBreaks,' +
      'IsDelimiter,LastDelimiter,string.Join,string.Create,string.Format,' +
      'string.IsNullOrEmpty,string.IsNullOrWhiteSpace,string.Compare,string.CompareOrdinal,string.CompareText,' +
      'string.LowerCase,string.UpperCase,string.EndsText'),
    (UnitName: 'System.StrUtils'; Names: 'PosEx,ContainsText,ContainsStr,StartsText,StartsStr,EndsText,EndsStr,' +
      'MatchText,MatchStr,IndexText,IndexStr,LeftStr,RightStr,MidStr,ReplaceStr,ReplaceText,AnsiReplaceStr,' +
      'AnsiReplaceText,AnsiContainsText,AnsiStartsText,AnsiEndsText,DupeString,ReverseString,SplitString,IfThen'),
    (UnitName: 'System.Math'; Names: 'Max,Min,Ceil,Floor,Power,IntPower,Sign,EnsureRange,InRange,SameValue,' +
      'IsZero,RoundTo,SimpleRoundTo,Log10,Log2'),
    (UnitName: 'System.IOUtils'; Names: 'TPath.Combine,TPath.GetFileName,TPath.GetFileNameWithoutExtension,' +
      'TPath.GetExtension,TPath.GetDirectoryName,TPath.ChangeExtension'));
  // Methoden von TStringHelper, die einen neuen Wert liefern. ToInteger, ToDouble usw. fehlen absichtlich: Sie
  // werfen bei falscher Eingabe und stehen daher manchmal allein als Prüfung.
  cStringMembers: array[0..32] of string = ('Trim', 'TrimLeft', 'TrimRight', 'TrimStart', 'TrimEnd', 'ToUpper',
    'ToLower', 'ToUpperInvariant', 'ToLowerInvariant', 'Replace', 'Substring', 'PadLeft', 'PadRight', 'Insert',
    'Remove', 'QuotedString', 'DeQuotedString', 'Contains', 'StartsWith', 'EndsWith', 'IndexOf', 'IndexOfAny',
    'LastIndexOf', 'LastIndexOfAny', 'IsEmpty', 'Split', 'ToCharArray', 'Equals', 'CompareTo', 'CountChar',
    'IsDelimiter', 'LastDelimiter', 'GetHashCode');
  // Units der RTL ohne Namensraum (alte Schreibweise in uses).
  cUnscopedRtlUnits: array[0..3] of string = ('SysUtils', 'StrUtils', 'Math', 'IOUtils');

var
  // Kleingeschriebener Name → Unit; nur in der Initialisierung beschrieben, danach nur gelesen.
  GUnits: TDictionary<string, string>;
  GNames: TArray<string>;

procedure BuildIndex;
var
  mGroup: TPureRoutineGroup;
  mName: string;
begin
  GUnits := TDictionary<string, string>.Create;
  GNames := nil;
  for mGroup in cGroups do
  begin
    for mName in mGroup.Names.Split([',']) do
    begin
      GNames := GNames + [mName];
      GUnits.AddOrSetValue(LowerCase(mName), mGroup.UnitName);
    end;
  end;
end;

class function TPureRoutines.Names: TArray<string>;
begin
  Result := Copy(GNames);
end;

class function TPureRoutines.Groups: TArray<TPureRoutineGroup>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(cGroups));
  for mIndex := 0 to High(cGroups) do
  begin
    Result[mIndex] := cGroups[mIndex];
  end;
end;

class function TPureRoutines.IsPure(const AName: string): Boolean;
begin
  Result := (AName <> '') and GUnits.ContainsKey(LowerCase(AName));
end;

class function TPureRoutines.UnitOf(const AName: string): string;
begin
  if not GUnits.TryGetValue(LowerCase(AName), Result) then
  begin
    Result := '';
  end;
end;

class function TPureRoutines.IsRtlUnit(const AUnitName: string): Boolean;
begin
  Result := SameText(AUnitName, 'System') or StartsText('System.', AUnitName) or
    MatchText(AUnitName, cUnscopedRtlUnits);
end;

class function TPureRoutines.IsPureStringMember(const AName: string): Boolean;
begin
  Result := MatchText(AName, cStringMembers);
end;

class function TPureRoutines.StringMembers: TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(cStringMembers));
  for mIndex := 0 to High(cStringMembers) do
  begin
    Result[mIndex] := cStringMembers[mIndex];
  end;
end;

initialization
  BuildIndex;

finalization
  GUnits.Free;
  GNames := nil;

end.
