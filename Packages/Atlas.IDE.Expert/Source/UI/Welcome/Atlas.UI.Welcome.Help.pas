unit Atlas.UI.Welcome.Help;

// Bereich „Hilfe und Rückmeldung“ der Willkommensseite (#766), ohne Open
// Tools API:
//   [Atlas-Doku] [Tastenkürzel] [Problem melden …] [Atlas unterstützen ♥]
//   Nichts wird automatisch gesendet.
// Ein schmaler Bereich mit vier Knöpfen, bei zu wenig Breite in weiteren
// Reihen. „Tastenkürzel“ ist ausgegraut, wenn die Übersicht aus #520
// abgeschaltet ist (keys.overview). Aktionen kommen über IAtlasHelpSource
// aus der IDE-Schicht; Klicks rufen die Quelle über die Nachrichtenschleife
// auf, damit ein modaler Dialog nicht im Klick des Knopfs läuft.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.Graphics,
  Atlas.Core.Welcome.Help,
  Atlas.UI.Welcome.Frame;

type
  IAtlasHelpSource = interface
    ['{6B1E2F7A-3C94-4D58-9A0B-5E7C1D2F8A46}']
    /// <summary>Gibt es die Tastenkürzel-Übersicht (#520)?</summary>
    function KeysAvailable: Boolean;
    /// <summary>„Atlas-Doku“: installierte Doku oder Doku-Seite des Repositorys im Browser.</summary>
    procedure OpenDocs;
    /// <summary>„Tastenkürzel“: Übersicht aus #520.</summary>
    procedure ShowKeys;
    /// <summary>„Problem melden …“: Dialog mit Diagnosepaket.</summary>
    procedure ReportProblem;
    /// <summary>„Atlas unterstützen“: Spendenseite im Browser.</summary>
    procedure Donate;
  end;

  TAtlasWelcomeHelpFrame = class(TAtlasWelcomeSectionFrame)
  public const
    Indent = 8;
    Gap = 8;
    ButtonHeight = 24;
    ButtonPadding = 16;
  private
    FSource: IAtlasHelpSource;
    FButtons: array[TAtlasHelpButton] of TButton;
    FNote: TLabel;
    FContentHeight: Integer;
    FArranging: Boolean;
    procedure SetSource(const AValue: IAtlasHelpSource);
    procedure Arrange;
    procedure BodyResize(Sender: TObject);
    procedure ButtonClick(Sender: TObject);
  protected
    function BodyHeight: Integer; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure UpdateContent; override;
    /// <summary>Klick auf einen Knopf wie mit der Maus (auch für Tests).</summary>
    procedure ClickButton(AButton: TAtlasHelpButton);
    function Button(AButton: TAtlasHelpButton): TButton;
    /// <summary>„Hilfe und Rückmeldung“ in der Sprache der IDE.</summary>
    class function TitleText: string; static;
    class function ButtonCaption(AButton: TAtlasHelpButton): string; static;
    property Source: IAtlasHelpSource read FSource write SetSource;
    property NoteLabel: TLabel read FNote;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Strings;

{ TAtlasWelcomeHelpFrame }

constructor TAtlasWelcomeHelpFrame.Create(AOwner: TComponent);
var
  Kind: TAtlasHelpButton;
begin
  inherited Create(AOwner);
  for Kind := Low(TAtlasHelpButton) to High(TAtlasHelpButton) do
  begin
    FButtons[Kind] := TButton.Create(Self);
    FButtons[Kind].Parent := Body;
    FButtons[Kind].Caption := ButtonCaption(Kind);
    FButtons[Kind].Tag := Ord(Kind);
    FButtons[Kind].OnClick := ButtonClick;
  end;
  FNote := TLabel.Create(Self);
  FNote.Parent := Body;
  FNote.ShowAccelChar := False;
  FNote.Font.Color := clGrayText;
  FNote.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeHelpNote);
  Body.OnResize := BodyResize;
  UpdateContent;
end;

class function TAtlasWelcomeHelpFrame.TitleText: string;
begin
  Result := TAtlasStrings.Text(TAtlasTextId.WelcomeHelpTitle);
end;

class function TAtlasWelcomeHelpFrame.ButtonCaption(AButton: TAtlasHelpButton): string;
begin
  case AButton of
    TAtlasHelpButton.Docs:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeHelpDocs);
    TAtlasHelpButton.Keys:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeHelpKeys);
    TAtlasHelpButton.Donate:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeHelpDonate);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeHelpReport);
  end;
