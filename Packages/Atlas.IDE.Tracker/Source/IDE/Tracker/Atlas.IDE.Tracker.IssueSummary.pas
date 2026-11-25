unit Atlas.IDE.Tracker.IssueSummary;

// „Zusammenfassen“ im Fenster „Atlas-Issue“ (#2462): fragt den KI-Anbieter des
// Moduls KI-Assistenten über den Vertrag Atlas.IDE.Base.Foundation.AiText; der
// Tracker kennt weder Anbieter noch Schlüssel. Ohne das Modul, ohne
// eingerichteten Anbieter oder mit issues.aiSummary aus gibt es weder Knopf
// noch Menüeintrag.
// - Knopf in der Werkzeugleiste ab issues.aiSummary.minComments Kommentaren,
//   im Kontextmenü immer. Nur auf Knopfdruck; vor dem ersten Senden je
//   Tracker-Verbindung ein Hinweis, dass die Inhalte an den Anbieter gehen.
// - Eingabe, Anweisung und Antwort: Atlas.Core.Tracker.AiSummary. Units nur,
//   wenn sie in den Projekten der offenen Gruppe liegen; Klick öffnet sie.
// - Zwischenspeicher je Tracker und Issue in <Zwischenspeicher>\summaries.json;
//   hat sich das Issue seitdem geändert, steht die Karte mit „veraltet“ da.
// - Eine Anfrage zur Zeit; Stop bricht sie ab (danach kommt keine Antwort mehr).
// - In den Tracker geht nichts: „Als Kommentar übernehmen“ füllt nur das
//   Kommentarfeld, gesendet wird mit „Senden“.
// - Protokoll anonym: nie Kennung, Titel, Inhalt oder Anbieter-Antwort.
// Hauptthread.

interface

uses
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Preview,
  Atlas.Core.Tracker.AiSummary,
  Atlas.IDE.Base.Foundation.AiText,
  Atlas.UI.Tracker.IssueFrame,
  Atlas.UI.Tracker.IssueFrame.Types,
  Atlas.IDE.Tracker.IssueContext;

type
  TAtlasIdeIssueSummary = class
  private
    FContext: TAtlasIdeIssueContext;
    FCache: TAtlasIssueSummaryCache;
    /// <summary>Datei des Zwischenspeichers; '' = nur im Speicher.</summary>
    FFile: string;
    FKept: Boolean;
    FLoaded: Boolean;
    /// <summary>Laufende Anfrage: Dienst, Ticket und Issue.</summary>
    FAi: IAtlasAiText;
    FTicket: Integer;
    FEntry: TAtlasIssueHistoryEntry;
    FStamp: string;
    procedure Load;
    procedure Save;
    function ShownFromCache(const AEntry: TAtlasIssueHistoryEntry; const ADetails: TAtlasTrackerDetails):
      TAtlasIssueSummaryShown;
    /// <summary>Hinweis vor dem ersten Senden für ATarget; True, wenn gesendet werden darf.</summary>
    function Consent(const ATarget: TAtlasTrackerTarget; const AProvider: string): Boolean;
    procedure Done(const AResult: TAtlasAiTextResult);
    procedure Show(const AShown: TAtlasIssueSummaryShown);
  public
    /// <summary>ACacheFolder: Ordner des Zwischenspeichers ('' = nur im Speicher).</summary>
    constructor Create(AContext: TAtlasIdeIssueContext; const ACacheFolder: string);
    destructor Destroy; override;
    /// <summary>Text vom KI-Anbieter, wenn das Modul KI-Assistenten läuft und einer eingerichtet ist; sonst nil.
    /// </summary>
    class function AiText: IAtlasAiText; static;
    /// <summary>Zusammenfassen und Unit öffnen in AEvents eintragen.</summary>
    procedure AddEvents(const AKeep: IInterface; var AEvents: TAtlasIssueFrameEvents);
    /// <summary>Nach ShowDetails: Knopf, Menüeintrag und Karte aus dem Zwischenspeicher.</summary>
    procedure Shown(AFrame: TAtlasIssueFrame; const ADetails: TAtlasTrackerDetails);
    /// <summary>Gezeigtes Issue zusammenfassen (Knopf, Kontextmenü, „Neu zusammenfassen“).</summary>
    procedure Summarize;
    procedure OpenUnit(const APath: string);
    /// <summary>Laufende Anfrage abbrechen und den Zwischenspeicher sichern.</summary>
    procedure Stop;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.UITypes,
  Vcl.Dialogs,
  Atlas.Plugin.Files.DataFile,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Contributions,
  Atlas.Plugin.Localization.Strings,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Problems.Files,
  Atlas.UI.Tracker.Issue.Strings;

const
  cCacheFile = 'summaries.json';
  cCacheKind = 'Zusammenfassungen'; // german-ok Protokoll

{ TAtlasIdeIssueSummary }

constructor TAtlasIdeIssueSummary.Create(AContext: TAtlasIdeIssueContext; const ACacheFolder: string);
begin
  inherited Create;
  FContext := AContext;
  FCache := TAtlasIssueSummaryCache.Create;
  FFile := '';
  if ACacheFolder <> '' then
  begin
    FFile := TPath.Combine(ACacheFolder, cCacheFile);
  end;
