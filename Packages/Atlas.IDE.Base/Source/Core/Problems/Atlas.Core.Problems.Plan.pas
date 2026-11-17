unit Atlas.Core.Problems.Plan;

// Entscheidungen von Prüfung und Fenster „Atlas-Prüfung“ (#398, #909) ohne
// VCL und Open Tools API: ob Diagnosen überhaupt zu holen sind (Probleme oder
// eins der Abblenden an), welche Dateien als Quelltext gelten, wann die
// Zähler der Statusleiste neu gehen (#509), wie ein Wechsel der Datei den
// alten Text abgleicht (#492) und welcher Hinweis zu einem uses-Eintrag
// gehört (#621). Takt und Threads bleiben in Atlas.IDE.Problems.Controller;
// die Entscheidungen des Fensters stehen in Atlas.Core.Problems.Findings
// (TAtlasFindingsWindow).

{$SCOPEDENUMS ON}

interface

uses
  Atlas.Core.Settings.Plugin;

type
  /// <summary>Was beim Wechsel der Datei im Editor zu tun ist: nur merken (erste oder dieselbe Datei); warten, bis
  /// keine Anfrage läuft; den Text der vorigen Datei an den Server geben und die neue merken.</summary>
  TAtlasProblemsSwitch = (Remember, Wait, SyncPrevious);

  /// <summary>Grund eines uses-Hinweises (#621).</summary>
  TAtlasProblemsUsesHint = (Unused, Initialization_, Allowlist, Implementation_);

  TAtlasProblemsPlan = record
  public const
    /// <summary>Wert von problems.compilerMerge, mit dem Compilermeldungen und Befunde getrennt bleiben (#1024).
    /// </summary>
    cCompilerBoth = 'both';
  public
    /// <summary>Diagnosen holen: für Probleme oder für das Abblenden inaktiver Zweige bzw. ungenutzter uses.</summary>
    class function Active(const ASettings: TAtlasPluginSettings): Boolean; static;
    /// <summary>Probleme zeigen (Wellenlinien, Hover, Meldungsliste).</summary>
    class function Shown(const ASettings: TAtlasPluginSettings): Boolean; static;
    /// <summary>Inaktive Zweige abblenden (#615).</summary>
    class function InactiveShown(const ASettings: TAtlasPluginSettings): Boolean; static;
    /// <summary>Bestätigte Compilermeldungen mit Befunden zusammenführen (problems.compilerMerge).</summary>
    class function CompilerMerge(const ASettings: TAtlasPluginSettings): Boolean; static;
    /// <summary>Zähler der Statusleiste zeigen (#509), außer die Atlas-Statusleiste am Editor zeigt die Befunde.
    /// </summary>
    class function StatusCounter(const ASettings: TAtlasPluginSettings): Boolean; static;
    /// <summary>Meldungen gelöschter Zeilen verwerfen statt auf die Folgezeile zu schieben (#1818,
    /// editor.trackLines).</summary>
    class function DropDeletedLines(const ASettings: TAtlasPluginSettings): Boolean; static;
    /// <summary>Ungenutzte uses abblenden (#621).</summary>
    class function UsesDimmed(const ASettings: TAtlasPluginSettings): Boolean; static;
    /// <summary>Delphi-Quelltext (.pas, .dpr, .dpk, .inc, .lpr), ohne Groß-/Kleinschreibung.</summary>
    class function IsSource(const AFileName: string): Boolean; static;
    /// <summary>Zähler der Statusleiste neu melden: Sichtbarkeit AShow gegenüber zuletzt AShown geändert oder,
    /// sichtbar, Stand AVersion des Speichers gegenüber zuletzt AKnownVersion.</summary>
    class function CountsDue(AShow, AShown: Boolean; AVersion, AKnownVersion: Cardinal): Boolean; static;
    /// <summary>Schritt beim Takt für AFileName, zuletzt ALastFile ('' = keine); AIdle: keine Anfrage läuft.</summary>
    class function Switch(const ALastFile, AFileName: string; AIdle: Boolean): TAtlasProblemsSwitch; static;
    /// <summary>Grund des uses-Hinweises nach dem Zustand AState des Servers (initialization, allowlist,
    /// implementation, sonst ungenutzt).</summary>
    class function UsesHint(const AState: string): TAtlasProblemsUsesHint; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Problems.Switches;

{ TAtlasProblemsPlan }

class function TAtlasProblemsPlan.Active(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := ASettings.Enabled and (ASettings.Problems or ASettings.InactiveDim or ASettings.DimUnusedUses or
    ASettings.HighlightMovableUses);
end;

class function TAtlasProblemsPlan.Shown(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := ASettings.Enabled and ASettings.Problems;
end;

class function TAtlasProblemsPlan.StatusCounter(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := TAtlasProblemSwitches.ProblemsStatusCounter(ASettings);
end;

class function TAtlasProblemsPlan.DropDeletedLines(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := ASettings.Enabled and ASettings.TrackLines;
end;

class function TAtlasProblemsPlan.UsesDimmed(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := ASettings.Enabled and ASettings.DimUnusedUses;
end;

class function TAtlasProblemsPlan.InactiveShown(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := ASettings.Enabled and ASettings.InactiveDim;
end;

class function TAtlasProblemsPlan.CompilerMerge(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := not SameText(ASettings.ProblemsCompilerMerge, cCompilerBoth);
end;

class function TAtlasProblemsPlan.IsSource(const AFileName: string): Boolean;
const
  cSources: array[0..4] of string = ('.pas', '.dpr', '.dpk', '.inc', '.lpr');
var
  mExtension, mSource: string;
begin
  mExtension := LowerCase(ExtractFileExt(AFileName));
  for mSource in cSources do
  begin
    if mExtension = mSource then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasProblemsPlan.CountsDue(AShow, AShown: Boolean; AVersion, AKnownVersion: Cardinal): Boolean;
begin
  Result := (AShow <> AShown) or (AShow and (AVersion <> AKnownVersion));
end;

class function TAtlasProblemsPlan.Switch(const ALastFile, AFileName: string; AIdle: Boolean): TAtlasProblemsSwitch;
begin
  if (ALastFile = '') or SameText(ALastFile, AFileName) then
  begin
    Exit(TAtlasProblemsSwitch.Remember);
  end;
  if not AIdle then
  begin
    Exit(TAtlasProblemsSwitch.Wait);
  end;
  Result := TAtlasProblemsSwitch.SyncPrevious;
end;

class function TAtlasProblemsPlan.UsesHint(const AState: string): TAtlasProblemsUsesHint;
const
  cStates: array[TAtlasProblemsUsesHint] of string = ('', TAtlasProblem.cUsesInitialization,
    TAtlasProblem.cUsesAllowlist, TAtlasProblem.cUsesImplementation);
var
  mHint: TAtlasProblemsUsesHint;
begin
  for mHint := Low(TAtlasProblemsUsesHint) to High(TAtlasProblemsUsesHint) do
  begin
    if AState = cStates[mHint] then
    begin
      Exit(mHint);
    end;
  end;
  Result := TAtlasProblemsUsesHint.Unused;
end;

end.