end;

function TAtlasWelcomeHelpFrame.Button(AButton: TAtlasHelpButton): TButton;
begin
  Result := FButtons[AButton];
end;

procedure TAtlasWelcomeHelpFrame.SetSource(const AValue: IAtlasHelpSource);
begin
  FSource := AValue;
  UpdateContent;
end;

procedure TAtlasWelcomeHelpFrame.UpdateContent;
var
  Kind: TAtlasHelpButton;
  Keys: Boolean;
  OldHeight: Integer;
begin
  OldHeight := FContentHeight;
  Keys := (FSource <> nil) and FSource.KeysAvailable;
  for Kind := Low(TAtlasHelpButton) to High(TAtlasHelpButton) do
    FButtons[Kind].Enabled := (FSource <> nil) and TAtlasHelp.Enabled(Kind, Keys);
  Arrange;
  inherited;
  if OldHeight <> FContentHeight then
    HeightChanged;
end;

procedure TAtlasWelcomeHelpFrame.BodyResize(Sender: TObject);
var
  OldHeight: Integer;
begin
  OldHeight := FContentHeight;
  Arrange;
  // Andere Reihen bei neuer Breite: Der Frame „Atlas“ ordnet die Spalten neu.
  if OldHeight <> FContentHeight then
    HeightChanged;
end;

procedure TAtlasWelcomeHelpFrame.Arrange;
var
  mLeft, Right, ButtonLeft, ButtonTop, ButtonWidth: Integer;
  Kind: TAtlasHelpButton;
  Measure: TBitmap;
begin
  // Ohne Fenster lässt sich kein Text messen; CreateWnd holt UpdateContent nach.
  if FArranging or (FNote = nil) or not HasWindow then
    Exit;
  FArranging := True;
  try
    // Breite des Frames statt der Inhaltsfläche: Die richtet sich erst später nach dem Frame aus.
    mLeft := ScaleValue(Indent);
    Right := ClientWidth - ScaleValue(Indent);
    ButtonLeft := mLeft;
    ButtonTop := ScaleValue(Gap) div 2;
    Measure := TBitmap.Create;
    try
      Measure.Canvas.Font.Assign(Font);
      for Kind := Low(TAtlasHelpButton) to High(TAtlasHelpButton) do
      begin
        ButtonWidth := Measure.Canvas.TextWidth(FButtons[Kind].Caption) + 2 * ScaleValue(ButtonPadding);
        if (ButtonLeft > mLeft) and (ButtonLeft + ButtonWidth > Right) then
        begin
          ButtonLeft := mLeft;
          Inc(ButtonTop, ScaleValue(ButtonHeight) + ScaleValue(Gap) div 2);
        end;
        FButtons[Kind].SetBounds(ButtonLeft, ButtonTop, ButtonWidth, ScaleValue(ButtonHeight));
        Inc(ButtonLeft, ButtonWidth + ScaleValue(Gap) div 2);
      end;
    finally
      Measure.Free;
    end;
    FNote.SetBounds(mLeft, ButtonTop + ScaleValue(ButtonHeight) + ScaleValue(Gap) div 2, FNote.Width, FNote.Height);
    FContentHeight := FNote.Top + FNote.Height + ScaleValue(Gap) div 2;
  finally
    FArranging := False;
  end;
end;

function TAtlasWelcomeHelpFrame.BodyHeight: Integer;
begin
  // Für die aktuelle Breite: Der Frame „Atlas“ setzt erst die Breite, dann die Höhe.
  Arrange;
  Result := Max(FContentHeight, ScaleValue(40));
end;

procedure TAtlasWelcomeHelpFrame.ClickButton(AButton: TAtlasHelpButton);
var
  mSource: IAtlasHelpSource;
begin
  if (FSource = nil) or not FButtons[AButton].Enabled then
    Exit;
  mSource := FSource;
  // Nicht im Klick des Knopfs: „Problem melden“ zeigt einen modalen Dialog.
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      case AButton of
        TAtlasHelpButton.Docs:
          mSource.OpenDocs;
        TAtlasHelpButton.Keys:
          mSource.ShowKeys;
        TAtlasHelpButton.Donate:
          mSource.Donate;
      else
        mSource.ReportProblem;
      end;
    end);
end;

procedure TAtlasWelcomeHelpFrame.ButtonClick(Sender: TObject);
begin
  ClickButton(TAtlasHelpButton((Sender as TButton).Tag));
end;

end.
