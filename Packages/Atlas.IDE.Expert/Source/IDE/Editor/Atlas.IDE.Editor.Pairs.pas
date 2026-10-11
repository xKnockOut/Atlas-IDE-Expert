unit Atlas.IDE.Editor.Pairs;

// Klammer- und Blockpaare farbig (#514). Die Analyse (TAtlasPairs) läuft je
// Datei einmal, wenn sich der Puffer geändert hat; geprüft wird zu Beginn
// jedes Zeichnens. Gezeichnet wird über OnEditorPaintText: Enthält ein
// Textlauf eine Klammer oder ein Blockwort, zeichnet Atlas den Lauf selbst
// (Pinsel und Schrift hat die IDE vorbereitet), die Paare in der Farbe ihrer
// Tiefe, unpaarige in der Fehlerfarbe. Markierter Text bleibt der IDE.
// Strings und Kommentare zählen nicht (eigener Lexer). Abschaltbar.
// Blocklinien (eigene Einstellung): Nach dem Zeichnen jeder Zeile senkrechte
// Linien der Blöcke über mehrere Zeilen in den Paarfarben, mit Haken an Öffner
// und Schließer; die Strukturhervorhebung der IDE ist dann aus
// (Atlas.IDE.Editor.Structure).

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Editor.Pairs,
  Atlas.Core.Editor.Guides;

type
  TAtlasEditorPairs = class
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;
    TLineTokens = TArray<TAtlasPairToken>;
    TGuidePart = (gpFirst, gpMiddle, gpLast);
    TLineGuide = record
      Column: Integer;
      Depth: Integer;
      Part: TGuidePart;
    end;
  private
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FFileName: string;
    FText: string;
    FCheck: Boolean;
    // Je 0-basierter Zeile die Paare, Character als 1-basierte Editorspalte (Tabs aufgelöst).
    FLines: TArray<TLineTokens>;
    // Je 0-basierter Zeile der Text wie im Editor (Tabs aufgelöst), zum Abgleich der Läufe.
    FDisplay: TArray<string>;
    // Je 0-basierter Zeile die Blocklinien, die sie kreuzen.
    FGuides: TArray<TArray<TLineGuide>>;
    FTabWidth: Integer;
    procedure BeginPaint(const Editor: TWinControl; const ForceFullRepaint: Boolean);
    procedure PaintText(const Rect: TRect; const ColNum: SmallInt; const Text: string;
      const SyntaxCode: TOTASyntaxCode; const Hilight, BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure Refresh(const Context: INTACodeEditorPaintContext);
  public
    constructor Create;
    destructor Destroy; override;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  System.Math,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Diagnostics.Hangs,
  Atlas.IDE.Editor.Buffer,
  Atlas.IDE.Editor.Style,
  Atlas.IDE.Settings.Store;

{ TAtlasEditorPairs.TEvents }

function TAtlasEditorPairs.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevBeginEndPaintEvents, cevPaintTextEvents, cevPaintLineEvents];
end;

function TAtlasEditorPairs.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasEditorPairs }

constructor TAtlasEditorPairs.Create;
var
  Services: INTACodeEditorServices;
begin
  inherited Create;
  FIndex := -1;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorBeginPaint := BeginPaint;
  FEvents.OnEditorPaintText := PaintText;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    FIndex := Services.AddEditorEventsNotifier(FEventsRef);
end;

destructor TAtlasEditorPairs.Destroy;
var
  Services: INTACodeEditorServices;
begin
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.RemoveEditorEventsNotifier(FIndex);
  FEvents.OnEditorBeginPaint := nil;
  FEvents.OnEditorPaintText := nil;
  FEvents.OnEditorPaintLine := nil;
  FEventsRef := nil;
  inherited Destroy;
end;

procedure TAtlasEditorPairs.BeginPaint(const Editor: TWinControl; const ForceFullRepaint: Boolean);
begin
  // Durch die Sicherung abgeschaltet (#493).
  if TAtlasGuard.Disabled(TAtlasFeature.Pairs) then
    Exit;
  try
    FCheck := True;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Pairs, E);
  end;
end;

/// <summary>Zeichenindex (0-basiert) in ALine als 1-basierte Editorspalte, Tabs aufgelöst.</summary>
function ColumnOf(const ALine: string; ACharacter, ATabWidth: Integer): Integer;
var
  Index: Integer;
