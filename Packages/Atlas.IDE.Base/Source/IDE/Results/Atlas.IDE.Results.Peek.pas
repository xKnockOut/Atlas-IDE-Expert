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
  Atlas.UI.Results.Strings,
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
  cWatchMs = 200;
  /// <summary>Nach Vervollständigung (0), Parameter-Hint (10) und Tooltip (20).</summary>
  cKeyPriority = 25;
  /// <summary>Höchstens so viele Referenzen in der Liste.</summary>
  cMaxReferences = 500;
  cSymbolTimeoutMs = 3000;

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
  mEditors: IOTAEditorServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    Result := mEditors.TopView;
  end;
end;

/// <summary>Caret in Bildschirmkoordinaten und das Fenster des Editors; False ohne Caret.</summary>
function CaretRect(out ARect: TRect; out AEditor: HWND): Boolean;
var
  mInfo: TGUIThreadInfo;
begin
  FillChar(mInfo, SizeOf(mInfo), 0);
  mInfo.cbSize := SizeOf(mInfo);
  Result := GetGUIThreadInfo(GetCurrentThreadId, mInfo) and (mInfo.hwndCaret <> 0);
  if not Result then
  begin
    Exit;
  end;
  AEditor := mInfo.hwndCaret;
  ARect := mInfo.rcCaret;
  MapWindowPoints(mInfo.hwndCaret, 0, ARect, 2);
end;

{ TPeekKeys }

constructor TPeekKeys.Create(AOwner: TPeekState);
begin
  inherited Create(cKeyPriority);
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
  mView: TAtlasPeekView;
begin
  try
    if (FOwner.Window = nil) or (FOwner.Window.View = nil) then
    begin
      Exit;
    end;
    mView := FOwner.Window.View;
    case AKey of
      VK_ESCAPE:
        FOwner.Hide;
      VK_RETURN:
        FOwner.Open;
      VK_UP:
        if mView.Count > 1 then
        begin
          mView.SelectPrevious;
        end
        else
        begin
          mView.ScrollBy(-1);
        end;
      VK_DOWN:
        if mView.Count > 1 then
        begin
          mView.SelectNext;
        end
        else
        begin
          mView.ScrollBy(1);
        end;
      VK_PRIOR:
        mView.PageUp;
      VK_NEXT:
        mView.PageDown;
    end;
    if (AKey <> VK_ESCAPE) and (AKey <> VK_RETURN) and (FOwner.Window.View <> nil) then
    begin
      FOwner.Window.ViewChanged;
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Peek, E);
  end;
end;

{ TPeekState }

constructor TPeekState.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Window := TAtlasPeekWindow.Create(Self);
  Window.GuardFeature := TAtlasFeature.Peek;
  Window.OnOpen := WindowOpen;
  Keys := TPeekKeys.Create(Self);
  Timer := TTimer.Create(Self);
  Timer.Enabled := False;
  Timer.Interval := cWatchMs;
  Timer.OnTimer := Watch;
end;

destructor TPeekState.Destroy;
begin
  Timer.Enabled := False;
  if TAtlasKeyHook.Contains(Keys) then
  begin
    TAtlasKeyHook.Remove(Keys);
  end;
  Keys.Free;
  inherited Destroy;
end;

procedure TPeekState.Hide;
begin
  Timer.Enabled := False;
  if TAtlasKeyHook.Contains(Keys) then
  begin
    TAtlasKeyHook.Remove(Keys);
  end;
  Window.Dismiss;
end;

procedure TPeekState.Open;
var
  mPlace: TAtlasPeekPlace;
begin
  if (Window.View = nil) or (Window.View.Count = 0) then
  begin
    Exit;
  end;
  mPlace := Window.View.OpenPlace;
  Hide;
  if mPlace.FileName <> '' then
  begin
    TAtlasIdeNavigation.GoToLocation(mPlace.FileName, mPlace.Line, mPlace.Character);
  end;
end;

procedure TPeekState.WindowOpen(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Peek,
    procedure
    begin
      Open;
    end);
end;

