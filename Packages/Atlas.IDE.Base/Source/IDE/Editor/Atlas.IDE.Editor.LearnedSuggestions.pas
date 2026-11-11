unit Atlas.IDE.Editor.LearnedSuggestions;

// Gelernte Vorschläge (#1890) in der IDE: der Anbieter für die Schattentext-
// Vorschläge (Atlas.IDE.Editor.GhostSuggestions), die Lernzähler und der
// Befehl „Gelernte Vorschläge anzeigen …“.
// - Was folgt, rechnet der Server aus dem Index (atlas.server.suggestNext);
//   das Plugin schickt den Puffer, die Schwellen suggestions.minCount und
//   suggestions.minShare und die Zuschläge aus den Lernzählern.
// - Lernzähler (TAtlasLearnedUsage) je Projektgruppe in
//   %LOCALAPPDATA%\Atlas\learned-suggestions.json, gelesen beim Start und
//   geschrieben nach jeder Änderung (TAtlasDataFile). Ohne
//   suggestions.learnFromUsage zählt Atlas nicht, abgeschaltete Muster bleiben
//   aus.
// - Die Liste holt atlas.server.learnedPatterns im Hintergrund und zeigt sie
//   modal (Atlas.UI.Editor.LearnedSuggestions).
// Nur im Hauptthread, außer der Arbeit des Anbieters.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Lsp.BackgroundRequest,
  Atlas.Core.Editor.LearnedSuggestions,
  Atlas.Core.Editor.LearnedUsage,
  Atlas.IDE.Contracts.GhostSuggestions;

type
  TAtlasIdeLearnedSuggestions = class
  private class var
    FSessionOf: TFunc<TLspSession>;
    FMessage: TProc<string>;
    FUsage: TAtlasLearnedUsage;
    FProvider: IAtlasGhostProvider;
    FListRequest: TAtlasBackgroundRequest;
    /// <summary>Datei nicht lesbar: nicht überschreiben.</summary>
    FKept: Boolean;
    class function Session: TLspSession; static;
    class function UsageFile: string; static;
    class procedure Load; static;
    class procedure Save; static;
    class procedure ShowList(const APatterns: TArray<TAtlasLearnedPattern>); static;
  public
    /// <summary>Meldet den Anbieter an. ASessionOf liefert die laufende Sitzung oder nil; AMessage meldet, wenn die
    /// Liste nicht verfügbar ist.</summary>
    class procedure Install(const ASessionOf: TFunc<TLspSession>; const AMessage: TProc<string>); static;
    class procedure Uninstall; static;
    /// <summary>Atlas an und suggestions.learned an?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Lernzähler; nil vor Install.</summary>
    class function Usage: TAtlasLearnedUsage; static;
    /// <summary>Projektgruppe für die Lernzähler setzen (Pfad der .groupproj, sonst des Projekts).</summary>
    class procedure UpdateGroup; static;
    /// <summary>Befehl „Gelernte Vorschläge anzeigen …“.</summary>
    class procedure ShowPatterns; static;
    /// <summary>Vorschlag aus der Antwort des Servers.</summary>
    class function ProposalOf(const ASuggestion: TAtlasLearnedSuggestion): TAtlasGhostProposal; static;
    class procedure Accepted(const AId: string); static;
    class procedure Rejected(const AId: string); static;
  end;

implementation

uses
  System.IOUtils,
  System.JSON,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.Uris,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Navigation,
  Atlas.UI.Editor.LearnedSuggestions;

const
  cUsageFile = 'learned-suggestions.json';
  cUsageKind = 'Gelernte Vorschläge'; // german-ok Protokoll

type
  TLearnedProvider = class(TInterfacedObject, IAtlasGhostProvider)
  public
    function Enabled: Boolean;
    function Prepare(const AContext: TAtlasGhostContext): TAtlasGhostWork;
    procedure Accepted(const AProposal: TAtlasGhostProposal);
    procedure Rejected(const AProposal: TAtlasGhostProposal);
  end;

{ TLearnedProvider }

function TLearnedProvider.Enabled: Boolean;
begin
  Result := TAtlasIdeLearnedSuggestions.Enabled;
end;

function TLearnedProvider.Prepare(const AContext: TAtlasGhostContext): TAtlasGhostWork;
var
  mSession: TLspSession;
  mArguments: string;
  mLine: Integer;
  mSettings: TAtlasPluginSettings;
