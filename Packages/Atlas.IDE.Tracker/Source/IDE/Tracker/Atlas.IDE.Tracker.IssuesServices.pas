unit Atlas.IDE.Tracker.IssuesServices;

// Dienste von „Meine Issues“ (aus Atlas.IDE.Tracker.MyIssues gelöst, #1455):
// Vorschau „Atlas-Issue“ (#1264), Board (#1272), Sprint-Kachel (#1277),
// Tracker nachführen (#1266), Zeiterfassung (#1267), Issues in der
// Befehlspalette (#1270), Kommentar-Editor (#1278), Meldungen zu meinen Issues
// (#1271) und „An Issue anhängen“ (#1276). Alle mit Anbieter und Transport aus
// dem Kontext; ihre Hooks halten den Besitzer (TAtlasIssuesLink.Keep), Stop
// löst den Ring.

interface

uses
  System.SysUtils,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.MyIssues,
  Atlas.Core.Tracker.TimeLog,
  Atlas.IDE.Tracker.IssuePreview,
  Atlas.IDE.Tracker.Attach,
  Atlas.IDE.Tracker.Notify,
  Atlas.IDE.Tracker.TimeTracking,
  Atlas.IDE.Tracker.Board,
  Atlas.IDE.Tracker.Workflow,
  Atlas.IDE.Tracker.PaletteSearch,
  Atlas.IDE.Tracker.CommentAssist,
  Atlas.IDE.Tracker.SprintTile,
  Atlas.IDE.Tracker.IssuesContext;

type
  TAtlasIdeIssuesServices = class
  private
    FContext: TAtlasIdeIssuesContext;
    FPreview: TAtlasIdeIssuePreview;
    FBoard: TAtlasIdeBoard;
    FSprint: TAtlasIdeSprint;
    FSync: TAtlasIdeTrackerSync;
    FTime: TAtlasIdeTrackerTime;
    FSearch: TAtlasIdeIssueSearch;
    FSearchRef: IAtlasPaletteSource;
    FComments: TAtlasIdeCommentService;
    FNotify: TAtlasIdeIssueNotify;
    FAttach: TAtlasIdeIssueAttach;
    // Referenzgezählte Dienste: gehalten bis Stop.
    FRefs: TArray<IInterface>;
    procedure Keep(const AService: IInterface);
  public
    constructor Create(AContext: TAtlasIdeIssuesContext);
    /// <summary>Alle Dienste anlegen und starten.</summary>
    procedure Start;
    /// <summary>Alle Dienste stoppen und lösen (zuerst die Zeiterfassung); danach nil.</summary>
    procedure Stop;
    /// <summary>Nach geänderten Einstellungen oder anderem Projekt.</summary>
    procedure Refresh;
    function Options: TAtlasIssuesOptions;
    /// <summary>Issues mit neuen Änderungen (#1271) bei ATarget.</summary>
    function UnseenOf(const ATarget: TAtlasTrackerTarget): TArray<string>;
    /// <summary>Tracker des aktuellen Projekts, dann die persönlichen Verbindungen.</summary>
    function NotifyTargets: TArray<TAtlasTrackerTarget>;
    /// <summary>Gemeldetes Issue öffnen: Vorschau am ersten neuen Kommentar, sonst Browser.</summary>
    procedure OpenNotified(const ATarget: TAtlasTrackerTarget; const AKey: string; AAnchor: TDateTime);
    function TimeIssueOf(const AProject, AKey: string): TAtlasTimeIssue;
    /// <summary>Die Uhr der Zeiterfassung auf das aktuelle Issue von AProject stellen ('' = keins).</summary>
    procedure SyncTime(const AProject, AKey: string);
    /// <summary>Befehl Atlas.IssueTimeOpen (#1267): offene Zeitbuchungen zeigen.</summary>
    procedure ShowTimeOpen;
    /// <summary>Die zuletzt abgefragte Liste aus „Meine Issues“ als Vorschläge, ohne Netz.</summary>
    function AttachIssues: TArray<string>;
    /// <summary>Aktuelles Issue begonnen oder beendet: Vorschau und Board nachziehen.</summary>
    procedure ActiveChanged;
    /// <summary>Vorschau-Steuerung (nil vor Start bzw. nach Stop).</summary>
    property Preview: TAtlasIdeIssuePreview read FPreview;
    /// <summary>Fenster „Atlas-Board“ (#1272; nil vor Start bzw. nach Stop).</summary>
    property Board: TAtlasIdeBoard read FBoard;
    /// <summary>Sprint-Kachel (#1277; nil vor Start bzw. nach Stop).</summary>
    property Sprint: TAtlasIdeSprint read FSprint;
    /// <summary>Tracker nachführen (#1266; nil vor Start bzw. nach Stop).</summary>
    property Sync: TAtlasIdeTrackerSync read FSync;
    /// <summary>Zeiterfassung (#1267; nil vor Start bzw. nach Stop).</summary>
    property Time: TAtlasIdeTrackerTime read FTime;
    /// <summary>Quelle der Befehlspalette für Issues (#1270); nil vor Start bzw. nach Stop.</summary>
    property PaletteSearch: IAtlasPaletteSource read FSearchRef;
    /// <summary>Meldungen zu meinen Issues (#1271; nil vor Start bzw. nach Stop).</summary>
    property Notify: TAtlasIdeIssueNotify read FNotify;
    /// <summary>„An Issue anhängen“ (#1276; nil vor Start bzw. nach Stop).</summary>
    property Attach: TAtlasIdeIssueAttach read FAttach;
  end;

