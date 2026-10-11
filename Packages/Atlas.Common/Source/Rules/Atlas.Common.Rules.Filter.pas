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
  Pattern: string;
  UnitName: string;
begin
  if Length(Units) = 0 then
    Exit(True);
  UnitName := ChangeFileExt(ExtractFileName(StringReplace(APath, '/', '\', [rfReplaceAll])), '');
  for Pattern in Units do
    if SameText(Pattern, UnitName) or MatchesGlob(Pattern, APath) then
      Exit(True);
  Result := False;
end;

function TFindingFilter.AcceptsFinding(const AFinding: TRuleFinding): Boolean;
var
  Id: string;
begin
  if (Ord(MinSeverity) > Ord(TRuleSeverity.Off)) and (Ord(AFinding.Severity) < Ord(MinSeverity)) then
    Exit(False);
  if Length(Rules) = 0 then
    Exit(True);
  for Id in Rules do
    if SameText(Id, AFinding.RuleId) then
      Exit(True);
  Result := False;
end;

function TFindingFilter.Apply(const AFindings: TArray<TRuleFinding>): TArray<TRuleFinding>;
var
  Finding: TRuleFinding;
begin
  Result := nil;
  for Finding in AFindings do
    if AcceptsFinding(Finding) then
      Result := Result + [Finding];
end;

class function TFindingFilter.SplitList(const AText: string): TArray<string>;
var
  I, Start: Integer;
  Part: string;
begin
  Result := nil;
  Start := 1;
  for I := 1 to Length(AText) + 1 do
    if (I > Length(AText)) or (AText[I] = ',') then
    begin
      Part := Trim(Copy(AText, Start, I - Start));
      if Part <> '' then
        Result := Result + [Part];
      Start := I + 1;
    end;
end;

end.