procedure TPeekState.Watch(Sender: TObject);
var
  mView: IOTAEditView;
  mStale: Boolean;
begin
  try
    if not Window.IsShown then
    begin
      Hide;
      Exit;
    end;
    mView := TopView;
    // Weg, sobald sich Ansicht, Cursor oder Bildlauf ändern.
    mStale := not Application.Active or (mView = nil) or (Pointer(mView) <> ShownView);
    mStale := mStale or (mView.CursorPos.Line <> ShownCursor.Line) or (mView.CursorPos.Col <> ShownCursor.Col) or
      (mView.TopRow <> ShownTop);
    if mStale then
    begin
      Hide;
    end;
  except
    on E: Exception do
    begin
      Hide;
      TAtlasGuard.Report(TAtlasFeature.Peek, E);
    end;
  end;
end;

procedure TPeekState.Show(AView: TAtlasPeekView);
var
  mCaret, mEditor, mArea, mBounds: TRect;
  mEditorWindow: HWND;
  mView: IOTAEditView;
  mHeight: Integer;
begin
  mView := TopView;
  if (mView = nil) or not CaretRect(mCaret, mEditorWindow) or not GetWindowRect(mEditorWindow, mEditor) then
  begin
    AView.Free;
    Exit;
  end;
  TAtlasIdeStyle.Apply(Window, mCaret);
  mArea := TAtlasPopupWindow.WorkAreaAt(mCaret.CenterPoint);
  mHeight := Window.HeightForLines(TAtlasIdeSettings.Current.PeekHeightLines);
  // Unter der Cursorzeile, sonst darüber; nie größer als der Platz.
  if (mCaret.Bottom + mHeight <= mArea.Bottom) or (mCaret.Top - mArea.Top < mArea.Bottom - mCaret.Bottom) then
  begin
    mBounds := Rect(mEditor.Left, mCaret.Bottom + 1, mEditor.Right, Min(mArea.Bottom, mCaret.Bottom + 1 + mHeight));
  end
  else
  begin
    mBounds := Rect(mEditor.Left, Max(mArea.Top, mCaret.Top - 1 - mHeight), mEditor.Right, mCaret.Top - 1);
  end;
  mBounds.Left := Max(mBounds.Left, mArea.Left);
  mBounds.Right := Min(mBounds.Right, mArea.Right);
  ShownView := Pointer(mView);
  ShownCursor := mView.CursorPos;
  ShownTop := mView.TopRow;
  Window.ShowView(AView, mBounds);
  if not TAtlasKeyHook.Contains(Keys) then
  begin
    TAtlasKeyHook.Add(Keys);
  end;
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
  mKey, mText: string;
