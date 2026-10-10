unit Argus.IDE.Hover.Editor;

// Hover-Tooltip im Editor (#442) über die Code-Editor-API (ToolsAPI.Editor):
//   - Mausbewegung im Editor → Bezeichner unter der Maus (Zeile, Wortgrenzen).
//   - Nach 500 ms Verweilen auf demselben Bezeichner: textDocument/hover in
//     Teilen (TLspSession.HoverParts) und Tooltip unter dem Wort.
//   - Schließen 300 ms nachdem die Maus Bezeichner und Tooltip verlassen hat;
//     sofort bei Taste, Mausklick, Scrollen, Größenänderung, IDE inaktiv.
// Die IDE zeigt dann keinen eigenen Tooltip: GetHintText liefert '' (Manager).

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.ExtCtrls,
  ToolsAPI,
  ToolsAPI.Editor,
  Argus.Core.Lsp.Session,
  Argus.UI.Hover.Tip;

type
  TArgusHoverSessionFunc = reference to function: TLspSession;
  TArgusHoverLogFunc = reference to procedure(const AMessage: string);

  TArgusEditorHover = class
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
    end;
  private
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FTip: TArgusHoverTip;
    FShowTimer: TTimer;
    FHideTimer: TTimer;
    FSession: TArgusHoverSessionFunc;
    FLog: TArgusHoverLogFunc;
    // Bezeichner unter der Maus bzw. im offenen Tooltip.
    FEditor: TWinControl;
    FView: IOTAEditView;
    FLine: Integer;
    FStart: Integer;
    FWordRect: TRect;
    FKey: string;
    FShownKey: string;
    procedure EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
    procedure EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure EditorKeyDown(const Editor: TWinControl; Key: Word; Shift: TShiftState; var Handled: Boolean);
    procedure EditorScrolled(const Editor: TWinControl; const Direction: TCodeEditorScrollDirection);
    procedure EditorResized(const Editor: TWinControl);
    procedure ShowTimerTick(Sender: TObject);
    procedure HideTimerTick(Sender: TObject);
    procedure Log(const AMessage: string);
  public
    constructor Create(const ASession: TArgusHoverSessionFunc; const ALog: TArgusHoverLogFunc);
    destructor Destroy; override;
    procedure Hide;
  end;

implementation

uses
  Winapi.Windows,
  Vcl.Forms,
  Argus.Core.Completion.Word,
  Argus.IDE.Editor.Buffer,
  Argus.IDE.Editor.Style,
  Argus.IDE.Settings.Store;

{ TArgusEditorHover.TEvents }

function TArgusEditorHover.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevWindowEvents, cevMouseEvents, cevKeyboardEvents];
end;

{ TArgusEditorHover }

constructor TArgusEditorHover.Create(const ASession: TArgusHoverSessionFunc; const ALog: TArgusHoverLogFunc);
var
  Services: INTACodeEditorServices;
begin
  inherited Create;
  FSession := ASession;
  FLog := ALog;
  FIndex := -1;
  FTip := TArgusHoverTip.Create(nil);
  FShowTimer := TTimer.Create(nil);
  FShowTimer.Enabled := False;
  FShowTimer.Interval := 500;
  FShowTimer.OnTimer := ShowTimerTick;
  FHideTimer := TTimer.Create(nil);
  FHideTimer.Enabled := False;
  FHideTimer.Interval := 300;
  FHideTimer.OnTimer := HideTimerTick;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorMouseMove := EditorMouseMove;
  FEvents.OnEditorMouseDown := EditorMouseDown;
  FEvents.OnEditorKeyDown := EditorKeyDown;
  FEvents.OnEditorScrolled := EditorScrolled;
  FEvents.OnEditorResized := EditorResized;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    FIndex := Services.AddEditorEventsNotifier(FEventsRef);
end;

destructor TArgusEditorHover.Destroy;
var
  Services: INTACodeEditorServices;
begin
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.RemoveEditorEventsNotifier(FIndex);
  FEvents.OnEditorMouseMove := nil;
  FEvents.OnEditorMouseDown := nil;
  FEvents.OnEditorKeyDown := nil;
  FEvents.OnEditorScrolled := nil;
  FEvents.OnEditorResized := nil;
  FEventsRef := nil;
  FShowTimer.Free;
  FHideTimer.Free;
  FTip.Free;
  inherited Destroy;
end;

procedure TArgusEditorHover.Log(const AMessage: string);
begin
  if Assigned(FLog) then
    FLog(AMessage);
end;

procedure TArgusEditorHover.Hide;
begin
  FShowTimer.Enabled := False;
  FHideTimer.Enabled := False;
  FTip.HidePopup;
  FShownKey := '';
  FKey := '';
  FView := nil;
end;

