unit Argus.IDE.Hover.Editor;

// Hover-Tooltip im Editor (#442) über die Code-Editor-API (ToolsAPI.Editor):
//   - Mausbewegung im Editor → Bezeichner unter der Maus (Zeile, Wortgrenzen).
//   - Nach 500 ms Verweilen auf demselben Bezeichner: textDocument/hover
//     (TLspSession.HoverData) und Tooltip unter dem Wort (Kurzform).
//   - Schließen 300 ms nachdem die Maus Bezeichner und Tooltip verlassen hat;
//     sofort bei Taste (außer Umschalt, Strg, Alt allein), Mausklick, Scrollen,
//     Größenänderung, IDE inaktiv (ein Wächter prüft das, solange der Tooltip
//     offen ist, #414).
// Navigation über Typen (#588):
//   - Klick auf einen Typ (Deklaration, Kette, Pfad) zeigt dessen Inhalt im
//     selben Fenster (Hover über den Fundort, TArgusHoverHistory) und heftet
//     den Tooltip an: Dann schließt er nur mit Esc oder Klick in den Editor.
//   - Strg+Klick springt zur Deklaration und schließt.
//   - Tasten über den gemeinsamen Hook, solange der Tooltip sichtbar ist:
//     Esc schließt; angeheftet Rücktaste bzw. Alt+← zurück; angeheftet oder mit
//     der Maus über dem Tooltip F12, Umschalt+F12, Strg+C und F1 für den
//     angezeigten Typ.
// Probleme (#398): Liegt unter der Maus ein Problem, zeigt der Tooltip es oben
// an, auch ohne Bezeichner (dann nur das Problem).
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
  Argus.Core.Hover.Contract,
  Argus.Core.Hover.History,
  Argus.Core.Problems.Contract,
  Argus.IDE.Editor.KeyHook,
  Argus.UI.Hover.Tip;

type
  TArgusHoverSessionFunc = reference to function: TLspSession;
  TArgusHoverLogFunc = reference to procedure(const AMessage: string);
  /// <summary>Probleme an der Stelle (0-basiert, #398).</summary>
  TArgusHoverProblemsFunc = reference to function(const AFileName: string; ALine, ACharacter: Integer):
    TArray<TArgusProblem>;

  TArgusEditorHover = class
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
    end;

    THoverKeys = class(TArgusKeyClient)
    private
      FOwner: TArgusEditorHover;
    protected
      function WantsKey(AKey: Word; AShift: TShiftState): Boolean; override;
      procedure HandleKey(AKey: Word; AShift: TShiftState); override;
    public
      constructor Create(AOwner: TArgusEditorHover);
    end;
  public const
    /// <summary>Nach Vervollständigung (0) und Parameter-Hint (10).</summary>
    KeyPriority = 20;
  private
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FTip: TArgusHoverTip;
    FKeys: THoverKeys;
    FHistory: TArgusHoverHistory;
    FUsagesCount: Integer;
    FShowTimer: TTimer;
    FHideTimer: TTimer;
    FWatchTimer: TTimer;
    FSession: TArgusHoverSessionFunc;
    FLog: TArgusHoverLogFunc;
    FProblemsAt: TArgusHoverProblemsFunc;
    // Probleme an der Mausposition; nur Probleme, wenn dort kein Bezeichner steht.
    FProblems: TArray<TArgusProblem>;
    FMouseCharacter: Integer;
    FProblemsOnly: Boolean;
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
    procedure WatchTimerTick(Sender: TObject);
    procedure TipLink(Sender: TObject; const ARef: TArgusHoverTypeRef; AControl: Boolean);
    procedure TipPath(Sender: TObject; AIndex: Integer);
    procedure TipBack(Sender: TObject);
    procedure TipAction(Sender: TObject; AAction: TArgusHoverAction);
    function CurrentSession: TLspSession;
    function Fetch(const ARef: TArgusHoverTypeRef; out AData: TArgusHoverData): Boolean;
    function CurrentView: TArgusHoverView;
    procedure Refresh;
    procedure Execute(AAction: TArgusHoverAction);
    procedure ShowUsages;
    function MouseOverTip: Boolean;
    function WantsKey(AKey: Word; AShift: TShiftState): Boolean;
    procedure HandleKey(AKey: Word; AShift: TShiftState);
    procedure Log(const AMessage: string);
  public
    constructor Create(const ASession: TArgusHoverSessionFunc; const ALog: TArgusHoverLogFunc;
      const AProblemsAt: TArgusHoverProblemsFunc = nil);
    destructor Destroy; override;
    procedure Hide;
    /// <summary>Öffnet AFileName im Editor und setzt den Cursor (0-basiert).</summary>
    class procedure GoToLocation(const AFileName: string; ALine, ACharacter: Integer); static;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.ShellAPI,
  System.IOUtils,
  Vcl.Forms,
  Vcl.Clipbrd,
  Argus.Core.Completion.Word,
  Argus.IDE.Editor.Buffer,
  Argus.IDE.Editor.Style,
  Argus.IDE.Settings.Store,
  Argus.UI.Strings;

