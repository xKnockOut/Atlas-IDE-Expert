unit Atlas.IDE.Results.Peek;

// Definition und Referenzen einblenden (#505) in der IDE:
// - Alt+F12 (keys.peekDefinition): Deklaration am Cursor über
//   textDocument/declaration. Steht dort eine Routine, liefert die Gliederung
//   der Datei (documentSymbol) alle Überladungen; „Gehe zu Definition“ von
//   jeder Deklaration aus findet ihre Implementierung (TAtlasPeek.Pair).
// - Umschalt+Alt+F12 (keys.peekReferences): Fundstellen aus
//   textDocument/references (#29), je Fundstelle ein Eintrag.
// - Das Fenster (TAtlasPeekWindow) steht unter der Cursorzeile, so breit wie
//   der Editor, peek.heightLines Zeilen hoch; passt es nicht darunter, steht es
//   darüber. Farben, Schrift und Zoom wie der Editor (TAtlasIdeStyle).
// - Tasten über den Tastatur-Hook, nur solange das Fenster offen ist: Escape
//   schließt (der Cursor bleibt), Enter öffnet die Stelle, Pfeile wechseln das
//   Ziel (bei nur einem scrollen sie), Bild auf/ab scrollt im Ausschnitt.
// - Ein Zeitgeber schließt das Fenster, sobald sich Editor, Cursor oder
//   oberste Zeile ändern oder die IDE nicht mehr aktiv ist; so bleibt es beim
//   Weitertippen nicht stehen.
// Nur im Hauptthread; die Anfragen gehen mit den Zeitgrenzen der Sitzung.

interface

uses
  System.SysUtils,
  System.Classes;

type
  TAtlasIdePeek = class
  private class var
    FState: TObject;
  public
    class procedure Install; static;
    class procedure Uninstall; static;
    class procedure PeekDefinition; static;
    class procedure PeekReferences; static;
    class function IsShown: Boolean; static;
    class procedure Close; static;
  end;

implementation

uses
  Winapi.Windows,
  System.Types,
  System.Math,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.Peek,
  Atlas.UI.Strings,
  Atlas.UI.Popup.Window,
  Atlas.UI.Editor.Peek,
  Atlas.IDE.Foundation.KeyHook,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Results.Commands;

const
  WatchMs = 200;
  /// <summary>Nach Vervollständigung (0), Parameter-Hint (10) und Tooltip (20).</summary>
  KeyPriority = 25;
  /// <summary>Höchstens so viele Referenzen in der Liste.</summary>
  MaxReferences = 500;
  SymbolTimeoutMs = 3000;

type
  TPeekState = class;

  TPeekKeys = class(TAtlasKeyClient)
  private
    FOwner: TPeekState;
  protected
    function WantsKey(AKey: Word; AShift: TShiftState): Boolean; override;
    procedure HandleKey(AKey: Word; AShift: TShiftState); override;
  public
    constructor Create(AOwner: TPeekState);
  end;

  TPeekState = class(TComponent)
  private
    procedure Watch(Sender: TObject);
    procedure WindowOpen(Sender: TObject);
  public
    Window: TAtlasPeekWindow;
    Keys: TPeekKeys;
    Timer: TTimer;
    // Editor beim Öffnen: geändert = schließen.
    ShownView: Pointer;
    ShownCursor: TOTAEditPos;
    ShownTop: Integer;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Hide;
    procedure Open;
    procedure Show(AView: TAtlasPeekView);
  end;

function State: TPeekState;
begin
  Result := TPeekState(TAtlasIdePeek.FState);
end;

function TopView: IOTAEditView;
var
  Editors: IOTAEditorServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
    Result := Editors.TopView;
end;

/// <summary>Caret in Bildschirmkoordinaten und das Fenster des Editors; False ohne Caret.</summary>
function CaretRect(out ARect: TRect; out AEditor: HWND): Boolean;
var
  Info: TGUIThreadInfo;
begin
  FillChar(Info, SizeOf(Info), 0);
  Info.cbSize := SizeOf(Info);
  Result := GetGUIThreadInfo(GetCurrentThreadId, Info) and (Info.hwndCaret <> 0);
  if not Result then
    Exit;
  AEditor := Info.hwndCaret;
  ARect := Info.rcCaret;
  MapWindowPoints(Info.hwndCaret, 0, ARect, 2);
end;

{ TPeekKeys }

