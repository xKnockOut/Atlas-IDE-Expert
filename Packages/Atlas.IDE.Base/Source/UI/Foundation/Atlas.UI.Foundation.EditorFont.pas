unit Atlas.UI.Foundation.EditorFont;

// Fassung der Editorschrift mit fester Schriftart-Auszeichnung für Texte, die
// Atlas in den Editor zeichnet (Befunde und Werte am Zeilenende, Änderungsmarken,
// Ausstiegspunkte, Auswahltreffer). Follow baut sie nur neu auf, wenn sich Name,
// Größe oder DPI der Editorschrift ändern; die Zeichenroutinen rufen es bei
// jedem Zeichnen. Nur im Hauptthread.

interface

uses
  Vcl.Graphics;

type
  TAtlasEditorFont = class
  private
    FFont: TFont;
    FStyle: TFontStyles;
    FKey: string;
  public
    /// <summary>AStyle ersetzt die Auszeichnung der Editorschrift ([fsItalic] oder [] für schlicht).</summary>
    constructor Create(AStyle: TFontStyles);
    destructor Destroy; override;
    /// <summary>Font der Editorschrift AEditorFont anpassen, mit der Auszeichnung aus Create.</summary>
    procedure Follow(const AEditorFont: TFont);
    /// <summary>Schrift nach dem letzten Follow.</summary>
    property Font: TFont read FFont;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasEditorFont }

constructor TAtlasEditorFont.Create(AStyle: TFontStyles);
begin
  inherited Create;
  FFont := TFont.Create;
  FStyle := AStyle;
end;

destructor TAtlasEditorFont.Destroy;
begin
  FFont.Free;
  inherited Destroy;
end;

procedure TAtlasEditorFont.Follow(const AEditorFont: TFont);
var
  mKey: string;
begin
  mKey := AEditorFont.Name + '|' + IntToStr(AEditorFont.Size) + '|' + IntToStr(AEditorFont.PixelsPerInch);
  if mKey = FKey then
  begin
    Exit;
  end;
  FFont.Assign(AEditorFont);
  FFont.Style := FStyle;
  FKey := mKey;
end;

end.
