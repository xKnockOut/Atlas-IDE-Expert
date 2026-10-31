unit Atlas.UI.Tracker.DocBox;

// Gesetzte Doku in voller Höhe (Beschreibung, Kommentar, Vorschau des
// Kommentar-Editors, #1264): Links, Auswahl mit Strg+C und Kästchen von
// Checklisten (#1273, TaskHint/TasksLocked). Eigene Unit, damit Issue-Ansicht
// und Kommentar-Editor sie nutzen, ohne sich gegenseitig einzubinden (#1450).

interface

uses
  System.SysUtils,
  System.Classes,
  Winapi.Messages,
  Vcl.Controls,
  Vcl.Graphics,
  Atlas.Core.Style.Palette,
  Atlas.Core.Documentation.Contract,
  Atlas.UI.Documentation.View;

type
  /// <summary>Eine gesetzte Doku in voller Höhe (Beschreibung bzw. Kommentar).</summary>
  TAtlasIssueDocBox = class(TCustomControl)
  private
    FView: TAtlasDocView;
    FDoc: TAtlasDoc;
    FColors: TAtlasColors;
    FMono: TFont;
    FBuiltWidth: Integer;
    FOnLink: TProc<string>;
    FTaskHint: string;
    FTasksLocked: Boolean;
    procedure Rebuild;
    function TaskAt(X, Y: Integer): Boolean;
    procedure WMGetDlgCode(var AMessage: TWMGetDlgCode); message WM_GETDLGCODE;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure CreateWnd; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SetDoc(const ADoc: TAtlasDoc; const AColors: TAtlasColors; AMono: TFont);
    function SelectedText: string;
    /// <summary>Enthält ein anklickbares Kästchen einer Checkliste (#1273).</summary>
    function HasTasks: Boolean;
    property View: TAtlasDocView read FView;
    property OnLink: TProc<string> read FOnLink write FOnLink;
    /// <summary>Tooltip über einem Kästchen; TasksLocked: Kästchen nur lesend (Pfeil statt Hand, kein Klick).
    /// </summary>
    property TaskHint: string read FTaskHint write FTaskHint;
    property TasksLocked: Boolean read FTasksLocked write FTasksLocked;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  System.UITypes,
  Vcl.Forms,
  Vcl.Clipbrd,
  Atlas.Core.Style.Color,
  Atlas.Core.Documentation.Layout,
  Atlas.Core.Tracker.Markdown;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

{ TAtlasIssueDocBox }

constructor TAtlasIssueDocBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FView := TAtlasDocView.Create;
  FMono := TFont.Create;
  FColors := TAtlasColors.Light;
  TabStop := True;
  DoubleBuffered := True;
  Height := 16;
end;

destructor TAtlasIssueDocBox.Destroy;
begin
  FView.Free;
  FMono.Free;
  inherited;
end;

procedure TAtlasIssueDocBox.WMGetDlgCode(var AMessage: TWMGetDlgCode);
begin
  inherited;
  AMessage.Result := AMessage.Result or DLGC_WANTARROWS;
end;

procedure TAtlasIssueDocBox.SetDoc(const ADoc: TAtlasDoc; const AColors: TAtlasColors; AMono: TFont);
begin
  FDoc := ADoc;
  FColors := AColors;
  if AMono <> nil then
    FMono.Assign(AMono);
  FBuiltWidth := -1;
  Rebuild;
end;

procedure TAtlasIssueDocBox.CreateWnd;
begin
  inherited;
  // Messen braucht ein Fenster.
  FBuiltWidth := -1;
  Rebuild;
end;

procedure TAtlasIssueDocBox.Rebuild;
var
  mHeight: Integer;