{ TArgusEditorHover.TEvents }

function TArgusEditorHover.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevWindowEvents, cevMouseEvents, cevKeyboardEvents];
end;

{ TArgusEditorHover.THoverKeys }

constructor TArgusEditorHover.THoverKeys.Create(AOwner: TArgusEditorHover);
begin
  inherited Create(KeyPriority);
  FOwner := AOwner;
end;

function TArgusEditorHover.THoverKeys.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := FOwner.WantsKey(AKey, AShift);
end;

procedure TArgusEditorHover.THoverKeys.HandleKey(AKey: Word; AShift: TShiftState);
begin
  FOwner.HandleKey(AKey, AShift);
end;

{ TArgusEditorHover }

constructor TArgusEditorHover.Create(const ASession: TArgusHoverSessionFunc; const ALog: TArgusHoverLogFunc;
  const AProblemsAt: TArgusHoverProblemsFunc);
var
  Services: INTACodeEditorServices;
begin
  inherited Create;
  FSession := ASession;
  FLog := ALog;
  FProblemsAt := AProblemsAt;
  FIndex := -1;
  FUsagesCount := -1;
  FTip := TArgusHoverTip.Create(nil);
  FTip.OnLink := TipLink;
  FTip.OnPath := TipPath;
  FTip.OnBack := TipBack;
  FTip.OnAction := TipAction;
  FKeys := THoverKeys.Create(Self);
  FHistory := TArgusHoverHistory.Create(Fetch);
  FShowTimer := TTimer.Create(nil);
  FShowTimer.Enabled := False;
  FShowTimer.Interval := 500;
  FShowTimer.OnTimer := ShowTimerTick;
  FHideTimer := TTimer.Create(nil);
  FHideTimer.Enabled := False;
  FHideTimer.Interval := 300;
  FHideTimer.OnTimer := HideTimerTick;
  FWatchTimer := TTimer.Create(nil);
  FWatchTimer.Enabled := False;
  FWatchTimer.Interval := 250;
  FWatchTimer.OnTimer := WatchTimerTick;
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
  TArgusKeyHook.Remove(FKeys);
  FEvents.OnEditorMouseMove := nil;
  FEvents.OnEditorMouseDown := nil;
  FEvents.OnEditorKeyDown := nil;
  FEvents.OnEditorScrolled := nil;
  FEvents.OnEditorResized := nil;
  FEventsRef := nil;
  FShowTimer.Free;
  FHideTimer.Free;
  FWatchTimer.Free;
  FTip.Free;
  FHistory.Free;
  FKeys.Free;
  inherited Destroy;
end;

procedure TArgusEditorHover.Log(const AMessage: string);
begin
  if Assigned(FLog) then
    FLog(AMessage);
end;

function TArgusEditorHover.CurrentSession: TLspSession;
begin
  Result := nil;
  if Assigned(FSession) then
    Result := FSession();
end;

function TArgusEditorHover.Fetch(const ARef: TArgusHoverTypeRef; out AData: TArgusHoverData): Boolean;
var
  Session: TLspSession;
