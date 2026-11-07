unit Atlas.Common.Rules.Filter;

// Filter des Kommandozeilen-Linters nach Regeln, Units und Mindest-Schweregrad.

interface

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract;

type
  TFindingFilter = record
    /// <summary>Regelkennungen; leer = alle.</summary>
    Rules: TArray<string>;
    /// <summary>Unit-Namen oder Glob-Muster für Pfade; leer = alle.</summary>
    Units: TArray<string>;
    /// <summary>Kleinster gemeldeter Schweregrad; Default = alle.</summary>
    MinSeverity: TRuleSeverity;
    function AcceptsFile(const APath: string): Boolean;
    function AcceptsFinding(const AFinding: TRuleFinding): Boolean;
    /// <summary>Nur die akzeptierten Treffer.</summary>
    function Apply(const AFindings: TArray<TRuleFinding>): TArray<TRuleFinding>;
    /// <summary>Kommagetrennte Liste ohne Leereinträge.</summary>
    class function SplitList(const AText: string): TArray<string>; static;
  end;

implementation

function TFindingFilter.AcceptsFile(const APath: string): Boolean;
var
  mPattern: string;
  mUnitName: string;
begin
  if Length(Units) = 0 then
  begin
    Exit(True);
  end;
  mUnitName := ChangeFileExt(ExtractFileName(StringReplace(APath, '/', '\', [rfReplaceAll])), '');
  for mPattern in Units do
  begin
    if SameText(mPattern, mUnitName) or MatchesGlob(mPattern, APath) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TFindingFilter.AcceptsFinding(const AFinding: TRuleFinding): Boolean;
var
  mId: string;
begin
  if (Ord(MinSeverity) > Ord(TRuleSeverity.Off)) and (Ord(AFinding.Severity) < Ord(MinSeverity)) then
  begin
    Exit(False);
  end;
  if Length(Rules) = 0 then
  begin
    Exit(True);
  end;
  for mId in Rules do
  begin
    if SameText(mId, AFinding.RuleId) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TFindingFilter.Apply(const AFindings: TArray<TRuleFinding>): TArray<TRuleFinding>;
var
  mFinding: TRuleFinding;
begin
  Result := nil;
  for mFinding in AFindings do
  begin
    if AcceptsFinding(mFinding) then
    begin
      Result := Result + [mFinding];
    end;
  end;
end;

class function TFindingFilter.SplitList(const AText: string): TArray<string>;
var
  I, mStart: Integer;
  mPart: string;
begin
  Result := nil;
  mStart := 1;
  for I := 1 to Length(AText) + 1 do
  begin
    if (I > Length(AText)) or (AText[I] = ',') then
    begin
      mPart := Trim(Copy(AText, mStart, I - mStart));
      if mPart <> '' then
      begin
        Result := Result + [mPart];
      end;
      mStart := I + 1;
    end;
  end;
end;

end.
