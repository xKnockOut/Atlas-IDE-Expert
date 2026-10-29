unit Atlas.IDE.Editor.ExitPoints;

// Austrittspunkte hervorheben (#698) im Editor. Welche Stellen zählen, rechnet
// der Server (atlas.server.exitPoints, Atlas.Common.Semantics.ExitPoints);
// Antwort lesen, Auslöser und Sprünge rechnet Atlas.Core.Editor.ExitPoints.
// Hier bleiben Zeitgeber, Anfrage, Zeichnen und F3.
// - Ein Zeitgeber (100 ms) liest den Cursor der Ansicht vorn. Steht er auf
//   einem Auslöser (TAtlasExitPoints.Triggers) und ruht zwei Takte, fragt Atlas
//   den laufenden Server im Hintergrund; nur die jüngste Antwort zählt, und
//   nur, solange der Text derselbe ist (TAtlasEditorSnapshots).
// - Steht der Cursor auf einer markierten Stelle oder dem Routinennamen, bleibt
//   die Hervorhebung (F3 springt so auch auf das end); woanders verschwindet
//   sie, ebenso bei jeder Änderung am Text und mit einer Markierung (dann
//   gehört F3 der Markierungssuche).
// - PaintLine (plsEndPaint) überzieht jede Stelle halb durchsichtig: Austritte
//   in der Warnfarbe, Austritte ohne Ergebnis und die Quellen einer Exception
//   in der Fehlerfarbe, Zuweisungen an Result in der Farbe für Hinzugefügtes,
//   Schleifen in der Akzentfarbe. Hinter dem Routinenkopf steht die Marke
//   („3 Austritte“, editor.exitPoints.badge); den Platz teilt sie mit den
//   anderen Zeichnern (TAtlasLineTail).
// - F3/Umschalt+F3 (Atlas.IDE.Commands.Bindings) springt reihum, solange die
//   Hervorhebung steht und der Cursor auf einer ihrer Stellen liegt.
// - editor.exitPoints aus oder Atlas aus: nichts. Je Datei oder überall
//   ausblenden über das Element ExitPoints (#628) an der Marke.
// Gesichert über TAtlasFeature.ExitPoints (#493). Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Generics.Collections,
  Winapi.Windows,
  Vcl.Graphics,
  Vcl.ExtCtrls,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Style.Color,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.ExitPoints;

