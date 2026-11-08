unit Atlas.Core.Settings.Plugin.VersionControl;

// Einstellungen des IDE-Plugins, Bereich Versionsverwaltung (vcs.*) (#227, ADR 0017):
// Felder, Vorgaben, Grenzen, Lesen und Schreiben. TAtlasPluginSettings (Atlas.Core.Settings.Plugin)
// fasst die Bereiche zusammen und reicht die Felder als Eigenschaften durch.

interface

uses
  Atlas.Core.Settings.Plugin.Store;

const
  /// <summary>Grenzen und Vorgabe von vcs.timeoutSeconds (#1285).</summary>
  cMinVcsTimeoutSeconds = 1;
  cMaxVcsTimeoutSeconds = 300;
  cDefaultVcsTimeoutSeconds = 15;
  /// <summary>Vorgaben von vcs.branch.svn.* (#1290); wie TAtlasVcsSvnBranchOptions.Default.</summary>
  cDefaultVcsBranchSvnLocation = '{projektwurzel}/branches/{name}';
  cDefaultVcsBranchSvnCheckoutFolder = '..\{projekt}-{kennung}';
  cDefaultVcsBranchSvnMessage = '{kennung} Branch für {titel}';
  /// <summary>Vorgabe für vcs.branch.git.worktreeFolder (#1289); wie
  /// TAtlasVcsGitBranchOptions.cDefaultWorktreeFolder.</summary>
  cDefaultVcsWorktreeFolder = '..\{repo}-{kennung}';

type
  /// <summary>Plugin-Einstellungen: Versionsverwaltung.</summary>
  TAtlasPluginVcsSettings = record
    /// <summary>Modul-Schalter vcs.enabled (#1891): Versionsverwaltung; aus = keine Arbeitskopie, kein
    /// Branch beim Beginnen, keine Zeilenhistorie. Die Einzelschalter behalten ihre Werte.</summary>
    VcsEnabled: Boolean;
    /// <summary>Art der Versionsverwaltung (#571, vcs.provider, seit #1285 auf der Seite Versionsverwaltung):
    /// auto, git, svn oder off; liegt in settings.json, damit Plugin und Server denselben Wert lesen.</summary>
    VcsProvider: string;
    /// <summary>Eigener Pfad zu git.exe bzw. svn.exe (#1285, vcs.git.path, vcs.svn.path); '' = in PATH und den
    /// üblichen Ordnern suchen. Liegen in settings.json, damit auch atlas --changed dasselbe Programm verwendet.
    /// </summary>
    VcsGitPath: string;
    VcsSvnPath: string;
    /// <summary>Zeitlimit je Aufruf von git bzw. svn in Sekunden (#1285, vcs.timeoutSeconds, 1–300).</summary>
    VcsTimeoutSeconds: Integer;
    /// <summary>Persönliche Art und Hauptbranch je Delphi-Projekt (#1286, vcs.projects) als JSON-Liste mit match,
    /// provider und mainBranch; liegt in settings.json, gelesen mit TAtlasVcsProjects. '[]' = keine.</summary>
    VcsProjects: string;
    /// <summary>SVN-Branches (#1290, vcs.branch.svn.*): Ort im Repository (Muster mit {projektwurzel} oder ^/,
    /// {name}, {kennung}), Quelle ("head", "workingCopy"), danach ("switch", "checkout", "none"), Ordner beim
    /// Auschecken (relativ zur Arbeitskopie, {projekt}, {name}, {kennung}) und Commit-Nachricht der Kopie
    /// ({kennung}, {titel}, {name}). Vorgaben in den Feldern des Dialogs „Branch anlegen“. Persönlich (Registry).
    /// </summary>
    VcsBranchSvnLocation: string;
    VcsBranchSvnSource: string;
    VcsBranchSvnAfter: string;
    VcsBranchSvnCheckoutFolder: string;
    VcsBranchSvnMessage: string;
    /// <summary>SVN-Externals beim Anlegen eines Branchs (#1291, vcs.externals.*): Externals ohne Revision
    /// ("pin" festschreiben, "keep" lassen, "ask" ohne Vorauswahl), wann „mitverzweigen“ vorgeschlagen wird
    /// ("modified", "never", "always") und feste Behandlung je Quelle als JSON-Liste mit source und onBranch
    /// (gelesen mit TAtlasVcsExternalRules.RulesOf; '[]' = keine). Persönlich (Registry).</summary>
    VcsExternalsOnBranch: string;
    VcsExternalsSuggestBranch: string;
    VcsExternalsRules: string;
    /// <summary>Arbeitskopien einer Gruppe (#1292, vcs.externals.show): Tabelle „Arbeitskopien“ mit Wurzel,
    /// svn:externals und Git-Submodulen samt Aufschlüsselung in „Nicht gesicherte Arbeit“; aus = Projektstand wie
    /// vor #1292. Persönlich (Registry).</summary>
    VcsExternalsShow: Boolean;
    /// <summary>Aktualisieren unter SVN (#1292, vcs.externals.update): "with" svn update samt Externals,
    /// "without" mit --ignore-externals, "ask" fragt (Untermenü „mit Externals“/„ohne Externals“). Persönlich
    /// (Registry).</summary>
    VcsExternalsUpdate: string;
    /// <summary>Dialog „Branch anlegen“ vor dem Anlegen bei „Beginnen“ zeigen (#1288, vcs.branch.confirm); aus =
    /// mit den Vorgaben ohne Dialog. Der Befehl „Branch anlegen …“ zeigt ihn immer. Persönlich (Registry).
    /// </summary>
    VcsBranchConfirm: Boolean;
    /// <summary>Git: wovon der Branch abzweigt (#1289, vcs.branch.git.base): remote (vorher fetch, dann
    /// &lt;Remote&gt;/&lt;Hauptbranch&gt;), local (lokaler Hauptbranch, sonst origin; Verhalten vor #1289) oder
    /// current (aktueller Branch). Persönlich (Registry).</summary>
    VcsBranchGitBase: string;
    /// <summary>Git: later (Upstream setzt der erste Push) oder now (gleich push --set-upstream) (#1289,
    /// vcs.branch.git.push).</summary>
    VcsBranchGitPush: string;
    /// <summary>Git: offene Änderungen carry (mitnehmen), stash (vorher beiseitelegen) oder ask (nachfragen)
    /// (#1289, vcs.branch.git.uncommitted).</summary>
    VcsBranchGitUncommitted: string;
    /// <summary>Git: Branch in eigenem Ordner über git worktree (#1289, vcs.branch.git.worktree).</summary>
    VcsBranchGitWorktree: Boolean;
    /// <summary>Ordner für den worktree mit {repo}, {name}, {kennung}, relativ zur Wurzel der Arbeitskopie
    /// (#1289, vcs.branch.git.worktreeFolder).</summary>
    VcsBranchGitWorktreeFolder: string;
    /// <summary>Vorgaben.</summary>
    class function Defaults: TAtlasPluginVcsSettings; static;
    /// <summary>Werte in ihre Grenzen bringen.</summary>
    procedure Normalize;
    /// <summary>Werte über AIo lesen bzw. schreiben, jeden unter seinem Namen.</summary>
    procedure Exchange(const AIo: TAtlasSettingsExchange);
  end;