begin
  Result := nil;
  mSession := TAtlasIdeLearnedSuggestions.Session;
  if (mSession = nil) or not mSession.Initialized or (TAtlasIdeLearnedSuggestions.Usage = nil) then
  begin
    Exit;
  end;
  TAtlasIdeLearnedSuggestions.UpdateGroup;
  mSettings := TAtlasIdeSettings.Current;
  // Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  mSession.Sync(AContext.FileName, AContext.Text);
  mArguments := TAtlasLearnedSuggestions.SuggestArguments(TLspUris.FromPath(AContext.FileName), AContext.Line,
    AContext.TabSize, AContext.InsertSpaces, mSettings.SuggestionsMinCount, mSettings.SuggestionsMinShare,
    TAtlasIdeLearnedSuggestions.Usage.AdjustList(mSettings.SuggestionsLearnFromUsage));
  mLine := AContext.Line;
  Result :=
    function(out AProposal: TAtlasGhostProposal): Boolean
    var
      mValue: TJSONValue;
      mSuggestion: TAtlasLearnedSuggestion;
    begin
      AProposal := Default(TAtlasGhostProposal);
      try
        mValue := mSession.RunCommand(TAtlasLearnedSuggestions.cSuggestCommand, mArguments,
          TAtlasLearnedSuggestions.cTimeoutMs);
      except
        // Zeitlimit oder Fehler beim Tippen: kein Vorschlag, keine Meldung.
        on ELspClientError do
          Exit(False);
      end;
      try
        Result := TAtlasLearnedSuggestions.ReadSuggestion(mValue, mLine, mSuggestion);
      finally
        mValue.Free;
      end;
      if Result then
      begin
        AProposal := TAtlasIdeLearnedSuggestions.ProposalOf(mSuggestion);
      end;
    end;
end;

procedure TLearnedProvider.Accepted(const AProposal: TAtlasGhostProposal);
begin
  TAtlasIdeLearnedSuggestions.Accepted(AProposal.Id);
end;

procedure TLearnedProvider.Rejected(const AProposal: TAtlasGhostProposal);
begin
  TAtlasIdeLearnedSuggestions.Rejected(AProposal.Id);
end;

{ TAtlasIdeLearnedSuggestions }

class procedure TAtlasIdeLearnedSuggestions.Install(const ASessionOf: TFunc<TLspSession>;
  const AMessage: TProc<string>);
begin
  FSessionOf := ASessionOf;
  FMessage := AMessage;
  if FUsage = nil then
  begin
    FUsage := TAtlasLearnedUsage.Create;
    Load;
  end;
  if FListRequest = nil then
  begin
    FListRequest := TAtlasBackgroundRequest.Create(TAtlasFeature.LearnedSuggestions);
  end;
  if FProvider = nil then
  begin
    FProvider := TLearnedProvider.Create;
    TAtlasGhostProviders.Add(FProvider);
  end;
end;

class procedure TAtlasIdeLearnedSuggestions.Uninstall;
begin
  if FProvider <> nil then
  begin
    TAtlasGhostProviders.Remove(FProvider);
    FProvider := nil;
  end;
  FreeAndNil(FListRequest);
  FreeAndNil(FUsage);
  FSessionOf := nil;
  FMessage := nil;
end;

class function TAtlasIdeLearnedSuggestions.Enabled: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Enabled and TAtlasIdeSettings.Current.SuggestionsLearned;
end;

class function TAtlasIdeLearnedSuggestions.Usage: TAtlasLearnedUsage;
begin
  Result := FUsage;
end;

class function TAtlasIdeLearnedSuggestions.Session: TLspSession;
begin
  Result := nil;
  if Assigned(FSessionOf) then
  begin
    Result := FSessionOf();
  end;
end;

class function TAtlasIdeLearnedSuggestions.UsageFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), cUsageFile);
end;

class procedure TAtlasIdeLearnedSuggestions.Load;
var
  mLoad: TAtlasDataLoad;
begin
  mLoad := TAtlasDataFile.Load(UsageFile, cUsageKind,
    function(const AText: string): Boolean
    begin
      Result := FUsage.FromJson(AText);
    end);
  FKept := not TAtlasDataFile.Writable(mLoad);
  if mLoad <> TAtlasDataLoad.Loaded then
  begin
    FUsage.Clear;
  end;
  FUsage.MarkSaved;
end;

class procedure TAtlasIdeLearnedSuggestions.Save;
begin
  if (FUsage = nil) or FKept or not FUsage.Changed then
  begin
    Exit;
  end;
  try
    TAtlasDataFile.Write(UsageFile, FUsage.ToJson);
    FUsage.MarkSaved;
  except
    on E: Exception do
      TAtlasDataFile.ReportNotWritten(cUsageKind, E);
  end;
end;

class procedure TAtlasIdeLearnedSuggestions.UpdateGroup;
var
  mServices: IOTAModuleServices;
  mGroup: IOTAProjectGroup;
  mProject: IOTAProject;
begin
  if (FUsage = nil) or not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  mGroup := mServices.MainProjectGroup;
  if mGroup <> nil then
  begin
    FUsage.SetGroup(mGroup.FileName);
    Exit;
  end;
  mProject := GetActiveProject;
  if mProject <> nil then
  begin
    FUsage.SetGroup(mProject.FileName);
  end
  else
  begin
    FUsage.SetGroup('');
  end;
end;