implementation

uses
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Tracker.CommentEditor,
  Atlas.Core.Tracker.Connections,
  Atlas.UI.Tracker.EndDialog,
  Atlas.IDE.Foundation.Settings;

type
  /// <summary>Was die Hooks der Dienste einfangen: den Besitzer (hält ihn bis Stop), Kontext und Dienste.
  /// </summary>
  TAtlasIssuesLink = record
    Keep: IInterface;
    Context: TAtlasIdeIssuesContext;
    Services: TAtlasIdeIssuesServices;
    class function Create(AServices: TAtlasIdeIssuesServices): TAtlasIssuesLink; static;
    function Provider(const AName: string): IAtlasTrackerProvider;
    function Transport(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget):
      IAtlasCiTransport;
    procedure Report(const AText: string);
    function Project: string;
    procedure Start(const AIssue: TAtlasTrackerIssue);
    function CanStart: Boolean;
    procedure Settings;
    function Recent(const ATarget: TAtlasTrackerTarget): TArray<TAtlasTrackerIssue>;
    function Assist(const ATarget: TAtlasTrackerTarget; const AKey, AField: string): IAtlasCommentAssist;
    procedure Show(const ATarget: TAtlasTrackerTarget; const AKey: string);
    function PreviewActive: Boolean;
    /// <summary>Ohne Tracker nachführen: ADone mit „nicht eingerichtet“, Ergebnis True.</summary>
    function NoSync(const ADone: TAtlasTrackerSendDone): Boolean;
    procedure Comment(const ATarget: TAtlasTrackerTarget; const AKey, AText: string;
      const ADone: TAtlasTrackerSendDone);
    procedure AssignMe(const ATarget: TAtlasTrackerTarget; const AKey: string; const ADone: TAtlasTrackerSendDone);
    function CanWrite(const ATarget: TAtlasTrackerTarget): Boolean;
    procedure EndIssue(const AKey: string);
    procedure Attach(const ATarget: TAtlasTrackerTarget; const AKey: string);
    function CanAttach: Boolean;
    procedure OpenBoard;
    procedure Updated;
    function ActiveTarget: TAtlasTrackerTarget;
    function ActiveKey: string;
  end;

{ TAtlasIssuesLink }

class function TAtlasIssuesLink.Create(AServices: TAtlasIdeIssuesServices): TAtlasIssuesLink;
begin
  Result.Keep := AServices.FContext.Actions;
  Result.Context := AServices.FContext;
  Result.Services := AServices;
end;

function TAtlasIssuesLink.Provider(const AName: string): IAtlasTrackerProvider;
begin
  Result := nil;
  if Keep <> nil then
  begin
    Result := Context.ProviderOf(AName);
  end;
end;

function TAtlasIssuesLink.Transport(const AProvider: IAtlasTrackerProvider;
  const ATarget: TAtlasTrackerTarget): IAtlasCiTransport;
begin
  Result := nil;
  if Keep <> nil then
  begin
    Result := Context.TransportOf(AProvider, ATarget);
  end;
end;

procedure TAtlasIssuesLink.Report(const AText: string);
begin
  if Keep <> nil then
  begin
    Context.Report(AText);
  end;
end;

function TAtlasIssuesLink.Project: string;
begin
  Result := '';
  if Keep <> nil then
  begin
    Result := Context.CurrentProject;
  end;
end;

procedure TAtlasIssuesLink.Start(const AIssue: TAtlasTrackerIssue);
begin
  if (Keep <> nil) and (Context.Actions <> nil) then
  begin
    Context.Actions.Start(AIssue, Services.Options.Start);
  end;
end;

function TAtlasIssuesLink.CanStart: Boolean;
begin
  Result := (Keep <> nil) and Context.CanStart;
end;

procedure TAtlasIssuesLink.Settings;
var
  mSettings: TProc;