begin
  AData := Default(TArgusHoverData);
  Session := CurrentSession;
  Result := (Session <> nil) and ARef.HasLocation;
  if Result then
  begin
    AData := Session.HoverDataAt(ARef.FileName, ARef.Line, ARef.Character);
    Result := AData.Found;
  end;
end;

function TArgusEditorHover.CurrentView: TArgusHoverView;
begin
  Result := TArgusHoverView.Create(FHistory.Current);
  Result.Path := FHistory.Path;
  Result.Pinned := FHistory.Pinned;
  Result.CanGoBack := FHistory.CanGoBack;
  Result.UsagesCount := FUsagesCount;
  // Probleme gehören zur Stelle im Editor, nicht zu angeklickten Typen.
  if FHistory.Count <= 1 then
    Result.Problems := FProblems;
end;

procedure TArgusEditorHover.Refresh;
begin
  FTip.UpdateContent(CurrentView);
end;

procedure TArgusEditorHover.Hide;
begin
  FWatchTimer.Enabled := False;
  FShowTimer.Enabled := False;
  FHideTimer.Enabled := False;
  TArgusKeyHook.Remove(FKeys);
  FTip.HidePopup;
  FHistory.Clear;
  FProblems := nil;
  FUsagesCount := -1;
  FShownKey := '';
  FKey := '';
  FView := nil;
end;

function TArgusEditorHover.MouseOverTip: Boolean;
begin
  Result := FTip.IsShown and PtInRect(FTip.BoundsRect, Mouse.CursorPos);
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
    // Angeheftet: Der Tooltip bleibt, bis Esc oder ein Klick in den Editor ihn schließt (#588).
    if FHistory.Pinned and FTip.IsShown then
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
            FMouseCharacter := Index;
            FProblemsOnly := False;
            // Wortrechteck aus der ersten und letzten Spalte des Worts (Bildschirmkoordinaten).
            First := State.GetCharacterPosPx(Column - (Index - Start), VisibleLine);
            Last := State.GetCharacterPosPx(Column + (Stop - Index - 1), VisibleLine);
            FWordRect := TRect.Create(Editor.ClientToScreen(First.TopLeft), Editor.ClientToScreen(Last.BottomRight));
          end;
        end
        else if Assigned(FProblemsAt) and
          (Length(FProblemsAt(View.Buffer.FileName, Line - 1, Index)) > 0) then
        begin
          // Kein Bezeichner, aber ein Problem (etwa ein fehlendes Semikolon): nur das Problem zeigen.
          Key := Format('%s|%d|p%d', [View.Buffer.FileName, Line, Index]);
          if Key <> FKey then
          begin
            FEditor := Editor;
            FView := View;
            FLine := Line;
            FStart := Index;
            FMouseCharacter := Index;
            FProblemsOnly := True;
            First := State.GetCharacterPosPx(Column, VisibleLine);
            FWordRect := TRect.Create(Editor.ClientToScreen(First.TopLeft), Editor.ClientToScreen(First.BottomRight));
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
  Data: TArgusHoverData;
begin
  FShowTimer.Enabled := False;
  try
    if (FView = nil) or (FKey = '') or not Application.Active then
      Exit;
    FProblems := nil;
    if Assigned(FProblemsAt) then
      FProblems := FProblemsAt(FView.Buffer.FileName, FLine - 1, FMouseCharacter);
    Data := Default(TArgusHoverData);
    if not FProblemsOnly then
    begin
      Session := CurrentSession;
      if Session <> nil then
      begin
        Text := TArgusEditorBuffer.Text(FView.Buffer);
        Data := Session.HoverData(FView.Buffer.FileName, Text, FLine - 1, FStart);
      end;
    end;
    if not Data.Found and (Length(FProblems) = 0) then
    begin
      Hide;
      Exit;
    end;
    FHistory.Start(Data);
    FUsagesCount := -1;
    TArgusIdeStyle.Apply(FTip, FWordRect);
    FTip.ShowContent(CurrentView, FWordRect);
    TArgusKeyHook.Add(FKeys);
    FShownKey := FKey;
    FHideTimer.Enabled := False;
    FWatchTimer.Enabled := True;
  except
    on E: Exception do
      Log('Hover: ' + E.Message);
  end;