type
  /// <summary>Laufende Sitzung oder nil; startet keinen Server.</summary>
  TAtlasExitPointsSessionFunc = reference to function: TLspSession;

  TAtlasIdeExitPoints = class
  public const
    Command = 'atlas.server.exitPoints';
  private const
    TickMs = 100;
    /// <summary>So viele Takte ohne Bewegung, bevor Atlas den Server fragt.</summary>
    IdleTicks = 2;
    TimeoutMs = 1500;
    /// <summary>Deckkraft der Stellen über dem Text (0–255).</summary>
    PointAlpha = 70;
    /// <summary>Anteil der Farbe am Hintergrund der Marke.</summary>
    MarkStrength = 0.16;
    /// <summary>Innenabstand der Marke links und rechts in Pixeln.</summary>
    MarkPadding = 4;
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;
  private class var
    FInstance: TAtlasIdeExitPoints;
  private
    FSession: TAtlasExitPointsSessionFunc;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FTimer: TTimer;
    FWorkers: TList<TThread>;
    FFont: TFont;
    FFontKey: string;
    FRequest: Integer;
    FIdleKey: string;
    FIdleCount: Integer;
    FAskedKey: string;
    // Stand der Hervorhebung: Datei, Pufferstand, Zeilen und Antwort.
    FFileName: string;
    FVersion: Cardinal;
    FLines: TArray<string>;
    FTabWidth: Integer;
    FSet: TAtlasExitPointSet;
    FBadge: Boolean;
    procedure TimerTick(Sender: TObject);
    procedure Update;
    procedure Clear;
    procedure Ask(const AView: IOTAEditView; const AText: string; ALine, ACharacter: Integer;
      AExceptions, ALoops: Boolean);
    procedure Accept(ARequest: Integer; const AFileName: string; AVersion: Cardinal; const ASet: TAtlasExitPointSet);
    procedure ReapWorkers(AWait: Boolean);
    procedure EnsureFont(const AEditorFont: TFont);
    function Jump(ABackward: Boolean): Boolean;
    procedure PaintPoints(const Rect: TRect; const Context: INTACodeEditorPaintContext; const AText: string;
      const APoints: TArray<TAtlasExitPoint>; ABack: TAtlasColor);
    procedure PaintBadge(const Rect: TRect; const Context: INTACodeEditorPaintContext; const AText: string;
      ABack: TAtlasColor);
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    class procedure ReadCaret(const AView: IOTAEditView; out ALine, ACharacter: Integer); static;
    class function HasBlock(const AView: IOTAEditView): Boolean; static;
    class function IsSource(const AFileName: string): Boolean; static;
    class procedure Invalidate; static;
  public
    constructor Create(const ASession: TAtlasExitPointsSessionFunc);
    destructor Destroy; override;
    class procedure Install(const ASession: TAtlasExitPointsSessionFunc); static;
    class procedure Uninstall; static;
    class function Installed: Boolean; static;
    /// <summary>F3 (ABackward: Umschalt+F3): zur nächsten Stelle springen, solange die Hervorhebung steht und der
    /// Cursor auf einer ihrer Stellen liegt; sonst False (die Taste geht weiter).</summary>
    class function TryJump(ABackward: Boolean): Boolean; static;
  end;

implementation

uses
  System.Math,
  System.JSON,
  Atlas.Text.Lines,
  Atlas.Core.Style.Palette,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Editor.LineTail,
  Atlas.Core.Editor.Elements,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Elements,
  Atlas.IDE.Foundation.EditorRefresh;

function RoleColor(const AColors: TAtlasColors; ARole: TAtlasExitPointRole): TAtlasColor;
begin
  case ARole of
    TAtlasExitPointRole.Assign:
      Result := AColors.Add;
    TAtlasExitPointRole.Missing, TAtlasExitPointRole.Source:
      Result := AColors.Error;
    TAtlasExitPointRole.Loop:
      Result := AColors.Accent;
  else
    Result := AColors.Warn;
  end;
end;

{ TAtlasIdeExitPoints.TEvents }

function TAtlasIdeExitPoints.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents];
end;

function TAtlasIdeExitPoints.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasIdeExitPoints }

constructor TAtlasIdeExitPoints.Create(const ASession: TAtlasExitPointsSessionFunc);
var
  Services: INTACodeEditorServices;
begin
  inherited Create;
  FSession := ASession;
  FIndex := -1;
  FWorkers := TList<TThread>.Create;
  FFont := TFont.Create;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    FIndex := Services.AddEditorEventsNotifier(FEventsRef);
  FTimer := TTimer.Create(nil);
  FTimer.Interval := TickMs;
  FTimer.OnTimer := TimerTick;
  FTimer.Enabled := True;
end;

destructor TAtlasIdeExitPoints.Destroy;
var
  Services: INTACodeEditorServices;
  Painted: Boolean;
begin
  FreeAndNil(FTimer);
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.RemoveEditorEventsNotifier(FIndex);
  FEvents.OnEditorPaintLine := nil;
  FEventsRef := nil;
  // Laufende Anfragen halten die Sitzung als rohen Zeiger: abwarten.
  ReapWorkers(True);
  FreeAndNil(FWorkers);
  Painted := FSet.Found;
  Clear;
  FreeAndNil(FFont);
  if Painted then
    Invalidate;
  inherited;
end;

class procedure TAtlasIdeExitPoints.Install(const ASession: TAtlasExitPointsSessionFunc);
begin
  if FInstance = nil then
    FInstance := TAtlasIdeExitPoints.Create(ASession);
