unit Atlas.UI.Tracker.EndPullRows;

// Abschnitt „Pull Request anlegen“ im Beenden-Dialog (#2136, nur GitHub mit
// Git): Häkchen (Vorgabe issues.github.createPr), „Von → nach“ (Branch des
// Issues → issues.github.prBase, leer = Standard-Branch), Titel (Titel des
// Issues), Text (issues.github.prBody, ausgefüllt), „Labels und Meilenstein
// des Issues übernehmen“, Prüfer aus der Benutzerliste des Repositorys und
// „als Entwurf“ (issues.github.prDraft).
// - Ist für den Branch schon ein Pull Request offen, nennt der Abschnitt ihn
//   und das Häkchen ist aus; angehakt pusht „Senden“ dann nur (kein zweiter).
// - Spec liefert, was angelegt werden soll; ohne Häkchen Wanted = False.
// - Nach dem Anlegen bleibt der Abschnitt gesperrt (Lock), ein erneutes
//   Senden überspringt ihn (TAtlasTrackerEndSteps).
// - OnToggle meldet das Häkchen, damit der Dialog den Abschluss („Schließt
//   der Merge“) und die Beschriftung von „Senden“ anpasst.

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Tracker.Contract,
  Atlas.UI.Tracker.ValueBox,
  Atlas.UI.Foundation.Dialog;

type
  /// <summary>Was der Abschnitt anbietet; Offered False = kein Abschnitt.</summary>
  TAtlasEndPullOffer = record
    Offered: Boolean;
    /// <summary>Vorab angehakt (issues.github.createPr, ohne offenen Pull Request).</summary>
    Checked: Boolean;
    Head: string;
    /// <summary>Ziel; '' = Standard-Branch des Repositorys.</summary>
    Base: string;
    Title: string;
    /// <summary>Ausgefüllte Textvorlage (Zeilen mit #10).</summary>
    Body: string;
    Draft: Boolean;
    /// <summary>Adresse eines offenen Pull Requests für den Branch; '' ohne.</summary>
    Existing: string;
    /// <summary>Repository des Trackers „owner/repo“ (für den Hinweis bei einem Fork).</summary>
    Repository: string;
    class function None: TAtlasEndPullOffer; static;
  end;

  /// <summary>Steuerelemente des Abschnitts (für Tests); nil ohne Angebot.</summary>
  TAtlasEndPullParts = record
    Check: TCheckBox;
    Route: TLabel;
    Title: TEdit;
    Body: TMemo;
    CopyIssue: TCheckBox;
    Reviewer: TAtlasValueBox;
    Draft: TCheckBox;
  end;

  TAtlasEndPullRows = class(TComponent)
  private
    FDialog: TAtlasDialog;
    FOffer: TAtlasEndPullOffer;
    FParts: TAtlasEndPullParts;
    FOnToggle: TNotifyEvent;
    FTitleTouched: Boolean;
    procedure AddRows;
    function AddCaptionRow(AHeight96: Integer; const ACaption: string): TPanel;
    procedure CheckClick(Sender: TObject);
    procedure TitleChange(Sender: TObject);
    procedure ShowOpen;
    /// <summary>AValue96 in Pixeln des Dialogs.</summary>
    function Px(AValue96: Integer): Integer;
  public
    constructor CreateRows(ADialog: TAtlasDialog; const AOffer: TAtlasEndPullOffer);
    /// <summary>Häkchen gesetzt (und angeboten).</summary>
    function Wanted: Boolean;
    /// <summary>Was angelegt werden soll; Wanted False ohne Häkchen.</summary>
    function Spec: TAtlasTrackerPullSpec;
    /// <summary>Titel des Issues nachgeladen; ersetzt den Titel, solange er nicht von Hand geändert ist.</summary>
    procedure SetTitle(const ATitle: string);
    /// <summary>Benutzer des Repositorys für „Prüfer“.</summary>
    procedure SetUsers(const AUsers: TArray<string>);
    /// <summary>Sperren beim Senden bzw. für immer, sobald ein Pull Request steht (ADone).</summary>
    procedure Lock(ABusy, ADone: Boolean);
    property Parts: TAtlasEndPullParts read FParts;
    property Offer: TAtlasEndPullOffer read FOffer;
    property OnToggle: TNotifyEvent read FOnToggle write FOnToggle;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Tracker.GitHubStrings;

