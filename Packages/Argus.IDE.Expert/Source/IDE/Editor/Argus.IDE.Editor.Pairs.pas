unit Argus.IDE.Editor.Pairs;

// Klammer- und Blockpaare farbig (#514). Die Analyse (TArgusPairs) läuft je
// Datei einmal, wenn sich der Puffer geändert hat; geprüft wird zu Beginn
// jedes Zeichnens. Gezeichnet wird über OnEditorPaintText: Enthält ein
// Textlauf eine Klammer oder ein Blockwort, zeichnet Argus den Lauf selbst
// (Pinsel und Schrift hat die IDE vorbereitet), die Paare in der Farbe ihrer
// Tiefe, unpaarige in der Fehlerfarbe. Markierter Text bleibt der IDE.
// Strings und Kommentare zählen nicht (eigener Lexer). Abschaltbar.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  ToolsAPI,
  ToolsAPI.Editor,
  Argus.Core.Editor.Pairs;

type
  TArgusEditorPairs = class
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
    end;
    TLineTokens = TArray<TArgusPairToken>;
  private
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FFileName: string;
    FText: string;
    FCheck: Boolean;
    // Je 0-basierter Zeile die Paare, Character als 1-basierte Editorspalte (Tabs aufgelöst).
    FLines: TArray<TLineTokens>;
    procedure BeginPaint(const Editor: TWinControl; const ForceFullRepaint: Boolean);
    procedure PaintText(const Rect: TRect; const ColNum: SmallInt; const Text: string;
      const SyntaxCode: TOTASyntaxCode; const Hilight, BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure Refresh(const Context: INTACodeEditorPaintContext);
  public
    constructor Create;
    destructor Destroy; override;
  end;

implementation

uses
  Argus.Core.Style.Color,
  Argus.Core.Style.Palette,
  Argus.Core.Diagnostics.Hangs,
  Argus.IDE.Editor.Buffer,
  Argus.IDE.Editor.Style,
  Argus.IDE.Settings.Store;

{ TArgusEditorPairs.TEvents }

function TArgusEditorPairs.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevBeginEndPaintEvents, cevPaintTextEvents];
end;

{ TArgusEditorPairs }

constructor TArgusEditorPairs.Create;
var
  Services: INTACodeEditorServices;
begin
  inherited Create;
  FIndex := -1;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorBeginPaint := BeginPaint;
  FEvents.OnEditorPaintText := PaintText;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    FIndex := Services.AddEditorEventsNotifier(FEventsRef);
end;

destructor TArgusEditorPairs.Destroy;
var
  Services: INTACodeEditorServices;
begin
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.RemoveEditorEventsNotifier(FIndex);
  FEvents.OnEditorBeginPaint := nil;
  FEvents.OnEditorPaintText := nil;
  FEventsRef := nil;
  inherited Destroy;
end;

procedure TArgusEditorPairs.BeginPaint(const Editor: TWinControl; const ForceFullRepaint: Boolean);
begin
  FCheck := True;
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

procedure TArgusEditorPairs.Refresh(const Context: INTACodeEditorPaintContext);
var
  View: IOTAEditView;
  Text: string;
  Lines: TArray<string>;
  Token: TArgusPairToken;
  TabWidth: Integer;
  Activity: IInterface;
begin
  FCheck := False;
  View := Context.EditView;
  if (View = nil) or (View.Buffer = nil) then
    Exit;
  Text := TArgusEditorBuffer.Text(View.Buffer);
  if (Text = FText) and SameText(Context.FileName, FFileName) then
    Exit;
  Activity := TArgusActivity.Scope('Klammerpaare');
  FFileName := Context.FileName;
  FText := Text;
  Lines := Text.Split([#10]);
  SetLength(FLines, Length(Lines));
  TabWidth := TArgusEditorBuffer.TabWidth(View.Buffer);
  for Token in TArgusPairs.Analyze(Text) do
    if Token.Line <= High(FLines) then
    begin
      // Spalte der IDE statt Zeichenindex.
      FLines[Token.Line] := FLines[Token.Line] + [Token];
      FLines[Token.Line][High(FLines[Token.Line])].Character := ColumnOf(Lines[Token.Line], Token.Character, TabWidth);
    end;
end;

procedure TArgusEditorPairs.PaintText(const Rect: TRect; const ColNum: SmallInt; const Text: string;
  const SyntaxCode: TOTASyntaxCode; const Hilight, BeforeEvent: Boolean; var AllowDefaultPainting: Boolean;
  const Context: INTACodeEditorPaintContext);
var
  Line, Index, Column, Cell, Top: Integer;
  Tokens: TLineTokens;
  Token: TArgusPairToken;
  Colors: TArgusColors;
  Canvas: TCanvas;
  Original: TColor;
  CharColors: TArray<TColor>;
  Found: Boolean;
begin
  if not BeforeEvent or Hilight or (Text = '') or (Context = nil) then
    Exit;
  try
    if not TArgusIdeSettings.Current.PairColors then
      Exit;
    if FCheck or not SameText(Context.FileName, FFileName) then
      Refresh(Context);
    Line := Context.LogicalLineNum - 1;
    if (Line < 0) or (Line > High(FLines)) or (Length(FLines[Line]) = 0) then
      Exit;
    Tokens := FLines[Line];
    Canvas := Context.Canvas;
    Original := Canvas.Font.Color;
    SetLength(CharColors, Length(Text));
    for Index := 0 to High(CharColors) do
      CharColors[Index] := Original;
    Colors := TArgusIdeStyle.Colors;
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
    AllowDefaultPainting := False;
    Cell := Context.CellSize.cx;
    if Cell <= 0 then
      Cell := Canvas.TextWidth('W');
    Top := Rect.Top + (Rect.Height - Canvas.TextHeight('Wg')) div 2;
    Canvas.FillRect(Rect);
    Canvas.Brush.Style := bsClear;
    for Index := 0 to High(CharColors) do
    begin
      Canvas.Font.Color := CharColors[Index];
      Canvas.TextOut(Rect.Left + Index * Cell, Top, Text[Index + 1]);
    end;
    Canvas.Font.Color := Original;
    Canvas.Brush.Style := bsSolid;
  except
    // Zeichnen darf die IDE nie stören; die IDE zeichnet dann selbst.
    AllowDefaultPainting := True;
  end;
end;

end.