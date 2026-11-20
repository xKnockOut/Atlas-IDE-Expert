unit Atlas.IDE.Assistants.Adapters.IdePlugin;

// Adapter über ToolsAPI.AI (#2745): meldet den eigenen KI-Anbieter von Atlas als „Atlas (…)“ bei Smart CodeInsight
// der IDE an (AIEngineService.RegisterPlugin) und reicht die Aufrufe der IDE an TAtlasIdeAiBridge weiter.
// - Funktionen: Chat, Anweisung und, wenn der Anbieter es kann, Modelle. Bild, Sprache und Moderation lehnt der
//   Eintrag ab (leere Kennung); die IDE bietet sie ohnehin nicht an, weil AvailableFeatures sie nicht nennt.
// - Die Notifier der IDE bekommt die Brücke als IAtlasIdeAiAnswers; Kennungen gehen als TGUID zurück.
// - GetSettingFrame liefert die kurze Seite TAtlasAssistantsIdePluginFrame, ergänzt um IOTAAIPluginSetting; sie
//   speichert nichts (die Einstellungen stehen auf der Atlas-Seite).
// - Destroy meldet den Eintrag ab (UnregisterPlugin), stoppt die Brücke und trennt den Eintrag von ihr: Was die
//   IDE danach noch aufruft, erreicht das Modul nicht mehr (Regel 3).
// - Ohne ToolsAPI.AI (Delphi 12.0/12.1) meldet der Host nichts an.

interface

{$IF Declared(RTLVersion122) or (CompilerVersion >= 37.0)}
  {$DEFINE ATLAS_TOOLSAPI_AI}
{$IFEND}

uses
  System.SysUtils,
  Atlas.IDE.Assistants.IdeBridge,
  Atlas.UI.Assistants.IdePluginFrame;

type
  TAtlasIdeAiPluginHooks = record
    /// <summary>Was die Seite in Smart CodeInsight zeigt.</summary>
    View: TFunc<TAtlasIdePluginFrameView>;
    /// <summary>„In Atlas einrichten …“</summary>
    OpenAtlas: TProc;
  end;

  /// <summary>Meldet die Brücke bei der IDE an (Create) und ab (Destroy); besitzt die Brücke.</summary>
  TAtlasIdeAiPluginHost = class
  private
    FBridge: TAtlasIdeAiBridge;
    FPlugin: IInterface;
    /// <summary>Trennt den angemeldeten Eintrag von der Brücke.</summary>
    FCut: TProc;
    FIndex: Integer;
  public
    constructor Create(ABridge: TAtlasIdeAiBridge; const AHooks: TAtlasIdeAiPluginHooks);
    destructor Destroy; override;
    /// <summary>Die IDE hat den Eintrag angenommen.</summary>
    function Registered: Boolean;
    property Bridge: TAtlasIdeAiBridge read FBridge;
  end;

implementation

uses
  System.Classes,
{$IFDEF ATLAS_TOOLSAPI_AI}
  ToolsAPI,
  ToolsAPI.AI,
{$ENDIF}
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Assistants.Contract.IdeAi,
  Atlas.Core.Assistants.IdeProviders;

{$IFDEF ATLAS_TOOLSAPI_AI}
type
  /// <summary>Ein Notifier der IDE, wie die Brücke ihn braucht.</summary>
  TAnswers = class(TInterfacedObject, IAtlasIdeAiAnswers)
  private
    FNotifier: IOTAAIServicesNotifier;
  public
    constructor Create(const ANotifier: IOTAAIServicesNotifier);
    procedure Answer(const AText, AId: string);
    procedure Error(const AText, AId: string);
    procedure Models(const AModels: TArray<string>; const AId: string);
  end;

  /// <summary>Kurze Seite in Smart CodeInsight; speichert nichts.</summary>
  TAtlasIdeAiPluginSettingFrame = class(TAtlasAssistantsIdePluginFrame, IOTAAIPluginSetting)
  public
    procedure LoadSettings;
    procedure SaveSettings;
    function GetModified: Boolean;
    function ParameterValidations: Boolean;
  end;

  /// <summary>Der Eintrag „Atlas (…)“ in der Anbieterliste der IDE.</summary>
  TAtlasIdeAiPlugin = class(TInterfacedObject, IOTAAIPlugin)
  private
    FBridge: TAtlasIdeAiBridge;
    FHooks: TAtlasIdeAiPluginHooks;
    function GuidOf(const AId: string): TGUID;
  public
    constructor Create(ABridge: TAtlasIdeAiBridge; const AHooks: TAtlasIdeAiPluginHooks);
    /// <summary>Von der Brücke trennen; danach antwortet der Eintrag mit nichts.</summary>
    procedure Cut;
    function Chat(const AQuestion: string): TGUID;
    function Instruction(const AInput: string; const AInstruction: string): TGUID;
    function LoadModels: TGUID;
    function Moderation(const AInput: string): TGUID;
    function GenerateImage(const APrompt: string; const ASize: string; const AFormat: string): TGUID;
    function GenerateSpeechFromText(const AText: string; const AVoice: string): TGUID;
    function GenerateTextFromAudioFile(const AAudioFilePath: string): TGUID;
    procedure Cancel;
    function GetName: string;
    function GetEnabled: Boolean;
    function GetFeatures: TAIFeatures;
    function GetSettingFrame(AOwner: TComponent): IOTAAIPluginSetting;
    function AddNotifier(const ANotifier: IOTAAIServicesNotifier): Integer;
    procedure RemoveNotifier(const AIndex: Integer);
  end;

