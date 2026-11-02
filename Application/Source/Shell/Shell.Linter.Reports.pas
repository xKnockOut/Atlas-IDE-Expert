unit Shell.Linter.Reports;

// Internals-Rolle Shell: Berichte des Linter-Modus statt der Treffer: Code-Metriken (#66) mit Grenzwerten aus
// atlas.json (Regeln metric-*, Option "max") und offene TODO-Einträge (#68) mit Marken aus atlas.json (Regel
// todo-comment, Option "keywords"), jeweils als Markdown oder JSON.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Metrics.Contract,
  Atlas.Common.Todos.Contract;

type
  TLinterReports = class
  public
    /// <summary>Pfad mit / als Trenner für Berichte.</summary>
    class function SlashPath(const APath: string): string; static;
    /// <summary>Metriken von AText unter ARelativePath.</summary>
    class function MetricsOf(const ARelativePath, AText: string): TFileMetrics; static;
    /// <summary>Offene TODO-Einträge von AText; erledigte (DONE) zählen nicht, ohne offenen Eintrag leer.</summary>
    class function TodosOf(const ARelativePath, AText: string; const ASettings: TServerSettings): TArray<TFileTodos>;
      static;
    /// <summary>Metrikbericht als JSON oder Markdown mit Titel ATitle.</summary>
    class function MetricsText(const AMetrics: TArray<TFileMetrics>; const ASettings: TServerSettings;
      AJson: Boolean; const ATitle: string): string; static;
    /// <summary>TODO-Übersicht als JSON oder Markdown mit Titel ATitle.</summary>
    class function TodosText(const ATodos: TArray<TFileTodos>; AJson: Boolean; const ATitle: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Metrics.Calculator,
  Atlas.Common.Metrics.Report,
  Atlas.Common.Todos.Scanner,
  Atlas.Common.Todos.Report,
  Atlas.Common.Rules.Builtin.Metrics,
  Atlas.Common.Rules.Builtin.Todos;

class function TLinterReports.SlashPath(const APath: string): string;
begin
  Result := StringReplace(APath, '\', '/', [rfReplaceAll]);
end;

class function TLinterReports.MetricsOf(const ARelativePath, AText: string): TFileMetrics;
begin
  Result := TFileMetrics.Create(SlashPath(ARelativePath), TMetricsCalculator.ForText(AText));
end;

class function TLinterReports.TodosOf(const ARelativePath, AText: string;
  const ASettings: TServerSettings): TArray<TFileTodos>;
begin
  Result := TTodoScanner.Filter([TFileTodos.Create(SlashPath(ARelativePath), TTodoScanner.ForText(AText,
    TTodoRules.Keywords(ASettings)))], TTodoFilter.Default);
end;

class function TLinterReports.MetricsText(const AMetrics: TArray<TFileMetrics>; const ASettings: TServerSettings;
  AJson: Boolean; const ATitle: string): string;
begin
  if AJson then
  begin
    Result := TMetricsReport.Json(AMetrics, TMetricRules.Limits(ASettings));
  end
  else
  begin
    Result := TMetricsReport.Markdown(AMetrics, TMetricRules.Limits(ASettings), ATitle);
  end;
end;

class function TLinterReports.TodosText(const ATodos: TArray<TFileTodos>; AJson: Boolean;
  const ATitle: string): string;
begin
  if AJson then
  begin
    Result := TTodoReport.Json(ATodos);
  end
  else
  begin
    Result := TTodoReport.Markdown(ATodos, ATitle);
  end;
end;

end.