end;

procedure TArgusEditorHover.WatchTimerTick(Sender: TObject);
begin
  // Andere Anwendung im Vordergrund: kein Argus-Fenster bleibt stehen (#414).
  if not FTip.IsShown then
    FWatchTimer.Enabled := False
  else if not Application.Active then
    Hide;
end;

procedure TArgusEditorHover.HideTimerTick(Sender: TObject);
begin
  FHideTimer.Enabled := False;
  // Angeheftet bleibt der Tooltip; sonst darf die Maus in den Tooltip wandern (#442).
  if FTip.IsShown and (FHistory.Pinned or MouseOverTip) and Application.Active then
  begin
    if not FHistory.Pinned then
      FHideTimer.Enabled := True;
    Exit;
  end;
  Hide;
end;

procedure TArgusEditorHover.TipLink(Sender: TObject; const ARef: TArgusHoverTypeRef; AControl: Boolean);
begin
  try
    // Strg+Klick: wie bisher zur Deklaration im Quelltext.
    if AControl then
    begin
      if ARef.HasLocation then
      begin
        Hide;
        GoToLocation(ARef.FileName, ARef.Line, ARef.Character);
      end;
      Exit;
    end;
    if FHistory.Open(ARef) then
    begin
      FUsagesCount := -1;
      Refresh;
    end;
  except
    on E: Exception do
      Log('Hover: ' + E.Message);
  end;
end;

procedure TArgusEditorHover.TipPath(Sender: TObject; AIndex: Integer);
begin
  if FHistory.JumpTo(AIndex) then
  begin
    FUsagesCount := -1;
    Refresh;
  end;
end;

procedure TArgusEditorHover.TipBack(Sender: TObject);
begin
  if FHistory.Back then
  begin
    FUsagesCount := -1;
    Refresh;
  end;
end;

procedure TArgusEditorHover.TipAction(Sender: TObject; AAction: TArgusHoverAction);
begin
  Execute(AAction);
end;

class procedure TArgusEditorHover.GoToLocation(const AFileName: string; ALine, ACharacter: Integer);
var
  Actions: IOTAActionServices;
  Modules: IOTAModuleServices;
  Module: IOTAModule;
  Index: Integer;
  Editor: IOTASourceEditor;
  View: IOTAEditView;
  Cursor: TOTAEditPos;
begin
  if not Supports(BorlandIDEServices, IOTAActionServices, Actions) or not Actions.OpenFile(AFileName) or
    not Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    Exit;
  Module := Modules.FindModule(AFileName);
  if Module = nil then
    Exit;
  for Index := 0 to Module.ModuleFileCount - 1 do
    if Supports(Module.ModuleFileEditors[Index], IOTASourceEditor, Editor) then
    begin
      Editor.Show;
      if Editor.EditViewCount = 0 then
        Exit;
      View := Editor.EditViews[0];
      Cursor.Line := ALine + 1;
      Cursor.Col := ACharacter + 1;
      View.CursorPos := Cursor;
      View.MoveViewToCursor;
      View.Paint;
      Exit;
    end;
end;

procedure TArgusEditorHover.ShowUsages;
var
  Session: TLspSession;
  Data: TArgusHoverData;
  Locations: TArray<TLspLocation>;
  Location: TLspLocation;
  Messages: IOTAMessageServices;
  Group: IOTAMessageGroup;
  Lines: TArray<string>;
  LastFile, Text: string;
  LineRef: Pointer;