constructor TPeekKeys.Create(AOwner: TPeekState);
begin
  inherited Create(KeyPriority);
  FOwner := AOwner;
end;

function TPeekKeys.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := (FOwner.Window <> nil) and FOwner.Window.IsShown and (FOwner.Window.View <> nil) and (AShift = []) and
    ((AKey = VK_ESCAPE) or (AKey = VK_RETURN) or (AKey = VK_UP) or (AKey = VK_DOWN) or (AKey = VK_PRIOR) or
    (AKey = VK_NEXT));
end;

procedure TPeekKeys.HandleKey(AKey: Word; AShift: TShiftState);
var
  View: TAtlasPeekView;
begin
  try
    if (FOwner.Window = nil) or (FOwner.Window.View = nil) then
      Exit;
    View := FOwner.Window.View;
    case AKey of
      VK_ESCAPE:
        FOwner.Hide;
      VK_RETURN:
        FOwner.Open;
      VK_UP:
        if View.Count > 1 then
          View.SelectPrevious
        else
          View.ScrollBy(-1);
      VK_DOWN:
        if View.Count > 1 then
          View.SelectNext
        else
          View.ScrollBy(1);
      VK_PRIOR:
        View.PageUp;
      VK_NEXT:
        View.PageDown;
    end;
    if (AKey <> VK_ESCAPE) and (AKey <> VK_RETURN) and (FOwner.Window.View <> nil) then
      FOwner.Window.ViewChanged;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.EditorCommands, E);
  end;
end;

{ TPeekState }

constructor TPeekState.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Window := TAtlasPeekWindow.Create(Self);
  Window.GuardFeature := TAtlasFeature.EditorCommands;
  Window.OnOpen := WindowOpen;
  Keys := TPeekKeys.Create(Self);
  Timer := TTimer.Create(Self);
  Timer.Enabled := False;
  Timer.Interval := WatchMs;
  Timer.OnTimer := Watch;
end;

destructor TPeekState.Destroy;
begin
  Timer.Enabled := False;
  if TAtlasKeyHook.Contains(Keys) then
    TAtlasKeyHook.Remove(Keys);
  Keys.Free;
  inherited Destroy;
end;

procedure TPeekState.Hide;
begin
  Timer.Enabled := False;
  if TAtlasKeyHook.Contains(Keys) then
    TAtlasKeyHook.Remove(Keys);
  Window.Dismiss;
end;

procedure TPeekState.Open;
var
  Place: TAtlasPeekPlace;
begin
  if (Window.View = nil) or (Window.View.Count = 0) then
    Exit;
  Place := Window.View.OpenPlace;
  Hide;
  if Place.FileName <> '' then
    TAtlasIdeNavigation.GoToLocation(Place.FileName, Place.Line, Place.Character);
end;

procedure TPeekState.WindowOpen(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.EditorCommands,
    procedure
    begin
      Open;
    end);
end;

procedure TPeekState.Watch(Sender: TObject);
var
  View: IOTAEditView;
begin
  try
    if not Window.IsShown then
    begin
      Hide;
      Exit;
    end;
    View := TopView;
    if not Application.Active or (View = nil) or (Pointer(View) <> ShownView) or
      (View.CursorPos.Line <> ShownCursor.Line) or (View.CursorPos.Col <> ShownCursor.Col) or
      (View.TopRow <> ShownTop) then
      Hide;
  except
    on E: Exception do
    begin
      Hide;
      TAtlasGuard.Report(TAtlasFeature.EditorCommands, E);
    end;
  end;
end;

procedure TPeekState.Show(AView: TAtlasPeekView);
var
  Caret, Editor, Area, Bounds: TRect;
  EditorWindow: HWND;
  View: IOTAEditView;
  Height: Integer;
