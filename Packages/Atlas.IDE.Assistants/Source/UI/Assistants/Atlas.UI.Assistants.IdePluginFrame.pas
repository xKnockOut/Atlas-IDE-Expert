unit Atlas.UI.Assistants.IdePluginFrame;

// Kurze Seite des Eintrags „Atlas (…)“ unter Tools › Optionen › Smart CodeInsight (#2745): Anbieter und Modell,
// Anfragen heute und „In Atlas einrichten …“. Die Einstellungen selbst stehen nur auf der Seite Atlas ›
// KI-Assistenten (eine Stelle); die IDE bekommt den Rahmen über den Adapter
// Atlas.IDE.Assistants.Adapters.IdePlugin, der ihn um die Schnittstelle der IDE ergänzt.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls;

type
  /// <summary>Was die Seite zeigt.</summary>
  TAtlasIdePluginFrameView = record
    /// <summary>Anbieter und Modell („Anthropic-API, claude-haiku-5-5“); '' = keiner eingerichtet.</summary>
    Provider: string;
    Today: Integer;
    Limit: Integer;
  end;

  TAtlasAssistantsIdePluginFrame = class(TFrame)
  private
    FProvider: TLabel;
    FToday: TLabel;
    FHint: TLabel;
    FOpen: TButton;
    FOnOpenAtlas: TProc;
    procedure OpenClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    procedure ShowView(const AView: TAtlasIdePluginFrameView);
    /// <summary>Zeile „Anbieter: …“; ohne Anbieter der Hinweis, dass keiner eingerichtet ist.</summary>
    class function ProviderText(const AView: TAtlasIdePluginFrameView): string; static;
    /// <summary>Zeile „Heute n von m Anfragen“.</summary>
    class function TodayText(const AView: TAtlasIdePluginFrameView): string; static;
    /// <summary>Klick auf „In Atlas einrichten …“.</summary>
    property OnOpenAtlas: TProc read FOnOpenAtlas write FOnOpenAtlas;
    property ProviderLabel: TLabel read FProvider;
    property TodayLabel: TLabel read FToday;
    property OpenButton: TButton read FOpen;
  end;

implementation

uses
  Atlas.UI.Assistants.Strings;

{$R *.dfm}

const
  cLeft = 8;
  cLineHeight = 20;
  cTextWidth = 460;
  cButtonWidth = 180;
  cButtonHeight = 25;
  /// <summary>Knopf unter den drei Textzeilen, mit etwas Abstand.</summary>
  cButtonTop = cLeft + 3 * cLineHeight + 4;

/// <summary>Lage in Pixeln bei 96 dpi, an die Auflösung des Steuerelements angepasst.</summary>
procedure PlaceScaled(AControl: TControl; ALeft, ATop, AWidth, AHeight: Integer);
begin
  AControl.SetBounds(AControl.ScaleValue(ALeft), AControl.ScaleValue(ATop), AControl.ScaleValue(AWidth),
    AControl.ScaleValue(AHeight));
end;

function NewLabel(AOwner: TAtlasAssistantsIdePluginFrame; ATop: Integer): TLabel;
begin
  Result := TLabel.Create(AOwner);
  Result.Parent := AOwner;
  Result.ShowAccelChar := False;
  PlaceScaled(Result, cLeft, ATop, cTextWidth, cLineHeight);
end;

{ TAtlasAssistantsIdePluginFrame }

constructor TAtlasAssistantsIdePluginFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FProvider := NewLabel(Self, cLeft);
  FToday := NewLabel(Self, cLeft + cLineHeight);
  FHint := NewLabel(Self, cLeft + 2 * cLineHeight);
  FHint.Caption := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.FrameHint);
  FOpen := TButton.Create(Self);
  FOpen.Parent := Self;
  FOpen.Caption := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.FrameOpenAtlas);
  PlaceScaled(FOpen, cLeft, cButtonTop, cButtonWidth, cButtonHeight);
  FOpen.OnClick := OpenClick;
end;

class function TAtlasAssistantsIdePluginFrame.ProviderText(const AView: TAtlasIdePluginFrameView): string;
begin
  if AView.Provider = '' then
  begin
    Exit(TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.BridgeNotReady));
  end;
  Result := TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.FrameProvider, [AView.Provider]);
end;

class function TAtlasAssistantsIdePluginFrame.TodayText(const AView: TAtlasIdePluginFrameView): string;
begin
  Result := TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.FrameToday, [AView.Today, AView.Limit]);
end;

procedure TAtlasAssistantsIdePluginFrame.ShowView(const AView: TAtlasIdePluginFrameView);
begin
  FProvider.Caption := ProviderText(AView);
  FToday.Caption := TodayText(AView);
end;

procedure TAtlasAssistantsIdePluginFrame.OpenClick(Sender: TObject);
begin
  if Assigned(FOnOpenAtlas) then
  begin
    FOnOpenAtlas();
  end;
end;

end.