const
  cRowHeight = 26;
  cBodyHeight = 64;
  cLabelTop = 4;
  cCheckTop = 3;
  cFieldLeft = 180;
  cFieldWidth = 240;
  cGap = 8;
  cDesignPpi = 96;

{ TAtlasEndPullOffer }

class function TAtlasEndPullOffer.None: TAtlasEndPullOffer;
begin
  Result := Default(TAtlasEndPullOffer);
  Result.Offered := False;
end;

{ TAtlasEndPullRows }

constructor TAtlasEndPullRows.CreateRows(ADialog: TAtlasDialog; const AOffer: TAtlasEndPullOffer);
begin
  inherited Create(ADialog);
  FDialog := ADialog;
  FOffer := AOffer;
  FParts := Default(TAtlasEndPullParts);
  if AOffer.Offered then
  begin
    AddRows;
  end;
end;

function TAtlasEndPullRows.Px(AValue96: Integer): Integer;
begin
  Result := AValue96 * FDialog.CurrentPPI div cDesignPpi;
end;

/// <summary>Zeile mit Beschriftung links.</summary>
function TAtlasEndPullRows.AddCaptionRow(AHeight96: Integer; const ACaption: string): TPanel;
begin
  Result := FDialog.AddRow(AHeight96);
  FDialog.AddLabel(Result, ACaption).Top := Px(cLabelTop);
end;

procedure TAtlasEndPullRows.AddRows;
var
  mRow: TPanel;
  mBase: string;