procedure TArgusEditorHover.EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
var
  Services: INTACodeEditorServices;
  State: INTACodeEditorState;
  Column, VisibleLine, Line, Index, Start, Stop: Integer;
  View: IOTAEditView;
  Text, Key: string;
  First, Last: TRect;
begin
  try
    if not TArgusIdeSettings.Current.Enabled or not TArgusIdeSettings.Current.HoverTooltip or
      not Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
      Exit;
    State := Services.EditorState[Editor];
    Key := '';
    if (State <> nil) and State.PointToCharacterPos(Point(X, Y), Column, VisibleLine) then
    begin
      View := State.View;
      Line := State.LineState[VisibleLine].LogicalLineNum;
      if (View <> nil) and (View.Buffer <> nil) and (Line > 0) then
      begin
        Text := TArgusEditorBuffer.LineText(View, Line);
        Index := TLspSession.ColumnToIndex(Text, Column, TArgusEditorBuffer.TabWidth(View.Buffer));
        if (Index < Length(Text)) and TArgusWord.IsIdentifierChar(Text[Index + 1]) and
          not CharInSet(Text[TArgusWord.StartBefore(Text, Index + 1) + 1], ['0'..'9']) then
        begin
          Start := TArgusWord.StartBefore(Text, Index + 1);
          Stop := TArgusWord.EndAfter(Text, Index);
          Key := Format('%s|%d|%d', [View.Buffer.FileName, Line, Start]);
          if Key <> FKey then
          begin
            FEditor := Editor;
            FView := View;
            FLine := Line;
            FStart := Start;
            // Wortrechteck aus der ersten und letzten Spalte des Worts (Bildschirmkoordinaten).
            First := State.GetCharacterPosPx(Column - (Index - Start), VisibleLine);
            Last := State.GetCharacterPosPx(Column + (Stop - Index - 1), VisibleLine);
            FWordRect := TRect.Create(Editor.ClientToScreen(First.TopLeft), Editor.ClientToScreen(Last.BottomRight));
          end;
        end;
      end;
    end;
    if Key = '' then
    begin
      // Kein Bezeichner: offenen Tooltip nach 300 ms schließen, wartenden verwerfen.
      FShowTimer.Enabled := False;
      FKey := '';
      if FTip.IsShown then
        FHideTimer.Enabled := True;
      Exit;
    end;
    if Key = FShownKey then
    begin
      FHideTimer.Enabled := False;
      Exit;
    end;
    if Key <> FKey then
    begin
      FKey := Key;
      FShowTimer.Enabled := False;
      FShowTimer.Enabled := True;
      if FTip.IsShown then
        FHideTimer.Enabled := True;
    end;
  except
    on E: Exception do
      Log('Hover: ' + E.Message);
  end;
end;

procedure TArgusEditorHover.ShowTimerTick(Sender: TObject);
var
  Session: TLspSession;
  Text: string;
  Parts: TLspHoverParts;
  Content: TArgusHoverContent;
begin
  FShowTimer.Enabled := False;
  try
    if (FView = nil) or (FKey = '') or not Application.Active then
      Exit;
    Session := nil;
    if Assigned(FSession) then
      Session := FSession();
    if Session = nil then
      Exit;
    Text := TArgusEditorBuffer.Text(FView.Buffer);
    Parts := Session.HoverParts(FView.Buffer.FileName, Text, FLine - 1, FStart);
    if not Parts.Found then
    begin
      Hide;
      Exit;
    end;
    Content.Declaration := Parts.Declaration;
    Content.UnitName := Parts.UnitName;
    Content.Documentation := Parts.Documentation;
    Content.Value := Parts.Value;
    Content.Deprecation := Parts.Deprecation;
    TArgusIdeStyle.Apply(FTip, FWordRect);
    FTip.ShowContent(Content, FWordRect);
    FShownKey := FKey;
    FHideTimer.Enabled := False;
  except
    on E: Exception do
      Log('Hover: ' + E.Message);
  end;
end;

procedure TArgusEditorHover.HideTimerTick(Sender: TObject);
begin
  FHideTimer.Enabled := False;
  // Die Maus darf in den Tooltip wandern (#442).
  if FTip.IsShown and PtInRect(FTip.BoundsRect, Mouse.CursorPos) and Application.Active then
  begin
    FHideTimer.Enabled := True;
    Exit;
  end;
  FTip.HidePopup;
  FShownKey := '';
end;

procedure TArgusEditorHover.EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  Hide;
end;

procedure TArgusEditorHover.EditorKeyDown(const Editor: TWinControl; Key: Word; Shift: TShiftState;
  var Handled: Boolean);
begin
  Hide;
end;

procedure TArgusEditorHover.EditorScrolled(const Editor: TWinControl; const Direction: TCodeEditorScrollDirection);
begin
  Hide;
end;

procedure TArgusEditorHover.EditorResized(const Editor: TWinControl);
begin
  Hide;
end;

end.
