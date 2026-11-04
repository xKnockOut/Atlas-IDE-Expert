unit Atlas.Core.Settings.Plugin.Rules;

// Einstellungen des IDE-Plugins, Bereich Prüfregeln (problems.*) (#227, ADR 0017):
// Felder, Vorgaben, Grenzen, Lesen und Schreiben. TAtlasPluginSettings (Atlas.Core.Settings.Plugin)
// fasst die Bereiche zusammen und reicht die Felder als Eigenschaften durch.

interface

uses
  Atlas.Core.Settings.Plugin.Store;

type
  /// <summary>Plugin-Einstellungen: Prüfregeln und Problemliste.</summary>
  TAtlasPluginRulesSettings = record
    /// <summary>Fenster „Atlas-Prüfung“ (#909): verfügbar (aus = kein Menüeintrag, kein Fenster); nur mit Problems.
    /// </summary>
    ProblemsWindow: Boolean;
    /// <summary>Bereich des Fensters: 'file', 'project', 'group' (Vorgabe).</summary>
    ProblemsWindowScope: string;
    /// <summary>Gruppierung: 'none', 'file' (Vorgabe), 'rule', 'category'.</summary>
    ProblemsWindowGroupBy: string;
    /// <summary>Spalten mit Reihenfolge, Breite und Sichtbarkeit ("kind:70,-rule,…", TAtlasFindings.ParseColumns); '' =
    /// alle in der Vorgabe-Reihenfolge.</summary>
    ProblemsWindowColumns: string;
    /// <summary>Compilermeldungen (dcc) im Fenster mit anzeigen.</summary>
    ProblemsWindowCompiler: Boolean;
    /// <summary>Eintrag zur Cursorzeile im Fenster markieren.</summary>
    ProblemsWindowFollowCursor: Boolean;
    /// <summary>Offene Units zuerst (#1108): aktive Unit oben angepinnt, geöffnete darunter, nicht geöffnete danach;
    /// Hauptschalter von ProblemsWindowClosedUnits und ProblemsWindowShowCleanActive.</summary>
    ProblemsWindowOpenFirst: Boolean;
    /// <summary>Nicht geöffnete Units: 'dimmed' (Vorgabe, ausgegraut), 'normal' (nur einsortiert), 'hidden'.</summary>
    ProblemsWindowClosedUnits: string;
    /// <summary>Aktive Unit auch ohne Befunde oben zeigen („Keine Befunde“ bzw. „wird geprüft …“).</summary>
    ProblemsWindowShowCleanActive: Boolean;
    /// <summary>Bestätigt der Build einen Atlas-Befund (gleiche Zeile, gleicher Code, #1024): 'merge' (Vorgabe)
    /// zeigt nur den Atlas-Befund mit Marke „Atlas + dcc“, 'both' beide Meldungen.</summary>
    ProblemsCompilerMerge: string;
    /// <summary>Compilercode (E2035 …) in Meldung, Spalte „Compiler“ und Hover zeigen (#1024).</summary>
    ProblemsShowCompilerCode: Boolean;
    /// <summary>Laufende Prüfung beim Tippen (#909); aus = Prüfung der offenen Datei nur beim Speichern.</summary>
    ProblemsLive: Boolean;
    /// <summary>„Alle sicheren Treffer korrigieren …“ im Fenster Atlas-Prüfung (#1352, fix.bulk).</summary>
    FixBulk: Boolean;
    /// <summary>Modul-Schalter ruleChecks.enabled (#1454): Prüfregeln; aus = die wirksamen Werte aller Einstellungen des Moduls sind
    /// „aus“ (TAtlasModuleSwitches), gespeichert bleiben sie.</summary>
    RuleChecksEnabled: Boolean;
    /// <summary>Vorgaben.</summary>
    class function Defaults: TAtlasPluginRulesSettings; static;
    /// <summary>Werte in ihre Grenzen bringen.</summary>
    procedure Normalize;
    /// <summary>Werte über AIo lesen bzw. schreiben, jeden unter seinem Namen.</summary>
    procedure Exchange(const AIo: TAtlasSettingsExchange);
  end;

implementation

{ TAtlasPluginRulesSettings }

class function TAtlasPluginRulesSettings.Defaults: TAtlasPluginRulesSettings;
begin
  Result.ProblemsWindow := True;
  Result.ProblemsWindowScope := 'group';
  Result.ProblemsWindowGroupBy := 'file';
  Result.ProblemsWindowColumns := '';
  Result.ProblemsWindowCompiler := False;
  Result.ProblemsWindowFollowCursor := True;
  Result.ProblemsWindowOpenFirst := True;
  Result.ProblemsWindowClosedUnits := 'dimmed';
  Result.ProblemsWindowShowCleanActive := True;
  Result.ProblemsCompilerMerge := 'merge';
  Result.ProblemsShowCompilerCode := True;
  Result.ProblemsLive := True;
  Result.FixBulk := True;
  Result.RuleChecksEnabled := True;
end;

procedure TAtlasPluginRulesSettings.Normalize;
begin
  ProblemsWindowScope := Choice(ProblemsWindowScope, ['group', 'file', 'project']);
  ProblemsWindowGroupBy := Choice(ProblemsWindowGroupBy, ['file', 'none', 'rule', 'category']);
  ProblemsWindowClosedUnits := Choice(ProblemsWindowClosedUnits, ['dimmed', 'normal', 'hidden']);
  ProblemsCompilerMerge := Choice(ProblemsCompilerMerge, ['merge', 'both']);
end;

procedure TAtlasPluginRulesSettings.Exchange(const AIo: TAtlasSettingsExchange);
begin
  AIo.Flag('ProblemsWindow', ProblemsWindow);
  AIo.Text('ProblemsWindowScope', ProblemsWindowScope);
  AIo.Text('ProblemsWindowGroupBy', ProblemsWindowGroupBy);
  AIo.Text('ProblemsWindowColumns', ProblemsWindowColumns);
  AIo.Flag('ProblemsWindowCompiler', ProblemsWindowCompiler);
  AIo.Flag('ProblemsWindowFollowCursor', ProblemsWindowFollowCursor);
  AIo.Flag('ProblemsWindowOpenFirst', ProblemsWindowOpenFirst);
  AIo.Text('ProblemsWindowClosedUnits', ProblemsWindowClosedUnits);
  AIo.Flag('ProblemsWindowShowCleanActive', ProblemsWindowShowCleanActive);
  AIo.Text('ProblemsCompilerMerge', ProblemsCompilerMerge);
  AIo.Flag('ProblemsShowCompilerCode', ProblemsShowCompilerCode);
  AIo.Flag('ProblemsLive', ProblemsLive);
  AIo.Flag('FixBulk', FixBulk);
  AIo.Flag('RuleChecksEnabled', RuleChecksEnabled);
end;

end.