implementation

uses
  System.SysUtils;

{ TAtlasPluginVcsSettings }

class function TAtlasPluginVcsSettings.Defaults: TAtlasPluginVcsSettings;
begin
  Result.VcsEnabled := True;
  Result.VcsProvider := 'auto';
  Result.VcsGitPath := '';
  Result.VcsSvnPath := '';
  Result.VcsTimeoutSeconds := cDefaultVcsTimeoutSeconds;
  Result.VcsProjects := '[]';
  Result.VcsBranchSvnLocation := cDefaultVcsBranchSvnLocation;
  Result.VcsBranchSvnSource := 'head';
  Result.VcsBranchSvnAfter := 'switch';
  Result.VcsBranchSvnCheckoutFolder := cDefaultVcsBranchSvnCheckoutFolder;
  Result.VcsBranchSvnMessage := cDefaultVcsBranchSvnMessage;
  Result.VcsExternalsOnBranch := 'pin';
  Result.VcsExternalsSuggestBranch := 'modified';
  Result.VcsExternalsRules := '[]';
  Result.VcsExternalsShow := True;
  Result.VcsExternalsUpdate := 'with';
  Result.VcsBranchConfirm := True;
  Result.VcsBranchGitBase := 'remote';
  Result.VcsBranchGitPush := 'later';
  Result.VcsBranchGitUncommitted := 'carry';
  Result.VcsBranchGitWorktree := False;
  Result.VcsBranchGitWorktreeFolder := cDefaultVcsWorktreeFolder;
end;