begin
  mSettings := nil;
  if Keep <> nil then
  begin
    mSettings := Context.Hooks.Settings;
  end;
  if Assigned(mSettings) then
  begin
    mSettings();
  end;
end;

function TAtlasIssuesLink.Recent(const ATarget: TAtlasTrackerTarget): TArray<TAtlasTrackerIssue>;
begin
  Result := nil;
  if (Keep <> nil) and (Services.FPreview <> nil) then
  begin
    Result := Services.FPreview.RecentIssues(ATarget);
  end;
end;

function TAtlasIssuesLink.Assist(const ATarget: TAtlasTrackerTarget; const AKey, AField: string):
  IAtlasCommentAssist;
begin
  Result := nil;
  if (Keep <> nil) and (Services.FComments <> nil) then
  begin
    Result := Services.FComments.Assist(ATarget, AKey, AField);
  end;
end;

procedure TAtlasIssuesLink.Show(const ATarget: TAtlasTrackerTarget; const AKey: string);
begin
  if (Keep <> nil) and (Services.FPreview <> nil) then
  begin
    Services.FPreview.Show(ATarget, AKey);
  end;
end;

function TAtlasIssuesLink.PreviewActive: Boolean;
begin
  Result := (Keep <> nil) and (Services.FPreview <> nil) and TAtlasIdeIssuePreview.Active;
end;

function TAtlasIssuesLink.NoSync(const ADone: TAtlasTrackerSendDone): Boolean;
begin
  Result := (Keep = nil) or (Services.FSync = nil);
  if Result then
  begin
    ADone(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, ''));
  end;
end;

procedure TAtlasIssuesLink.Comment(const ATarget: TAtlasTrackerTarget; const AKey, AText: string;
  const ADone: TAtlasTrackerSendDone);
begin
  if not NoSync(ADone) then
  begin
    Services.FSync.SendComment(Context.ProviderOf(ATarget.Provider), ATarget, AKey, AText, ADone);
  end;
end;

procedure TAtlasIssuesLink.AssignMe(const ATarget: TAtlasTrackerTarget; const AKey: string;
  const ADone: TAtlasTrackerSendDone);
var
  mChange: TAtlasTrackerWrite;
begin
  if NoSync(ADone) then
  begin
    Exit;
  end;
  // Derselbe Schreibweg wie „Beginnen“ (#1266), mit dem Benutzerfeld der Verbindung.
  mChange := TAtlasTrackerWrite.Empty;
  mChange.AssigneeField := TAtlasIdeTrackerSync.Options(ATarget).AssigneeField;
  mChange.Assign := TAtlasTrackerAssign.Me;
  Services.FSync.Apply(Context.ProviderOf(ATarget.Provider), ATarget, AKey, mChange, ADone);
end;

function TAtlasIssuesLink.CanWrite(const ATarget: TAtlasTrackerTarget): Boolean;
begin
  Result := (Keep <> nil) and (Services.FSync <> nil) and
    Services.FSync.Enabled(Context.ProviderOf(ATarget.Provider), ATarget);
end;

procedure TAtlasIssuesLink.EndIssue(const AKey: string);
begin
  if (Keep <> nil) and (Context.Actions <> nil) and SameText(Context.ActiveKey, AKey) then
  begin
    Context.Actions.EndActive;
  end;
end;

procedure TAtlasIssuesLink.Attach(const ATarget: TAtlasTrackerTarget; const AKey: string);
begin
  if (Keep <> nil) and (Services.FAttach <> nil) then
  begin
    Services.FAttach.Execute(ATarget, AKey);
  end;
end;

function TAtlasIssuesLink.CanAttach: Boolean;
begin
  Result := (Keep <> nil) and (Services.FAttach <> nil) and TAtlasIdeIssueAttach.Active;
end;

procedure TAtlasIssuesLink.OpenBoard;
begin
  if (Keep <> nil) and (Services.FBoard <> nil) then
  begin
    Services.FBoard.Show;
  end;
end;

procedure TAtlasIssuesLink.Updated;
begin
  if Keep = nil then
  begin
    Exit;
  end;
  // Das Board lädt nur, wenn es sichtbar ist; der Sprint lädt sofort neu.
  if Services.FBoard <> nil then
  begin
    Services.FBoard.Refresh;
  end;
  if Services.FSprint <> nil then
  begin
    Services.FSprint.IssuesFetched(True);
  end;
end;

function TAtlasIssuesLink.ActiveTarget: TAtlasTrackerTarget;
begin
  // Tracker wie „Issue anzeigen …“: aktives Projekt der IDE, sonst das des Bereichs.
  Result := Default(TAtlasTrackerTarget);
  if Keep <> nil then
  begin
    Context.ActiveTarget(Result);
  end;
