unit Atlas.IDE.Editor.Reassigned;

// Neu zugewiesene Variablen unterstreichen (#712) im Editor. Welche Namen
// zählen, rechnet der Server (atlas.server.reassigned,
// Atlas.Common.Semantics.Reassigned); Antwort lesen und Linien rechnen
// Atlas.Core.Editor.Reassigned. Hier bleiben Zeitgeber, Anfrage und Zeichnen.
// - Ein Zeitgeber (250 ms) liest die Ansicht vorn. Ruht der Text 700 ms, fragt
//   Atlas den laufenden Server im Hintergrund nach allen Stellen der Datei
//   (Arten aus highlight.reassigned.targets); nur die jüngste Antwort zählt
//   und je Datei, Textstand und Arten nur einmal. Scheitert die Anfrage,
//   wartet Atlas 5 s.
// - PaintLine (plsEndPaint) zieht unter jede Stelle eines neu zugewiesenen
//   Namens eine dünne Linie (highlight.reassigned.style: gepunktet,
//   durchgezogen, Welle) in der Akzentfarbe des Themas oder der eigenen Farbe
//   (highlight.reassigned.color); nur, solange die Zeile noch den Text vom
//   Abruf hat. Die Linie sitzt eine Einheit über der Wellenlinie der Probleme.
// - Den Hover („Neu zugewiesen: 3 Zuweisungen“) liefert der Server mit der
//   Hover-Antwort; Atlas.IDE.Hover.Editor blendet ihn mit der Einstellung aus.
// - highlight.reassigned aus oder Atlas aus: nichts. Je Datei oder überall
//   ausblenden über das Element Reassigned (#628) an der Linie.
// Gesichert über TAtlasFeature.Reassigned (#493). Nur im Hauptthread.

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
  Atlas.Core.Settings.Reassigned,
  Atlas.Core.Editor.Reassigned;

type
  /// <summary>Laufende Sitzung oder nil; startet keinen Server.</summary>
  TAtlasReassignedSessionFunc = reference to function: TLspSession;

  TAtlasIdeReassigned = class
  public const
    Command = 'atlas.server.reassigned';
  private const
    TickMs = 250;
    QuietMs = 700;
    TimeoutMs = 2000;
    RetryMs = 5000;
    /// <summary>Anteil der Akzentfarbe am Hintergrund bei der Themenfarbe.</summary>
    ThemeStrength = 0.7;
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;
  private class var
    FInstance: TAtlasIdeReassigned;
  private
    FSession: TAtlasReassignedSessionFunc;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FTimer: TTimer;
    FWorkers: TList<TThread>;
    FRequest: Integer;
    // Stand des Editors: Datei, Pufferstand und Zeitpunkt der letzten Änderung.
    FFileName: string;
    FVersion: Cardinal;
    FChangedAt: Cardinal;
    FRetryAt: Cardinal;
    FAskedKey: string;
    // Stand der Antwort: Datei, Pufferstand, Zeilen und Stellen.
    FShownFile: string;
    FLines: TArray<string>;
    FTabWidth: Integer;
    FSet: TAtlasReassignedSet;
    FStyle: TAtlasReassignedStyle;
    FColor: string;
    procedure TimerTick(Sender: TObject);
    procedure Update;
    procedure Clear;
    procedure Ask(const AText: string; ATargets: TAtlasReassignedTargets);
    procedure Accept(ARequest: Integer; const AFileName, AText: string;
      const ASet: TAtlasReassignedSet; AFailed: Boolean);
    procedure ReapWorkers(AWait: Boolean);
    function LineColor(ABack: TAtlasColor): TAtlasColor;
    procedure PaintUses(const Rect: TRect; const Context: INTACodeEditorPaintContext; const AText: string;
      const AUses: TArray<TAtlasReassignedUse>; ABack: TAtlasColor);
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    class function IsSource(const AFileName: string): Boolean; static;
    class procedure Invalidate; static;
  public
    constructor Create(const ASession: TAtlasReassignedSessionFunc);
    destructor Destroy; override;
    class procedure Install(const ASession: TAtlasReassignedSessionFunc); static;
    class procedure Uninstall; static;
    class function Installed: Boolean; static;
  end;

implementation

uses
  System.Math,
  System.JSON,
  Atlas.Text.Lines,
  Atlas.Core.Style.Palette,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Editor.Elements,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Elements,
  Atlas.IDE.Foundation.EditorRefresh;

{ TAtlasIdeReassigned.TEvents }

function TAtlasIdeReassigned.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents];
end;

function TAtlasIdeReassigned.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasIdeReassigned }

constructor TAtlasIdeReassigned.Create(const ASession: TAtlasReassignedSessionFunc);
var
  Services: INTACodeEditorServices;
begin
  inherited Create;
  FSession := ASession;
  FIndex := -1;
  FWorkers := TList<TThread>.Create;
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

destructor TAtlasIdeReassigned.Destroy;
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
  Painted := FSet.HasUses;
  Clear;
  if Painted then
    Invalidate;
  inherited;
end;

