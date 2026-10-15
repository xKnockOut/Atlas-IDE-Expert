unit Atlas.UI.Welcome.Frame;

// Frames der Atlas-Willkommensseite (#753):
// - TAtlasWelcomeFrame: Basis mit .dfm; abgeleitete Frames (Kopf, Bereiche,
//   Atlas-Layout) brauchen dadurch keine eigene. Der Name aus der .dfm wird
//   gelöscht, damit mehrere Frames denselben Besitzer haben dürfen.
// - TAtlasWelcomeSectionFrame: Bereich mit Titelzeile (nur im Atlas-Layout und
//   im Fenster „Atlas-Start“; auf der Willkommensseite der IDE trägt der
//   Rahmen der IDE den Titel) und Inhaltsfläche Body. Bereiche aus späteren
//   Issues leiten davon ab und überschreiben UpdateContent und PreferredHeight.
// - TAtlasWelcomeViews: Kennung → Fabrik der Frames. Jeder Bereich meldet seine
//   Fabrik an; Willkommensseite und „Atlas-Start“ erzeugen daraus ihre Frames.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Graphics;

type
  TAtlasWelcomeFrame = class(TFrame)
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Inhalt neu lesen und zeichnen; im Hauptthread.</summary>
    procedure UpdateContent; virtual;
  end;

  TAtlasWelcomeSectionFrame = class(TAtlasWelcomeFrame)
  public const
    TitleHeight = 24;
    /// <summary>Höhe ohne eigene Angabe (logische Pixel).</summary>
    DefaultBodyHeight = 120;
  private
    FSectionId: string;
    FTitleBar: TPanel;
    FTitle: TLabel;
    FBody: TPanel;
    function GetShowTitle: Boolean;
    procedure SetShowTitle(AValue: Boolean);
    function GetTitle: string;
    procedure SetTitle(const AValue: string);
  protected
    /// <summary>Höhe des Inhalts in Pixeln bei der aktuellen Skalierung.</summary>
    function BodyHeight: Integer; virtual;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Höhe, die der Frame im Atlas-Layout braucht (Titel plus Inhalt).</summary>
    function PreferredHeight: Integer;
    property SectionId: string read FSectionId write FSectionId;
    property Title: string read GetTitle write SetTitle;
    property ShowTitle: Boolean read GetShowTitle write SetShowTitle;
    /// <summary>Hierhin legen Bereiche ihren Inhalt.</summary>
    property Body: TPanel read FBody;
    property TitleLabel: TLabel read FTitle;
  end;

  TAtlasWelcomeViewFactory = reference to function(AOwner: TComponent): TAtlasWelcomeSectionFrame;

  TAtlasWelcomeViews = class
  private class var
    FFactories: TDictionary<string, TAtlasWelcomeViewFactory>;
  public
    class procedure Register(const AId: string; const AFactory: TAtlasWelcomeViewFactory); static;
    class procedure Unregister(const AId: string); static;
    class function Exists(const AId: string): Boolean; static;
    /// <summary>Neuer Frame für AId mit SectionId; nil ohne Fabrik.</summary>
    class function CreateView(const AId: string; AOwner: TComponent): TAtlasWelcomeSectionFrame; static;
    /// <summary>Beim Entladen: alle Fabriken vergessen.</summary>
    class procedure Release; static;
  end;

implementation

{$R *.dfm}

{ TAtlasWelcomeFrame }

constructor TAtlasWelcomeFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Mehrere Frames unter einem Besitzer: kein fester Name aus der .dfm.
  Name := '';
  ParentBackground := True;
end;

procedure TAtlasWelcomeFrame.UpdateContent;
begin
  Invalidate;
end;

{ TAtlasWelcomeSectionFrame }

constructor TAtlasWelcomeSectionFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTitleBar := TPanel.Create(Self);
  FTitleBar.Parent := Self;
  FTitleBar.Align := alTop;
  FTitleBar.BevelOuter := bvNone;
  FTitleBar.ParentBackground := True;
  FTitleBar.Height := TitleHeight;
  FTitle := TLabel.Create(Self);
  FTitle.Parent := FTitleBar;
  FTitle.Left := 2;
  FTitle.Top := 4;
  FTitle.Font.Style := [fsBold];
  FBody := TPanel.Create(Self);
  FBody.Parent := Self;
  FBody.Align := alClient;
  FBody.BevelOuter := bvNone;
  FBody.ParentBackground := True;
end;

function TAtlasWelcomeSectionFrame.GetShowTitle: Boolean;
begin
  Result := FTitleBar.Visible;
end;

procedure TAtlasWelcomeSectionFrame.SetShowTitle(AValue: Boolean);
begin
  FTitleBar.Visible := AValue;
end;

function TAtlasWelcomeSectionFrame.GetTitle: string;
begin
  Result := FTitle.Caption;
end;

procedure TAtlasWelcomeSectionFrame.SetTitle(const AValue: string);
begin
  FTitle.Caption := AValue;
end;

function TAtlasWelcomeSectionFrame.BodyHeight: Integer;
begin
  Result := DefaultBodyHeight;
end;

function TAtlasWelcomeSectionFrame.PreferredHeight: Integer;
begin
  Result := BodyHeight;
  if ShowTitle then
    Inc(Result, FTitleBar.Height);
end;

{ TAtlasWelcomeViews }

class procedure TAtlasWelcomeViews.Register(const AId: string; const AFactory: TAtlasWelcomeViewFactory);
begin
  if FFactories = nil then
    FFactories := TDictionary<string, TAtlasWelcomeViewFactory>.Create;
  FFactories.AddOrSetValue(LowerCase(AId), AFactory);
end;

class procedure TAtlasWelcomeViews.Unregister(const AId: string);
begin
  if FFactories <> nil then
    FFactories.Remove(LowerCase(AId));
end;

class function TAtlasWelcomeViews.Exists(const AId: string): Boolean;
begin
  Result := (FFactories <> nil) and FFactories.ContainsKey(LowerCase(AId));
end;

class function TAtlasWelcomeViews.CreateView(const AId: string; AOwner: TComponent): TAtlasWelcomeSectionFrame;
var
  Factory: TAtlasWelcomeViewFactory;
begin
  Result := nil;
  if (FFactories = nil) or not FFactories.TryGetValue(LowerCase(AId), Factory) then
    Exit;
  Result := Factory(AOwner);
  if Result <> nil then
    Result.SectionId := AId;
end;

class procedure TAtlasWelcomeViews.Release;
begin
  FreeAndNil(FFactories);
end;

end.
