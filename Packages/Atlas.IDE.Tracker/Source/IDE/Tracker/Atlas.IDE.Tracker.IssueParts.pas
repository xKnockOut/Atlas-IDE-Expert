unit Atlas.IDE.Tracker.IssueParts;

// Teile des Fensters „Atlas-Issue“ (#1264): gemeinsamer Kontext, Kurzabfrage
// für den Hover (#1265), Checklisten (#1273), Verknüpfungen (#1279), Bilder
// und Anhänge, Kommentare (#1278) und der Reiter „Entwicklung“ (#1269).
// Legt sie an und gibt sie frei; die Vorschau (Atlas.IDE.Tracker.IssuePreview)
// und das Laden (Atlas.IDE.Tracker.IssueLoad) arbeiten mit ihnen.

interface

uses
  System.SysUtils,
  Atlas.Core.Tracker.Preview,
  Atlas.IDE.Tracker.Development,
  Atlas.IDE.Tracker.IssueContext,
  Atlas.IDE.Tracker.IssueLookups,
  Atlas.IDE.Tracker.IssueChecklists,
  Atlas.IDE.Tracker.IssueLinkWrites,
  Atlas.IDE.Tracker.IssueMedia,
  Atlas.IDE.Tracker.IssueComments;

type
  /// <summary>Was die Teile von außen brauchen.</summary>
  TAtlasIssuePartsHooks = record
    Provider: TAtlasIssuePreviewProviderHook;
    Transport: TAtlasIssuePreviewTransportHook;
    Comments: TAtlasIssueCommentHooks;
    /// <summary>Projektdatei des aktuellen Projekts für den Reiter „Entwicklung“ ('' ohne).</summary>
    Project: TFunc<string>;
    /// <summary>Issue neu laden (Checkliste nach einem abgewiesenen Abhaken).</summary>
    Reload: TProc<TAtlasIssueHistoryEntry>;
    /// <summary>Gezeigtes Issue neu laden (nach Verknüpfen bzw. Kommentieren).</summary>
    Refresh: TProc;
  end;

  TAtlasIdeIssueParts = class
  private
    FContext: TAtlasIdeIssueContext;
    FLookups: TAtlasIdeIssueLookups;
    FChecklists: TAtlasIdeIssueChecklists;
    FLinkWrites: TAtlasIdeIssueLinkWrites;
    FMedia: TAtlasIdeIssueMedia;
    FComments: TAtlasIdeIssueComments;
    FDevelopment: TAtlasIdeIssueDevelopment;
    FDevelopmentRef: IInterface;
    procedure CreateDevelopment(const AProject: TFunc<string>);
  public
    /// <summary>AOwner hält die Teile am Leben, solange ein Rückruf ihn fängt (TAtlasIdeIssueContext.Keep);
    /// ACacheFolder: Ordner des Zwischenspeichers ('' = nur im Speicher).</summary>
    constructor Create(AOwner: TInterfacedObject; const AHooks: TAtlasIssuePartsHooks; const ACacheFolder: string);
    /// <summary>Hält die Entwicklung an und gibt alle Teile frei; vorher die Threads abgeben
    /// (TAtlasIdeIssueLoad.ReleaseThreads).</summary>
    destructor Destroy; override;
    property Context: TAtlasIdeIssueContext read FContext;
    property Lookups: TAtlasIdeIssueLookups read FLookups;
    property Checklists: TAtlasIdeIssueChecklists read FChecklists;
    property LinkWrites: TAtlasIdeIssueLinkWrites read FLinkWrites;
    property Media: TAtlasIdeIssueMedia read FMedia;
    property Comments: TAtlasIdeIssueComments read FComments;
    property Development: TAtlasIdeIssueDevelopment read FDevelopment;
  end;

implementation

uses
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.UI.Tracker.IssueFrame;

{ TAtlasIdeIssueParts }

constructor TAtlasIdeIssueParts.Create(AOwner: TInterfacedObject; const AHooks: TAtlasIssuePartsHooks;
  const ACacheFolder: string);
begin
  inherited Create;
  FContext := TAtlasIdeIssueContext.Create(AOwner, AHooks.Provider, AHooks.Transport, ACacheFolder);
  FLookups := TAtlasIdeIssueLookups.Create(FContext);
  FChecklists := TAtlasIdeIssueChecklists.Create(FContext, AHooks.Reload);
  FLinkWrites := TAtlasIdeIssueLinkWrites.Create(FContext, AHooks.Refresh);
  FMedia := TAtlasIdeIssueMedia.Create(FContext);
  FComments := TAtlasIdeIssueComments.Create(FContext, AHooks.Comments, AHooks.Refresh);
  CreateDevelopment(AHooks.Project);
end;

destructor TAtlasIdeIssueParts.Destroy;
begin
  if FDevelopment <> nil then
  begin
    FDevelopment.Stop;
  end;
  FDevelopment := nil;
  FDevelopmentRef := nil;
  FComments.Free;
  FMedia.Free;
  FLinkWrites.Free;
  FChecklists.Free;
  FLookups.Free;
  FContext.Free;
  inherited;
end;

procedure TAtlasIdeIssueParts.CreateDevelopment(const AProject: TFunc<string>);
var
  mHooks: TAtlasIssueDevelopmentHooks;
  mContext: TAtlasIdeIssueContext;
  mProject: TFunc<string>;
begin
  // Eigene Routine: Die anonymen Methoden halten nur den Kontext und den Hook. Stop der Entwicklung löst sie wieder.
  mContext := FContext;
  mProject := AProject;
  mHooks := Default(TAtlasIssueDevelopmentHooks);
  mHooks.Provider :=
    function(const ATarget: TAtlasTrackerTarget): IAtlasTrackerProvider
    begin
      Result := mContext.ProviderOf(ATarget);
    end;
  mHooks.Transport :=
    function(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): IAtlasCiTransport
    begin
      Result := mContext.TransportOf(AProvider, ATarget);
    end;
  mHooks.Project :=
    function: string
    begin
      Result := '';
      if Assigned(mProject) then
      begin
        Result := mProject();
      end;
    end;
  mHooks.Browse :=
    procedure(AUrl: string)
    begin
      TAtlasIssuePreview.Browse(AUrl);
    end;
  mHooks.Frame :=
    function: TAtlasIssueFrame
    begin
      Result := mContext.Frame;
    end;
  FDevelopment := TAtlasIdeIssueDevelopment.Create(mHooks);
  FDevelopmentRef := FDevelopment;
end;

end.