begin
  Result := 1;
  for Index := 1 to ACharacter do
    if (Index <= Length(ALine)) and (ALine[Index] = #9) and (ATabWidth > 0) then
      Result := ((Result - 1) div ATabWidth + 1) * ATabWidth + 1
    else
      Inc(Result);
end;

procedure TAtlasEditorPairs.Refresh(const Context: INTACodeEditorPaintContext);
var
  View: IOTAEditView;
  Text: string;
  Lines: TArray<string>;
  Token: TAtlasPairToken;
  Blocks: TArray<TAtlasPairBlock>;
  Guide: TAtlasGuide;
  LineGuide: TLineGuide;
  TabWidth, Index, Line: Integer;
  Activity: IInterface;
begin
  FCheck := False;
  View := Context.EditView;
  if (View = nil) or (View.Buffer = nil) then
    Exit;
  Text := TAtlasEditorBuffer.Text(View.Buffer);
  if (Text = FText) and SameText(Context.FileName, FFileName) then
    Exit;
  Activity := TAtlasActivity.Scope('Klammerpaare');
  FFileName := Context.FileName;
  FText := Text;
  Lines := Text.Split([#10]);
  FLines := nil;
  SetLength(FLines, Length(Lines));
  SetLength(FDisplay, Length(Lines));
  FGuides := nil;
  SetLength(FGuides, Length(Lines));
  TabWidth := TAtlasEditorBuffer.TabWidth(View.Buffer);
  FTabWidth := TabWidth;
  for Index := 0 to High(Lines) do
    FDisplay[Index] := TAtlasPairs.DisplayLine(Lines[Index], TabWidth);
  for Token in TAtlasPairs.Analyze(Text, Blocks) do
    if Token.Line <= High(FLines) then
    begin
      // Spalte der IDE statt Zeichenindex.
      FLines[Token.Line] := FLines[Token.Line] + [Token];
      FLines[Token.Line][High(FLines[Token.Line])].Character := ColumnOf(Lines[Token.Line], Token.Character, TabWidth);
    end;
  for Guide in TAtlasGuides.FromBlocks(Lines, Blocks, TabWidth) do
    for Line := Guide.FirstLine to Guide.LastLine do
    begin
      LineGuide.Column := Guide.Column;
      LineGuide.Depth := Guide.Depth;
      if Line = Guide.FirstLine then
        LineGuide.Part := gpFirst
      else if Line = Guide.LastLine then
        LineGuide.Part := gpLast
      else
        LineGuide.Part := gpMiddle;
      FGuides[Line] := FGuides[Line] + [LineGuide];
    end;
end;

procedure TAtlasEditorPairs.PaintText(const Rect: TRect; const ColNum: SmallInt; const Text: string;
  const SyntaxCode: TOTASyntaxCode; const Hilight, BeforeEvent: Boolean; var AllowDefaultPainting: Boolean;
  const Context: INTACodeEditorPaintContext);
var
  Line, Index, Column, Cell, Top: Integer;
  Tokens: TLineTokens;
  Token: TAtlasPairToken;
  Colors: TAtlasColors;
  Canvas: TCanvas;
  Original: TColor;
  CharColors: TArray<TColor>;
  Found: Boolean;
  DC: HDC;
  Saved: Integer;
begin
  // Durch die Sicherung abgeschaltet (#493).
  if TAtlasGuard.Disabled(TAtlasFeature.Pairs) then
    Exit;
  if not BeforeEvent or Hilight or (Text = '') or (Context = nil) then
    Exit;
  try
    if not TAtlasIdeSettings.Current.PairColors then
      Exit;
    if FCheck or not SameText(Context.FileName, FFileName) then
      Refresh(Context);
    Line := Context.LogicalLineNum - 1;
    if (Line < 0) or (Line > High(FLines)) or (Length(FLines[Line]) = 0) then
      Exit;
    // Nur einfärben, wenn der Lauf in der analysierten Zeile an dieser Stelle steht.
    // Die IDE meldet beim Neuzeichnen von Teilbereichen nicht immer die Zeile des
    // Laufs; sonst landeten Paarfarben mitten in Bezeichnern anderer Zeilen.
    if (Line > High(FDisplay)) or not TAtlasPairs.RunMatches(FDisplay[Line], Text, ColNum) then
      Exit;
    Tokens := FLines[Line];
    Canvas := Context.Canvas;
    Original := Canvas.Font.Color;
    SetLength(CharColors, Length(Text));
    for Index := 0 to High(CharColors) do
      CharColors[Index] := Original;
    Colors := TAtlasIdeStyle.Colors;
    Found := False;
    for Token in Tokens do
      for Column := Token.Character to Token.Character + Token.Length - 1 do
        if (Column >= ColNum) and (Column < ColNum + Length(Text)) then
        begin
          Found := True;
          if Token.Unpaired then
            CharColors[Column - ColNum] := TColor(Colors.Error)
          else
            CharColors[Column - ColNum] := TColor(Colors.Pairs[Token.Depth mod Length(Colors.Pairs)]);
        end;
    if not Found then
      Exit;
    // Lauf selbst zeichnen: Hintergrund wie vorbereitet, Zeichen in fester Zellbreite.
    // Direkt im DC und mit gesichertem Zustand: Die IDE setzt die Textfarbe nur
    // beim Wechsel des Attributs; eine stehengebliebene Paarfarbe färbte sonst
    // Teile späterer Läufe ein (z. B. nach dem Neuzeichnen unter einem Tooltip).
    AllowDefaultPainting := False;
    Cell := Context.CellSize.cx;
    if Cell <= 0 then
      Cell := Canvas.TextWidth('W');
    Top := Rect.Top + (Rect.Height - Canvas.TextHeight('Wg')) div 2;
    Canvas.FillRect(Rect);
    DC := Canvas.Handle;
    Saved := SaveDC(DC);
    try
      SetBkMode(DC, TRANSPARENT);
      for Index := 0 to High(CharColors) do
      begin
        SetTextColor(DC, ColorToRGB(CharColors[Index]));
        Winapi.Windows.TextOut(DC, Rect.Left + Index * Cell, Top, PChar(Text) + Index, 1);
      end;
    finally
      RestoreDC(DC, Saved);
    end;
  except
    // Zeichnen darf die IDE nie stören; die IDE zeichnet dann selbst.
    on E: Exception do
    begin
      AllowDefaultPainting := True;
      TAtlasGuard.Report(TAtlasFeature.Pairs, E);
    end;
  end;
end;

procedure TAtlasEditorPairs.PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
  var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  Settings: TAtlasPluginSettings;
  LineState: INTACodeEditorLineState;
  Line, X, Top, Bottom, Tick: Integer;
  Guide: TLineGuide;
  Colors: TAtlasColors;
  Cell, Code: TRect;
  DC: HDC;
  Saved: Integer;
  Pen, Old: HGDIOBJ;
begin
  // Durch die Sicherung abgeschaltet (#493).
  if TAtlasGuard.Disabled(TAtlasFeature.Pairs) then
    Exit;
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) then
    Exit;
  try
    Settings := TAtlasIdeSettings.Current;
    if not (Settings.PairColors and Settings.PairGuides) then
      Exit;
    if FCheck or not SameText(Context.FileName, FFileName) then
      Refresh(Context);
    Line := Context.LogicalLineNum - 1;
    if (Line < 0) or (Line > High(FGuides)) or (Length(FGuides[Line]) = 0) then
      Exit;
    // Wie bei den Läufen: nur, wenn die Zeile zur Analyse passt.
    LineState := Context.LineState;
    if (LineState = nil) or
      (TrimRight(TAtlasPairs.DisplayLine(LineState.Text, FTabWidth)) <> TrimRight(FDisplay[Line])) then
      Exit;
    Colors := TAtlasIdeStyle.Colors;
    Code := LineState.CodeRect;
    DC := Context.Canvas.Handle;
    Saved := SaveDC(DC);
    try
      // Nicht in den Rand zeichnen.
      if Code.Right > Code.Left then
        IntersectClipRect(DC, Code.Left, Rect.Top, Rect.Right, Rect.Bottom);
      for Guide in FGuides[Line] do
      begin
        Cell := Context.EditorState.GetCharacterPosPx(Guide.Column, Context.EditorLineNum);
        Tick := Max(3, Cell.Width div 2);
        X := Cell.Left - Max(2, Cell.Width div 3);
        Top := Rect.Top;
        Bottom := Rect.Bottom;
        if Guide.Part = gpFirst then
          Top := Rect.Top + 2;
        if Guide.Part = gpLast then
          Bottom := Rect.Bottom - 3;
        Pen := CreatePen(PS_SOLID, 1, ColorToRGB(TColor(Colors.Pairs[Guide.Depth mod Length(Colors.Pairs)])));
        Old := SelectObject(DC, Pen);
        try
          MoveToEx(DC, X, Top, nil);
          LineTo(DC, X, Bottom + 1);
          if Guide.Part = gpFirst then
          begin
            MoveToEx(DC, X, Top, nil);
            LineTo(DC, X + Tick, Top);
          end;
          if Guide.Part = gpLast then
          begin
            MoveToEx(DC, X, Bottom, nil);
            LineTo(DC, X + Tick, Bottom);
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
    begin
      FGuides := nil;
      TAtlasGuard.Report(TAtlasFeature.Pairs, E);
    end;
  end;
end;

end.