end;

destructor TAtlasIdeIssueSummary.Destroy;
begin
  Stop;
  FCache.Free;
  inherited Destroy;
end;

class function TAtlasIdeIssueSummary.AiText: IAtlasAiText;
var
  mItem: IInterface;
begin
  Result := nil;
  for mItem in TAtlasModuleContributions.Active(AtlasModuleRegistry, IAtlasAiText) do
  begin
    if Supports(mItem, IAtlasAiText, Result) and Result.Ready then
    begin
      Exit;
    end;
  end;
  Result := nil;
end;

procedure TAtlasIdeIssueSummary.Load;
var
  mLoad: TAtlasDataLoad;
  mCache: TAtlasIssueSummaryCache;
begin
  // Erst beim ersten Bedarf: Das Fenster öffnet ohne Plattenzugriff.
  if FLoaded then
  begin
    Exit;
  end;
  FLoaded := True;
  if FFile = '' then
  begin
    Exit;
  end;
  mCache := FCache;
  mLoad := TAtlasDataFile.Load(FFile, cCacheKind,
    function(const AText: string): Boolean
    begin
      Result := mCache.LoadJson(AText);
    end);
  FKept := not TAtlasDataFile.Writable(mLoad);
  FCache.MarkSaved;
end;

procedure TAtlasIdeIssueSummary.Save;
begin
  if (FFile = '') or FKept or not FCache.Changed then
  begin
    Exit;
  end;
  try
    TAtlasDataFile.Write(FFile, FCache.ToJson);
    FCache.MarkSaved;
  except
    on E: Exception do
      TAtlasDataFile.ReportNotWritten(cCacheKind, E);
  end;
end;

procedure TAtlasIdeIssueSummary.AddEvents(const AKeep: IInterface; var AEvents: TAtlasIssueFrameEvents);
var
  mKeep: IInterface;
  mOwner: TAtlasIdeIssueSummary;
begin
  mKeep := AKeep;
  mOwner := Self;
  AEvents.Summarize :=
    procedure
    begin
      if mKeep <> nil then
      begin
        mOwner.Summarize;
      end;
    end;
  AEvents.OpenUnit :=
    procedure(APath: string)
    begin
      if mKeep <> nil then
      begin
        mOwner.OpenUnit(APath);
      end;
    end;
end;

function TAtlasIdeIssueSummary.ShownFromCache(const AEntry: TAtlasIssueHistoryEntry;
  const ADetails: TAtlasTrackerDetails): TAtlasIssueSummaryShown;
var
  mFilesKey: string;
begin
  Result := Default(TAtlasIssueSummaryShown);
  Result.Key := ADetails.Key;
  if (FTicket > 0) and FEntry.SameAs(AEntry) then
  begin
    // Läuft noch: Die Karte bleibt bei „Wird zusammengefasst …“.
    Result.Kind := TAtlasIssueSummaryKind.Running;
    if FAi <> nil then
    begin
      Result.Text := FAi.ProviderName;
    end;
    Exit;
  end;
  if FCache.Find(TAtlasIssueSummaryCache.KeyOf(AEntry.Target, ADetails.Key), TAtlasIssueSummaries.StampOf(ADetails),
    Result.Summary, Result.Stale) then
  begin
    Result.Kind := TAtlasIssueSummaryKind.Ready;
    Result.Units := TAtlasIssueSummaries.KnownUnits(Result.Summary.Units, TAtlasIdeProblemFiles.GroupFiles(mFilesKey));
  end;
end;

procedure TAtlasIdeIssueSummary.Shown(AFrame: TAtlasIssueFrame; const ADetails: TAtlasTrackerDetails);
var
  mCan: Boolean;
  mShown: TAtlasIssueSummaryShown;
begin
  mCan := TAtlasIdeSettings.Current.IssuesAiSummary and FContext.HasCurrent and (AiText <> nil);
  AFrame.SetFlag(TAtlasIssueFlag.CanSummarize, mCan);
  AFrame.SetFlag(TAtlasIssueFlag.SummaryButton, mCan and TAtlasIssueSummaries.ShowButton(Length(ADetails.Comments),
    TAtlasIdeSettings.Current.IssuesAiSummaryMinComments));
  mShown := Default(TAtlasIssueSummaryShown);
  if mCan or (FTicket > 0) then
  begin
    Load;
    mShown := ShownFromCache(FContext.Current, ADetails);
  end;
  // Neu bauen nur, wenn sich an der Karte etwas ändert.
  if (mShown.Kind <> TAtlasIssueSummaryKind.None) or (AFrame.State.Summary.Kind <> TAtlasIssueSummaryKind.None) then
  begin
    AFrame.ShowSummary(mShown);
  end;
end;