end;

function TAtlasIssuesLink.ActiveKey: string;
begin
  Result := '';
  if Keep <> nil then
  begin
    Result := Context.ActiveKey;
  end;
end;

{ Hooks der Dienste }

function CommentHooks(const ALink: TAtlasIssuesLink): TAtlasCommentAssistHooks;
var
  mLink: TAtlasIssuesLink;
begin
  mLink := ALink;
  Result := Default(TAtlasCommentAssistHooks);
  Result.Provider :=
    function(const AName: string): IAtlasTrackerProvider
    begin
      Result := mLink.Provider(AName);
    end;
  Result.Transport :=
    function(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): IAtlasCiTransport
    begin
      Result := mLink.Transport(AProvider, ATarget);
    end;
  Result.Recent :=
    function(const ATarget: TAtlasTrackerTarget): TArray<TAtlasTrackerIssue>
    begin
      Result := mLink.Recent(ATarget);
    end;
  Result.Folder :=
    function: string
    begin
      Result := ExtractFileDir(mLink.Project);
    end;
end;

function CreateSync(const ALink: TAtlasIssuesLink): TAtlasIdeTrackerSync;
var
  mLink: TAtlasIssuesLink;
begin
  mLink := ALink;
  Result := TAtlasIdeTrackerSync.Create(
    function(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): IAtlasCiTransport
    begin
      Result := mLink.Transport(AProvider, ATarget);
    end,
    procedure(AText: string)
    begin
      mLink.Report(AText);
    end);
  Result.CommentAssist :=
    function(const ATarget: TAtlasTrackerTarget; const AKey, AField: string): IAtlasCommentAssist
    begin
      Result := mLink.Assist(ATarget, AKey, AField);
    end;
end;

function CreateTime(const ALink: TAtlasIssuesLink): TAtlasIdeTrackerTime;
var
  mLink: TAtlasIssuesLink;
begin
  mLink := ALink;
  Result := TAtlasIdeTrackerTime.Create(ALink.Services.FSync,
    function(const AName: string): IAtlasTrackerProvider
    begin
      Result := mLink.Provider(AName);
    end,
    procedure(AText: string)
    begin
      mLink.Report(AText);
    end,
    TAtlasTimeFile.DefaultPath);
  Result.OnStatus := ALink.Context.Hooks.TimeStatus;
  ALink.Services.FSync.TimeText :=
    function(const AKey: string): string
    begin
      Result := '';
      if (mLink.Keep <> nil) and (mLink.Services.FTime <> nil) then
      begin
        Result := mLink.Services.FTime.TimeText(AKey);
      end;
    end;
end;

/// <summary>Zugriff, Beginnen und Anhängen der Vorschau.</summary>
procedure PreviewAccessHooks(const ALink: TAtlasIssuesLink; var AHooks: TAtlasIssuePreviewHooks);
var
  mLink: TAtlasIssuesLink;
begin
  mLink := ALink;
  AHooks.Provider :=
    function(const AName: string): IAtlasTrackerProvider
    begin
      Result := mLink.Provider(AName);
    end;
  AHooks.Transport :=
    function(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): IAtlasCiTransport
    begin
      Result := mLink.Transport(AProvider, ATarget);
    end;
  AHooks.Credentials :=
    function(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): Boolean
    begin
      Result := (mLink.Keep <> nil) and mLink.Context.CanEnterCredentials and
        mLink.Context.Hooks.Credentials(AProvider, ATarget);
    end;
  AHooks.Start :=
    procedure(AIssue: TAtlasTrackerIssue)
    begin
      mLink.Start(AIssue);
    end;
  AHooks.CanStart :=
    function: Boolean
    begin
      Result := mLink.CanStart;
    end;
  AHooks.Settings :=
    procedure
    begin
      mLink.Settings;
    end;
  AHooks.Attach :=
    procedure(ATarget: TAtlasTrackerTarget; AKey: string)
    begin
      mLink.Attach(ATarget, AKey);
    end;
  AHooks.CanAttach :=
    function: Boolean
    begin
      Result := mLink.CanAttach;
    end;
end;

/// <summary>Reiter „Entwicklung“, Beenden und Kommentare der Vorschau.</summary>
procedure PreviewWorkHooks(const ALink: TAtlasIssuesLink; var AHooks: TAtlasIssuePreviewHooks);
var
  mLink: TAtlasIssuesLink;