end;

class procedure TAtlasIdeExitPoints.Uninstall;
begin
  FreeAndNil(FInstance);
end;

class function TAtlasIdeExitPoints.Installed: Boolean;
begin
  Result := FInstance <> nil;
end;

class procedure TAtlasIdeExitPoints.Invalidate;
var
  Services: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    TAtlasIdeEditorRefresh.InvalidateTop(Services);
end;

class function TAtlasIdeExitPoints.IsSource(const AFileName: string): Boolean;
var
  Extension: string;
begin
  Extension := ExtractFileExt(AFileName);
  Result := SameText(Extension, '.pas') or SameText(Extension, '.dpr') or SameText(Extension, '.dpk') or
    SameText(Extension, '.inc');
end;

class procedure TAtlasIdeExitPoints.ReadCaret(const AView: IOTAEditView; out ALine, ACharacter: Integer);
var
  Cursor: TOTAEditPos;
  LineText: string;
begin
  Cursor := AView.CursorPos;
  ALine := Max(0, Cursor.Line - 1);
  LineText := TAtlasEditorBuffer.LineText(AView, ALine + 1);
  ACharacter := Min(TLspSession.ColumnToIndex(LineText, Cursor.Col, TAtlasEditorBuffer.TabWidth(AView.Buffer)),
    Length(LineText));
end;

class function TAtlasIdeExitPoints.HasBlock(const AView: IOTAEditView): Boolean;
var
  Block: IOTAEditBlock;
begin
  Block := AView.Block;
  Result := (Block <> nil) and Block.IsValid and (Block.Size > 0);
end;

procedure TAtlasIdeExitPoints.Clear;
begin
  FSet := Default(TAtlasExitPointSet);
  FFileName := '';
  FVersion := 0;
  FLines := nil;
  FAskedKey := '';
end;

procedure TAtlasIdeExitPoints.ReapWorkers(AWait: Boolean);
var
  Index: Integer;
begin
  if FWorkers = nil then
    Exit;
  for Index := FWorkers.Count - 1 downto 0 do
    if AWait or FWorkers[Index].Finished then
    begin
      FWorkers[Index].WaitFor;
      FWorkers[Index].Free;
      FWorkers.Delete(Index);
    end;
end;

procedure TAtlasIdeExitPoints.TimerTick(Sender: TObject);
begin
  try
    Update;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.ExitPoints, E);
  end;
end;

procedure TAtlasIdeExitPoints.Update;
var
  View: IOTAEditView;
  Snapshot: TAtlasEditorSnapshot;
  Exceptions, Loops, Badge, Had: Boolean;
  Line, Character, Start, Stop: Integer;
  LineText, Key: string;