class procedure TAtlasIdeReassigned.Install(const ASession: TAtlasReassignedSessionFunc);
begin
  if FInstance = nil then
    FInstance := TAtlasIdeReassigned.Create(ASession);
end;

class procedure TAtlasIdeReassigned.Uninstall;
begin
  FreeAndNil(FInstance);
end;

class function TAtlasIdeReassigned.Installed: Boolean;
begin
  Result := FInstance <> nil;
end;

class procedure TAtlasIdeReassigned.Invalidate;
var
  Services: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    TAtlasIdeEditorRefresh.InvalidateTop(Services);
end;

class function TAtlasIdeReassigned.IsSource(const AFileName: string): Boolean;
var
  Extension: string;
begin
  Extension := ExtractFileExt(AFileName);
  Result := SameText(Extension, '.pas') or SameText(Extension, '.dpr') or SameText(Extension, '.dpk');
end;

procedure TAtlasIdeReassigned.Clear;
begin
  FSet := Default(TAtlasReassignedSet);
  FShownFile := '';
  FLines := nil;
  FAskedKey := '';
end;

procedure TAtlasIdeReassigned.ReapWorkers(AWait: Boolean);
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

procedure TAtlasIdeReassigned.TimerTick(Sender: TObject);
begin
  try
    Update;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Reassigned, E);
  end;
end;

procedure TAtlasIdeReassigned.Update;
var
  View: IOTAEditView;
  Snapshot: TAtlasEditorSnapshot;
  TargetsText, StyleText, ColorText, Key: string;
  Targets: TAtlasReassignedTargets;
  Style: TAtlasReassignedStyle;
  Had: Boolean;
  Moment: Cardinal;
begin
  View := nil;
  if TAtlasIdeSettings.ReassignedOn(TargetsText, StyleText, ColorText) and
    not TAtlasGuard.Disabled(TAtlasFeature.Reassigned) then
    View := TAtlasEditorBuffer.ActiveView;
  Had := FSet.HasUses;
  if (View = nil) or (View.Buffer = nil) or not IsSource(View.Buffer.FileName) then
  begin
    // Aus oder kein Quelltext vorn: nichts zeigen, beim Wiederkommen neu fragen.
    if View = nil then
    begin
      Clear;
      if Had then
        Invalidate;
    end;
    Exit;
  end;
  Style := TAtlasReassignedNames.StyleOf(StyleText);
  if (Style <> FStyle) or (ColorText <> FColor) then
  begin
    FStyle := Style;
    FColor := ColorText;
    if Had then
      Invalidate;
  end;
  Snapshot := TAtlasEditorSnapshots.Get(View);
  Moment := GetTickCount;
  if (Snapshot.Version <> FVersion) or not SameText(Snapshot.FileName, FFileName) then
  begin
    // Die Linien bleiben stehen (PaintLine prüft je Zeile den Text); gefragt wird nach der Tipp-Pause.
    FFileName := Snapshot.FileName;
    FVersion := Snapshot.Version;
    FChangedAt := Moment;
    Exit;
  end;
  if (Moment - FChangedAt < QuietMs) or (Moment < FRetryAt) then
    Exit;
  Targets := TAtlasReassignedNames.ParseTargets(TargetsText);
  Key := Format('%s|%d|%s', [FFileName, FVersion, TAtlasReassignedNames.TargetsText(Targets)]);
  if Key = FAskedKey then
    Exit;
  FAskedKey := Key;
  FTabWidth := TAtlasEditorBuffer.TabWidth(View.Buffer);
  Ask(Snapshot.Text, Targets);
end;

procedure TAtlasIdeReassigned.Ask(const AText: string; ATargets: TAtlasReassignedTargets);
var
  Session: TLspSession;
  FileName, Arguments, Text: string;
  Request: Integer;
  Worker: TThread;
begin
  if not Assigned(FSession) then
    Exit;
  Session := FSession();
  if Session = nil then
  begin
    // Server läuft (noch) nicht: beim nächsten Takt nach der Wartezeit noch einmal.
    FAskedKey := '';
    FRetryAt := GetTickCount + RetryMs;
    Exit;
  end;
  FileName := FFileName;
  Text := AText;
  Arguments := TAtlasReassigned.Arguments(TLspSession.PathToUri(FileName), ATargets);
  // Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  Session.Sync(FileName, AText);
  ReapWorkers(False);
  Inc(FRequest);
  Request := FRequest;
  Worker := TThread.CreateAnonymousThread(
    procedure
    var
      Answer: TJSONValue;
      Found: TAtlasReassignedSet;
      Failed: Boolean;
    begin
      Found := Default(TAtlasReassignedSet);
      Failed := False;
      try
        Answer := Session.RunCommand(Command, Arguments, TimeoutMs);
        try
          Found := TAtlasReassignedSet.FromJson(Answer);
        finally
          Answer.Free;
        end;
      except
        // Server beschäftigt, weg oder zu alt (Befehl unbekannt): später noch einmal, der Editor bleibt frei.
        Failed := True;
      end;
      // Atlas gehört der Eintrag: beim Entladen verworfen (Code-Review A-02).
      TAtlasMainThread.Queue(TAtlasFeature.Reassigned,
        procedure
        begin
          if FInstance <> nil then
            TAtlasGuard.Run(TAtlasFeature.Reassigned,
              procedure
              begin
                if FInstance <> nil then
                  FInstance.Accept(Request, FileName, Text, Found, Failed);
              end);
        end);
    end);
  Worker.FreeOnTerminate := False;
  FWorkers.Add(Worker);
  Worker.Start;
