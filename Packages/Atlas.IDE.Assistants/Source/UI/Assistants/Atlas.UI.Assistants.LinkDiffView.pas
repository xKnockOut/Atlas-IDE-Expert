unit Atlas.UI.Assistants.LinkDiffView;

// Assistenten-Kopplung (#2377): Vorschlag des verbundenen Assistenten als Vergleich (openDiff). Ein nicht modales
// Fenster zeigt den vereinigten Unterschied zwischen dem jetzigen Stand der Datei und dem Vorschlag in fester
// Schrift; „Annehmen“, „Ablehnen“ und „Annehmen und öffnen“ melden die Entscheidung über OnDecide. Schließen über
// das Kreuz oder Esc gilt als Ablehnen. Das Fenster entscheidet nur einmal; was dann geschieht (Anwenden, Antwort
// an den Assistenten, Freigeben), macht die Kopplung.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.UI.Foundation.Dialog;

type
  {$SCOPEDENUMS ON}
  TAtlasLinkDecision = (Accept, Reject, Edit);
  {$SCOPEDENUMS OFF}

  TAtlasLinkDecided = reference to procedure(AId: Integer; ADecision: TAtlasLinkDecision);

  TAtlasLinkDiffView = class(TAtlasDialog)
  private
    FId: Integer;
    FLines: TMemo;
    FAccept: TButton;
    FReject: TButton;
    FEdit: TButton;
    FDecided: Boolean;
    FOnDecide: TAtlasLinkDecided;
    procedure Decide(ADecision: TAtlasLinkDecision);
    procedure AcceptClick(Sender: TObject);
    procedure RejectClick(Sender: TObject);
    procedure EditClick(Sender: TObject);
    procedure ViewClose(Sender: TObject; var AAction: TCloseAction);
    /// <summary>Knopf an Stelle AIndex (0 = links) der unteren Leiste.</summary>
    function AddButton(AParent: TWinControl; const ACaption: string; AIndex: Integer;
      const AOnClick: TNotifyEvent): TButton;
  public
    /// <summary>Vorschlag AId für AFileName mit den Zeilen ALines des Unterschieds.</summary>
    constructor CreateView(AOwner: TComponent; AId: Integer; const ATitle: string; const ALines: TArray<string>);
    /// <summary>Unterschied von AOld nach ANew für die Anzeige; ohne Unterschied ein Hinweis.</summary>
    class function DiffLines(const AFileName, AOld, ANew: string): TArray<string>; static;
    /// <summary>Entscheidung gilt nicht (Anwenden scheiterte): Knöpfe wieder frei.</summary>
    procedure Reopen;
    /// <summary>Zeilen des Unterschieds ersetzen (die Datei hat sich inzwischen geändert).</summary>
    procedure ShowLines(const ALines: TArray<string>);
    property Id: Integer read FId;
    property Decided: Boolean read FDecided;
    property OnDecide: TAtlasLinkDecided read FOnDecide write FOnDecide;
    property Lines: TMemo read FLines;
    property AcceptButton: TButton read FAccept;
    property RejectButton: TButton read FReject;
    property EditButton: TButton read FEdit;
  end;

implementation

uses
  Atlas.Text.Diff,
  Atlas.UI.Assistants.Strings;

const
  cViewWidth = 860;
  cViewHeight = 520;
  cBottomHeight = 40;
  cGap = 8;
  cButtonWidth = 150;
  /// <summary>Zeilen Umgebung um jede Änderung.</summary>
  cContextLines = 3;

{ TAtlasLinkDiffView }

constructor TAtlasLinkDiffView.CreateView(AOwner: TComponent; AId: Integer; const ATitle: string;
  const ALines: TArray<string>);
var
  mBottom: TPanel;
begin
  inherited CreateDialog(AOwner, ATitle, cViewWidth);
  FId := AId;
  BorderIcons := [biSystemMenu, biMaximize];
  BorderStyle := bsSizeable;
  Position := poScreenCenter;
  ClientHeight := ScaleValue(cViewHeight);
  KeyPreview := True;
  OnClose := ViewClose;
  mBottom := TPanel.Create(Self);
  mBottom.Parent := Self;
  mBottom.Align := alBottom;
  mBottom.BevelOuter := bvNone;
  mBottom.Height := ScaleValue(cBottomHeight);
  FAccept := AddButton(mBottom, TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.LinkDiffAccept), 0, AcceptClick);
  FAccept.Default := True;
  FReject := AddButton(mBottom, TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.LinkDiffReject), 1, RejectClick);
  FReject.Cancel := True;
  FEdit := AddButton(mBottom, TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.LinkDiffEdit), 2, EditClick);
  FLines := TMemo.Create(Self);
  FLines.Parent := Self;
  FLines.Align := alClient;
  FLines.AlignWithMargins := True;
  FLines.ReadOnly := True;
  FLines.WordWrap := False;
  FLines.ScrollBars := ssBoth;
  FLines.Font.Name := 'Consolas';
  ShowLines(ALines);
end;

procedure TAtlasLinkDiffView.ShowLines(const ALines: TArray<string>);
var
  mLine: string;
begin
  FLines.Lines.BeginUpdate;
  try
    FLines.Lines.Clear;
    for mLine in ALines do
    begin
      FLines.Lines.Add(mLine);
    end;
  finally
    FLines.Lines.EndUpdate;
  end;
end;

function TAtlasLinkDiffView.AddButton(AParent: TWinControl; const ACaption: string; AIndex: Integer;
  const AOnClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Top := ScaleValue(cGap);
  Result.Left := ScaleValue(cGap + AIndex * (cGap + cButtonWidth));
  Result.Width := ScaleValue(cButtonWidth);
  Result.OnClick := AOnClick;
end;

class function TAtlasLinkDiffView.DiffLines(const AFileName, AOld, ANew: string): TArray<string>;
begin
  Result := TTextDiff.Unified(AFileName, AFileName, AOld.Split([#13#10, #10]), ANew.Split([#13#10, #10]),
    cContextLines);
  if Length(Result) = 0 then
  begin
    Result := [TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.LinkDiffSame)];
  end;
end;

procedure TAtlasLinkDiffView.Decide(ADecision: TAtlasLinkDecision);
begin
  if FDecided then
  begin
    Exit;
  end;
  FDecided := True;
  FAccept.Enabled := False;
  FReject.Enabled := False;
  FEdit.Enabled := False;
  if Assigned(FOnDecide) then
  begin
    FOnDecide(FId, ADecision);
  end;
end;

procedure TAtlasLinkDiffView.Reopen;
begin
  FDecided := False;
  FAccept.Enabled := True;
  FReject.Enabled := True;
  FEdit.Enabled := True;
end;

procedure TAtlasLinkDiffView.AcceptClick(Sender: TObject);
begin
  Decide(TAtlasLinkDecision.Accept);
end;

procedure TAtlasLinkDiffView.RejectClick(Sender: TObject);
begin
  Decide(TAtlasLinkDecision.Reject);
end;

procedure TAtlasLinkDiffView.EditClick(Sender: TObject);
begin
  Decide(TAtlasLinkDecision.Edit);
end;

procedure TAtlasLinkDiffView.ViewClose(Sender: TObject; var AAction: TCloseAction);
begin
  // Freigeben macht die Kopplung; Schließen ohne Entscheidung lehnt ab.
  AAction := caHide;
  Decide(TAtlasLinkDecision.Reject);
end;

end.