function TAtlasIdeIssueSummary.Consent(const ATarget: TAtlasTrackerTarget; const AProvider: string): Boolean;
begin
  Load;
  Result := FCache.Acknowledged(ATarget.Key);
  if Result then
  begin
    Exit;
  end;
  Result := MessageDlg(TAtlasIssueStrings.Fmt(TAtlasIssueTextId.IssueSummaryConsent, [AProvider,
    sLineBreak + sLineBreak]), mtConfirmation, [mbYes, mbNo], 0) = mrYes;
  if Result then
  begin
    FCache.Acknowledge(ATarget.Key);
    Save;
  end;
end;

/// <summary>Sprache der Antwort wie die der Oberfläche.</summary>
function AnswerLanguage: string;
begin
  Result := 'German';
  if TAtlasStrings.Language = TAtlasLanguage.English then
  begin
    Result := 'English';
  end;
end;

procedure TAtlasIdeIssueSummary.Summarize;
var
  mFrame: TAtlasIssueFrame;
  mAi: IAtlasAiText;
  mRequest: TAtlasAiTextRequest;
  mShown: TAtlasIssueSummaryShown;
  mOwner: TAtlasIdeIssueSummary;
  mDetails: TAtlasTrackerDetails;
begin
  mFrame := FContext.Frame;
  mAi := AiText;
  if (mFrame = nil) or not mFrame.State.HasDetails or not FContext.HasCurrent or (mAi = nil) or
    not TAtlasIdeSettings.Current.IssuesAiSummary then
  begin
    Exit;
  end;
  mDetails := mFrame.State.Details;
  if not Consent(FContext.Current.Target, mAi.ProviderName) then
  begin
    Exit;
  end;
  Stop;
  FAi := mAi;
  FEntry := FContext.Current;
  FStamp := TAtlasIssueSummaries.StampOf(mDetails);
  mRequest := Default(TAtlasAiTextRequest);
  mRequest.Instructions := TAtlasIssueSummaries.Instructions(AnswerLanguage);
  mRequest.Task := TAtlasIssueSummaries.Input(mDetails, TAtlasIssueSummaries.cMaxInput);
  mRequest.MaxTokens := TAtlasIssueSummaries.cMaxTokens;
  mShown := Default(TAtlasIssueSummaryShown);
  mShown.Kind := TAtlasIssueSummaryKind.Running;
  mShown.Key := mDetails.Key;
  mShown.Text := mAi.ProviderName;
  mFrame.ShowSummary(mShown);
  mOwner := Self;
  // Ask kann ADone sofort rufen (nicht bereit, Ticket 0): Done setzt FTicket dann selbst zurück.
  FTicket := mAi.Ask(mRequest,
    procedure(const AResult: TAtlasAiTextResult)
    begin
      mOwner.Done(AResult);
    end);
end;

procedure TAtlasIdeIssueSummary.Done(const AResult: TAtlasAiTextResult);
var
  mShown: TAtlasIssueSummaryShown;
  mFilesKey: string;
begin
  FTicket := 0;
  FAi := nil;
  mShown := Default(TAtlasIssueSummaryShown);
  mShown.Key := FEntry.Key;
  case AResult.Status of
    TAtlasAiTextStatus.Ok:
      begin
        if TAtlasIssueSummaries.TryParse(AResult.Text, mShown.Summary) then
        begin
          FCache.Put(TAtlasIssueSummaryCache.KeyOf(FEntry.Target, FEntry.Key), FStamp, mShown.Summary);
          Save;
          mShown.Kind := TAtlasIssueSummaryKind.Ready;
          mShown.Units := TAtlasIssueSummaries.KnownUnits(mShown.Summary.Units,
            TAtlasIdeProblemFiles.GroupFiles(mFilesKey));
        end
        else
        begin
          mShown.Kind := TAtlasIssueSummaryKind.Failed;
          mShown.Text := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssueSummaryUnreadable);
        end;
      end;
    TAtlasAiTextStatus.Failed:
      begin
        mShown.Kind := TAtlasIssueSummaryKind.Failed;
        mShown.Text := AResult.Error;
      end;
    TAtlasAiTextStatus.Cancelled, TAtlasAiTextStatus.NotReady:
      begin
        // Abgebrochen bzw. Anbieter weg: Karte weg.
      end;
  end;
  Show(mShown);
end;

/// <summary>AShown zeigen, wenn das Fenster noch das Issue der Anfrage zeigt.</summary>
procedure TAtlasIdeIssueSummary.Show(const AShown: TAtlasIssueSummaryShown);
var
  mFrame: TAtlasIssueFrame;
begin
  mFrame := FContext.Frame;
  if (mFrame <> nil) and FContext.HasCurrent and FContext.Current.SameAs(FEntry) then
  begin
    mFrame.ShowSummary(AShown);
  end;
end;

procedure TAtlasIdeIssueSummary.OpenUnit(const APath: string);
begin
  if (APath <> '') and FileExists(APath) then
  begin
    TAtlasIdeNavigation.GoToLocation(APath, 0, 0);
  end;
end;

procedure TAtlasIdeIssueSummary.Stop;
begin
  if (FTicket > 0) and (FAi <> nil) then
  begin
    FAi.Cancel(FTicket);
  end;
  FTicket := 0;
  FAi := nil;
  Save;
end;

end.
