unit Atlas.IDE.Hover.Editor;

// Hover-Tooltip im Editor (#442) über die Code-Editor-API (ToolsAPI.Editor):
//   - Mausbewegung im Editor → Bezeichner unter der Maus (Zeile, Wortgrenzen).
//   - Nach 500 ms Verweilen auf demselben Bezeichner: textDocument/hover (im Hintergrund; die IDE wartet nie auf den Server)
//     (TLspSession.HoverData) und Tooltip unter dem Wort (Kurzform).
//   - Schließen 300 ms nachdem die Maus Bezeichner und Tooltip verlassen hat;
//     sofort bei Taste (außer Umschalt, Strg, Alt allein), Mausklick, Scrollen,
//     Größenänderung, IDE inaktiv (ein Wächter prüft das, solange der Tooltip
//     offen ist, #414).
// Navigation über Typen (#588):
//   - Klick auf einen Typ (Deklaration, Kette, Pfad) zeigt dessen Inhalt im
//     selben Fenster (Hover über den Fundort, TAtlasHoverHistory) und heftet
//     den Tooltip an: Dann schließt er nur mit Esc oder Klick in den Editor.
//   - Strg+Klick springt zur Deklaration und schließt.
//   - Tasten über den gemeinsamen Hook, solange der Tooltip sichtbar ist:
//     Esc schließt; angeheftet Rücktaste bzw. Alt+← zurück; angeheftet oder mit
//     der Maus über dem Tooltip F12, Umschalt+F12, Strg+C und F1 für den
//     angezeigten Typ.
// Probleme (#398): Liegt unter der Maus ein Problem, zeigt der Tooltip es oben
// an, auch ohne Bezeichner (dann nur das Problem).
// Die IDE zeigt dann keinen eigenen Tooltip: GetHintText liefert '' (Manager).
// Delphi 12 (#281): Tastatur-Ereignisse des Code-Editors gibt es erst ab
// Delphi 13 (INTACodeEditorEvents370). Dort schließt der Tooltip über den
// Tastatur-Hook, solange er sichtbar ist.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.ExtCtrls,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Hover.Contract,
  Atlas.Core.Hover.History,
  Atlas.Core.Problems.Contract,
  Atlas.IDE.Editor.KeyHook,
  Atlas.UI.Hover.Tip;

