unit Atlas.IDE.Problems.Painter;

// Unterstreicht Probleme im Editor (#398): nach dem Zeichnen jeder Zeile
// (PaintLine, plsEndPaint) eine Wellenlinie unter dem Bereich jedes Problems,
// Farbe nach Schweregrad (Fehler, Warnung, Info), Hinweise gepunktet; blasse
// Probleme (Text seither geändert) in abgeschwächter Farbe. Gezeichnet wird
// nur, wenn die Zeile im Editor der Zeile im Speicher entspricht.
// Direkt im DC zwischen SaveDC und RestoreDC (siehe Klammerfarben, #514).

interface

uses
  System.SysUtils,
  System.Types,
  Vcl.Controls,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Store;

type
  TAtlasProblemsPainter = class
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;
  private
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FStore: TAtlasProblemStore;
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
  public
    /// <summary>AStore gehört dem Aufrufer und lebt länger als der Zeichner.</summary>
    constructor Create(AStore: TAtlasProblemStore);
    destructor Destroy; override;
    /// <summary>Oberen Editor neu zeichnen lassen.</summary>
    class procedure Invalidate; static;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Winapi.Windows,
  System.Math,
  Vcl.Graphics,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.Pairs,
  Atlas.IDE.Editor.Buffer,
  Atlas.IDE.Editor.Style,
  Atlas.IDE.Settings.Store;

{ TAtlasProblemsPainter.TEvents }

function TAtlasProblemsPainter.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents];
end;

function TAtlasProblemsPainter.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasProblemsPainter }

constructor TAtlasProblemsPainter.Create(AStore: TAtlasProblemStore);
var
  Services: INTACodeEditorServices;
begin
  inherited Create;
  FStore := AStore;
  FIndex := -1;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    FIndex := Services.AddEditorEventsNotifier(FEventsRef);
end;

destructor TAtlasProblemsPainter.Destroy;
var
  Services: INTACodeEditorServices;
begin
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.RemoveEditorEventsNotifier(FIndex);
  FEvents.OnEditorPaintLine := nil;
  FEventsRef := nil;
  inherited Destroy;
end;

class procedure TAtlasProblemsPainter.Invalidate;
var
  Services: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.InvalidateTopEditor;
end;

/// <summary>Editorspalte (1-basiert) zum Zeichenindex (0-basiert) in ALine; Tabs aufgelöst.</summary>
function ColumnOf(const ALine: string; ACharacter, ATabWidth: Integer): Integer;
begin
  Result := Length(TAtlasPairs.DisplayLine(Copy(ALine, 1, Max(0, ACharacter)), ATabWidth)) + 1;
end;

function SeverityColor(const AColors: TAtlasColors; const AProblem: TAtlasProblem): TAtlasColor;
begin
  case AProblem.Severity of
    TAtlasProblemSeverity.Error:
      Result := AColors.Error;
    TAtlasProblemSeverity.Warning:
      Result := AColors.Warn;
    TAtlasProblemSeverity.Information:
      Result := AColors.Accent;
  else
    Result := AColors.Muted;
  end;
  if AProblem.Stale then
    Result := TAtlasColorMath.Mix(Result, AColors.Surface, 0.55);
end;

procedure TAtlasProblemsPainter.PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
  var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  Settings: TAtlasPluginSettings;
  Problems: TArray<TAtlasProblem>;
  Problem: TAtlasProblem;
  LineState: INTACodeEditorLineState;
  Line, TabWidth, From, Till, Left, Right, X, Y, Cell: Integer;
  Text, Stored: string;
  Colors: TAtlasColors;
  Code, First, Last: TRect;
  DC: HDC;
  Saved: Integer;
  Pen, Old: HGDIOBJ;
  Up: Boolean;
begin
  // Durch die Sicherung abgeschaltet (#493).
  if TAtlasGuard.Disabled(TAtlasFeature.Problems) then
    Exit;
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) then
    Exit;
  try
    Settings := TAtlasIdeSettings.Current;
    if not (Settings.Enabled and Settings.Problems) then
      Exit;
    Line := Context.LogicalLineNum - 1;
    Problems := FStore.OnLine(Context.FileName, Line);
    if Length(Problems) = 0 then
      Exit;
    LineState := Context.LineState;
    if (LineState = nil) or (Context.EditView = nil) or (Context.EditView.Buffer = nil) or
      not FStore.LineText(Context.FileName, Line, Stored) then
      Exit;
    TabWidth := TAtlasEditorBuffer.TabWidth(Context.EditView.Buffer);
    Text := Stored;
    // Nur, wenn die Zeile im Editor der im Speicher entspricht.
    if TrimRight(TAtlasPairs.DisplayLine(LineState.Text, TabWidth)) <>
      TrimRight(TAtlasPairs.DisplayLine(Text, TabWidth)) then
      Exit;
    Colors := TAtlasIdeStyle.Colors;
    Code := LineState.CodeRect;
    DC := Context.Canvas.Handle;
    Saved := SaveDC(DC);
    try
      if Code.Right > Code.Left then
        IntersectClipRect(DC, Code.Left, Rect.Top, Rect.Right, Rect.Bottom);
      for Problem in Problems do
      begin
        if Line = Problem.StartLine then
          From := Problem.StartCharacter
        else
          From := 0;
        if Line = Problem.EndLine then
          Till := Problem.EndCharacter
        else
          Till := Length(Text);
        From := EnsureRange(From, 0, Length(Text));
        Till := EnsureRange(Till, 0, Length(Text));
        // Leerer Bereich: ein Zeichen, am Zeilenende das letzte.
        if Till <= From then
        begin
          if From >= Length(Text) then
            From := Max(0, Length(Text) - 1);
          Till := From + 1;
        end;
        First := Context.EditorState.GetCharacterPosPx(ColumnOf(Text, From, TabWidth), Context.EditorLineNum);
        Last := Context.EditorState.GetCharacterPosPx(ColumnOf(Text, Till, TabWidth), Context.EditorLineNum);
        Cell := Max(4, First.Width);
        Left := First.Left;
        Right := Max(Last.Left, Left + Cell);
        Y := Rect.Bottom - 2;
        Pen := CreatePen(PS_SOLID, 1, ColorToRGB(TColor(SeverityColor(Colors, Problem))));
        Old := SelectObject(DC, Pen);
        try
          if Problem.Severity = TAtlasProblemSeverity.Hint then
          begin
            // Hinweis: gepunktet.
            X := Left;
            while X < Right do
            begin
              MoveToEx(DC, X, Y, nil);
              LineTo(DC, X + 2, Y);
              Inc(X, 4);
            end;
          end
          else
          begin
            // Welle: je 2 Pixel auf und ab.
            X := Left;
            Up := False;
            MoveToEx(DC, X, Y, nil);
            while X < Right do
            begin
              Inc(X, 2);
              Up := not Up;
              if Up then
                LineTo(DC, X, Y - 2)
              else
                LineTo(DC, X, Y);
            end;
          end;
        finally
          SelectObject(DC, Old);
          DeleteObject(Pen);
        end;
      end;
    finally
      RestoreDC(DC, Saved);
    end;
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Problems, E);
  end;
end;

end.