begin
  View := nil;
  Badge := False;
  if TAtlasIdeSettings.ExitPointsOn(Exceptions, Loops, Badge) and not TAtlasGuard.Disabled(TAtlasFeature.ExitPoints) then
    View := TAtlasEditorBuffer.ActiveView;
  Had := FSet.Found;
  if (View = nil) or (View.Buffer = nil) or not IsSource(View.Buffer.FileName) or HasBlock(View) then
  begin
    Clear;
    if Had then
      Invalidate;
    Exit;
  end;
  if Badge <> FBadge then
  begin
    FBadge := Badge;
    if Had then
      Invalidate;
  end;
  Snapshot := TAtlasEditorSnapshots.Get(View);
  if (Snapshot.Version <> FVersion) or not SameText(Snapshot.FileName, FFileName) then
  begin
    // Neuer Text: Die alte Antwort gilt nicht mehr.
    Clear;
    if Had then
      Invalidate;
    Had := False;
    FFileName := Snapshot.FileName;
    FVersion := Snapshot.Version;
    FLines := TTextLines.SplitLines(Snapshot.Text);
    FTabWidth := TAtlasEditorBuffer.TabWidth(View.Buffer);
  end;
  ReadCaret(View, Line, Character);
  if FSet.Holds(Line, Character) then
    Exit;
  if Had then
  begin
    FSet := Default(TAtlasExitPointSet);
    Invalidate;
  end;
  LineText := '';
  if Line < Length(FLines) then
    LineText := FLines[Line];
  if not TAtlasExitPoints.Triggers(LineText, Character) or
    not TAtlasExitPoints.WordAt(LineText, Character, Start, Stop) then
  begin
    FIdleKey := '';
    FAskedKey := '';
    Exit;
  end;
  // Je Wort eine Anfrage: Cursorbewegungen innerhalb des Worts ändern den Schlüssel nicht.
  Key := Format('%s|%d|%d|%d|%d|%d', [FFileName, FVersion, Line, Start, Ord(Exceptions), Ord(Loops)]);
  if Key <> FIdleKey then
  begin
    FIdleKey := Key;
    FIdleCount := 0;
    Exit;
  end;
  Inc(FIdleCount);
  if (FIdleCount < IdleTicks) or (Key = FAskedKey) then
    Exit;
  FAskedKey := Key;
  Ask(View, Snapshot.Text, Line, Character, Exceptions, Loops);
end;

procedure TAtlasIdeExitPoints.Ask(const AView: IOTAEditView; const AText: string; ALine, ACharacter: Integer;
  AExceptions, ALoops: Boolean);
var
  Session: TLspSession;
  FileName, Arguments: string;
  Version: Cardinal;
  Request: Integer;
  Values: TJSONArray;
  Position, Options: TJSONObject;
  Worker: TThread;
begin
  if not Assigned(FSession) then
    Exit;
  Session := FSession();
  if Session = nil then
    Exit;
  FileName := FFileName;
  Version := FVersion;
  Values := TJSONArray.Create;
  try
    Values.Add(TLspSession.PathToUri(FileName));
    Position := TJSONObject.Create;
    Position.AddPair('line', TJSONNumber.Create(ALine));
    Position.AddPair('character', TJSONNumber.Create(ACharacter));
    Values.AddElement(Position);
    Options := TJSONObject.Create;
    Options.AddPair('exceptions', TJSONBool.Create(AExceptions));
    Options.AddPair('loops', TJSONBool.Create(ALoops));
    Values.AddElement(Options);
    Arguments := Values.ToJSON;
  finally
    Values.Free;
  end;
  // Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  Session.Sync(FileName, AText);
  ReapWorkers(False);
  Inc(FRequest);
  Request := FRequest;
  Worker := TThread.CreateAnonymousThread(
    procedure
    var
      Answer: TJSONValue;
      Found: TAtlasExitPointSet;
    begin
      Found := Default(TAtlasExitPointSet);
      try
        Answer := Session.RunCommand(Command, Arguments, TimeoutMs);
        try
          Found := TAtlasExitPointSet.FromJson(Answer);
        finally
          Answer.Free;
        end;
      except
        // Server beschäftigt, weg oder zu alt (Befehl unbekannt): keine Hervorhebung, der Editor bleibt frei.
        Found := Default(TAtlasExitPointSet);
      end;
      // Atlas gehört der Eintrag: beim Entladen verworfen (Code-Review A-02).
      TAtlasMainThread.Queue(TAtlasFeature.ExitPoints,
        procedure
        begin
          if FInstance <> nil then
            TAtlasGuard.Run(TAtlasFeature.ExitPoints,
              procedure
              begin
                if FInstance <> nil then
                  FInstance.Accept(Request, FileName, Version, Found);
              end);
        end);
    end);
  Worker.FreeOnTerminate := False;
  FWorkers.Add(Worker);
  Worker.Start;
end;

procedure TAtlasIdeExitPoints.Accept(ARequest: Integer; const AFileName: string; AVersion: Cardinal;
  const ASet: TAtlasExitPointSet);