type
  TAtlasHoverSessionFunc = reference to function: TLspSession;
  TAtlasHoverLogFunc = reference to procedure(const AMessage: string);
  /// <summary>Probleme an der Stelle (0-basiert, #398).</summary>
  TAtlasHoverProblemsFunc = reference to function(const AFileName: string; ALine, ACharacter: Integer):
    TArray<TAtlasProblem>;

  /// <summary>Lebt der Tooltip noch? Hintergrund-Anfragen prüfen das, bevor sie ihr Ergebnis zeigen.</summary>
  TAtlasHoverAlive = class(TInterfacedObject)
  public
    Alive: Boolean;
  end;

  TAtlasEditorHover = class
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
    end;

    THoverKeys = class(TAtlasKeyClient)
    private
      FOwner: TAtlasEditorHover;
    protected
      function WantsKey(AKey: Word; AShift: TShiftState): Boolean; override;
      procedure HandleKey(AKey: Word; AShift: TShiftState); override;
    public
      constructor Create(AOwner: TAtlasEditorHover);
    end;
  public const
    /// <summary>Nach Vervollständigung (0) und Parameter-Hint (10).</summary>
    KeyPriority = 20;
  private
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FTip: TAtlasHoverTip;
    FKeys: THoverKeys;
    FHistory: TAtlasHoverHistory;
    FUsagesCount: Integer;
    FShowTimer: TTimer;
    FHideTimer: TTimer;
    FWatchTimer: TTimer;
    FSession: TAtlasHoverSessionFunc;
    FLog: TAtlasHoverLogFunc;
    FProblemsAt: TAtlasHoverProblemsFunc;
    // Probleme an der Mausposition; nur Probleme, wenn dort kein Bezeichner steht.
    FProblems: TArray<TAtlasProblem>;
    // Anfrage an den Server im Hintergrund: Die IDE friert nie ein, auch wenn er langsam ist.
    // FRequest zählt die Anfragen; nur die jüngste wird angezeigt. FAlive endet mit dem Objekt.
    FRequest: Integer;
    FAlive: TAtlasHoverAlive;
    FAliveRef: IInterface;
    FWorkers: TList<TThread>;
    FMouseCharacter: Integer;
    FProblemsOnly: Boolean;
    // Bezeichner unter der Maus bzw. im offenen Tooltip.
    FEditor: TWinControl;
    FView: IOTAEditView;
    FLine: Integer;
    FStart: Integer;
    FWordRect: TRect;
    // Fokus beim Anzeigen; wechselt er innerhalb der IDE, schließt der Tooltip (#414).
    FShownFocus: THandle;
    FKey: string;
    FShownKey: string;
    procedure EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
    procedure EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    {$IF CompilerVersion >= 37.0}
    procedure EditorKeyDown(const Editor: TWinControl; Key: Word; Shift: TShiftState; var Handled: Boolean);
    {$ENDIF}
    procedure EditorScrolled(const Editor: TWinControl; const Direction: TCodeEditorScrollDirection);
    procedure EditorResized(const Editor: TWinControl);
    procedure ShowData(const AData: TAtlasHoverData);
    procedure ReapWorkers(AWait: Boolean);
    procedure ShowTimerTick(Sender: TObject);
    procedure HideTimerTick(Sender: TObject);
    procedure WatchTimerTick(Sender: TObject);
    procedure TipLink(Sender: TObject; const ARef: TAtlasHoverTypeRef; AControl: Boolean);
    procedure TipPath(Sender: TObject; AIndex: Integer);
    procedure TipBack(Sender: TObject);
    procedure TipAction(Sender: TObject; AAction: TAtlasHoverAction);
    /// <summary>Link (href) in der XMLDoc (#654): im Browser öffnen.</summary>
    procedure TipUrl(Sender: TObject; const AUrl: string);
    function CurrentSession: TLspSession;
    function Fetch(const ARef: TAtlasHoverTypeRef; out AData: TAtlasHoverData): Boolean;
    function CurrentView: TAtlasHoverView;
    procedure Refresh;
    procedure Execute(AAction: TAtlasHoverAction);
    procedure ShowUsages;
    function MouseOverTip: Boolean;
    function CurrentEditView: IOTAEditView;
    function WantsKey(AKey: Word; AShift: TShiftState): Boolean;
    procedure HandleKey(AKey: Word; AShift: TShiftState);
    procedure Log(const AMessage: string);
  public
    constructor Create(const ASession: TAtlasHoverSessionFunc; const ALog: TAtlasHoverLogFunc;
      const AProblemsAt: TAtlasHoverProblemsFunc = nil);
    destructor Destroy; override;
    procedure Hide;
    /// <summary>Öffnet AFileName im Editor und setzt den Cursor (0-basiert).</summary>
    class procedure GoToLocation(const AFileName: string; ALine, ACharacter: Integer); static;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Winapi.Windows,
  Winapi.ShellAPI,
  System.IOUtils,
  System.StrUtils,
  Vcl.Forms,
  Vcl.Clipbrd,
  Atlas.Core.Completion.Word,
  Atlas.IDE.Editor.Buffer,
  Atlas.IDE.Editor.Style,
  Atlas.IDE.Settings.Store,
  Atlas.Core.Documentation.Contract,
  Atlas.UI.Strings;

{ TAtlasEditorHover.TEvents }

function TAtlasEditorHover.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevWindowEvents, cevMouseEvents];
  {$IF CompilerVersion >= 37.0}
  Include(Result, cevKeyboardEvents);
  {$ENDIF}
end;

{ TAtlasEditorHover.THoverKeys }

constructor TAtlasEditorHover.THoverKeys.Create(AOwner: TAtlasEditorHover);
begin
  inherited Create(KeyPriority);
  FOwner := AOwner;
end;

function TAtlasEditorHover.THoverKeys.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := FOwner.WantsKey(AKey, AShift);
  {$IF CompilerVersion < 37.0}
  // Ohne Tastatur-Ereignisse des Editors: andere Tasten schließen nach der Verarbeitung (wie EditorKeyDown).
  if not Result and (AKey <> VK_SHIFT) and (AKey <> VK_CONTROL) and (AKey <> VK_MENU) and
    not FOwner.FHistory.Pinned then
    TThread.ForceQueue(nil,
      procedure
      begin
        FOwner.Hide;
      end);
  {$ENDIF}
