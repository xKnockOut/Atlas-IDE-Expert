unit Atlas.UI.Results.SymbolPath;

// Weg zwischen Symbolen (#1117) im Ergebnisfenster: statt des Baums eine gezeichnete Kette
// (TAtlasSymbolPathChain) mit Statuszeile; „In Architekturkarte zeigen“ meldet die Units des ersten Wegs über
// OnShowRoute.

interface

uses
  Vcl.StdCtrls,
  Vcl.Forms,
  Vcl.ExtCtrls,
  Atlas.Core.SymbolPath.Model,
  Atlas.UI.SymbolPath.Chain,
  Atlas.UI.Results.View;

type
  /// <summary>Units eines Wegs (#1117) auf der Architekturkarte zeigen.</summary>
  TAtlasShowRoute = reference to procedure(const AUnits: TArray<string>);

  TAtlasResultsPathPart = class(TAtlasResultsPart)
  private type
    /// <summary>Leiste, Statuszeile, Kette in einer Scrollbox.</summary>
    TParts = record
      Panel: TPanel;
      Status: TLabel;
      Map: TButton;
      Box: TScrollBox;
      Chain: TAtlasSymbolPathChain;
    end;
  private
    FParts: TParts;
    FShows: Boolean;
    FOnShowRoute: TAtlasShowRoute;
    procedure CreateChain;
    procedure ShowPanel(AVisible: Boolean);
    procedure MapClick(Sender: TObject);
    procedure BoxResize(Sender: TObject);
  protected
    procedure Reset; override;
  public
    constructor Create(AView: TAtlasResultsView);
    /// <summary>Weg als Kette; AMapAvailable: Knopf „In Architekturkarte zeigen“ anbieten (Architekturübersicht an
    /// und ein Weg gefunden).</summary>
    procedure Show(const ATitle: string; const AAnswer: TAtlasSymbolPathAnswer; AMapAvailable: Boolean);
    /// <summary>Statt der Kette nur ein Hinweis (Suche läuft, kein Server, Fehler).</summary>
    procedure ShowText(const ATitle, AText: string);
    /// <summary>Zeigt gerade einen Weg zwischen Symbolen.</summary>
    property Shows: Boolean read FShows;
    property Chain: TAtlasSymbolPathChain read FParts.Chain;
    property Status: TLabel read FParts.Status;
    property MapButton: TButton read FParts.Map;
    property OnShowRoute: TAtlasShowRoute read FOnShowRoute write FOnShowRoute;
  end;

implementation

uses
  Vcl.Controls,
  Atlas.UI.Strings;

{ TAtlasResultsPathPart }

constructor TAtlasResultsPathPart.Create(AView: TAtlasResultsView);
begin
  inherited Create(AView);
  // Anfangs verborgen, ersetzt den Baum.
  FParts.Panel := TPanel.Create(AView.Host);
  FParts.Panel.Parent := AView.Host;
  FParts.Panel.Align := alClient;
  FParts.Panel.BevelOuter := bvNone;
  FParts.Panel.ShowCaption := False;
  FParts.Panel.ParentBackground := True;
  FParts.Panel.Visible := False;
  FParts.Map := TAtlasResultsControls.Button(AView.Host, FParts.Panel, alTop, 75,
    TAtlasStrings.Text(TAtlasTextId.SymbolPathShowMap), MapClick);
  FParts.Map.Visible := False;
  FParts.Status := TLabel.Create(AView.Host);
  FParts.Status.Parent := FParts.Panel;
  FParts.Status.Align := alTop;
  FParts.Status.AlignWithMargins := True;
  FParts.Status.ShowAccelChar := False;
  FParts.Status.WordWrap := True;
  CreateChain;
end;

procedure TAtlasResultsPathPart.CreateChain;
begin
  FParts.Box := TScrollBox.Create(View.Host);
  FParts.Box.Parent := FParts.Panel;
  FParts.Box.Align := alClient;
  FParts.Box.BorderStyle := bsNone;
  FParts.Box.VertScrollBar.Tracking := True;
  FParts.Box.HorzScrollBar.Visible := False;
  FParts.Box.OnResize := BoxResize;
  FParts.Chain := TAtlasSymbolPathChain.Create(View.Host);
  FParts.Chain.Parent := FParts.Box;
  FParts.Chain.Left := 0;
  FParts.Chain.Top := 0;
  // Breite erst mit Fenster (BoxResize): ClientWidth der ScrollBox braucht ein Handle.
  FParts.Chain.OnOpen :=
    procedure(const AFileName: string; ALine, ACharacter: Integer)
    begin
      View.Open(TAtlasResultsNode.Place(TAtlasResultsNodeKind.Entry, AFileName, ALine, ACharacter));
    end;
end;

procedure TAtlasResultsPathPart.Reset;
begin
  ShowPanel(False);
end;

procedure TAtlasResultsPathPart.ShowPanel(AVisible: Boolean);
begin
  FShows := AVisible;
  FParts.Panel.Visible := AVisible;
  View.Tree.Visible := not AVisible;
end;

procedure TAtlasResultsPathPart.BoxResize(Sender: TObject);
begin
  FParts.Chain.Width := FParts.Box.ClientWidth;
end;

procedure TAtlasResultsPathPart.MapClick(Sender: TObject);
begin
  if Assigned(FOnShowRoute) and (Length(FParts.Chain.Answer.Routes) > 0) then
  begin
    FOnShowRoute(FParts.Chain.Answer.Routes[0].UnitNames);
  end;
end;

procedure TAtlasResultsPathPart.Show(const ATitle: string; const AAnswer: TAtlasSymbolPathAnswer;
  AMapAvailable: Boolean);
begin
  View.Clear(ATitle);
  ShowPanel(True);
  FParts.Status.Caption := TAtlasSymbolPathChain.StatusText(AAnswer);
  FParts.Map.Visible := AMapAvailable and (Length(AAnswer.Routes) > 0);
  FParts.Chain.SetAnswer(AAnswer);
  FParts.Box.VertScrollBar.Position := 0;
  // Nur im gezeigten Fenster; SetFocus in einem verborgenen löst eine Ausnahme aus.
  if FParts.Chain.Showing and FParts.Chain.CanFocus then
  begin
    FParts.Chain.SetFocus;
  end;
end;

procedure TAtlasResultsPathPart.ShowText(const ATitle, AText: string);
begin
  View.Clear(ATitle);
  ShowPanel(True);
  FParts.Status.Caption := AText;
  FParts.Map.Visible := False;
  FParts.Chain.SetAnswer(Default(TAtlasSymbolPathAnswer));
end;

end.