class procedure TAtlasIdeLearnedSuggestions.Accepted(const AId: string);
begin
  if (FUsage <> nil) and TAtlasIdeSettings.Current.SuggestionsLearnFromUsage then
  begin
    UpdateGroup;
    FUsage.Accepted(AId);
    Save;
  end;
end;

class procedure TAtlasIdeLearnedSuggestions.Rejected(const AId: string);
begin
  if (FUsage <> nil) and TAtlasIdeSettings.Current.SuggestionsLearnFromUsage then
  begin
    UpdateGroup;
    FUsage.Rejected(AId);
    Save;
  end;
end;

class function TAtlasIdeLearnedSuggestions.ProposalOf(const ASuggestion: TAtlasLearnedSuggestion):
  TAtlasGhostProposal;
var
  mEvidence: TAtlasLearnedEvidence;
  mLocation: TAtlasGhostLocation;
begin
  Result := Default(TAtlasGhostProposal);
  Result.Id := ASuggestion.Pattern.Id;
  Result.Lines := ASuggestion.Lines;
  Result.CursorLine := ASuggestion.CursorLine;
  Result.CursorCharacter := ASuggestion.CursorCharacter;
  Result.StatusText := TAtlasLearnedSuggestions.StatusText(ASuggestion.Pattern);
  Result.Hint := TAtlasLearnedSuggestions.HintText(ASuggestion.Pattern);
  for mEvidence in ASuggestion.Pattern.Evidence do
  begin
    mLocation.FileName := mEvidence.FileName;
    mLocation.Line := mEvidence.Line;
    Result.Locations := Result.Locations + [mLocation];
  end;
end;

class procedure TAtlasIdeLearnedSuggestions.ShowPatterns;
var
  mSession: TLspSession;
  mArguments: string;
  mPatterns: TArray<TAtlasLearnedPattern>;
  mProject: IOTAProject;
begin
  mSession := Session;
  if (mSession = nil) or not mSession.Initialized or (FListRequest = nil) or FListRequest.Busy then
  begin
    if Assigned(FMessage) then
    begin
      FMessage(TAtlasLearnedTexts.Text(TAtlasLearnedText.NoServer));
    end;
    Exit;
  end;
  UpdateGroup;
  mProject := GetActiveProject;
  mArguments := '[]';
  if mProject <> nil then
  begin
    mArguments := TAtlasLearnedSuggestions.ListArguments(TLspUris.FromPath(mProject.FileName));
  end;
  mPatterns := nil;
  FListRequest.Start(
    procedure
    var
      mValue: TJSONValue;
    begin
      mValue := mSession.RunCommand(TAtlasLearnedSuggestions.cListCommand, mArguments,
        TAtlasLearnedSuggestions.cListTimeoutMs);
      try
        mPatterns := TAtlasLearnedSuggestions.ReadList(mValue);
      finally
        mValue.Free;
      end;
    end,
    procedure(AOk: Boolean; const AError: string)
    begin
      if AOk then
      begin
        ShowList(mPatterns);
      end
      else if Assigned(FMessage) then
      begin
        FMessage(TAtlasLearnedTexts.Text(TAtlasLearnedText.NoServer));
      end;
    end);
end;

/// <summary>Zeile der Liste für APattern mit den Lernzählern aus AUsage.</summary>
function ListItemOf(AUsage: TAtlasLearnedUsage; const APattern: TAtlasLearnedPattern): TAtlasLearnedListItem;
begin
  Result.Pattern := APattern;
  Result.On_ := not AUsage.IsOff(APattern.Id);
  AUsage.Counts(APattern.Id, Result.Accepted, Result.Rejected);
end;

class procedure TAtlasIdeLearnedSuggestions.ShowList(const APatterns: TArray<TAtlasLearnedPattern>);
var
  mItems: TArray<TAtlasLearnedListItem>;
  mPattern: TAtlasLearnedPattern;
  mEvents: TAtlasLearnedListEvents;
  mList: TArray<TAtlasLearnedPattern>;
begin
  if FUsage = nil then
  begin
    Exit;
  end;
  mItems := nil;
  for mPattern in APatterns do
  begin
    mItems := mItems + [ListItemOf(FUsage, mPattern)];
  end;
  mList := APatterns;
  mEvents.Toggle :=
    procedure(AIndex: Integer; AOn: Boolean)
    begin
      FUsage.SetOff(mList[AIndex].Id, not AOn);
      Save;
    end;
  mEvents.Forget :=
    function(AIndex: Integer): TAtlasLearnedListItem
    begin
      FUsage.Forget(mList[AIndex].Id);
      Save;
      Result := ListItemOf(FUsage, mList[AIndex]);
    end;
  mEvents.GoTo_ :=
    procedure(AIndex: Integer)
    begin
      TAtlasIdeNavigation.GoToLocation(mList[AIndex].Evidence[0].FileName, mList[AIndex].Evidence[0].Line, 0);
    end;
  TAtlasLearnedList.Execute(mItems, mEvents);
end;

end.