begin
  mRow := FDialog.AddRow(cRowHeight);
  FParts.Check := TCheckBox.Create(FDialog);
  FParts.Check.Parent := mRow;
  FParts.Check.Caption := TAtlasGitHubStrings.Text(TAtlasGitHubTextId.EndPull);
  FParts.Check.SetBounds(0, Px(cCheckTop), Px(cFieldLeft + cFieldWidth),
    FParts.Check.Height);
  FParts.Check.Checked := FOffer.Checked;
  FParts.Check.OnClick := CheckClick;

  mRow := AddCaptionRow(cRowHeight, TAtlasGitHubStrings.Text(TAtlasGitHubTextId.EndPullRoute));
  mBase := FOffer.Base;
  if mBase = '' then
  begin
    mBase := TAtlasGitHubStrings.Text(TAtlasGitHubTextId.EndPullDefaultBase);
  end;
  FParts.Route := FDialog.AddLabel(mRow, FOffer.Head + ' → ' + mBase);
  FParts.Route.Left := Px(cFieldLeft);
  FParts.Route.Top := Px(cLabelTop);

  mRow := AddCaptionRow(cRowHeight, TAtlasGitHubStrings.Text(TAtlasGitHubTextId.EndPullTitle));
  FParts.Title := TEdit.Create(FDialog);
  FParts.Title.Parent := mRow;
  FParts.Title.SetBounds(Px(cFieldLeft), 0, Px(cFieldWidth), FParts.Title.Height);
  FParts.Title.Text := FOffer.Title;
  FParts.Title.OnChange := TitleChange;
  FDialog.FitRight(FParts.Title);

  mRow := AddCaptionRow(cBodyHeight, TAtlasGitHubStrings.Text(TAtlasGitHubTextId.EndPullBody));
  FParts.Body := TMemo.Create(FDialog);
  FParts.Body.Parent := mRow;
  FParts.Body.SetBounds(Px(cFieldLeft), 0, Px(cFieldWidth),
    Px(cBodyHeight - cGap div 2));
  FParts.Body.ScrollBars := ssVertical;
  FParts.Body.Text := StringReplace(FOffer.Body, #10, sLineBreak, [rfReplaceAll]);
  FDialog.FitRight(FParts.Body);

  mRow := AddCaptionRow(cRowHeight, TAtlasGitHubStrings.Text(TAtlasGitHubTextId.EndPullReviewer));
  FParts.Reviewer := TAtlasValueBox.Create(FDialog);
  FParts.Reviewer.Parent := mRow;
  FParts.Reviewer.Left := Px(cFieldLeft);
  FParts.Reviewer.Top := 0;
  FParts.Reviewer.Width := Px(cFieldWidth);

  mRow := FDialog.AddRow(cRowHeight);
  FParts.CopyIssue := TCheckBox.Create(FDialog);
  FParts.CopyIssue.Parent := mRow;
  FParts.CopyIssue.Caption := TAtlasGitHubStrings.Text(TAtlasGitHubTextId.EndPullCopyIssue);
  FParts.CopyIssue.SetBounds(Px(cFieldLeft), Px(cCheckTop),
    Px(cFieldWidth), FParts.CopyIssue.Height);
  FParts.CopyIssue.Checked := True;
  FParts.Draft := TCheckBox.Create(FDialog);
  FParts.Draft.Parent := mRow;
  FParts.Draft.Caption := TAtlasGitHubStrings.Text(TAtlasGitHubTextId.EndPullDraft);
  FParts.Draft.SetBounds(FParts.CopyIssue.BoundsRect.Right + Px(cGap),
    Px(cCheckTop), Px(cFieldWidth) div 2, FParts.Draft.Height);
  FParts.Draft.Checked := FOffer.Draft;
  ShowOpen;
  Lock(False, False);
end;

/// <summary>Ein offener Pull Request steht in „Von → nach“.</summary>
procedure TAtlasEndPullRows.ShowOpen;
begin
  if FOffer.Existing <> '' then
  begin
    FParts.Route.Caption := FParts.Route.Caption + '   ' +
      TAtlasGitHubStrings.Fmt(TAtlasGitHubTextId.EndPullExisting, [FOffer.Existing]);
  end;
end;

procedure TAtlasEndPullRows.CheckClick(Sender: TObject);
begin
  Lock(False, False);
  if Assigned(FOnToggle) then
  begin
    FOnToggle(Self);
  end;
end;

procedure TAtlasEndPullRows.TitleChange(Sender: TObject);
begin
  FTitleTouched := FParts.Title.Focused;
end;

function TAtlasEndPullRows.Wanted: Boolean;
begin
  Result := (FParts.Check <> nil) and FParts.Check.Checked;
end;

function TAtlasEndPullRows.Spec: TAtlasTrackerPullSpec;
begin
  Result := TAtlasTrackerPullSpec.None;
  if not Wanted then
  begin
    Exit;
  end;
  Result.Wanted := True;
  Result.Head := FOffer.Head;
  Result.Base := FOffer.Base;
  Result.Title := Trim(FParts.Title.Text);
  Result.Body := StringReplace(FParts.Body.Text, #13#10, #10, [rfReplaceAll]);
  Result.CopyIssue := FParts.CopyIssue.Checked;
  Result.Draft := FParts.Draft.Checked;
  Result.Reviewers := nil;
  if Trim(FParts.Reviewer.Value) <> '' then
  begin
    Result.Reviewers := TArray<string>.Create(Trim(FParts.Reviewer.Value));
  end;
end;

procedure TAtlasEndPullRows.SetTitle(const ATitle: string);
begin
  if (FParts.Title <> nil) and not FTitleTouched and (Trim(ATitle) <> '') then
  begin
    FParts.Title.Text := ATitle;
    FTitleTouched := False;
  end;
end;

procedure TAtlasEndPullRows.SetUsers(const AUsers: TArray<string>);
begin
  if FParts.Reviewer <> nil then
  begin
    FParts.Reviewer.SetValues(AUsers);
  end;
end;

procedure TAtlasEndPullRows.Lock(ABusy, ADone: Boolean);
var
  mOpen: Boolean;
begin
  if FParts.Check = nil then
  begin
    Exit;
  end;
  FParts.Check.Enabled := not ABusy and not ADone;
  mOpen := FParts.Check.Enabled and FParts.Check.Checked;
  FParts.Title.Enabled := mOpen;
  FParts.Body.Enabled := mOpen;
  FParts.CopyIssue.Enabled := mOpen;
  FParts.Reviewer.Enabled := mOpen;
  FParts.Draft.Enabled := mOpen;
end;

end.