procedure TAtlasPluginVcsSettings.Normalize;
begin
  VcsProvider := Choice(LowerCase(Trim(VcsProvider)), ['auto', 'git', 'svn', 'off']);
  VcsGitPath := Trim(VcsGitPath);
  VcsSvnPath := Trim(VcsSvnPath);
  // Außerhalb der Grenzen gilt die Vorgabe wie im Server (vcs.timeoutSeconds).
  if (VcsTimeoutSeconds < cMinVcsTimeoutSeconds) or (VcsTimeoutSeconds > cMaxVcsTimeoutSeconds) then
  begin
    VcsTimeoutSeconds := cDefaultVcsTimeoutSeconds;
  end;
  VcsProjects := Trim(VcsProjects);
  if VcsProjects = '' then
  begin
    VcsProjects := '[]';
  end;
  // Ort beginnt mit {projektwurzel} oder ^/ (#1290); sonst die Vorgabe.
  VcsBranchSvnLocation := Trim(VcsBranchSvnLocation);
  if not (SameText(Copy(VcsBranchSvnLocation, 1, 15), '{projektwurzel}') or
    (Copy(VcsBranchSvnLocation, 1, 2) = '^/')) then
  begin
    VcsBranchSvnLocation := cDefaultVcsBranchSvnLocation;
  end;
  VcsBranchSvnSource := Choice(VcsBranchSvnSource, ['head', 'workingCopy']);
  VcsBranchSvnAfter := Choice(VcsBranchSvnAfter, ['switch', 'checkout', 'none']);
  VcsBranchSvnCheckoutFolder := Trim(VcsBranchSvnCheckoutFolder);
  if VcsBranchSvnCheckoutFolder = '' then
  begin
    VcsBranchSvnCheckoutFolder := cDefaultVcsBranchSvnCheckoutFolder;
  end;
  VcsBranchSvnMessage := NormalizedIssuesText(VcsBranchSvnMessage, True);
  if VcsBranchSvnMessage = '' then
  begin
    VcsBranchSvnMessage := cDefaultVcsBranchSvnMessage;
  end;
  VcsExternalsOnBranch := Choice(VcsExternalsOnBranch, ['pin', 'keep', 'ask']);
  VcsExternalsSuggestBranch := Choice(VcsExternalsSuggestBranch, ['modified', 'never', 'always']);
  VcsExternalsRules := Trim(VcsExternalsRules);
  if VcsExternalsRules = '' then
  begin
    VcsExternalsRules := '[]';
  end;
  VcsExternalsUpdate := Choice(VcsExternalsUpdate, ['with', 'without', 'ask']);
  VcsBranchGitBase := Choice(LowerCase(Trim(VcsBranchGitBase)), ['remote', 'local', 'current']);
  VcsBranchGitPush := Choice(LowerCase(Trim(VcsBranchGitPush)), ['later', 'now']);
  VcsBranchGitUncommitted := Choice(LowerCase(Trim(VcsBranchGitUncommitted)), ['carry', 'stash', 'ask']);
  VcsBranchGitWorktreeFolder := Trim(VcsBranchGitWorktreeFolder);
  if VcsBranchGitWorktreeFolder = '' then
  begin
    VcsBranchGitWorktreeFolder := cDefaultVcsWorktreeFolder;
  end;
end;

procedure TAtlasPluginVcsSettings.Exchange(const AIo: TAtlasSettingsExchange);
begin
  AIo.Flag('VcsEnabled', VcsEnabled);
  AIo.Text('VcsProvider', VcsProvider);
  AIo.Text('VcsGitPath', VcsGitPath);
  AIo.Text('VcsSvnPath', VcsSvnPath);
  AIo.Number('VcsTimeoutSeconds', VcsTimeoutSeconds);
  AIo.Text('VcsProjects', VcsProjects);
  AIo.Text('VcsBranchSvnLocation', VcsBranchSvnLocation);
  AIo.Text('VcsBranchSvnSource', VcsBranchSvnSource);
  AIo.Text('VcsBranchSvnAfter', VcsBranchSvnAfter);
  AIo.Text('VcsBranchSvnCheckoutFolder', VcsBranchSvnCheckoutFolder);
  AIo.Text('VcsBranchSvnMessage', VcsBranchSvnMessage);
  AIo.Text('VcsExternalsOnBranch', VcsExternalsOnBranch);
  AIo.Text('VcsExternalsSuggestBranch', VcsExternalsSuggestBranch);
  AIo.Text('VcsExternalsRules', VcsExternalsRules);
  AIo.Flag('VcsExternalsShow', VcsExternalsShow);
  AIo.Text('VcsExternalsUpdate', VcsExternalsUpdate);
  AIo.Flag('VcsBranchConfirm', VcsBranchConfirm);
  AIo.Text('VcsBranchGitBase', VcsBranchGitBase);
  AIo.Text('VcsBranchGitPush', VcsBranchGitPush);
  AIo.Text('VcsBranchGitUncommitted', VcsBranchGitUncommitted);
  AIo.Flag('VcsBranchGitWorktree', VcsBranchGitWorktree);
  AIo.Text('VcsBranchGitWorktreeFolder', VcsBranchGitWorktreeFolder);
end;

end.