begin
  mLink := ALink;
  // Reiter „Entwicklung“ (#1269): Branches und Commits aus der Arbeitskopie des aktuellen Projekts.
  AHooks.Project :=
    function: string
    begin
      Result := mLink.Project;
    end;
  AHooks.CanWrite :=
    function(ATarget: TAtlasTrackerTarget): Boolean
    begin
      Result := mLink.CanWrite(ATarget);
    end;
  AHooks.IsActive :=
    function(AKey: string): Boolean
    begin
      Result := (mLink.Keep <> nil) and (AKey <> '') and SameText(mLink.Context.ActiveKey, AKey);
    end;
  AHooks.EndIssue :=
    procedure(AKey: string)
    begin
      mLink.EndIssue(AKey);
    end;
  AHooks.Comment :=
    procedure(const ATarget: TAtlasTrackerTarget; const AKey, AText: string; const ADone: TAtlasTrackerSendDone)
    begin
      mLink.Comment(ATarget, AKey, AText, ADone);
    end;
  AHooks.CommentAssist :=
    function(const ATarget: TAtlasTrackerTarget; const AKey: string): IAtlasCommentAssist
    begin
      Result := mLink.Assist(ATarget, AKey, TAtlasCommentDrafts.FieldPreview);
    end;
  AHooks.CommentSent :=
    procedure(const ATarget: TAtlasTrackerTarget; const AKey: string)
    begin
      if (mLink.Keep <> nil) and (mLink.Services.FComments <> nil) then
      begin
        mLink.Services.FComments.DeleteDraft(ATarget, AKey, TAtlasCommentDrafts.FieldPreview);
      end;
    end;
end;

function PreviewHooks(const ALink: TAtlasIssuesLink): TAtlasIssuePreviewHooks;
begin
  Result := Default(TAtlasIssuePreviewHooks);
  PreviewAccessHooks(ALink, Result);
  PreviewWorkHooks(ALink, Result);
end;

function BoardHooks(const ALink: TAtlasIssuesLink): TAtlasBoardHooks;
var
  mLink: TAtlasIssuesLink;
begin
  mLink := ALink;
  Result := Default(TAtlasBoardHooks);
  Result.Provider :=
    function(const AName: string): IAtlasTrackerProvider
    begin
      Result := mLink.Provider(AName);
    end;
  Result.Transport :=
    function(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): IAtlasCiTransport
    begin
      Result := mLink.Transport(AProvider, ATarget);
    end;
  Result.Target :=
    function: TAtlasTrackerTarget
    begin
      Result := mLink.ActiveTarget;
    end;
  Result.Preview :=
    procedure(ATarget: TAtlasTrackerTarget; AKey: string)
    begin
      if mLink.PreviewActive then
      begin
        mLink.Show(ATarget, AKey);
      end;
    end;
  Result.Start :=
    procedure(AIssue: TAtlasTrackerIssue)
    begin
      mLink.Start(AIssue);
    end;
  Result.CanStart :=
    function: Boolean
    begin
      Result := mLink.CanStart;
    end;
  Result.ActiveKey :=
    function: string
    begin
      Result := mLink.ActiveKey;
    end;
  Result.Assign :=
    procedure(const ATarget: TAtlasTrackerTarget; const AKey: string; const ADone: TAtlasTrackerSendDone)
    begin
      mLink.AssignMe(ATarget, AKey, ADone);
    end;
  Result.Message :=
    procedure(AText: string)
    begin
      mLink.Report(AText);
    end;
end;

function SprintHooks(const ALink: TAtlasIssuesLink): TAtlasSprintHooks;
var
  mLink: TAtlasIssuesLink;
begin
  mLink := ALink;
  Result := Default(TAtlasSprintHooks);
  Result.Provider :=
    function(const AName: string): IAtlasTrackerProvider
    begin
      Result := mLink.Provider(AName);
    end;
  Result.Transport :=
    function(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): IAtlasCiTransport
    begin
      Result := mLink.Transport(AProvider, ATarget);
    end;
  Result.Project :=
    function: string
    begin
      Result := mLink.Project;
    end;
  Result.Target :=
    function(AProject: string): TAtlasTrackerTarget
    begin
      Result := TAtlasTrackerTarget.Create('', '', '', '');
      if mLink.Keep <> nil then
      begin
        Result := mLink.Context.TargetOf(AProject);
      end;
    end;
  Result.OpenBoard :=
    procedure
    begin
      mLink.OpenBoard;
    end;
  Result.Filter :=
    procedure(const ACaption: string; const AIssues: TArray<TAtlasTrackerIssue>)
    begin
      if (mLink.Keep <> nil) and (mLink.Context.Actions <> nil) then
      begin
        mLink.Context.Actions.SetFilter(ACaption, AIssues);
      end;
    end;
  Result.CanAssign :=
    function: Boolean
    begin
      Result := (mLink.Keep <> nil) and mLink.Context.CanAssign;
    end;
  Result.Assign :=
    procedure
    begin
      if (mLink.Keep <> nil) and (mLink.Context.Actions <> nil) then
      begin
        mLink.Context.Actions.AssignProject;
      end;
    end;
  Result.Welcome := ALink.Context.Welcome;
