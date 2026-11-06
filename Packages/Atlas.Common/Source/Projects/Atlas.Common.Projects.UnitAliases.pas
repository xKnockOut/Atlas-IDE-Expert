unit Atlas.Common.Projects.UnitAliases;

// Unit-Aliase wie beim Compiler (Projektoptionen „Unit-Aliase“, dcc -A,
// DCC_UnitAlias): Ein Name im uses wie WinTypes steht für eine andere Unit
// (Winapi.Windows). Delphi gibt die Aliase der alten Units aus Delphi 1 vor
// (WinTypes, WinProcs → Winapi.Windows; DbiTypes, DbiProcs, DbiErrs → BDE),
// auch wenn die .dproj keine eigenen nennt. Eigene Aliase der .dproj gelten
// zusätzlich und haben bei gleichem Namen Vorrang.
//
// Gebraucht von der Unit-Suche (uses-unit-not-found), dem Nachladen über die
// Suchpfade und dem Index, damit ein Alias überall auf dieselbe Unit führt.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Projects.Contract;

type
  /// <summary>Ein Unit-Alias: Name im uses → Unit, die der Compiler stattdessen lädt.</summary>
  TUnitAlias = TPair<string, string>;

  TUnitAliases = record
  public const
    /// <summary>Eigenschaft der .dproj mit den Aliasen des Projekts (Name=Unit;…).</summary>
    cProperty = 'DCC_UnitAlias';
  public
    /// <summary>Aliase, die Delphi ohne Angabe im Projekt vorgibt.</summary>
    class function Defaults: TArray<TUnitAlias>; static;
    /// <summary>Liest "Name=Unit;Name=Unit"; Einträge ohne "=", mit leerem Teil oder offenem Makro "$(…)"
    /// fallen weg.</summary>
    class function Parse(const AValue: string): TArray<TUnitAlias>; static;
    /// <summary>AFirst und danach die Einträge aus ASecond, deren Name in AFirst fehlt.</summary>
    class function Merge(const AFirst, ASecond: TArray<TUnitAlias>): TArray<TUnitAlias>; static;
    /// <summary>Aliase des Projekts (DCC_UnitAlias) vor den Vorgaben von Delphi.</summary>
    class function OfProject(const AProject: TProjectInfo): TArray<TUnitAlias>; static;
    /// <summary>Unit hinter dem Alias AName (ohne Groß-/Kleinschreibung); False, wenn AName kein Alias ist.
    /// </summary>
    class function Target(const AAliases: TArray<TUnitAlias>; const AName: string; out AUnit: string): Boolean;
      static;
  end;

implementation

class function TUnitAliases.Defaults: TArray<TUnitAlias>;
begin
  Result := Parse('WinTypes=Winapi.Windows;WinProcs=Winapi.Windows;DbiTypes=BDE;DbiProcs=BDE;DbiErrs=BDE');
end;

class function TUnitAliases.Parse(const AValue: string): TArray<TUnitAlias>;
var
  mEntry, mName, mUnit: string;
  mPosition: Integer;
begin
  Result := nil;
  for mEntry in AValue.Split([';']) do
  begin
    mPosition := Pos('=', mEntry);
    if (mPosition = 0) or (Pos('$(', mEntry) > 0) then
    begin
      Continue;
    end;
    mName := Trim(Copy(mEntry, 1, mPosition - 1));
    mUnit := Trim(Copy(mEntry, mPosition + 1, MaxInt));
    if (mName <> '') and (mUnit <> '') then
    begin
      Result := Result + [TUnitAlias.Create(mName, mUnit)];
    end;
  end;
end;

class function TUnitAliases.Merge(const AFirst, ASecond: TArray<TUnitAlias>): TArray<TUnitAlias>;
var
  mAlias: TUnitAlias;
  mKnown: string;
begin
  Result := AFirst;
  for mAlias in ASecond do
  begin
    if not Target(Result, mAlias.Key, mKnown) then
    begin
      Result := Result + [mAlias];
    end;
  end;
end;

class function TUnitAliases.OfProject(const AProject: TProjectInfo): TArray<TUnitAlias>;
var
  mProperty: TPair<string, string>;
  mOwn: TArray<TUnitAlias>;
begin
  mOwn := nil;
  for mProperty in AProject.Properties do
  begin
    if SameText(mProperty.Key, cProperty) then
    begin
      mOwn := Parse(mProperty.Value);
    end;
  end;
  Result := Merge(mOwn, Defaults);
end;

class function TUnitAliases.Target(const AAliases: TArray<TUnitAlias>; const AName: string;
  out AUnit: string): Boolean;
var
  mAlias: TUnitAlias;
begin
  AUnit := '';
  for mAlias in AAliases do
  begin
    if SameText(mAlias.Key, AName) then
    begin
      AUnit := mAlias.Value;
      Exit(True);
    end;
  end;
  Result := False;
end;

end.
