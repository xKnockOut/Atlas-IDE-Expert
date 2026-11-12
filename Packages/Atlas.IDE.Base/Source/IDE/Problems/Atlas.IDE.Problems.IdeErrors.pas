unit Atlas.IDE.Problems.IdeErrors;

// Fehler der IDE (#1819, problems.ideErrors) für Base: Das Modul Prüfregeln
// liest Error Insight über die Open Tools API und stellt IAtlasIdeErrors
// bereit (Atlas.IDE.Contracts.Rules). Der Problem-Controller ruft nach jeder
// Prüfung einer Datei nur diese Unit; sie fragt bei jedem Aufruf die laufenden
// Module (Regel 3: das Modul kann inzwischen fort sein) und rechnet die Werte
// der IDE in Probleme um (Atlas.Core.Problems.IdeErrors). Ohne Modul gibt es
// keine Fehler der IDE. Nur im Hauptthread verwenden.

interface

uses
  Atlas.Core.Problems.Contract;

type
  TAtlasIdeErrorSource = class
  public
    /// <summary>Plugin und Probleme an und problems.ideErrors an (#1819).</summary>
    class function Enabled: Boolean; static;
    /// <summary>Fehler der IDE zu AFileName als Probleme mit Quelle "IDE"; False ohne Modul oder wenn die IDE die
    /// Datei nicht kennt (dann ist AProblems nil).</summary>
    class function Query(const AFileName: string; out AProblems: TArray<TAtlasProblem>): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Foundation.Settings,
  Atlas.Core.Modules.Contributions,
  Atlas.Core.Problems.IdeErrors,
  Atlas.IDE.Contracts.Rules;

/// <summary>Quelle des ersten laufenden Moduls; False ohne.</summary>
function Find(out ASource: IAtlasIdeErrors): Boolean;
var
  mItem: IInterface;
begin
  ASource := nil;
  for mItem in TAtlasModuleContributions.Active(AtlasModuleRegistry, IAtlasIdeErrors) do
  begin
    if Supports(mItem, IAtlasIdeErrors, ASource) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasIdeErrorSource.Enabled: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.Enabled and mSettings.Problems and mSettings.ProblemsIdeErrors;
end;

class function TAtlasIdeErrorSource.Query(const AFileName: string; out AProblems: TArray<TAtlasProblem>): Boolean;
var
  mSource: IAtlasIdeErrors;
  mErrors: TArray<TAtlasIdeError>;
begin
  AProblems := nil;
  Result := Find(mSource) and mSource.ErrorsOf(AFileName, mErrors);
  if Result then
  begin
    AProblems := TAtlasIdeErrors.ToProblems(mErrors);
  end;
end;

end.