end;

function SearchHooks(const ALink: TAtlasIssuesLink): TAtlasIssueSearchHooks;
var
  mLink: TAtlasIssuesLink;
begin
  mLink := ALink;
  Result := Default(TAtlasIssueSearchHooks);
  Result.Target :=
    function(out ATarget: TAtlasTrackerTarget): IAtlasTrackerProvider
    begin
      ATarget := TAtlasTrackerTarget.Create('', '', '', '');
      Result := nil;
      if (mLink.Keep <> nil) and mLink.Context.Started then
      begin
        Result := mLink.Context.ActiveTarget(ATarget);
      end;
    end;
  Result.Transport :=
    function(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): IAtlasCiTransport
    begin
      Result := mLink.Transport(AProvider, ATarget);
    end;
  Result.Show :=
    procedure(const ATarget: TAtlasTrackerTarget; const AKey: string)
    begin
      mLink.Show(ATarget, AKey);
    end;
  Result.PreviewActive :=
    function: Boolean
    begin
      Result := mLink.PreviewActive;
    end;
  Result.Recent :=
    function(const ATarget: TAtlasTrackerTarget): TArray<TAtlasTrackerIssue>
    begin
      Result := mLink.Recent(ATarget);
    end;
  Result.Start :=
    procedure(AIssue: TAtlasTrackerIssue)
    begin
      mLink.Start(AIssue);
    end;
  Result.CanStart :=
    function: Boolean
    begin
      Result := mLink.CanStart;
    end;
  Result.Report :=
    procedure(AText: string)
    begin
      mLink.Report(AText);
    end;
end;

function NotifyHooks(const ALink: TAtlasIssuesLink): TAtlasIssueNotifyHooks;
var
  mLink: TAtlasIssuesLink;
begin
  mLink := ALink;
  Result := Default(TAtlasIssueNotifyHooks);
  Result.Provider :=
    function(const AName: string): IAtlasTrackerProvider
    begin
      Result := mLink.Provider(AName);
    end;
  Result.Transport :=
    function(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): IAtlasCiTransport
    begin
      Result := mLink.Transport(AProvider, ATarget);
    end;
  Result.Targets :=
    function: TArray<TAtlasTrackerTarget>
    begin
      Result := nil;
      if mLink.Keep <> nil then
      begin
        Result := mLink.Services.NotifyTargets;
      end;
    end;
  Result.Open :=
    procedure(const ATarget: TAtlasTrackerTarget; const AKey: string; AAnchor: TDateTime)
    begin
      if mLink.Keep <> nil then
      begin
        mLink.Services.OpenNotified(ATarget, AKey, AAnchor);
      end;
    end;
  Result.Settings :=
    procedure
    begin
      mLink.Settings;
    end;
  Result.Changed :=
    procedure
    begin
      if (mLink.Keep <> nil) and (mLink.Context.Actions <> nil) then
      begin
        mLink.Context.Actions.UpdateTileInfo;
        mLink.Context.Changed;
      end;
    end;
  Result.Updated :=
    procedure
    begin
      mLink.Updated;
    end;
end;

function AttachHooks(const ALink: TAtlasIssuesLink): TAtlasIssueAttachHooks;
var
  mLink: TAtlasIssuesLink;
begin
  mLink := ALink;
  Result := Default(TAtlasIssueAttachHooks);
  Result.Provider :=
    function(const AName: string): IAtlasTrackerProvider
    begin
      Result := mLink.Provider(AName);
    end;
  Result.Transport :=
    function(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): IAtlasCiTransport
    begin
      Result := mLink.Transport(AProvider, ATarget);
    end;
  Result.Issues :=
    function: TArray<string>
    begin
      Result := nil;
      if mLink.Keep <> nil then
      begin
        Result := mLink.Services.AttachIssues;
      end;
    end;
  Result.Project :=
    function: string
    begin
      Result := mLink.Project;
    end;
  Result.Report :=
    procedure(AText: string)
    begin
      mLink.Report(AText);
    end;
end;

/// <summary>Die Referenz auf AService lösen (gibt ihn frei, wenn sonst niemand ihn hält).</summary>
procedure DropRef(AServices: TAtlasIdeIssuesServices; AService: TObject);
var
  mIndex: Integer;