end;

procedure TAtlasEditorHover.THoverKeys.HandleKey(AKey: Word; AShift: TShiftState);
begin
  try
    FOwner.HandleKey(AKey, AShift);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
  end;
end;

{ TAtlasEditorHover }

constructor TAtlasEditorHover.Create(const ASession: TAtlasHoverSessionFunc; const ALog: TAtlasHoverLogFunc;
  const AProblemsAt: TAtlasHoverProblemsFunc);
var
  Services: INTACodeEditorServices;
begin
  inherited Create;
  FSession := ASession;
  FLog := ALog;
  FProblemsAt := AProblemsAt;
  FIndex := -1;
  FUsagesCount := -1;
  FTip := TAtlasHoverTip.Create(nil);
  FTip.OnLink := TipLink;
  FTip.OnPath := TipPath;
  FTip.OnBack := TipBack;
  FTip.OnAction := TipAction;
  FTip.OnUrl := TipUrl;
  FKeys := THoverKeys.Create(Self);
  FHistory := TAtlasHoverHistory.Create(Fetch);
  FAlive := TAtlasHoverAlive.Create;
  FAlive.Alive := True;
  FAliveRef := FAlive;
  FWorkers := TList<TThread>.Create;
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
  {$IF CompilerVersion >= 37.0}
  FEvents.OnEditorKeyDown := EditorKeyDown;
  {$ENDIF}
  FEvents.OnEditorScrolled := EditorScrolled;
  FEvents.OnEditorResized := EditorResized;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    FIndex := Services.AddEditorEventsNotifier(FEventsRef);
end;

destructor TAtlasEditorHover.Destroy;
var
  Services: INTACodeEditorServices;
begin
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.RemoveEditorEventsNotifier(FIndex);
  TAtlasKeyHook.Remove(FKeys);
  FEvents.OnEditorMouseMove := nil;
  FEvents.OnEditorMouseDown := nil;
  {$IF CompilerVersion >= 37.0}
  FEvents.OnEditorKeyDown := nil;
  {$ENDIF}
  FEvents.OnEditorScrolled := nil;
  FEvents.OnEditorResized := nil;
  FEventsRef := nil;
  // Laufende Anfragen zeigen nichts mehr; auf sie warten, bevor die Sitzung wegfällt.
  FAlive.Alive := False;
  ReapWorkers(True);
  FWorkers.Free;
  FShowTimer.Free;
  FHideTimer.Free;
  FWatchTimer.Free;
  FTip.Free;
  FHistory.Free;
  FKeys.Free;
  inherited Destroy;
end;

procedure TAtlasEditorHover.Log(const AMessage: string);
begin
  if Assigned(FLog) then
    FLog(AMessage);
end;

function TAtlasEditorHover.CurrentSession: TLspSession;
begin
  Result := nil;
  if Assigned(FSession) then
    Result := FSession();
end;

function TAtlasEditorHover.Fetch(const ARef: TAtlasHoverTypeRef; out AData: TAtlasHoverData): Boolean;
var
  Session: TLspSession;
begin
  AData := Default(TAtlasHoverData);
  Session := CurrentSession;
  Result := (Session <> nil) and ARef.HasLocation;
  if Result then
  begin
    AData := Session.HoverDataAt(ARef.FileName, ARef.Line, ARef.Character);
    Result := AData.Found;
  end;
end;

function TAtlasEditorHover.CurrentView: TAtlasHoverView;
var
  Full: Boolean;
begin
  Result := TAtlasHoverView.Create(FHistory.Current);
  Result.Path := FHistory.Path;
  Result.Pinned := FHistory.Pinned;
  Result.CanGoBack := FHistory.CanGoBack;
  Result.UsagesCount := FUsagesCount;
  // Anzeige der XMLDoc (#654): hints aus atlas.json meldet der Server, sonst die Optionen des Plugins.
  if Result.Data.Display.Known then
    Result.Display := Result.Data.Display
  else
    Result.Display := TAtlasDocDisplay.Create(TAtlasIdeSettings.Current.XmlDocFull,
      TAtlasIdeSettings.Current.XmlDocMaxLines);
  // Schnellschalter nur für diese Sitzung (#604) gilt auch über dem Wert aus atlas.json.
  if TAtlasIdeSettings.SessionFlag('XmlDocFull', Full) then
    Result.Display.Full := Full;
  // Probleme gehören zur Stelle im Editor, nicht zu angeklickten Typen.
  if FHistory.Count <= 1 then
    Result.Problems := FProblems;