begin
  View := TopView;
  if (View = nil) or not CaretRect(Caret, EditorWindow) or not GetWindowRect(EditorWindow, Editor) then
  begin
    AView.Free;
    Exit;
  end;
  TAtlasIdeStyle.Apply(Window, Caret);
  Area := TAtlasPopupWindow.WorkAreaAt(Caret.CenterPoint);
  Height := Window.HeightForLines(TAtlasIdeSettings.Current.PeekHeightLines);
  // Unter der Cursorzeile, sonst darüber; nie größer als der Platz.
  if (Caret.Bottom + Height <= Area.Bottom) or (Caret.Top - Area.Top < Area.Bottom - Caret.Bottom) then
    Bounds := Rect(Editor.Left, Caret.Bottom + 1, Editor.Right, Min(Area.Bottom, Caret.Bottom + 1 + Height))
  else
    Bounds := Rect(Editor.Left, Max(Area.Top, Caret.Top - 1 - Height), Editor.Right, Caret.Top - 1);
  Bounds.Left := Max(Bounds.Left, Area.Left);
  Bounds.Right := Min(Bounds.Right, Area.Right);
  ShownView := Pointer(View);
  ShownCursor := View.CursorPos;
  ShownTop := View.TopRow;
  Window.ShowView(AView, Bounds);
  if not TAtlasKeyHook.Contains(Keys) then
    TAtlasKeyHook.Add(Keys);
  Timer.Enabled := True;
end;

{ Ziele }

type
  /// <summary>Zeilen je Datei, einmal gelesen (offener Puffer, sonst Platte).</summary>
  TLineCache = class
  private
    FLines: TDictionary<string, TArray<string>>;
  public
    constructor Create;
    destructor Destroy; override;
    function Lines(const AFileName: string): TArray<string>;
  end;

constructor TLineCache.Create;
begin
  inherited Create;
  FLines := TDictionary<string, TArray<string>>.Create;
end;

destructor TLineCache.Destroy;
begin
  FLines.Free;
  inherited Destroy;
end;

function TLineCache.Lines(const AFileName: string): TArray<string>;
var
  Key, Text: string;