begin
  for mIndex := High(AServices.FRefs) downto 0 do
  begin
    if (AServices.FRefs[mIndex] as TObject) = AService then
    begin
      Delete(AServices.FRefs, mIndex, 1);
    end;
  end;
end;

/// <summary>Zeiterfassung und Tracker nachführen anhalten (zuerst: schreibt die letzte Zeit über Sync).</summary>
procedure StopTracking(AServices: TAtlasIdeIssuesServices);
begin
  if AServices.FTime <> nil then
  begin
    AServices.FTime.Stop;
    DropRef(AServices, AServices.FTime);
  end;
  AServices.FTime := nil;
  if AServices.FSync <> nil then
  begin
    AServices.FSync.Stop;
  end;
end;

/// <summary>Vorschau, Board und Sprint anhalten (ihre Hooks halten den Besitzer).</summary>
procedure StopViews(AServices: TAtlasIdeIssuesServices);
begin
  if AServices.FPreview <> nil then
  begin
    AServices.FPreview.Stop;
    DropRef(AServices, AServices.FPreview);
  end;
  AServices.FPreview := nil;
  if AServices.FBoard <> nil then
  begin
    AServices.FBoard.Stop;
    DropRef(AServices, AServices.FBoard);
  end;
  AServices.FBoard := nil;
  if AServices.FSprint <> nil then
  begin
    AServices.FSprint.Stop;
    DropRef(AServices, AServices.FSprint);
  end;
  AServices.FSprint := nil;
  FreeAndNil(AServices.FSync);
end;

/// <summary>Palettensuche, Kommentare (nach der Vorschau: deren Feld hat den Entwurf gesichert), Meldungen und
/// Anhängen anhalten.</summary>
procedure StopOthers(AServices: TAtlasIdeIssuesServices);
begin
  if AServices.FSearch <> nil then
  begin
    AServices.FSearch.Stop;
  end;
  AServices.FSearch := nil;
  AServices.FSearchRef := nil;
  if AServices.FComments <> nil then
  begin
    AServices.FComments.Stop;
    DropRef(AServices, AServices.FComments);
  end;
  AServices.FComments := nil;
  if AServices.FNotify <> nil then
  begin
    AServices.FNotify.Stop;
    DropRef(AServices, AServices.FNotify);
  end;
  AServices.FNotify := nil;
  if AServices.FAttach <> nil then
  begin
    AServices.FAttach.Stop;
    DropRef(AServices, AServices.FAttach);
  end;
  AServices.FAttach := nil;
end;

{ TAtlasIdeIssuesServices }

constructor TAtlasIdeIssuesServices.Create(AContext: TAtlasIdeIssuesContext);
begin
  inherited Create;
  FContext := AContext;
end;

procedure TAtlasIdeIssuesServices.Keep(const AService: IInterface);
begin
  FRefs := FRefs + [AService];
end;

procedure TAtlasIdeIssuesServices.Start;
var
  mLink: TAtlasIssuesLink;
  mFolder: string;
begin
  mLink := TAtlasIssuesLink.Create(Self);
  mFolder := TAtlasIdeIssuesTargets.IssuesFolder;
  FComments := TAtlasIdeCommentService.Create(CommentHooks(mLink), mFolder);
  Keep(FComments);
  FSync := CreateSync(mLink);
  FTime := CreateTime(mLink);
  Keep(FTime);
  FTime.Start;
  // Anhängen vor der Vorschau: deren Knopf „Anhängen …“ ruft es.
  FAttach := TAtlasIdeIssueAttach.Create(AttachHooks(mLink));
  Keep(FAttach);
  FAttach.Start;
  FPreview := TAtlasIdeIssuePreview.Create(PreviewHooks(mLink), mFolder);
  Keep(FPreview);
  FPreview.Start;
  FBoard := TAtlasIdeBoard.Create(BoardHooks(mLink), mFolder);
  Keep(FBoard);
  FBoard.Start;
  FSprint := TAtlasIdeSprint.Create(SprintHooks(mLink), mFolder);
  Keep(FSprint);
  FSprint.Start;
  FSearch := TAtlasIdeIssueSearch.Create(SearchHooks(mLink));
  FSearchRef := FSearch;
  FNotify := TAtlasIdeIssueNotify.Create(NotifyHooks(mLink), mFolder);
  Keep(FNotify);
  FNotify.Start;
end;

procedure TAtlasIdeIssuesServices.Stop;
begin
  StopTracking(Self);
  StopViews(Self);
  StopOthers(Self);
  FRefs := nil;
end;