{ TAnswers }

constructor TAnswers.Create(const ANotifier: IOTAAIServicesNotifier);
begin
  inherited Create;
  FNotifier := ANotifier;
end;

procedure TAnswers.Answer(const AText, AId: string);
begin
  FNotifier.Answer(AText, StringToGUID(AId));
end;

procedure TAnswers.Error(const AText, AId: string);
begin
  FNotifier.Error(AText, StringToGUID(AId));
end;

procedure TAnswers.Models(const AModels: TArray<string>; const AId: string);
begin
  FNotifier.ModelsLoaded(AModels, StringToGUID(AId));
end;

{ TAtlasIdeAiPluginSettingFrame }

procedure TAtlasIdeAiPluginSettingFrame.LoadSettings;
begin
  // Nichts zu laden: Die Seite zeigt nur den Stand der Atlas-Einstellungen.
  OpenButton.Enabled := Assigned(OnOpenAtlas);
end;

procedure TAtlasIdeAiPluginSettingFrame.SaveSettings;
begin
  // Nichts zu speichern: Die Einstellungen stehen auf der Seite Atlas › KI-Assistenten.
  OpenButton.Enabled := Assigned(OnOpenAtlas);
end;

function TAtlasIdeAiPluginSettingFrame.GetModified: Boolean;
begin
  Result := False;
end;

function TAtlasIdeAiPluginSettingFrame.ParameterValidations: Boolean;
begin
  Result := True;
end;

{ TAtlasIdeAiPlugin }

constructor TAtlasIdeAiPlugin.Create(ABridge: TAtlasIdeAiBridge; const AHooks: TAtlasIdeAiPluginHooks);
begin
  inherited Create;
  FBridge := ABridge;
  FHooks := AHooks;
end;

procedure TAtlasIdeAiPlugin.Cut;
begin
  FBridge := nil;
  FHooks := Default(TAtlasIdeAiPluginHooks);
end;

function TAtlasIdeAiPlugin.GuidOf(const AId: string): TGUID;
begin
  Result := TGUID.Empty;
  if AId <> '' then
  begin
    Result := StringToGUID(AId);
  end;
end;

function TAtlasIdeAiPlugin.Chat(const AQuestion: string): TGUID;
begin
  Result := TGUID.Empty;
  if FBridge <> nil then
  begin
    Result := GuidOf(FBridge.Chat(AQuestion));
  end;
end;

function TAtlasIdeAiPlugin.Instruction(const AInput: string; const AInstruction: string): TGUID;
begin
  Result := TGUID.Empty;
  if FBridge <> nil then
  begin
    Result := GuidOf(FBridge.Instruction(AInput, AInstruction));
  end;
end;

function TAtlasIdeAiPlugin.LoadModels: TGUID;
begin
  Result := TGUID.Empty;
  if FBridge <> nil then
  begin
    Result := GuidOf(FBridge.LoadModels);
  end;
end;

function TAtlasIdeAiPlugin.Moderation(const AInput: string): TGUID;
begin
  // Nicht angeboten (AvailableFeatures ohne afModeration).
  Result := TGUID.Empty;
end;

function TAtlasIdeAiPlugin.GenerateImage(const APrompt: string; const ASize: string; const AFormat: string): TGUID;
begin
  // Nicht angeboten (AvailableFeatures ohne afImageGeneration).
  Result := TGUID.Empty;
end;

function TAtlasIdeAiPlugin.GenerateSpeechFromText(const AText: string; const AVoice: string): TGUID;
begin
  // Nicht angeboten (AvailableFeatures ohne afTextToSpeech).
  Result := TGUID.Empty;
