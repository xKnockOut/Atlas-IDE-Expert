unit Atlas.IDE.Assistants.Adapters.IdeProviders;

// Adapter über ToolsAPI.AI (Smart CodeInsight, ab Delphi 12.2) für die KI-Anbieter der IDE (#2744): Liste mit
// Status und Funktionen, Anweisung und Chat an einen Anbieter, Abbruch. Die IDE antwortet asynchron über einen
// Notifier je Anbieter; er reicht Kennung und Text über TAtlasMainThread an den Rückruf weiter, den die
// Komposition beim Anlegen übergibt (TAtlasIdeAiTextRequests.Answered/Failed).
// - Notifier hängen erst an einem Anbieter, wenn Atlas ihn das erste Mal fragt; Stop nimmt sie alle wieder ab
//   (RemoveNotifier) und trennt den Rückruf: Danach erreicht keine Antwort der IDE mehr das Modul (Regel 3).
// - Der Notifier hört alle Antworten des Anbieters, auch auf Anfragen anderer; fremde Kennungen verwirft der
//   Empfänger.
// - Ohne ToolsAPI.AI (Delphi 12.0/12.1) ist die Liste leer und keine Anfrage geht hinaus.
// - „Smart CodeInsight öffnen“: im offenen Optionsdialog den Knoten wählen, sonst Tools › Optionen auf dieser
//   Seite öffnen.

interface

{$IF Declared(RTLVersion122) or (CompilerVersion >= 37.0)}
  {$DEFINE ATLAS_TOOLSAPI_AI}
{$IFEND}

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Assistants.Contract.IdeAi;

type
  /// <summary>Antwort der IDE zur Kennung AId: Text oder Fehlermeldung. Im Hauptthread.</summary>
  TAtlasIdeAiReply = reference to procedure(const AId, AText: string; AIsError: Boolean);

  /// <summary>Verbindung der Notifier zum Rückruf; nach Cut kommt nichts mehr an.</summary>
  IAtlasIdeAiReplyLink = interface
    ['{0E7B6C25-93A1-4D58-B2F4-6C8A1E3D9F70}']
    procedure Reply(const AId, AText: string; AIsError: Boolean);
    procedure Cut;
  end;

  TAtlasIdeAiEngine = class(TInterfacedObject, IAtlasIdeAiEngine)
  private
    FLink: IAtlasIdeAiReplyLink;
    /// <summary>Name des Anbieters → Index seines Notifiers.</summary>
    FListening: TDictionary<string, Integer>;
    procedure Listen(const AName: string);
  public
    constructor Create(const AReply: TAtlasIdeAiReply);
    destructor Destroy; override;
    /// <summary>Notifier abnehmen, Rückruf trennen.</summary>
    procedure Stop;
    function Providers: TArray<TAtlasIdeAiProvider>;
    function Instruction(const AName, AInput, AInstruction: string): string;
    function Chat(const AName, AQuestion: string): string;
    procedure Cancel(const AName: string);
    /// <summary>Anbieter der IDE ohne laufende Anfragen (Einstellungsseite).</summary>
    class function List: TArray<TAtlasIdeAiProvider>; static;
    /// <summary>Seite „Smart CodeInsight“ der IDE-Optionen zeigen; False, wenn es nicht ging.</summary>
    class function OpenOptions: Boolean; static;
  end;

implementation

uses
  System.Classes,
  Vcl.Forms,
  Vcl.ComCtrls,
  ToolsAPI,
{$IFDEF ATLAS_TOOLSAPI_AI}
  ToolsAPI.AI,
{$ENDIF}
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.Plugin.Diagnostics.MainThread,
  Atlas.IDE.Settings.OptionsDialog;

const
  /// <summary>Beschriftung der Seite in Tools › Optionen.</summary>
  cOptionsPage = 'Smart CodeInsight';

type
  TReplyLink = class(TInterfacedObject, IAtlasIdeAiReplyLink)
  private
    FReply: TAtlasIdeAiReply;
  public
    constructor Create(const AReply: TAtlasIdeAiReply);
    procedure Reply(const AId, AText: string; AIsError: Boolean);
    procedure Cut;
  end;