end;

procedure TAtlasIdeReassigned.Accept(ARequest: Integer; const AFileName, AText: string;
  const ASet: TAtlasReassignedSet; AFailed: Boolean);
var
  Had: Boolean;
begin
  if ARequest <> FRequest then
    Exit;
  if AFailed then
  begin
    FAskedKey := '';
    FRetryAt := GetTickCount + RetryMs;
    Exit;
  end;
  if not ASet.Valid then
    Exit;
  Had := FSet.HasUses;
  FSet := ASet;
  FShownFile := AFileName;
  FLines := TTextLines.SplitLines(AText);
  if Had or FSet.HasUses then
    Invalidate;
end;

function TAtlasIdeReassigned.LineColor(ABack: TAtlasColor): TAtlasColor;
begin
  if not TAtlasReassignedNames.TryColor(FColor, Result) then
    Result := TAtlasColorMath.Mix(TAtlasColors.ForBackground(ABack).Accent, ABack, ThemeStrength);
end;

procedure TAtlasIdeReassigned.PaintUses(const Rect: TRect; const Context: INTACodeEditorPaintContext;
  const AText: string; const AUses: TArray<TAtlasReassignedUse>; ABack: TAtlasColor);
var
  Use: TAtlasReassignedUse;
  Part: TAtlasUnderlineSegment;
  First, Last, Code, Mark: TRect;
  Canvas: TCanvas;
  DC: HDC;
  Saved, Step, Baseline: Integer;
begin
  Canvas := Context.Canvas;
  DC := Canvas.Handle;
  Code := Context.LineState.CodeRect;
  // Eine Einheit je 16 Pixel Zeilenhöhe: wächst mit der Bildschirmskalierung.
  Step := Max(1, Rect.Height div 16);
  // Über der Wellenlinie der Probleme (Rect.Bottom - 2), damit beide lesbar bleiben.
  Baseline := Rect.Bottom - 2 - 2 * Step;
  Saved := SaveDC(DC);
  try
    if Code.Right > Code.Left then
      IntersectClipRect(DC, Code.Left, Rect.Top, Rect.Right, Rect.Bottom);
    Canvas.Pen.Color := TColor(LineColor(ABack));
    Canvas.Pen.Width := Step;
    Canvas.Pen.Style := psSolid;
    for Use in AUses do
    begin
      First := Context.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(AText, Use.Character, FTabWidth),
        Context.EditorLineNum);
      Last := Context.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(AText, Use.EndCharacter, FTabWidth),
        Context.EditorLineNum);
      for Part in TAtlasReassigned.Segments(FStyle, First.Left, Max(Last.Left, First.Left + 1), Baseline, Step) do
      begin
        Canvas.MoveTo(Part.X1, Part.Y1);
        Canvas.LineTo(Part.X2, Part.Y2);
      end;
      Mark := TRect.Create(First.Left, Baseline - 2 * Step, Max(Last.Left, First.Left + 1), Rect.Bottom);
      TAtlasIdeElements.Painted(TAtlasDrawnElement.Reassigned, Context.FileName, Context.LogicalLineNum - 1, AText,
        Mark, Context.EditView.TopRow, Rect.Height);
    end;
  finally
    RestoreDC(DC, Saved);
  end;
end;

procedure TAtlasIdeReassigned.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  LineState: INTACodeEditorLineState;
  Found: TArray<TAtlasReassignedUse>;
  Text: string;
  Line: Integer;
begin
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) or not FSet.HasUses or
    TAtlasGuard.Disabled(TAtlasFeature.Reassigned) then
    Exit;
  try
    if not SameText(Context.FileName, FShownFile) or
      TAtlasIdeElements.FileHidden(TAtlasDrawnElement.Reassigned, Context.FileName) then
      Exit;
    LineState := Context.LineState;
    if LineState = nil then
      Exit;
    Line := Context.LogicalLineNum - 1;
    if (Line < 0) or (Line >= Length(FLines)) then
      Exit;
    Found := FSet.UsesAt(Line);
    if Length(Found) = 0 then
      Exit;
    Text := FLines[Line];
    // Nur, wenn die Zeile im Editor dem gefragten Stand entspricht (sonst kommt nach der Tipp-Pause eine neue
    // Antwort).
    if TrimRight(LineState.Text) <> TrimRight(Text) then
      Exit;
    PaintUses(Rect, Context, Text, Found, TAtlasIdeStyle.SampleBack(Context.Canvas, Rect.Right - 2, Rect.Top + 1));
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Reassigned, E);
  end;
end;

end.