begin
  if not HandleAllocated or (ClientWidth <= 0) or (ClientWidth = FBuiltWidth) then
    Exit;
  FBuiltWidth := ClientWidth;
  Canvas.Font := Font;
  FView.Build(Canvas, FDoc, ClientWidth, FMono, Font, CurrentPPI, TAtlasDocLabels.German,
    Default(TAtlasDocSignature), True);
  mHeight := Max(FView.Height, 1);
  if Height <> mHeight then
    Height := mHeight;
  Invalidate;
end;

procedure TAtlasIssueDocBox.Resize;
begin
  inherited;
  Rebuild;
end;

procedure TAtlasIssueDocBox.Paint;
begin
  Canvas.Brush.Color := ToColor(FColors.Surface);
  Canvas.FillRect(ClientRect);
  FView.Paint(Canvas, FColors, 0, 0);
end;

procedure TAtlasIssueDocBox.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mLink: Integer;
  mUrl: string;
begin
  inherited;
  if Button <> mbLeft then
    Exit;
  if CanFocus then
    SetFocus;
  mLink := FView.LinkAt(X, Y);
  if mLink >= 0 then
  begin
    // Kästchen nur lesend (#1273): kein Klick.
    if FTasksLocked and TaskAt(X, Y) then
      Exit;
    if FView.Link(mLink).Kind = TAtlasDocLinkKind.Url then
    begin
      mUrl := FView.Link(mLink).Url;
      if Assigned(FOnLink) then
        FOnLink(mUrl);
    end;
    Exit;
  end;
  FView.StartSelection(Canvas, X, Y);
  Invalidate;
end;

procedure TAtlasIssueDocBox.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  mLink: Integer;
begin
  inherited;
  if FView.Selecting then
  begin
    FView.ExtendSelection(Canvas, X, Y);
    Invalidate;
    Exit;
  end;
  mLink := FView.LinkAt(X, Y);
  // Kästchen (#1273): Tooltip, nur lesend mit Pfeil.
  if (mLink >= 0) and TaskAt(X, Y) then
  begin
    if Hint <> FTaskHint then
    begin
      Hint := FTaskHint;
      Application.CancelHint;
    end;
    ShowHint := FTaskHint <> '';
    if FTasksLocked then
    begin
      Cursor := crArrow;
      mLink := -1;
    end
    else
      Cursor := crHandPoint;
  end
  else
  begin
    if Hint <> '' then
    begin
      Hint := '';
      Application.CancelHint;
    end;
    if mLink >= 0 then
      Cursor := crHandPoint
    else
      Cursor := crIBeam;
  end;
  if mLink <> FView.HotLink then
  begin
    FView.HotLink := mLink;
    Invalidate;
  end;
end;

function TAtlasIssueDocBox.TaskAt(X, Y: Integer): Boolean;
var
  mLink, mIndex: Integer;
begin
  mLink := FView.LinkAt(X, Y);
  Result := (mLink >= 0) and (FView.Link(mLink).Kind = TAtlasDocLinkKind.Url) and
    TAtlasTrackerMarkdown.TaskIndexOf(FView.Link(mLink).Url, mIndex);
end;

function TAtlasIssueDocBox.HasTasks: Boolean;
var
  mSection: TAtlasDocSection;
  mRun: TAtlasDocRun;
  mIndex: Integer;
begin
  Result := False;
  for mSection in FDoc.Sections do
    for mRun in mSection.Runs do
      if (mRun.Kind = TAtlasDocRunKind.Bullet) and TAtlasTrackerMarkdown.TaskIndexOf(mRun.Target, mIndex) then
        Exit(True);
end;

procedure TAtlasIssueDocBox.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if FView.Selecting then
  begin
    FView.EndSelection;
    Invalidate;
  end;
end;

procedure TAtlasIssueDocBox.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited;
  if (ssCtrl in Shift) and ((Key = Ord('C')) or (Key = VK_INSERT)) and FView.HasSelection then
  begin
    Clipboard.AsText := FView.SelectedText;
    Key := 0;
  end;
end;

function TAtlasIssueDocBox.SelectedText: string;
begin
  Result := FView.SelectedText;
end;

end.