end;

function TAtlasIdeAiPlugin.GenerateTextFromAudioFile(const AAudioFilePath: string): TGUID;
begin
  // Nicht angeboten (AvailableFeatures ohne afSpeechToText).
  Result := TGUID.Empty;
end;

procedure TAtlasIdeAiPlugin.Cancel;
begin
  if FBridge <> nil then
  begin
    FBridge.Cancel;
  end;
end;

function TAtlasIdeAiPlugin.GetName: string;
begin
  Result := TAtlasIdeAiProviders.OwnName('');
  if FBridge <> nil then
  begin
    Result := FBridge.Name;
  end;
end;

function TAtlasIdeAiPlugin.GetEnabled: Boolean;
begin
  Result := (FBridge <> nil) and FBridge.Enabled;
end;

function TAtlasIdeAiPlugin.GetFeatures: TAIFeatures;
var
  mFeatures: TAtlasIdeAiFeatures;
begin
  Result := [];
  if FBridge = nil then
  begin
    Exit;
  end;
  mFeatures := FBridge.Features;
  if TAtlasIdeAiFeature.Chat in mFeatures then
  begin
    Include(Result, afChat);
  end;
  if TAtlasIdeAiFeature.Instruction in mFeatures then
  begin
    Include(Result, afInstruction);
  end;
  if TAtlasIdeAiFeature.ListModels in mFeatures then
  begin
    Include(Result, afListModels);
  end;
end;

function TAtlasIdeAiPlugin.GetSettingFrame(AOwner: TComponent): IOTAAIPluginSetting;
var
  mFrame: TAtlasIdeAiPluginSettingFrame;
begin
  mFrame := TAtlasIdeAiPluginSettingFrame.Create(AOwner);
  mFrame.OnOpenAtlas := FHooks.OpenAtlas;
  if Assigned(FHooks.View) then
  begin
    mFrame.ShowView(FHooks.View());
  end;
  Result := mFrame;
end;

function TAtlasIdeAiPlugin.AddNotifier(const ANotifier: IOTAAIServicesNotifier): Integer;
begin
  Result := -1;
  if FBridge <> nil then
  begin
    Result := FBridge.AddNotifier(TAnswers.Create(ANotifier));
  end;
end;

procedure TAtlasIdeAiPlugin.RemoveNotifier(const AIndex: Integer);
begin
  if FBridge <> nil then
  begin
    FBridge.RemoveNotifier(AIndex);
  end;
end;

function Engine(out AService: IOTAAIEngineService): Boolean;
begin
  Result := Supports(BorlandIDEServices, IOTAAIEngineService, AService);
end;
{$ENDIF}

{ TAtlasIdeAiPluginHost }

constructor TAtlasIdeAiPluginHost.Create(ABridge: TAtlasIdeAiBridge; const AHooks: TAtlasIdeAiPluginHooks);
{$IFDEF ATLAS_TOOLSAPI_AI}
var
  mService: IOTAAIEngineService;
  mPlugin: TAtlasIdeAiPlugin;
{$ENDIF}
begin
  inherited Create;
  FBridge := ABridge;
  FIndex := -1;
{$IFDEF ATLAS_TOOLSAPI_AI}
  if not Engine(mService) then
  begin
    TAtlasGuard.Log('Smart CodeInsight: kein KI-Dienst der IDE, Atlas nicht angemeldet'); // german-ok Protokoll
    Exit;
  end;
  mPlugin := TAtlasIdeAiPlugin.Create(FBridge, AHooks);
  FPlugin := mPlugin as IOTAAIPlugin;
  FCut := mPlugin.Cut;
  FIndex := mService.RegisterPlugin(FPlugin as IOTAAIPlugin);
{$ENDIF}
end;

destructor TAtlasIdeAiPluginHost.Destroy;
{$IFDEF ATLAS_TOOLSAPI_AI}
var
  mService: IOTAAIEngineService;
{$ENDIF}
begin
{$IFDEF ATLAS_TOOLSAPI_AI}
  if (FIndex >= 0) and Engine(mService) then
  begin
    mService.UnregisterPlugin(FIndex);
  end;
{$ENDIF}
  if Assigned(FCut) then
  begin
    FCut();
  end;
  FCut := nil;
  FPlugin := nil;
  FIndex := -1;
  if FBridge <> nil then
  begin
    FBridge.Stop;
  end;
  FreeAndNil(FBridge);
  inherited Destroy;
end;

function TAtlasIdeAiPluginHost.Registered: Boolean;
begin
  Result := FIndex >= 0;
end;

end.