begin
  // Nur die jüngste Antwort und nur für den Text, nach dem gefragt wurde.
  if (ARequest <> FRequest) or not SameText(AFileName, FFileName) or (AVersion <> FVersion) then
    Exit;
  FSet := ASet;
  if FSet.Found then
    Invalidate;
end;

class function TAtlasIdeExitPoints.TryJump(ABackward: Boolean): Boolean;
begin
  Result := (FInstance <> nil) and not TAtlasGuard.Disabled(TAtlasFeature.ExitPoints) and FInstance.Jump(ABackward);
end;

function TAtlasIdeExitPoints.Jump(ABackward: Boolean): Boolean;
var
  View: IOTAEditView;
  Snapshot: TAtlasEditorSnapshot;
  Line, Character: Integer;
  Point: TAtlasExitPoint;
  Position: TOTAEditPos;
  LineText: string;
begin
  Result := False;
  if not FSet.Found then
    Exit;
  View := TAtlasEditorBuffer.ActiveView;
  if (View = nil) or (View.Buffer = nil) or HasBlock(View) then
    Exit;
  Snapshot := TAtlasEditorSnapshots.Get(View);
  if not SameText(Snapshot.FileName, FFileName) or (Snapshot.Version <> FVersion) then
    Exit;
  ReadCaret(View, Line, Character);
  if not FSet.Holds(Line, Character) or not FSet.Next(Line, Character, ABackward, Point) then
    Exit;
  LineText := '';
  if Point.Line < Length(FLines) then
    LineText := FLines[Point.Line];
  Position.Line := Point.Line + 1;
  Position.Col := TLspSession.IndexToColumn(LineText, Point.Character, FTabWidth);
  View.CursorPos := Position;
  View.MoveViewToCursor;
  View.Paint;
  Result := True;
end;

procedure TAtlasIdeExitPoints.EnsureFont(const AEditorFont: TFont);
var
  Key: string;
begin
  Key := AEditorFont.Name + '|' + IntToStr(AEditorFont.Size) + '|' + IntToStr(AEditorFont.PixelsPerInch);
  if Key = FFontKey then
    Exit;
  FFont.Assign(AEditorFont);
  FFont.Style := [];
  FFontKey := Key;
end;

procedure TAtlasIdeExitPoints.PaintPoints(const Rect: TRect; const Context: INTACodeEditorPaintContext;
  const AText: string; const APoints: TArray<TAtlasExitPoint>; ABack: TAtlasColor);
var
  Point: TAtlasExitPoint;
  Colors: TAtlasColors;
  First, Last, Code: TRect;
  DC: HDC;
  Saved: Integer;
begin
  Colors := TAtlasColors.ForBackground(ABack);
  DC := Context.Canvas.Handle;
  Code := Context.LineState.CodeRect;
  Saved := SaveDC(DC);
  try
    if Code.Right > Code.Left then
      IntersectClipRect(DC, Code.Left, Rect.Top, Rect.Right, Rect.Bottom);
    for Point in APoints do
    begin
      First := Context.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(AText, Point.Character, FTabWidth),
        Context.EditorLineNum);
      Last := Context.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(AText, Point.EndCharacter, FTabWidth),
        Context.EditorLineNum);
      TAtlasIdeStyle.Blend(DC, TRect.Create(First.Left, Rect.Top, Max(Last.Left, First.Left + 1), Rect.Bottom),
        COLORREF(ColorToRGB(TColor(RoleColor(Colors, Point.Role)))), PointAlpha);
    end;
  finally
    RestoreDC(DC, Saved);
  end;
end;

procedure TAtlasIdeExitPoints.PaintBadge(const Rect: TRect; const Context: INTACodeEditorPaintContext;
  const AText: string; ABack: TAtlasColor);
var
  Caption, Key: string;
  Cell, Mark: TRect;
  Colors: TAtlasColors;
  Tone: TAtlasColor;
  DC: HDC;
  Saved, X, Top: Integer;
  Size: TSize;
  Brush: HBRUSH;