begin
  Key := AnsiUpperCase(AFileName);
  if FLines.TryGetValue(Key, Result) then
    Exit;
  try
    Text := TAtlasIdeWorkspaceEdit.CurrentText(AFileName);
  except
    // Nicht lesbar: leerer Ausschnitt statt Fehler.
    on Exception do
      Text := '';
  end;
  Result := Text.Split([#13#10, #10]);
  FLines.Add(Key, Result);
end;

function ToPlace(const ALocation: TLspLocation): TAtlasPeekPlace;
begin
  Result := TAtlasPeekPlace.Create(ALocation.FileName, ALocation.Line, ALocation.Character);
end;

function TabWidth: Integer;
var
  View: IOTAEditView;
begin
  Result := 8;
  View := TopView;
  if (View <> nil) and (View.Buffer <> nil) then
    Result := TAtlasEditorBuffer.TabWidth(View.Buffer);
end;

function DefinitionEntries(ASession: TLspSession; const ADeclaration: TAtlasPeekPlace): TArray<TAtlasPeekEntry>;
var
  Places: TArray<TAtlasPeekPlace>;
  Targets: TArray<TAtlasPeekTarget>;
  Cache: TLineCache;
  Index, Tabs: Integer;
  Lines: TArray<string>;
  Show: Boolean;
begin
  Result := nil;
  Places := nil;
  try
    Places := TAtlasPeek.Overloads(ASession.DocumentSymbols(ADeclaration.FileName, SymbolTimeoutMs),
      ADeclaration.Line);
  except
    on ELspClientError do
      Places := nil;
  end;
  if Length(Places) = 0 then
    Places := [ADeclaration];
  Targets := TAtlasPeek.Pair(Places,
    function(const APlace: TAtlasPeekPlace; out ATarget: TAtlasPeekPlace): Boolean
    var
      Found: TArray<TLspLocation>;
    begin
      Result := False;
      try
        Found := ASession.Definitions(APlace.FileName, APlace.Line, APlace.Character);
      except
        on ELspClientError do
          Found := nil;
      end;
      if Length(Found) > 0 then
      begin
        ATarget := ToPlace(Found[0]);
        Result := True;
      end;
    end);
  Show := TAtlasIdeSettings.Current.PeekShowImplementation;
  Tabs := TabWidth;
  Cache := TLineCache.Create;
  try
    SetLength(Result, Length(Targets));
    for Index := 0 to High(Targets) do
    begin
      Lines := Cache.Lines(Targets[Index].Place.FileName);
      Result[Index].Target := Targets[Index];
      if (Targets[Index].Place.Line >= 0) and (Targets[Index].Place.Line <= High(Lines)) then
        Result[Index].Excerpt := TAtlasPeek.Excerpt(Lines[Targets[Index].Place.Line]);
      if Targets[Index].HasBody then
        Result[Index].Rows := TAtlasPeek.DefinitionRows(Targets[Index], Lines,
          Cache.Lines(Targets[Index].Body.FileName), Show, Tabs)
      else
        Result[Index].Rows := TAtlasPeek.DefinitionRows(Targets[Index], Lines, nil, Show, Tabs);
    end;
  finally
    Cache.Free;
  end;
end;

function ReferenceEntries(const ALocations: TArray<TLspLocation>): TArray<TAtlasPeekEntry>;
var
  Cache: TLineCache;
  Index, Count, Tabs: Integer;
  Lines: TArray<string>;
  Place: TAtlasPeekPlace;
begin
  Result := nil;
  Count := Min(Length(ALocations), MaxReferences);
  Tabs := TabWidth;
  Cache := TLineCache.Create;
  try
    SetLength(Result, Count);
    for Index := 0 to Count - 1 do
    begin
      Place := ToPlace(ALocations[Index]);
      Lines := Cache.Lines(Place.FileName);
      Result[Index].Target.Place := Place;
      Result[Index].Target.HasBody := False;
      if (Place.Line >= 0) and (Place.Line <= High(Lines)) then
        Result[Index].Excerpt := TAtlasPeek.Excerpt(Lines[Place.Line]);
      Result[Index].Rows := TAtlasPeek.ReferenceRows(Place, Lines, Tabs);
    end;
  finally
    Cache.Free;
  end;
end;

procedure Run(AMode: TAtlasPeekMode);
var
  Owner: TPeekState;
  Current: TLspSession;
  FileName, Name, Title: string;
  Line, Character: Integer;
  Found: TArray<TLspLocation>;
  Entries: TArray<TAtlasPeekEntry>;
  Cursor: TCursor;
begin
  Owner := State;
  if (Owner = nil) or not TAtlasIdeSettings.Current.Peek then
    Exit;
  Owner.Hide;
  if not TAtlasIdeResults.AtCursor(FileName, Line, Character, Name) then
    Exit;
  Current := TAtlasIdeResults.Session;
  if Current = nil then
    Exit;
  Entries := nil;
  Cursor := Screen.Cursor;
  Screen.Cursor := crHourGlass;
  try
    try
      if AMode = TAtlasPeekMode.Definition then
      begin
        Found := Current.Declarations(FileName, Line, Character);
        if Length(Found) > 0 then
          Entries := DefinitionEntries(Current, ToPlace(Found[0]));
        Title := TAtlasStrings.Fmt(TAtlasTextId.PeekTitleDefinition, [Name]);
      end
      else
      begin
        Found := Current.References(FileName, Line, Character);
        Entries := ReferenceEntries(Found);
        Title := TAtlasStrings.Fmt(TAtlasTextId.PeekTitleReferences, [Name, Length(Found)]);
      end;
    except
      on E: ELspClientError do
      begin
        TAtlasIdeResults.Say(TAtlasStrings.Fmt(TAtlasTextId.ResultsFailed, [E.Message]));
        Exit;
      end;
    end;
  finally
    Screen.Cursor := Cursor;
  end;
  if Length(Entries) = 0 then
  begin
    if AMode = TAtlasPeekMode.Definition then
      TAtlasIdeResults.Say(TAtlasStrings.Fmt(TAtlasTextId.PeekNoDefinition, [Name]))
    else
      TAtlasIdeResults.Say(TAtlasStrings.Fmt(TAtlasTextId.PeekNoReferences, [Name]));
    Exit;
  end;
  Owner.Show(TAtlasPeekView.Create(AMode, Title, Entries));
end;

{ TAtlasIdePeek }

class procedure TAtlasIdePeek.Install;
begin
  if FState = nil then
    FState := TPeekState.Create(nil);
end;

class procedure TAtlasIdePeek.Uninstall;
var
  Owner: TPeekState;
begin
  Owner := State;
  FState := nil;
  if Owner = nil then
    Exit;
  Owner.Hide;
  Owner.Free;
end;

class procedure TAtlasIdePeek.PeekDefinition;
begin
  Run(TAtlasPeekMode.Definition);
end;

class procedure TAtlasIdePeek.PeekReferences;
begin
  Run(TAtlasPeekMode.References);
end;

class function TAtlasIdePeek.IsShown: Boolean;
begin
  Result := (State <> nil) and State.Window.IsShown;
end;

class procedure TAtlasIdePeek.Close;
begin
  if State <> nil then
    State.Hide;
end;

end.