begin
  Session := CurrentSession;
  Data := FHistory.Current;
  if (Session = nil) or not Data.Location.HasLocation then
    Exit;
  Screen.Cursor := crHourGlass;
  try
    Locations := Session.References(Data.Location.FileName, Data.Location.Line, Data.Location.Character);
  finally
    Screen.Cursor := crDefault;
  end;
  FUsagesCount := Length(Locations);
  Refresh;
  // Bis es ein eigenes Ergebnisfenster gibt (#400): im Meldungsfenster, Gruppe Argus.
  if not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    Exit;
  Group := Messages.GetGroup('Argus');
  if Group = nil then
    Group := Messages.AddMessageGroup('Argus');
  Messages.ClearMessageGroup(Group);
  Messages.AddTitleMessage(TArgusStrings.Fmt(TArgusTextId.HoverUsagesOf, [Length(Locations), Data.Title]), Group);
  LastFile := '';
  Lines := nil;
  for Location in Locations do
  begin
    if not SameText(Location.FileName, LastFile) then
    begin
      LastFile := Location.FileName;
      try
        Lines := TFile.ReadAllLines(LastFile);
      except
        Lines := nil;
      end;
    end;
    Text := Data.Title;
    if (Location.Line >= 0) and (Location.Line <= High(Lines)) then
      Text := Trim(Lines[Location.Line]);
    Messages.AddToolMessage(Location.FileName, Text, 'Argus', Location.Line + 1, Location.Character + 1, nil,
      LineRef, Group);
  end;
  Messages.ShowMessageView(Group);
end;

procedure TArgusEditorHover.Execute(AAction: TArgusHoverAction);
var
  Data: TArgusHoverData;
begin
  try
    Data := FHistory.Current;
    case AAction of
      TArgusHoverAction.Navigate:
        if Data.Location.HasLocation then
        begin
          Hide;
          GoToLocation(Data.Location.FileName, Data.Location.Line, Data.Location.Character);
        end;
      TArgusHoverAction.Usages:
        ShowUsages;
      TArgusHoverAction.Copy:
        Clipboard.AsText := Data.Declaration;
      TArgusHoverAction.Help:
        if Data.DocWiki <> '' then
          ShellExecute(0, 'open', PChar(Data.DocWiki), nil, nil, SW_SHOWNORMAL);
    end;
  except
    on E: Exception do
      Log('Hover: ' + E.Message);
  end;
end;

function TArgusEditorHover.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
var
  Data: TArgusHoverData;
  ForTip: Boolean;
begin
  Result := False;
  if not FTip.IsShown then
    Exit;
  if (AKey = VK_ESCAPE) and (AShift = []) then
    Exit(True);
  if FHistory.Pinned and FHistory.CanGoBack and (((AKey = VK_BACK) and (AShift = [])) or
    ((AKey = VK_LEFT) and (AShift = [ssAlt]))) then
    Exit(True);
  // Kürzel der Aktionsleiste nur, wenn der Tooltip gemeint ist: angeheftet oder mit der Maus darüber.
  ForTip := FHistory.Pinned or MouseOverTip;
  Data := FHistory.Current;
  if not ForTip or not Data.Location.HasLocation then
    Exit;
  Result := ((AKey = VK_F12) and ((AShift = []) or (AShift = [ssShift]))) or
    ((AKey = Ord('C')) and (AShift = [ssCtrl])) or
    ((AKey = VK_F1) and (AShift = []) and (Data.DocWiki <> ''));
end;

procedure TArgusEditorHover.HandleKey(AKey: Word; AShift: TShiftState);
begin
  case AKey of
    VK_ESCAPE:
      Hide;
    VK_BACK, VK_LEFT:
      TipBack(nil);
    VK_F12:
      if ssShift in AShift then
        Execute(TArgusHoverAction.Usages)
      else
        Execute(TArgusHoverAction.Navigate);
    VK_F1:
      Execute(TArgusHoverAction.Help);
  else
    if AKey = Ord('C') then
      Execute(TArgusHoverAction.Copy);
  end;
end;

procedure TArgusEditorHover.EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  Hide;
end;

procedure TArgusEditorHover.EditorKeyDown(const Editor: TWinControl; Key: Word; Shift: TShiftState;
  var Handled: Boolean);
begin
  // Umschalt, Strg und Alt allein schließen nicht: Strg+Klick und die Kürzel brauchen sie.
  if (Key = VK_SHIFT) or (Key = VK_CONTROL) or (Key = VK_MENU) then
    Exit;
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