{ TReplyLink }

constructor TReplyLink.Create(const AReply: TAtlasIdeAiReply);
begin
  inherited Create;
  FReply := AReply;
end;

procedure TReplyLink.Reply(const AId, AText: string; AIsError: Boolean);
begin
  if Assigned(FReply) then
  begin
    FReply(AId, AText, AIsError);
  end;
end;

procedure TReplyLink.Cut;
begin
  FReply := nil;
end;

/// <summary>Antwort im Hauptthread an ALink; der Eintrag verfällt mit dem Modul.</summary>
procedure QueueReply(const ALink: IAtlasIdeAiReplyLink; const AId, AText: string; AIsError: Boolean);
begin
  TAtlasMainThread.Queue(TAtlasFeature.Settings,
    procedure
    begin
      ALink.Reply(AId, AText, AIsError);
    end);
end;

{$IFDEF ATLAS_TOOLSAPI_AI}
type
  /// <summary>Notifier der IDE für einen Anbieter; reicht Antwort und Fehler weiter, alles andere nicht.</summary>
  TAtlasIdeAiNotifier = class(TNotifierObject, IOTANotifier, IOTAAIServicesNotifier)
  private
    FLink: IAtlasIdeAiReplyLink;
  public
    constructor Create(const ALink: IAtlasIdeAiReplyLink);
    procedure Answer(const AMessage: string; const ARequestID: TGUID);
    procedure Error(const AMessage: string; const ARequestID: TGUID);
    procedure ModelsLoaded(const AModels: TArray<string>; const ARequestID: TGUID);
    // Delphi 13 hat zwei Fassungen (Base64-Texte und Stream); fehlt eine, meldet dcc E2291.
    procedure ImageLoaded(const AImages: TArray<string>; const ARequestID: TGUID); overload;
    procedure ImageLoaded(const AImage: TStream; const ARequestID: TGUID); overload;
    procedure ImageURlLoaded(const AImageURLs: TArray<string>; const ARequestID: TGUID);
    procedure SpeechLoaded(const ASpeech: TStream; const ARequestID: TGUID);
  end;

constructor TAtlasIdeAiNotifier.Create(const ALink: IAtlasIdeAiReplyLink);
begin
  inherited Create;
  FLink := ALink;
end;

procedure TAtlasIdeAiNotifier.Answer(const AMessage: string; const ARequestID: TGUID);
begin
  TAtlasGuard.Run(TAtlasFeature.Settings,
    procedure
    begin
      QueueReply(FLink, GUIDToString(ARequestID), AMessage, False);
    end);
end;

procedure TAtlasIdeAiNotifier.Error(const AMessage: string; const ARequestID: TGUID);
begin
  TAtlasGuard.Run(TAtlasFeature.Settings,
    procedure
    begin
      QueueReply(FLink, GUIDToString(ARequestID), AMessage, True);
    end);
end;

procedure TAtlasIdeAiNotifier.ModelsLoaded(const AModels: TArray<string>; const ARequestID: TGUID);
begin
  // Atlas fragt keine Modelle der IDE ab.
  TAtlasGuard.Run(TAtlasFeature.Settings,
    procedure
    begin
      TAtlasGuard.Log('KI-Anbieter der IDE: Modelle geladen, nicht angefordert'); // german-ok Protokoll
    end);
end;

procedure TAtlasIdeAiNotifier.ImageLoaded(const AImage: TStream; const ARequestID: TGUID);
begin
  TAtlasGuard.Run(TAtlasFeature.Settings,
    procedure
    begin
      TAtlasGuard.Log('KI-Anbieter der IDE: Bild geladen, nicht angefordert'); // german-ok Protokoll
    end);
end;

procedure TAtlasIdeAiNotifier.ImageLoaded(const AImages: TArray<string>; const ARequestID: TGUID);
begin
  TAtlasGuard.Run(TAtlasFeature.Settings,
    procedure
    begin
      TAtlasGuard.Log('KI-Anbieter der IDE: Bild geladen, nicht angefordert'); // german-ok Protokoll
    end);