end;

procedure TAtlasEditorHover.Refresh;
begin
  FTip.UpdateContent(CurrentView);
end;

procedure TAtlasEditorHover.Hide;
begin
  FWatchTimer.Enabled := False;
  FShowTimer.Enabled := False;
  FHideTimer.Enabled := False;
  TAtlasKeyHook.Remove(FKeys);
  FTip.HidePopup;
  FHistory.Clear;
  FProblems := nil;
  FUsagesCount := -1;
  FShownKey := '';
  FKey := '';
  FView := nil;
end;

function TAtlasEditorHover.CurrentEditView: IOTAEditView;
var
  Editors: IOTAEditorServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
    Result := Editors.TopView;
end;

function TAtlasEditorHover.MouseOverTip: Boolean;
begin
  Result := FTip.IsShown and PtInRect(FTip.BoundsRect, Mouse.CursorPos);
end;

procedure TAtlasEditorHover.EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
var
  Services: INTACodeEditorServices;
  State: INTACodeEditorState;
  Column, VisibleLine, Line, Index, Start, Stop: Integer;
  View: IOTAEditView;
  Text, Key: string;
  First, Last: TRect;
begin
  // Durch die Sicherung abgeschaltet (#493).
  if TAtlasGuard.Disabled(TAtlasFeature.Hover) then
    Exit;
  try
    if not TAtlasIdeSettings.Current.Enabled or not TAtlasIdeSettings.Current.HoverTooltip or
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
        Text := TAtlasEditorBuffer.LineText(View, Line);
        Index := TLspSession.ColumnToIndex(Text, Column, TAtlasEditorBuffer.TabWidth(View.Buffer));
        if (Index < Length(Text)) and TAtlasWord.IsIdentifierChar(Text[Index + 1]) and
          not CharInSet(Text[TAtlasWord.StartBefore(Text, Index + 1) + 1], ['0'..'9']) then
        begin
          Start := TAtlasWord.StartBefore(Text, Index + 1);
          Stop := TAtlasWord.EndAfter(Text, Index);
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
    begin
      Log('Hover: ' + E.Message);
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
    end;
  end;
end;

procedure TAtlasEditorHover.ReapWorkers(AWait: Boolean);
var
  Index: Integer;
begin
  for Index := FWorkers.Count - 1 downto 0 do
    if AWait or FWorkers[Index].Finished then
    begin
      FWorkers[Index].WaitFor;
      FWorkers[Index].Free;
      FWorkers.Delete(Index);
    end;
end;

procedure TAtlasEditorHover.ShowTimerTick(Sender: TObject);
var
  Session: TLspSession;
  Text, FileName, Key: string;
  Line, Character, Request: Integer;
  Owner: TAtlasEditorHover;
  Alive: TAtlasHoverAlive;
  AliveRef: IInterface;
  Worker: TThread;