begin
  mKey := AnsiUpperCase(AFileName);
  if FLines.TryGetValue(mKey, Result) then
  begin
    Exit;
  end;
  try
    mText := TAtlasIdeWorkspaceEdit.CurrentText(AFileName);
  except
    // Nicht lesbar: leerer Ausschnitt statt Fehler.
    on Exception do
      mText := '';
  end;
  Result := mText.Split([#13#10, #10]);
  FLines.Add(mKey, Result);
end;

function ToPlace(const ALocation: TLspLocation): TAtlasPeekPlace;
begin
  Result := TAtlasPeekPlace.Create(ALocation.FileName, ALocation.Line, ALocation.Character);
end;

function TabWidth: Integer;
var
  mView: IOTAEditView;
begin
  Result := 8;
  mView := TopView;
  if (mView <> nil) and (mView.Buffer <> nil) then
  begin
    Result := TAtlasEditorBuffer.TabWidth(mView.Buffer);
  end;
end;

/// <summary>Überladungen an der Deklaration; ohne Antwort nur die Deklaration selbst.</summary>
function DeclarationPlaces(ASession: TLspSession; const ADeclaration: TAtlasPeekPlace): TArray<TAtlasPeekPlace>;
begin
  try
    Result := TAtlasPeek.Overloads(ASession.DocumentSymbols(ADeclaration.FileName, cSymbolTimeoutMs),
      ADeclaration.Line);
  except
    on ELspClientError do
      Result := nil;
  end;
  if Length(Result) = 0 then
  begin
    Result := [ADeclaration];
  end;
end;

/// <summary>Zu jeder Stelle die Implementierung über textDocument/definition.</summary>
function PairDefinitions(ASession: TLspSession; const APlaces: TArray<TAtlasPeekPlace>): TArray<TAtlasPeekTarget>;
begin
  Result := TAtlasPeek.Pair(APlaces,
    function(const APlace: TAtlasPeekPlace; out ATarget: TAtlasPeekPlace): Boolean
    var
      mFound: TArray<TLspLocation>;
    begin
      Result := False;
      try
        mFound := ASession.Definitions(APlace.FileName, APlace.Line, APlace.Character);
      except
        on ELspClientError do
          mFound := nil;
      end;
      if Length(mFound) > 0 then
      begin
        ATarget := ToPlace(mFound[0]);
        Result := True;
      end;
    end);
end;

function DefinitionEntries(ASession: TLspSession; const ADeclaration: TAtlasPeekPlace): TArray<TAtlasPeekEntry>;
var
  mTargets: TArray<TAtlasPeekTarget>;
  mCache: TLineCache;
  mIndex, mTabs: Integer;
  mLines, mBody: TArray<string>;
  mShow: Boolean;
begin
  mTargets := PairDefinitions(ASession, DeclarationPlaces(ASession, ADeclaration));
  mShow := TAtlasIdeSettings.Current.PeekShowImplementation;
  mTabs := TabWidth;
  mCache := TLineCache.Create;
  try
    SetLength(Result, Length(mTargets));
    for mIndex := 0 to High(mTargets) do
    begin
      mLines := mCache.Lines(mTargets[mIndex].Place.FileName);
      Result[mIndex].Target := mTargets[mIndex];
      if (mTargets[mIndex].Place.Line >= 0) and (mTargets[mIndex].Place.Line <= High(mLines)) then
      begin
        Result[mIndex].Excerpt := TAtlasPeek.Excerpt(mLines[mTargets[mIndex].Place.Line]);
      end;
      mBody := nil;
      if mTargets[mIndex].HasBody then
      begin
        mBody := mCache.Lines(mTargets[mIndex].Body.FileName);
      end;
      Result[mIndex].Rows := TAtlasPeek.DefinitionRows(mTargets[mIndex], mLines, mBody, mShow, mTabs);
    end;
  finally
    mCache.Free;
  end;
end;

function ReferenceEntries(const ALocations: TArray<TLspLocation>): TArray<TAtlasPeekEntry>;
var
  mCache: TLineCache;
  mIndex, mCount, mTabs: Integer;
  mLines: TArray<string>;
  mPlace: TAtlasPeekPlace;
begin
  Result := nil;
  mCount := Min(Length(ALocations), cMaxReferences);
  mTabs := TabWidth;
  mCache := TLineCache.Create;
  try
    SetLength(Result, mCount);
    for mIndex := 0 to mCount - 1 do
    begin
      mPlace := ToPlace(ALocations[mIndex]);
      mLines := mCache.Lines(mPlace.FileName);
      Result[mIndex].Target.Place := mPlace;
      Result[mIndex].Target.HasBody := False;
      if (mPlace.Line >= 0) and (mPlace.Line <= High(mLines)) then
      begin
        Result[mIndex].Excerpt := TAtlasPeek.Excerpt(mLines[mPlace.Line]);
      end;
      // Erschlossene Treffer (#1119) wie im Ergebnisfenster mit ≈.
      if ALocations[mIndex].Confidence.Inferred then
      begin
        Result[mIndex].Excerpt := '≈ ' + Result[mIndex].Excerpt;
      end;
      Result[mIndex].Rows := TAtlasPeek.ReferenceRows(mPlace, mLines, mTabs);
    end;
  finally
    mCache.Free;
  end;
end;

type
  /// <summary>Bezeichner am Cursor: Datei, Name und Stelle (0-basiert).</summary>
  TPeekSpot = record
    FileName: string;
    Name: string;
    Line: Integer;
    Character: Integer;
  end;

/// <summary>Einträge und Titel für AMode; Ausnahme ELspClientError, wenn der Server nicht antwortet.</summary>
function PeekEntries(ACurrent: TLspSession; AMode: TAtlasPeekMode; const ASpot: TPeekSpot;
  out ATitle: string): TArray<TAtlasPeekEntry>;
var
  mFound: TArray<TLspLocation>;
begin
  Result := nil;
  if AMode = TAtlasPeekMode.Definition then
  begin
    mFound := ACurrent.Declarations(ASpot.FileName, ASpot.Line, ASpot.Character);
    if Length(mFound) > 0 then
    begin
      Result := DefinitionEntries(ACurrent, ToPlace(mFound[0]));
    end;
    ATitle := TAtlasResultsStrings.Fmt(TAtlasResultsTextId.PeekTitleDefinition, [ASpot.Name]);
  end
  else
  begin
    mFound := ACurrent.References(ASpot.FileName, ASpot.Line, ASpot.Character);
    Result := ReferenceEntries(mFound);
    ATitle := TAtlasResultsStrings.Fmt(TAtlasResultsTextId.PeekTitleReferences, [ASpot.Name, Length(mFound)]);
  end;
end;

procedure SayNothingFound(AMode: TAtlasPeekMode; const AName: string);
begin
  if AMode = TAtlasPeekMode.Definition then
  begin
    TAtlasIdeResults.Say(TAtlasResultsStrings.Fmt(TAtlasResultsTextId.PeekNoDefinition, [AName]));
  end
  else
  begin
    TAtlasIdeResults.Say(TAtlasResultsStrings.Fmt(TAtlasResultsTextId.PeekNoReferences, [AName]));
  end;
end;

procedure Run(AMode: TAtlasPeekMode);
var
  mOwner: TPeekState;
  mCurrent: TLspSession;
  mSpot: TPeekSpot;
  mTitle: string;
  mEntries: TArray<TAtlasPeekEntry>;
  mCursor: TCursor;
begin
  mOwner := State;
  if (mOwner = nil) or not TAtlasIdeSettings.Current.Peek then
  begin
    Exit;
  end;
  mOwner.Hide;
  mCurrent := nil;
  if TAtlasIdeResults.AtCursor(mSpot.FileName, mSpot.Line, mSpot.Character, mSpot.Name) then
  begin
    mCurrent := TAtlasIdeResults.Session;
  end;
  if mCurrent = nil then
  begin
    Exit;
  end;
  mCursor := Screen.Cursor;
  Screen.Cursor := crHourGlass;
  try
    try
      mEntries := PeekEntries(mCurrent, AMode, mSpot, mTitle);
    except
      on E: ELspClientError do
      begin
        TAtlasIdeResults.Say(TAtlasResultsStrings.Fmt(TAtlasResultsTextId.ResultsFailed, [E.Message]));
        Exit;
      end;
    end;
  finally
    Screen.Cursor := mCursor;
  end;
  if Length(mEntries) = 0 then
  begin
    SayNothingFound(AMode, mSpot.Name);
  end
  else
  begin
    mOwner.Show(TAtlasPeekView.Create(AMode, mTitle, mEntries));
  end;
end;

{ TAtlasIdePeek }

class procedure TAtlasIdePeek.Install;
begin
  if FState = nil then
  begin
    FState := TPeekState.Create(nil);
  end;
end;

class procedure TAtlasIdePeek.Uninstall;
var
  mOwner: TPeekState;
begin
  mOwner := State;
  FState := nil;
  if mOwner = nil then
  begin
    Exit;
  end;
  mOwner.Hide;
  mOwner.Free;
end;

class procedure TAtlasIdePeek.PeekDefinition;
begin
  Run(TAtlasPeekMode.Definition);
end;

class procedure TAtlasIdePeek.PeekReferences;
begin
  Run(TAtlasPeekMode.References);
end;

class procedure TAtlasIdePeek.Close;
begin
  if State <> nil then
  begin
    State.Hide;
  end;
end;

end.