end;

procedure TAtlasIdeAiNotifier.ImageURlLoaded(const AImageURLs: TArray<string>; const ARequestID: TGUID);
begin
  TAtlasGuard.Run(TAtlasFeature.Settings,
    procedure
    begin
      TAtlasGuard.Log('KI-Anbieter der IDE: Bildadressen geladen, nicht angefordert'); // german-ok Protokoll
    end);
end;

procedure TAtlasIdeAiNotifier.SpeechLoaded(const ASpeech: TStream; const ARequestID: TGUID);
begin
  TAtlasGuard.Run(TAtlasFeature.Settings,
    procedure
    begin
      TAtlasGuard.Log('KI-Anbieter der IDE: Sprache geladen, nicht angefordert'); // german-ok Protokoll
    end);
end;

function Engine(out AService: IOTAAIEngineService): Boolean;
begin
  Result := Supports(BorlandIDEServices, IOTAAIEngineService, AService);
end;

function PluginNamed(const AName: string): IOTAAIPlugin;
var
  mService: IOTAAIEngineService;
begin
  Result := nil;
  if Engine(mService) then
  begin
    Result := mService.GetPluginByName(AName);
  end;
end;

function FeaturesOf(AFeatures: TAIFeatures): TAtlasIdeAiFeatures;
begin
  Result := [];
  if afChat in AFeatures then
  begin
    Include(Result, TAtlasIdeAiFeature.Chat);
  end;
  if afInstruction in AFeatures then
  begin
    Include(Result, TAtlasIdeAiFeature.Instruction);
  end;
  if afListModels in AFeatures then
  begin
    Include(Result, TAtlasIdeAiFeature.ListModels);
  end;
end;

function GuidText(const AGuid: TGUID): string;
begin
  Result := '';
  if not IsEqualGUID(AGuid, TGUID.Empty) then
  begin
    Result := GUIDToString(AGuid);
  end;
end;
{$ENDIF}

{ TAtlasIdeAiEngine }

constructor TAtlasIdeAiEngine.Create(const AReply: TAtlasIdeAiReply);
begin
  inherited Create;
  FLink := TReplyLink.Create(AReply);
  FListening := TDictionary<string, Integer>.Create;
end;

destructor TAtlasIdeAiEngine.Destroy;
begin
  Stop;
  FreeAndNil(FListening);
  inherited Destroy;
end;

class function TAtlasIdeAiEngine.List: TArray<TAtlasIdeAiProvider>;
{$IFDEF ATLAS_TOOLSAPI_AI}
var
  mService: IOTAAIEngineService;
  mPlugin: IOTAAIPlugin;
  mIndex: Integer;
{$ENDIF}
begin
  Result := nil;
{$IFDEF ATLAS_TOOLSAPI_AI}
  if not Engine(mService) then
  begin
    Exit;
  end;
  for mIndex := 0 to mService.GetPluginCount - 1 do
  begin
    mPlugin := mService.GetPluginByIndex(mIndex);
    if mPlugin <> nil then
    begin
      Result := Result + [TAtlasIdeAiProvider.Make(mPlugin.GetName, mPlugin.GetEnabled,
        FeaturesOf(mPlugin.GetFeatures))];
    end;
  end;
{$ENDIF}
end;

function TAtlasIdeAiEngine.Providers: TArray<TAtlasIdeAiProvider>;
begin
  Result := List;
end;

procedure TAtlasIdeAiEngine.Listen(const AName: string);
{$IFDEF ATLAS_TOOLSAPI_AI}
var
  mPlugin: IOTAAIPlugin;
  mNotifier: IOTAAIServicesNotifier;
{$ENDIF}
begin
{$IFDEF ATLAS_TOOLSAPI_AI}
  if FListening.ContainsKey(AName) then
  begin
    Exit;
  end;
  mPlugin := PluginNamed(AName);
  if mPlugin <> nil then
  begin
    mNotifier := TAtlasIdeAiNotifier.Create(FLink);
    FListening.Add(AName, mPlugin.AddNotifier(mNotifier));
  end;
{$ENDIF}
end;