begin
  // Durch die Sicherung abgeschaltet (#493).
  if TAtlasGuard.Disabled(TAtlasFeature.Hover) then
    Exit;
  FShowTimer.Enabled := False;
  try
    if (FView = nil) or (FKey = '') or not Application.Active then
      Exit;
    FProblems := nil;
    if Assigned(FProblemsAt) then
      FProblems := FProblemsAt(FView.Buffer.FileName, FLine - 1, FMouseCharacter);
    Session := nil;
    if not FProblemsOnly then
      Session := CurrentSession;
    if Session = nil then
    begin
      ShowData(Default(TAtlasHoverData));
      Exit;
    end;
    // Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
    Text := TAtlasEditorBuffer.Text(FView.Buffer);
    FileName := FView.Buffer.FileName;
    Session.Sync(FileName, Text);
    ReapWorkers(False);
    Inc(FRequest);
    Request := FRequest;
    Key := FKey;
    Line := FLine - 1;
    Character := FStart;
    Owner := Self;
    Alive := FAlive;
    AliveRef := FAliveRef;
    Worker := TThread.CreateAnonymousThread(
      procedure
      var
        Data: TAtlasHoverData;
        Show: TThreadProcedure;
      begin
        Data := Default(TAtlasHoverData);
        try
          Data := Session.HoverDataAt(FileName, Line, Character);
        except
          // Server langsam oder weg: kein Tooltip, die IDE wartet nie darauf.
          Data := Default(TAtlasHoverData);
        end;
        Show :=
          procedure
          begin
            // Nur die jüngste Anfrage und nur, solange die Maus noch auf demselben Wort steht.
            if not Alive.Alive or (AliveRef = nil) or (Owner.FRequest <> Request) or (Owner.FKey <> Key) then
              Exit;
            TAtlasGuard.Run(TAtlasFeature.Hover,
              procedure
              begin
                Owner.ShowData(Data);
              end);
          end;
        TThread.Queue(nil, Show);
      end);
    Worker.FreeOnTerminate := False;
    FWorkers.Add(Worker);
    Worker.Start;
  except
    on E: Exception do
    begin
      Log('Hover: ' + E.Message);
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
    end;
  end;
end;

procedure TAtlasEditorHover.ShowData(const AData: TAtlasHoverData);
begin
  if (FView = nil) or not Application.Active then
    Exit;
  if not AData.Found and (Length(FProblems) = 0) then
  begin
    Hide;
    Exit;
  end;
  FHistory.Start(AData);
  FUsagesCount := -1;
  TAtlasIdeStyle.Apply(FTip, FWordRect);
  FTip.ShowContent(CurrentView, FWordRect);
  TAtlasKeyHook.Add(FKeys);
  FShownKey := FKey;
  FShownFocus := GetFocus;
  FHideTimer.Enabled := False;
  FWatchTimer.Enabled := True;
end;

procedure TAtlasEditorHover.WatchTimerTick(Sender: TObject);
begin
  try
    // Andere Anwendung im Vordergrund: kein Atlas-Fenster bleibt stehen (#414).
    if not FTip.IsShown then
      FWatchTimer.Enabled := False
    else if not Application.Active then
      Hide
    // Anderer Editor-Tab oder Fokus woanders in der IDE (Objektinspektor, Projektverwaltung …).
    else if not FHistory.Pinned and not MouseOverTip and
      ((GetFocus <> FShownFocus) or ((FView <> nil) and ((CurrentEditView = nil) or
      not SameText(CurrentEditView.Buffer.FileName, FView.Buffer.FileName)))) then
      Hide;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
  end;
end;

procedure TAtlasEditorHover.HideTimerTick(Sender: TObject);
begin
  try
    FHideTimer.Enabled := False;
    // Angeheftet bleibt der Tooltip; sonst darf die Maus in den Tooltip wandern (#442).
    if FTip.IsShown and (FHistory.Pinned or MouseOverTip) and Application.Active then
    begin
      if not FHistory.Pinned then
        FHideTimer.Enabled := True;
      Exit;
    end;
    Hide;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
  end;
end;

procedure TAtlasEditorHover.TipLink(Sender: TObject; const ARef: TAtlasHoverTypeRef; AControl: Boolean);
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
    begin
      Log('Hover: ' + E.Message);
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
    end;
  end;
end;

procedure TAtlasEditorHover.TipPath(Sender: TObject; AIndex: Integer);
begin
  try
    if FHistory.JumpTo(AIndex) then
    begin
      FUsagesCount := -1;
      Refresh;
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
  end;
end;

procedure TAtlasEditorHover.TipBack(Sender: TObject);
begin
  try
    if FHistory.Back then
    begin
      FUsagesCount := -1;
      Refresh;
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
  end;
end;

procedure TAtlasEditorHover.TipAction(Sender: TObject; AAction: TAtlasHoverAction);
begin
  try
    Execute(AAction);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
  end;
end;

procedure TAtlasEditorHover.TipUrl(Sender: TObject; const AUrl: string);
begin
  try
    // Nur Web- und Mail-Adressen; andere Schemata (file:, Programme) öffnet der Tooltip nicht.
    if StartsText('http://', AUrl) or StartsText('https://', AUrl) or StartsText('mailto:', AUrl) then
      ShellExecute(0, 'open', PChar(AUrl), nil, nil, SW_SHOWNORMAL);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
  end;
