unit Atlas.IDE.Problems.RuleActions;

// Regel-Aktionen am Befund (#909, #1755) für Base: „Regel einstellen…“, „Für
// diese Zeile unterdrücken“ und „Regel abschalten“ setzt das Modul Prüfregeln
// über IAtlasRuleActions um (Atlas.IDE.Contracts.Rules). Fenster
// „Atlas-Prüfung“, Befund-Hover, Statusleiste und Serverfenster rufen nur diese
// Unit; sie fragt bei jedem Aufruf die laufenden Module (Regel 3: das Modul
// kann inzwischen fort sein). Ohne Modul geschieht nichts, Available ist dann
// False und die Einträge fehlen. Nur im Hauptthread verwenden.

interface

uses
  Atlas.Core.Problems.Contract,
  Atlas.IDE.Contracts.Rules;

type
  TAtlasRuleActions = class
  public
    /// <summary>Ein laufendes Modul bietet die Aktionen an.</summary>
    class function Available: Boolean; static;
    class procedure Configure(const ARule: string); static;
    class procedure Suppress(const APlace: TAtlasRuleFindingPlace); static;
    class procedure Disable(const ARule: string); static;
    /// <summary>Ort des Befunds AProblem in AFileName ('' = oberer Editor).</summary>
    class function Place(const AFileName: string; const AProblem: TAtlasProblem): TAtlasRuleFindingPlace; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Contributions;

/// <summary>Aktionen des ersten laufenden Moduls; False ohne.</summary>
function Find(out AActions: IAtlasRuleActions): Boolean;
var
  mItem: IInterface;
begin
  AActions := nil;
  for mItem in TAtlasModuleContributions.Active(AtlasModuleRegistry, IAtlasRuleActions) do
  begin
    if Supports(mItem, IAtlasRuleActions, AActions) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasRuleActions.Available: Boolean;
var
  mActions: IAtlasRuleActions;
begin
  Result := Find(mActions);
end;

class procedure TAtlasRuleActions.Configure(const ARule: string);
var
  mActions: IAtlasRuleActions;
begin
  if Find(mActions) then
  begin
    mActions.Configure(ARule);
  end;
end;

class procedure TAtlasRuleActions.Suppress(const APlace: TAtlasRuleFindingPlace);
var
  mActions: IAtlasRuleActions;
begin
  if Find(mActions) then
  begin
    mActions.Suppress(APlace);
  end;
end;

class procedure TAtlasRuleActions.Disable(const ARule: string);
var
  mActions: IAtlasRuleActions;
begin
  if Find(mActions) then
  begin
    mActions.Disable(ARule);
  end;
end;

class function TAtlasRuleActions.Place(const AFileName: string; const AProblem: TAtlasProblem):
  TAtlasRuleFindingPlace;
begin
  Result := Default(TAtlasRuleFindingPlace);
  Result.FileName := AFileName;
  Result.Rule := AProblem.Code;
  Result.StartLine := AProblem.StartLine;
  Result.StartCharacter := AProblem.StartCharacter;
  Result.EndLine := AProblem.EndLine;
  Result.EndCharacter := AProblem.EndCharacter;
end;

end.