function TAtlasIdeAiEngine.Instruction(const AName, AInput, AInstruction: string): string;
{$IFDEF ATLAS_TOOLSAPI_AI}
var
  mPlugin: IOTAAIPlugin;
{$ENDIF}
begin
  Result := '';
{$IFDEF ATLAS_TOOLSAPI_AI}
  mPlugin := PluginNamed(AName);
  if mPlugin <> nil then
  begin
    Listen(AName);
    Result := GuidText(mPlugin.Instruction(AInput, AInstruction));
  end;
{$ENDIF}
end;

function TAtlasIdeAiEngine.Chat(const AName, AQuestion: string): string;
{$IFDEF ATLAS_TOOLSAPI_AI}
var
  mPlugin: IOTAAIPlugin;
{$ENDIF}
begin
  Result := '';
{$IFDEF ATLAS_TOOLSAPI_AI}
  mPlugin := PluginNamed(AName);
  if mPlugin <> nil then
  begin
    Listen(AName);
    Result := GuidText(mPlugin.Chat(AQuestion));
  end;
{$ENDIF}
end;

procedure TAtlasIdeAiEngine.Cancel(const AName: string);
{$IFDEF ATLAS_TOOLSAPI_AI}
var
  mPlugin: IOTAAIPlugin;
{$ENDIF}
begin
{$IFDEF ATLAS_TOOLSAPI_AI}
  mPlugin := PluginNamed(AName);
  if mPlugin <> nil then
  begin
    mPlugin.Cancel;
  end;
{$ENDIF}
end;

procedure TAtlasIdeAiEngine.Stop;
{$IFDEF ATLAS_TOOLSAPI_AI}
var
  mPair: TPair<string, Integer>;
  mPlugin: IOTAAIPlugin;
{$ENDIF}
begin
  if FLink <> nil then
  begin
    FLink.Cut;
  end;
  if FListening = nil then
  begin
    Exit;
  end;
{$IFDEF ATLAS_TOOLSAPI_AI}
  for mPair in FListening do
  begin
    mPlugin := PluginNamed(mPair.Key);
    if mPlugin <> nil then
    begin
      mPlugin.RemoveNotifier(mPair.Value);
    end;
  end;
{$ENDIF}
  FListening.Clear;
end;

type
  /// <summary>Zugriff auf Items des Baums im Optionsdialog (protected in TCustomTreeView).</summary>
  TTreeAccess = class(TCustomTreeView);

/// <summary>Im offenen Optionsdialog den Knoten ACaption wählen, gleich in welcher Tiefe.</summary>
function SelectInOpenDialog(const ACaption: string): Boolean;
var
  mForm: TCustomForm;
  mTree: TCustomTreeView;
  mIndex: Integer;
  mNode: TTreeNode;
begin
  Result := False;
  mForm := Screen.ActiveCustomForm;
  if mForm = nil then
  begin
    Exit;
  end;
  mTree := TAtlasOptionsSelector.FindTree(mForm);
  if mTree = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to TTreeAccess(mTree).Items.Count - 1 do
  begin
    mNode := TTreeAccess(mTree).Items[mIndex];
    if SameText(mNode.Text, ACaption) then
    begin
      mNode.MakeVisible;
      mNode.Selected := True;
      Exit(True);
    end;
  end;
end;

class function TAtlasIdeAiEngine.OpenOptions: Boolean;
var
  mForm: TCustomForm;
begin
  // Aus dem offenen Optionsdialog (Seite Atlas) nur den Knoten wählen: ein zweiter Dialog darüber ginge nicht.
  mForm := Screen.ActiveCustomForm;
  if (mForm <> nil) and (TAtlasOptionsSelector.FindTree(mForm) <> nil) then
  begin
    Exit(SelectInOpenDialog(cOptionsPage));
  end;
  Result := TAtlasIdeOptionsDialog.Open(cOptionsPage);
end;

end.