begin
  Caption := TAtlasExitPoints.BadgeText(FSet, TAtlasStrings.Text(TAtlasTextId.ExitPointsOne),
    TAtlasStrings.Text(TAtlasTextId.ExitPointsCount), TAtlasStrings.Text(TAtlasTextId.ExitPointsResultMissing));
  Cell := Context.EditorState.GetCharacterPosPx(
    TLspSession.IndexToColumn(AText, Length(TrimRight(AText)), FTabWidth) + 2, Context.EditorLineNum);
  Key := TAtlasLineTail.KeyOf(Context.FileName, Context.LogicalLineNum, Context.EditorLineNum, Rect.Top);
  X := TAtlasLineTail.Start(Self, Key, Cell.Left);
  Colors := TAtlasColors.ForBackground(ABack);
  Tone := Colors.Warn;
  if FSet.ResultMissing then
    Tone := Colors.Error;
  EnsureFont(Context.Canvas.Font);
  DC := Context.Canvas.Handle;
  Saved := SaveDC(DC);
  Brush := CreateSolidBrush(COLORREF(ColorToRGB(TColor(TAtlasColorMath.Mix(Tone, ABack, MarkStrength)))));
  try
    SelectObject(DC, FFont.Handle);
    GetTextExtentPoint32W(DC, PChar(Caption), Length(Caption), Size);
    Top := Rect.Top + Max(0, (Rect.Bottom - Rect.Top - Size.cy) div 2);
    Mark := TRect.Create(X, Rect.Top + 1, X + Size.cx + 2 * MarkPadding, Rect.Bottom - 1);
    FillRect(DC, Mark, Brush);
    SetTextColor(DC, COLORREF(ColorToRGB(TColor(Tone))));
    SetBkMode(DC, TRANSPARENT);
    TextOutW(DC, X + MarkPadding, Top, PChar(Caption), Length(Caption));
  finally
    DeleteObject(Brush);
    RestoreDC(DC, Saved);
  end;
  TAtlasLineTail.Finish(Self, Key, Mark.Right);
  TAtlasIdeElements.Painted(TAtlasDrawnElement.ExitPoints, Context.FileName, FSet.RoutineLine, AText, Mark,
    Context.EditView.TopRow, Rect.Height);
end;

procedure TAtlasIdeExitPoints.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  LineState: INTACodeEditorLineState;
  Points: TArray<TAtlasExitPoint>;
  Text: string;
  Line: Integer;
  Badge: Boolean;
  Back: TAtlasColor;
begin
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) or not FSet.Found or
    TAtlasGuard.Disabled(TAtlasFeature.ExitPoints) then
    Exit;
  try
    if not SameText(Context.FileName, FFileName) or
      TAtlasIdeElements.FileHidden(TAtlasDrawnElement.ExitPoints, Context.FileName) then
      Exit;
    LineState := Context.LineState;
    if LineState = nil then
      Exit;
    Line := Context.LogicalLineNum - 1;
    if (Line < 0) or (Line >= Length(FLines)) then
      Exit;
    Text := FLines[Line];
    // Nur, wenn die Zeile im Editor dem gefragten Stand entspricht (sonst kommt gleich ein neuer Takt).
    if TrimRight(LineState.Text) <> TrimRight(Text) then
      Exit;
    Points := FSet.PointsAt(Line);
    Badge := FBadge and FSet.HasBadge and (Line = FSet.RoutineLine);
    if (Length(Points) = 0) and not Badge then
      Exit;
    Back := TAtlasIdeStyle.SampleBack(Context.Canvas, Rect.Right - 2, Rect.Top + 1);
    if Length(Points) > 0 then
      PaintPoints(Rect, Context, Text, Points, Back);
    if Badge then
      PaintBadge(Rect, Context, Text, Back);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.ExitPoints, E);
  end;
end;

end.