procedure TAtlasIdeIssuesServices.Refresh;
begin
  // issues.syncState: Kommentarfeld und „Beenden …“ der Vorschau.
  if FPreview <> nil then
  begin
    FPreview.UpdateWrite;
  end;
  // issues.board aus: Fenster „Atlas-Board“ zu.
  if FBoard <> nil then
  begin
    FBoard.UpdateSettings;
  end;
  // welcomePage.sprint, issues.sprint.*, anderes Projekt.
  if FSprint <> nil then
  begin
    FSprint.Refresh;
  end;
  // issues.notify umgeschaltet, Abstand oder Umfang geändert.
  if FNotify <> nil then
  begin
    FNotify.Refresh;
  end;
end;

function TAtlasIdeIssuesServices.Options: TAtlasIssuesOptions;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := TAtlasIssuesOptions.Create(TAtlasMyIssues.StartOf(mSettings.IssuesStart),
    mSettings.IssuesBranchPattern, mSettings.IssuesBranchBase,
    mSettings.IssuesCommitPattern);
  Result.Preview := mSettings.IssuesPreview and (FPreview <> nil);
end;

function TAtlasIdeIssuesServices.UnseenOf(const ATarget: TAtlasTrackerTarget): TArray<string>;
begin
  Result := nil;
  if FNotify <> nil then
  begin
    Result := FNotify.Unseen(ATarget);
  end;
end;

function TAtlasIdeIssuesServices.NotifyTargets: TArray<TAtlasTrackerTarget>;
var
  mConnection: TAtlasTrackerConnection;
  mTarget: TAtlasTrackerTarget;
begin
  Result := nil;
  if not FContext.Started then
  begin
    Exit;
  end;
  // Der Tracker des aktuellen Projekts, dann die persönlichen Verbindungen (je Server zählt die erste).
  mTarget := FContext.TargetOf(FContext.CurrentProject);
  if mTarget.Server <> '' then
  begin
    Result := Result + [mTarget];
  end;
  for mConnection in TAtlasTrackerConnections.Read(TAtlasIdeSettings.Current.IssuesConnections) do
  begin
    mTarget := mConnection.Target;
    if mTarget.Server <> '' then
    begin
      Result := Result + [mTarget];
    end;
  end;
end;

procedure TAtlasIdeIssuesServices.OpenNotified(const ATarget: TAtlasTrackerTarget; const AKey: string;
  AAnchor: TDateTime);
var
  mProvider: IAtlasTrackerProvider;
begin
  if not FContext.Started then
  begin
    Exit;
  end;
  // Mit issues.preview in „Atlas-Issue“ am ersten neuen Kommentar, sonst im Browser.
  if (FPreview <> nil) and TAtlasIdeIssuePreview.Active then
  begin
    FPreview.Show(ATarget, AKey, AAnchor);
    Exit;
  end;
  mProvider := FContext.ProviderOf(ATarget.Provider);
  if mProvider <> nil then
  begin
    TAtlasIdeIssuesTargets.OpenPage(mProvider.IssuePage(ATarget, AKey));
  end;
end;

function TAtlasIdeIssuesServices.TimeIssueOf(const AProject, AKey: string): TAtlasTimeIssue;
var
  mTarget: TAtlasTrackerTarget;
begin
  Result := TAtlasTimeIssue.None;
  if (AProject = '') or (AKey = '') then
  begin
    Exit;
  end;
  mTarget := FContext.TargetOf(AProject);
  Result := TAtlasTimeIssue.Create(mTarget.Provider, mTarget.Url, mTarget.Project, AKey);
end;

procedure TAtlasIdeIssuesServices.SyncTime(const AProject, AKey: string);
begin
  if FTime <> nil then
  begin
    FTime.SetIssue(TimeIssueOf(AProject, AKey));
  end;
end;

procedure TAtlasIdeIssuesServices.ShowTimeOpen;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      if FContext.Started and (FTime <> nil) and TAtlasIdeTrackerTime.Active then
      begin
        FTime.ShowOpen;
      end;
    end);
end;

function TAtlasIdeIssuesServices.AttachIssues: TArray<string>;
var
  mData: TAtlasIssuesView;
  mIssue: TAtlasTrackerIssue;
begin
  // Die zuletzt abgefragte Liste aus „Meine Issues“, ohne Netz.
  Result := nil;
  if not FContext.Started or (FContext.Actions = nil) then
  begin
    Exit;
  end;
  mData := FContext.Actions.ViewOf(FContext.CurrentProject);
  for mIssue in mData.Items do
  begin
    Result := Result + [Trim(mIssue.Key + ' ' + mIssue.Title)];
  end;
end;

procedure TAtlasIdeIssuesServices.ActiveChanged;
begin
  if FPreview <> nil then
  begin
    FPreview.UpdateWrite;
  end;
  if FBoard <> nil then
  begin
    FBoard.UpdateActive;
  end;
end;

end.