end;

class procedure TAtlasEditorHover.GoToLocation(const AFileName: string; ALine, ACharacter: Integer);
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

procedure TAtlasEditorHover.ShowUsages;
var
  Session: TLspSession;
  Data: TAtlasHoverData;
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
  // Bis es ein eigenes Ergebnisfenster gibt (#400): im Meldungsfenster, Gruppe Atlas.
  if not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    Exit;
  Group := Messages.GetGroup('Atlas');
  if Group = nil then
    Group := Messages.AddMessageGroup('Atlas');
  Messages.ClearMessageGroup(Group);
  Messages.AddTitleMessage(TAtlasStrings.Fmt(TAtlasTextId.HoverUsagesOf, [Length(Locations), Data.Title]), Group);
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
    Messages.AddToolMessage(Location.FileName, Text, 'Atlas', Location.Line + 1, Location.Character + 1, nil,
      LineRef, Group);
  end;
  Messages.ShowMessageView(Group);
end;

procedure TAtlasEditorHover.Execute(AAction: TAtlasHoverAction);
var
  Data: TAtlasHoverData;
begin
  try
    Data := FHistory.Current;
    case AAction of
      TAtlasHoverAction.Navigate:
        if Data.Location.HasLocation then
        begin
          Hide;
          GoToLocation(Data.Location.FileName, Data.Location.Line, Data.Location.Character);
        end;
      TAtlasHoverAction.Usages:
        ShowUsages;
      TAtlasHoverAction.Copy:
        // Markierter Doku-Text (#654) hat Vorrang vor der Deklaration.
        if FTip.HasSelection then
          Clipboard.AsText := FTip.SelectedText
        else
          Clipboard.AsText := Data.Declaration;
      TAtlasHoverAction.Help:
        if Data.DocWiki <> '' then
          ShellExecute(0, 'open', PChar(Data.DocWiki), nil, nil, SW_SHOWNORMAL);
    end;
  except
    on E: Exception do
    begin
      Log('Hover: ' + E.Message);
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
    end;
  end;
end;

function TAtlasEditorHover.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
var
  Data: TAtlasHoverData;
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
  // Markierter Doku-Text lässt sich auch ohne Fundort kopieren (#654).
  if ForTip and FTip.HasSelection and (AKey = Ord('C')) and (AShift = [ssCtrl]) then
    Exit(True);
  if not ForTip or not Data.Location.HasLocation then
    Exit;
  Result := ((AKey = VK_F12) and ((AShift = []) or (AShift = [ssShift]))) or
    ((AKey = Ord('C')) and (AShift = [ssCtrl])) or
    ((AKey = VK_F1) and (AShift = []) and (Data.DocWiki <> ''));
end;

procedure TAtlasEditorHover.HandleKey(AKey: Word; AShift: TShiftState);
begin
  case AKey of
    VK_ESCAPE:
      Hide;
    VK_BACK, VK_LEFT:
      TipBack(nil);
    VK_F12:
      if ssShift in AShift then
        Execute(TAtlasHoverAction.Usages)
      else
        Execute(TAtlasHoverAction.Navigate);
    VK_F1:
      Execute(TAtlasHoverAction.Help);
  else
    if AKey = Ord('C') then
      Execute(TAtlasHoverAction.Copy);
  end;
end;

procedure TAtlasEditorHover.EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  try
    Hide;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
  end;
end;

{$IF CompilerVersion >= 37.0}
procedure TAtlasEditorHover.EditorKeyDown(const Editor: TWinControl; Key: Word; Shift: TShiftState;
  var Handled: Boolean);
begin
  try
    // Umschalt, Strg und Alt allein schließen nicht: Strg+Klick und die Kürzel brauchen sie.
    if (Key = VK_SHIFT) or (Key = VK_CONTROL) or (Key = VK_MENU) then
      Exit;
    Hide;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
  end;
end;
{$ENDIF}

procedure TAtlasEditorHover.EditorScrolled(const Editor: TWinControl; const Direction: TCodeEditorScrollDirection);
begin
  try
    Hide;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
  end;
end;

procedure TAtlasEditorHover.EditorResized(const Editor: TWinControl);
begin
  try
    Hide;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
  end;
end;

end.
