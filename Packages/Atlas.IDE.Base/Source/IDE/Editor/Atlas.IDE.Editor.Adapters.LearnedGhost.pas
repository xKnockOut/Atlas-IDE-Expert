unit Atlas.IDE.Editor.Adapters.LearnedGhost;

// Gelernte Vorschläge (#1890) als Anbieter des Schattentexts (IAtlasGhostProvider aus
// Atlas.IDE.Contracts.GhostSuggestions): schickt Puffer, Schwellen und Zuschläge aus den Lernzählern an den Server
// (atlas.server.suggestNext) und meldet angenommene und abgelehnte Vorschläge an die Lernzähler. Sitzung und
// Lernzähler hält Atlas.IDE.Editor.LearnedSuggestions; erzeugt nur die Kompositionswurzel. Prepare im
// Hauptthread, die Arbeit danach im Hintergrund.

interface

uses
  Atlas.IDE.Contracts.GhostSuggestions;

type
  /// <summary>Vorschlag aus dem Index des Servers für den Schattentext (#1890).</summary>
  TAtlasLearnedGhostProvider = class(TInterfacedObject, IAtlasGhostProvider)
  public
    function Enabled: Boolean;
    function Prepare(const AContext: TAtlasGhostContext): TAtlasGhostWork;
    procedure Accepted(const AProposal: TAtlasGhostProposal);
    procedure Rejected(const AProposal: TAtlasGhostProposal);
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.Uris,
  Atlas.Core.Editor.LearnedSuggestions,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Editor.LearnedSuggestions;

{ TAtlasLearnedGhostProvider }

function TAtlasLearnedGhostProvider.Enabled: Boolean;
begin
  Result := TAtlasIdeLearnedSuggestions.Enabled;
end;

function TAtlasLearnedGhostProvider.Prepare(const AContext: TAtlasGhostContext): TAtlasGhostWork;
var
  mSession: TLspSession;
  mArguments: string;
  mRequest: TAtlasLearnedRequest;
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
  mRequest.Uri := TLspUris.FromPath(AContext.FileName);
  mRequest.Line := AContext.Line;
  mRequest.TabSize := AContext.TabSize;
  mRequest.InsertSpaces := AContext.InsertSpaces;
  mRequest.MinCount := mSettings.SuggestionsMinCount;
  mRequest.MinShare := mSettings.SuggestionsMinShare;
  mRequest.Adjust := TAtlasIdeLearnedSuggestions.Usage.AdjustList(mSettings.SuggestionsLearnFromUsage);
  mArguments := TAtlasLearnedSuggestions.SuggestArguments(mRequest);
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

procedure TAtlasLearnedGhostProvider.Accepted(const AProposal: TAtlasGhostProposal);
begin
  TAtlasIdeLearnedSuggestions.Accepted(AProposal.Id);
end;

procedure TAtlasLearnedGhostProvider.Rejected(const AProposal: TAtlasGhostProposal);
begin
  TAtlasIdeLearnedSuggestions.Rejected(AProposal.Id);
end;

end.
