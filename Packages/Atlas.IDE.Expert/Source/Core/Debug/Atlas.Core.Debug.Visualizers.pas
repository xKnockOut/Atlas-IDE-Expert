unit Atlas.Core.Debug.Visualizers;

// Visualisierer für häufige Typen beim Debuggen (#835), Teil ohne VCL und
// Open Tools API:
// - Typen: Je Art (Listen, Dictionaries, Datenmengen, Bytes und Streams, JSON,
//   Farben, TGUID, Geometrie, Grafiken) die Typnamen, für die sich Atlas beim
//   Debugger der IDE anmeldet (mit und ohne Unit, generisch wie im Beispiel
//   von Embarcadero „System.Generics.Collections.TList<T>“), und die Zuordnung
//   eines Typnamens bzw. einer Vererbungskette zur Art (Atlas-Tooltip).
//   TDateTime, TStrings und std::string bleiben bei den Visualisierern der IDE.
// - Ersatztext: einzeilig, auf debug.visualizers.maxLength gekürzt, aus dem
//   Ergebnis der IDE und weiteren Auswertungen über den Rückruf Eval, z. B.
//   „TObjectList<TKunde> · Count = 3 · [Meier, Schulz, Öztürk]“. Jede
//   Auswertung nennt, was sie braucht: nur Felder, Getter von Eigenschaften
//   oder Funktionsaufrufe (ToString, ToJSON); mehr als
//   debug.visualizers.evaluation erlaubt, versucht Atlas nicht. Für jeden Wert
//   gibt es mehrere Ausdrücke (Eigenschaft, dann das Feld dahinter), der erste,
//   der gelingt, gilt. Gelingt nichts, bleibt der Text der IDE ('').
// - Ansicht für das Fenster: Tabelle (Liste, Dictionary, Datensatz mit altem
//   Wert), Hex-Zeilen mit Adresse und Text, JSON als Baum, Bild (24/32 Bit
//   aus dem DIB einer TBitmap), Farbfeld, Text.
// - Speicher liest der Rückruf Read (Bytes, Streams, Bilddaten).

interface

uses
  System.SysUtils,
  Atlas.Core.Settings.VisualizerKinds;

type
  {$SCOPEDENUMS ON}
  TAtlasVisualizerViewMode = (None, Table, Hex, Tree, Image, Color, Text);
  /// <summary>Spalten der Tabellenansicht; die Oberfläche setzt die Überschriften.</summary>
  TAtlasVisualizerColumn = (Index, Value, Key, Field, FieldType, OldValue);
  {$SCOPEDENUMS OFF}

  /// <summary>Anmeldung beim Debugger: Typname, mit Nachfahren, generisch.</summary>
  TAtlasVisualizerType = record
    TypeName: string;
    AllDescendants: Boolean;
    IsGeneric: Boolean;
  end;

  /// <summary>Wertet AExpression im angehaltenen Programm aus; AEvaluation sagt, was der Ausdruck braucht. False
  /// bei Fehler oder Zeitüberschreitung.</summary>
  TAtlasVisualizerEval = reference to function(const AExpression: string; AEvaluation: TAtlasVisualizerEvaluation;
    out AText: string): Boolean;
  /// <summary>Liest ACount Bytes ab AAddress aus dem Programm; False, wenn es nicht geht.</summary>
  TAtlasVisualizerRead = reference to function(AAddress: UInt64; ACount: Integer; out ABytes: TBytes): Boolean;

  TAtlasVisualizerContext = record
    Eval: TAtlasVisualizerEval;
    Read: TAtlasVisualizerRead;
  end;

  TAtlasVisualizerOptions = record
  public const
    /// <summary>Elemente im Ersatztext.</summary>
    PreviewItems = 5;
    /// <summary>Zeilen der Tabellenansicht.</summary>
    ViewItems = 1000;
    /// <summary>Bytes in der Hex-Ansicht.</summary>
    ViewBytes = 16 * 1024 * 1024;
    /// <summary>Bytes im Ersatztext.</summary>
    PreviewBytes = 16;
  public
    Kinds: TAtlasVisualizerKinds;
    NameFields: TArray<string>;
    MaxLength: Integer;
    Evaluation: TAtlasVisualizerEvaluation;
    MaxImagePixels: Integer;
    class function Defaults: TAtlasVisualizerOptions; static;
  end;

  /// <summary>Feld eines Records im Text des Debuggers, z. B. X:10 aus (X:10; Y:20); Name '' bei Array-Elementen.
  /// </summary>
  TAtlasDebugField = record
    Name: string;
    Value: string;
  end;

  TAtlasVisualizerNode = record
    Level: Integer;
    Text: string;
  end;

  TAtlasVisualizerView = record
    Mode: TAtlasVisualizerViewMode;
    Kind: TAtlasVisualizerKind;
    Summary: string;
    Columns: TArray<TAtlasVisualizerColumn>;
    Rows: TArray<TArray<string>>;
    /// <summary>Tabelle: alle Felder, wenn Rows nur eine Auswahl zeigt (atlas-debug-children, #854); sonst nil.
    /// </summary>
    AllRows: TArray<TArray<string>>;
    /// <summary>Hex: gelesene Bytes; Total ist die ganze Länge (mehr als Bytes, wenn gekürzt).</summary>
    Bytes: TBytes;
    Total: Int64;
    Nodes: TArray<TAtlasVisualizerNode>;
    Width: Integer;
    Height: Integer;
    /// <summary>Bild von oben nach unten, je Pixel $AARRGGBB.</summary>
    Pixels: TArray<Cardinal>;
    /// <summary>Farbe als $RRGGBB.</summary>
    Color: Cardinal;
    Text: string;
    /// <summary>Etwas fehlt, weil debug.visualizers.evaluation es nicht erlaubt.</summary>
    NeedsMore: Boolean;
  end;

  TAtlasVisualizers = class
  public
    /// <summary>Typnamen, für die sich der Visualisierer der Art beim Debugger anmeldet.</summary>
    class function SupportedTypes(AKind: TAtlasVisualizerKind): TArray<TAtlasVisualizerType>; static;
    /// <summary>Name ohne Units in allen Teilen: „System.Generics.Collections.TList&lt;Unit1.TKunde&gt;“ →
    /// „TList&lt;TKunde&gt;“.</summary>
    class function ShortTypeName(const ATypeName: string): string; static;
    /// <summary>Grundname ohne Unit und ohne Typargumente: „TList“.</summary>
    class function BaseTypeName(const ATypeName: string): string; static;
    /// <summary>Art zu einem Typnamen; Nachfahren (TFDQuery) erkennt erst KindOfChain.</summary>
    class function KindOf(const ATypeName: string; out AKind: TAtlasVisualizerKind): Boolean; static;
    /// <summary>Art des ersten Glieds einer Vererbungskette (Typ zuerst), das eine hat.</summary>
    class function KindOfChain(const ATypeNames: array of string; out AKind: TAtlasVisualizerKind): Boolean; static;
    /// <summary>Typ aus der Deklaration im Hover: „var Kunden: TObjectList&lt;TKunde&gt;“ → „TObjectList&lt;TKunde&gt;“,
    /// „property Items: TList&lt;Integer&gt; read FItems“ → „TList&lt;Integer&gt;“, „function F(A: Integer): TPoint“ → „TPoint“;
    /// '' ohne Typ.</summary>
    class function DeclaredType(const ADeclaration: string): string; static;
    /// <summary>Ersatztext für den Wert AExpression vom Typ ATypeName; AEvalResult ist der Text der IDE. '' = den
    /// Text der IDE lassen.</summary>
    class function Replacement(AKind: TAtlasVisualizerKind; const AExpression, ATypeName, AEvalResult: string;
      const AOptions: TAtlasVisualizerOptions; const AContext: TAtlasVisualizerContext): string; static;
    /// <summary>Inhalt des Ansichtsfensters.</summary>
    class function View(AKind: TAtlasVisualizerKind; const AExpression, ATypeName, AEvalResult: string;
      const AOptions: TAtlasVisualizerOptions; const AContext: TAtlasVisualizerContext): TAtlasVisualizerView; static;
  end;

  /// <summary>Formatierung ohne Debugger, einzeln getestet.</summary>
  TAtlasVisualizerFormat = class
  public
    /// <summary>Höchstens AMaxLength Zeichen, gekürzt mit „…“.</summary>
    class function Shorten(const AText: string; AMaxLength: Integer): string; static;
    /// <summary>Felder bzw. Elemente der obersten Ebene von (A:1; B:(2, 3)) bzw. (1, 2, 3); False ohne Klammern.
    /// </summary>
    class function ParseFields(const AText: string; out AFields: TArray<TAtlasDebugField>): Boolean; static;
    /// <summary>Wert des Felds AName (ohne Groß-/Kleinschreibung); False ohne.</summary>
    class function FieldValue(const AFields: TArray<TAtlasDebugField>; const AName: string;
      out AValue: string): Boolean; static;
    /// <summary>Ganze Zahl aus dem Text des Debuggers (dezimal, $hex, auch mit Typumwandlung „Pointer($1F)“).
    /// </summary>
    class function ParseInteger(const AText: string; out AValue: Int64): Boolean; static;
    /// <summary>Adresse aus „$0A3F1C20“, „Pointer($…)“ oder „:0A3F1C20“; False bei nil.</summary>
    class function ParseAddress(const AText: string; out AAddress: UInt64): Boolean; static;
    /// <summary>Bytes aus der Array-Anzeige „(72, 101, $6C)“; False, wenn es keine ist.</summary>
    class function ParseByteList(const AText: string; out ABytes: TBytes): Boolean; static;
    /// <summary>Zeichenkette des Debuggers ohne Anführungszeichen ('It''s' → It's, #13 bleibt); sonst der Text.
    /// </summary>
    class function Unquote(const AText: string): string; static;
    /// <summary>Wert eines Objekts statt eines einfachen Werts (Klammern, Adresse)?</summary>
    class function IsStructured(const AText: string): Boolean; static;
    /// <summary>„n Bytes · 48 65 6C 6C 6F · Hello“ mit höchstens AMaxBytes Bytes; nicht druckbare Zeichen als „.“.
    /// </summary>
    class function HexPreview(const ABytes: TBytes; ATotal: Int64; AMaxBytes: Integer): string; static;
    /// <summary>Zeile der Hex-Ansicht ab AOffset: „00000010  48 65 … 6F  Hello“ (16 Bytes je Zeile).</summary>
    class function HexLine(const ABytes: TBytes; AOffset: Integer): string; static;
    class function HexLineCount(ALength: Integer): Integer; static;
    /// <summary>JSON-Text kompakt (ohne Leerraum außerhalb von Zeichenketten).</summary>
    class function CompactJson(const AText: string): string; static;
    /// <summary>JSON als Baum (Schlüssel: Wert, Objekte {n}, Arrays [n]); False bei ungültigem JSON.</summary>
    class function JsonTree(const AText: string; out ANodes: TArray<TAtlasVisualizerNode>): Boolean; static;
    /// <summary>TColor-Wert ($00BBGGRR bzw. Systemfarbe $FF0000xx) als Name (clRed, clWebDodgerBlue, clBtnFace,
    /// clNone, clDefault); '' ohne Namen.</summary>
    class function ColorName(AValue: Int64): string; static;
    /// <summary>TColor als $RRGGBB; Systemfarben und clNone haben keinen.</summary>
    class function ColorRgb(AValue: Int64; out ARgb: Cardinal): Boolean; static;
    /// <summary>„clWebDodgerBlue · $1E90FF“, „$123456“, „clBtnFace“.</summary>
    class function ColorText(AValue: Int64): string; static;
    /// <summary>TAlphaColor ($AARRGGBB) als „claDodgerBlue“ bzw. „$801E90FF“.</summary>
    class function AlphaColorText(AValue: Int64): string; static;
    /// <summary>TGUID aus (D1:…; D2:…; D3:…; D4:(…)) als {XXXXXXXX-XXXX-…}; '' wenn es keiner ist.</summary>
    class function GuidText(const AEvalResult: string): string; static;
    /// <summary>TPoint, TRect, TSize (auch …F) kurz: „(10, 20)“, „(10, 20)–(110, 70)“, „100 × 50“; ''
    /// sonst.</summary>
    class function GeometryText(const ABaseType, AEvalResult: string): string; static;
    /// <summary>Pixel eines DIB (24 oder 32 Bit, Zeilen auf AWidthBytes ausgerichtet) von oben nach unten.</summary>
    class function DibPixels(const ABits: TBytes; AWidth, AHeight, ABitsPerPixel, AWidthBytes: Integer;
      ABottomUp: Boolean; out APixels: TArray<Cardinal>): Boolean; static;
    /// <summary>„Klasse · Count = n · [a, b, c, …]“.</summary>
    class function ListText(const AShown: string; ACount: Integer; const AItems: TArray<string>): string; static;
    /// <summary>„Klasse · Count = n · {k: v, …}“.</summary>
    class function DictionaryText(const AShown: string; ACount: Integer;
      const APairs: TArray<string>): string; static;
  end;

implementation

uses
  System.StrUtils,
  System.Math,
  System.JSON,
  System.Generics.Collections;

type
  TNamedValue = record
    Name: string;
    Value: Cardinal;
  end;

const
  // Feste Farben der VCL (RGB).
  StandardColors: array[0..19] of TNamedValue = (
    (Name: 'clBlack'; Value: $000000), (Name: 'clMaroon'; Value: $800000), (Name: 'clGreen'; Value: $008000),
    (Name: 'clOlive'; Value: $808000), (Name: 'clNavy'; Value: $000080), (Name: 'clPurple'; Value: $800080),
    (Name: 'clTeal'; Value: $008080), (Name: 'clGray'; Value: $808080), (Name: 'clSilver'; Value: $C0C0C0),
    (Name: 'clRed'; Value: $FF0000), (Name: 'clLime'; Value: $00FF00), (Name: 'clYellow'; Value: $FFFF00),
    (Name: 'clBlue'; Value: $0000FF), (Name: 'clFuchsia'; Value: $FF00FF), (Name: 'clAqua'; Value: $00FFFF),
    (Name: 'clWhite'; Value: $FFFFFF), (Name: 'clMoneyGreen'; Value: $C0DCC0), (Name: 'clSkyBlue'; Value: $A6CAF0),
    (Name: 'clCream'; Value: $FFFBF0), (Name: 'clMedGray'; Value: $A0A0A4));
  // Systemfarben: clXxx = $FF000000 or Index (COLOR_*).
  SystemColors: array[0..30] of string = ('clScrollBar', 'clBackground', 'clActiveCaption', 'clInactiveCaption',
    'clMenu', 'clWindow', 'clWindowFrame', 'clMenuText', 'clWindowText', 'clCaptionText', 'clActiveBorder',
    'clInactiveBorder', 'clAppWorkSpace', 'clHighlight', 'clHighlightText', 'clBtnFace', 'clBtnShadow',
    'clGrayText', 'clBtnText', 'clInactiveCaptionText', 'clBtnHighlight', 'cl3DDkShadow', 'cl3DLight',
    'clInfoText', 'clInfoBk', '', 'clHotLight', 'clGradientActiveCaption', 'clGradientInactiveCaption',
    'clMenuHighlight', 'clMenuBar');
  // CSS-Farben (RGB), ohne „Grey“-Schreibweisen: clWebXxx bzw. claXxx.
  WebColors: array[0..139] of TNamedValue = (
    (Name: 'AliceBlue'; Value: $F0F8FF), (Name: 'AntiqueWhite'; Value: $FAEBD7), (Name: 'Aqua'; Value: $00FFFF),
    (Name: 'Aquamarine'; Value: $7FFFD4), (Name: 'Azure'; Value: $F0FFFF), (Name: 'Beige'; Value: $F5F5DC),
    (Name: 'Bisque'; Value: $FFE4C4), (Name: 'Black'; Value: $000000), (Name: 'BlanchedAlmond'; Value: $FFEBCD),
    (Name: 'Blue'; Value: $0000FF), (Name: 'BlueViolet'; Value: $8A2BE2), (Name: 'Brown'; Value: $A52A2A),
    (Name: 'BurlyWood'; Value: $DEB887), (Name: 'CadetBlue'; Value: $5F9EA0), (Name: 'Chartreuse'; Value: $7FFF00),
    (Name: 'Chocolate'; Value: $D2691E), (Name: 'Coral'; Value: $FF7F50), (Name: 'CornflowerBlue'; Value: $6495ED),
    (Name: 'CornSilk'; Value: $FFF8DC), (Name: 'Crimson'; Value: $DC143C), (Name: 'Cyan'; Value: $00FFFF),
    (Name: 'DarkBlue'; Value: $00008B), (Name: 'DarkCyan'; Value: $008B8B),
    (Name: 'DarkGoldenRod'; Value: $B8860B), (Name: 'DarkGray'; Value: $A9A9A9),
    (Name: 'DarkGreen'; Value: $006400), (Name: 'DarkKhaki'; Value: $BDB76B),
    (Name: 'DarkMagenta'; Value: $8B008B), (Name: 'DarkOliveGreen'; Value: $556B2F),
    (Name: 'DarkOrange'; Value: $FF8C00), (Name: 'DarkOrchid'; Value: $9932CC), (Name: 'DarkRed'; Value: $8B0000),
    (Name: 'DarkSalmon'; Value: $E9967A), (Name: 'DarkSeaGreen'; Value: $8FBC8F),
    (Name: 'DarkSlateBlue'; Value: $483D8B), (Name: 'DarkSlateGray'; Value: $2F4F4F),
    (Name: 'DarkTurquoise'; Value: $00CED1), (Name: 'DarkViolet'; Value: $9400D3),
    (Name: 'DeepPink'; Value: $FF1493), (Name: 'DeepSkyBlue'; Value: $00BFFF), (Name: 'DimGray'; Value: $696969),
    (Name: 'DodgerBlue'; Value: $1E90FF), (Name: 'FireBrick'; Value: $B22222),
    (Name: 'FloralWhite'; Value: $FFFAF0), (Name: 'ForestGreen'; Value: $228B22),
    (Name: 'Fuchsia'; Value: $FF00FF), (Name: 'Gainsboro'; Value: $DCDCDC), (Name: 'GhostWhite'; Value: $F8F8FF),
    (Name: 'Gold'; Value: $FFD700), (Name: 'GoldenRod'; Value: $DAA520), (Name: 'Gray'; Value: $808080),
    (Name: 'Green'; Value: $008000), (Name: 'GreenYellow'; Value: $ADFF2F), (Name: 'HoneyDew'; Value: $F0FFF0),
    (Name: 'HotPink'; Value: $FF69B4), (Name: 'IndianRed'; Value: $CD5C5C), (Name: 'Indigo'; Value: $4B0082),
    (Name: 'Ivory'; Value: $FFFFF0), (Name: 'Khaki'; Value: $F0E68C), (Name: 'Lavender'; Value: $E6E6FA),
    (Name: 'LavenderBlush'; Value: $FFF0F5), (Name: 'LawnGreen'; Value: $7CFC00),
    (Name: 'LemonChiffon'; Value: $FFFACD), (Name: 'LightBlue'; Value: $ADD8E6),
    (Name: 'LightCoral'; Value: $F08080), (Name: 'LightCyan'; Value: $E0FFFF),
    (Name: 'LightGoldenRodYellow'; Value: $FAFAD2), (Name: 'LightGray'; Value: $D3D3D3),
    (Name: 'LightGreen'; Value: $90EE90), (Name: 'LightPink'; Value: $FFB6C1),
    (Name: 'LightSalmon'; Value: $FFA07A), (Name: 'LightSeaGreen'; Value: $20B2AA),
    (Name: 'LightSkyBlue'; Value: $87CEFA), (Name: 'LightSlateGray'; Value: $778899),
    (Name: 'LightSteelBlue'; Value: $B0C4DE), (Name: 'LightYellow'; Value: $FFFFE0),
    (Name: 'Lime'; Value: $00FF00), (Name: 'LimeGreen'; Value: $32CD32), (Name: 'Linen'; Value: $FAF0E6),
    (Name: 'Magenta'; Value: $FF00FF), (Name: 'Maroon'; Value: $800000),
    (Name: 'MediumAquamarine'; Value: $66CDAA), (Name: 'MediumBlue'; Value: $0000CD),
    (Name: 'MediumOrchid'; Value: $BA55D3), (Name: 'MediumPurple'; Value: $9370DB),
    (Name: 'MediumSeaGreen'; Value: $3CB371), (Name: 'MediumSlateBlue'; Value: $7B68EE),
    (Name: 'MediumSpringGreen'; Value: $00FA9A), (Name: 'MediumTurquoise'; Value: $48D1CC),
    (Name: 'MediumVioletRed'; Value: $C71585), (Name: 'MidnightBlue'; Value: $191970),
    (Name: 'MintCream'; Value: $F5FFFA), (Name: 'MistyRose'; Value: $FFE4E1), (Name: 'Moccasin'; Value: $FFE4B5),
    (Name: 'NavajoWhite'; Value: $FFDEAD), (Name: 'Navy'; Value: $000080), (Name: 'OldLace'; Value: $FDF5E6),
    (Name: 'Olive'; Value: $808000), (Name: 'OliveDrab'; Value: $6B8E23), (Name: 'Orange'; Value: $FFA500),
    (Name: 'OrangeRed'; Value: $FF4500), (Name: 'Orchid'; Value: $DA70D6), (Name: 'PaleGoldenRod'; Value: $EEE8AA),
    (Name: 'PaleGreen'; Value: $98FB98), (Name: 'PaleTurquoise'; Value: $AFEEEE),
    (Name: 'PaleVioletRed'; Value: $DB7093), (Name: 'PapayaWhip'; Value: $FFEFD5),
    (Name: 'PeachPuff'; Value: $FFDAB9), (Name: 'Peru'; Value: $CD853F), (Name: 'Pink'; Value: $FFC0CB),
    (Name: 'Plum'; Value: $DDA0DD), (Name: 'PowderBlue'; Value: $B0E0E6), (Name: 'Purple'; Value: $800080),
    (Name: 'Red'; Value: $FF0000), (Name: 'RosyBrown'; Value: $BC8F8F), (Name: 'RoyalBlue'; Value: $4169E1),
    (Name: 'SaddleBrown'; Value: $8B4513), (Name: 'Salmon'; Value: $FA8072), (Name: 'SandyBrown'; Value: $F4A460),
    (Name: 'SeaGreen'; Value: $2E8B57), (Name: 'SeaShell'; Value: $FFF5EE), (Name: 'Sienna'; Value: $A0522D),
    (Name: 'Silver'; Value: $C0C0C0), (Name: 'SkyBlue'; Value: $87CEEB), (Name: 'SlateBlue'; Value: $6A5ACD),
    (Name: 'SlateGray'; Value: $708090), (Name: 'Snow'; Value: $FFFAFA), (Name: 'SpringGreen'; Value: $00FF7F),
    (Name: 'SteelBlue'; Value: $4682B4), (Name: 'Tan'; Value: $D2B48C), (Name: 'Teal'; Value: $008080),
    (Name: 'Thistle'; Value: $D8BFD8), (Name: 'Tomato'; Value: $FF6347), (Name: 'Turquoise'; Value: $40E0D0),
    (Name: 'Violet'; Value: $EE82EE), (Name: 'Wheat'; Value: $F5DEB3), (Name: 'White'; Value: $FFFFFF),
    (Name: 'WhiteSmoke'; Value: $F5F5F5), (Name: 'Yellow'; Value: $FFFF00), (Name: 'YellowGreen'; Value: $9ACD32));
  ClNone = $1FFFFFFF;
  ClDefault = $20000000;
  SystemColorBase = Int64($FF000000);
  Separator = ' · ';
  // Leerer Platz eines Dictionaries (EMPTY_HASH in System.Generics.Collections).
  EmptyHash = -1;
  // Höchstens so viele Plätze eines Dictionaries durchsuchen, bis die ersten Paare gefunden sind.
  MaxDictionarySlots = 256;

type
  /// <summary>Ein Wert, für den es mehrere Ausdrücke gibt; %0:s ist der Ausdruck, %1:d der Index.</summary>
  TProbe = record
    Pattern: string;
    Evaluation: TAtlasVisualizerEvaluation;
  end;

function Probe(const APattern: string; AEvaluation: TAtlasVisualizerEvaluation): TProbe;
begin
  Result.Pattern := APattern;
  Result.Evaluation := AEvaluation;
end;

function Supported(const ATypeName: string; AAllDescendants, AIsGeneric: Boolean): TAtlasVisualizerType;
begin
  Result.TypeName := ATypeName;
  Result.AllDescendants := AAllDescendants;
  Result.IsGeneric := AIsGeneric;
end;

type
  /// <summary>Auswertungen für einen Ersatztext bzw. eine Ansicht.</summary>
  TEvaluator = record
    Options: TAtlasVisualizerOptions;
    Context: TAtlasVisualizerContext;
    Expression: string;
    /// <summary>Ein Ausdruck brauchte mehr, als erlaubt ist.</summary>
    Skipped: Boolean;
    /// <summary>Ausdruck, der zuletzt gelang.</summary>
    LastExpression: string;
    /// <summary>Erster Ausdruck aus AProbes, der gelingt; AIndex für %1:d.</summary>
    function First(const AProbes: array of TProbe; AIndex: Integer; out AText: string): Boolean;
    /// <summary>Wie First, mit AInner statt des Ausdrucks für %0:s.</summary>
    function FirstOf(const AInner: string; const AProbes: array of TProbe; AIndex: Integer;
      out AText: string): Boolean;
    function Int(const AProbes: array of TProbe; out AValue: Int64): Boolean;
    function Read(AAddress: UInt64; ACount: Integer; out ABytes: TBytes): Boolean;
  end;

function TEvaluator.FirstOf(const AInner: string; const AProbes: array of TProbe; AIndex: Integer;
  out AText: string): Boolean;
var
  Item: TProbe;
  Used: string;
begin
  AText := '';
  Result := False;
  if not Assigned(Context.Eval) then
    Exit;
  for Item in AProbes do
  begin
    if Item.Evaluation > Options.Evaluation then
    begin
      Skipped := True;
      Continue;
    end;
    Used := Format(Item.Pattern, [AInner, AIndex]);
    if Context.Eval(Used, Item.Evaluation, AText) then
    begin
      LastExpression := Used;
      Exit(True);
    end;
  end;
  AText := '';
end;

function TEvaluator.First(const AProbes: array of TProbe; AIndex: Integer; out AText: string): Boolean;
begin
  Result := FirstOf(Expression, AProbes, AIndex, AText);
end;

function TEvaluator.Int(const AProbes: array of TProbe; out AValue: Int64): Boolean;
var
  Text: string;
begin
  AValue := 0;
  Result := First(AProbes, 0, Text) and TAtlasVisualizerFormat.ParseInteger(Text, AValue);
end;

function TEvaluator.Read(AAddress: UInt64; ACount: Integer; out ABytes: TBytes): Boolean;
begin
  ABytes := nil;
  Result := (ACount > 0) and (AAddress <> 0) and Assigned(Context.Read) and Context.Read(AAddress, ACount, ABytes);
end;

function NewEvaluator(const AExpression: string; const AOptions: TAtlasVisualizerOptions;
  const AContext: TAtlasVisualizerContext): TEvaluator;
begin
  Result := Default(TEvaluator);
  Result.Options := AOptions;
  Result.Context := AContext;
  // Ausdruck geklammert, damit .Count und [0] am ganzen Ausdruck hängen (A.B^, P^).
  Result.Expression := AExpression;
  if (AExpression <> '') and not IsValidIdent(StringReplace(AExpression, '.', '', [rfReplaceAll])) then
    Result.Expression := '(' + AExpression + ')';
end;

{ TAtlasVisualizerOptions }

class function TAtlasVisualizerOptions.Defaults: TAtlasVisualizerOptions;
begin
  Result := Default(TAtlasVisualizerOptions);
  Result.Kinds := TAtlasVisualizerSettings.AllKinds;
  Result.NameFields := TAtlasVisualizerSettings.ParseNameFields(TAtlasVisualizerSettings.DefaultNameFields);
  Result.MaxLength := TAtlasVisualizerSettings.DefaultMaxLength;
  Result.Evaluation := TAtlasVisualizerEvaluation.Properties;
  Result.MaxImagePixels := TAtlasVisualizerSettings.DefaultMaxImagePixels;
end;

{ TAtlasVisualizerFormat }

class function TAtlasVisualizerFormat.Shorten(const AText: string; AMaxLength: Integer): string;
begin
  Result := AText;
  if (AMaxLength > 0) and (Length(Result) > AMaxLength) then
    Result := Copy(Result, 1, Max(AMaxLength - 1, 1)) + '…';
end;

class function TAtlasVisualizerFormat.ParseFields(const AText: string; out AFields: TArray<TAtlasDebugField>): Boolean;
var
  Text, Part: string;
  Index, Depth, Start, Colon: Integer;
  InString: Boolean;
  Field: TAtlasDebugField;

  procedure AddPart(const APart: string);
  var
    Trimmed: string;
    Head: string;
  begin
    Trimmed := Trim(APart);
    if Trimmed = '' then
      Exit;
    Field := Default(TAtlasDebugField);
    // „Name:Wert“ nur, wenn vor dem ersten Doppelpunkt ein Bezeichner steht (nicht in Zeichenketten).
    Colon := Pos(':', Trimmed);
    Head := '';
    if Colon > 1 then
      Head := Trim(Copy(Trimmed, 1, Colon - 1));
    if (Head <> '') and IsValidIdent(Head) then
    begin
      Field.Name := Head;
      Field.Value := Trim(Copy(Trimmed, Colon + 1, MaxInt));
    end
    else
      Field.Value := Trimmed;
    AFields := AFields + [Field];
  end;

begin
  AFields := nil;
  Text := Trim(AText);
  Result := (Length(Text) >= 2) and (Text[1] = '(') and (Text[Length(Text)] = ')');
  if not Result then
    Exit;
  Text := Copy(Text, 2, Length(Text) - 2);
  Depth := 0;
  InString := False;
  Start := 1;
  for Index := 1 to Length(Text) do
  begin
    if InString then
    begin
      if Text[Index] = '''' then
        InString := False;
      Continue;
    end;
    case Text[Index] of
      '''':
        InString := True;
      '(', '[':
        Inc(Depth);
      ')', ']':
        Dec(Depth);
      ';', ',':
        if Depth = 0 then
        begin
          Part := Copy(Text, Start, Index - Start);
          AddPart(Part);
          Start := Index + 1;
        end;
    end;
  end;
  AddPart(Copy(Text, Start, MaxInt));
end;

class function TAtlasVisualizerFormat.FieldValue(const AFields: TArray<TAtlasDebugField>; const AName: string;
  out AValue: string): Boolean;
var
  Field: TAtlasDebugField;
begin
  AValue := '';
  for Field in AFields do
    if SameText(Field.Name, AName) then
    begin
      AValue := Field.Value;
      Exit(True);
    end;
  Result := False;
end;

class function TAtlasVisualizerFormat.ParseInteger(const AText: string; out AValue: Int64): Boolean;
var
  Text: string;
  Open: Integer;
begin
  AValue := 0;
  Text := Trim(AText);
  // Typumwandlung der Anzeige: Pointer($1F), Cardinal(5).
  Open := Pos('(', Text);
  if (Open > 1) and (Text[Length(Text)] = ')') and IsValidIdent(Copy(Text, 1, Open - 1)) then
    Text := Trim(Copy(Text, Open + 1, Length(Text) - Open - 1));
  if (Text <> '') and (Text[1] = ':') then
    Text := '$' + Copy(Text, 2, MaxInt);
  Result := (Text <> '') and TryStrToInt64(Text, AValue);
  if not Result and (Length(Text) > 1) and (Text[1] = '$') then
  begin
    // Über Int64 hinaus (Adressen mit gesetztem höchstem Bit): als UInt64.
    Result := TryStrToUInt64(Text, UInt64(AValue));
  end;
end;

class function TAtlasVisualizerFormat.ParseAddress(const AText: string; out AAddress: UInt64): Boolean;
var
  Value: Int64;
begin
  AAddress := 0;
  Result := ParseInteger(AText, Value) and (Value <> 0);
  if Result then
    AAddress := UInt64(Value);
end;

class function TAtlasVisualizerFormat.ParseByteList(const AText: string; out ABytes: TBytes): Boolean;
var
  Fields: TArray<TAtlasDebugField>;
  Field: TAtlasDebugField;
  Value: Int64;
  Index: Integer;
begin
  ABytes := nil;
  if Trim(AText) = '()' then
    Exit(True);
  Result := ParseFields(AText, Fields);
  if not Result then
    Exit;
  SetLength(ABytes, Length(Fields));
  Index := 0;
  for Field in Fields do
  begin
    // „…“ am Ende einer gekürzten Anzeige: was davor steht, gilt.
    if (Field.Value = '...') or (Field.Value = '…') then
      Break;
    if (Field.Name <> '') or not ParseInteger(Field.Value, Value) or (Value < 0) or (Value > 255) then
    begin
      ABytes := nil;
      Exit(False);
    end;
    ABytes[Index] := Byte(Value);
    Inc(Index);
  end;
  SetLength(ABytes, Index);
end;

class function TAtlasVisualizerFormat.Unquote(const AText: string): string;
var
  Text: string;
begin
  Text := Trim(AText);
  if (Length(Text) >= 2) and (Text[1] = '''') and (Text[Length(Text)] = '''') then
    Result := StringReplace(Copy(Text, 2, Length(Text) - 2), '''''', '''', [rfReplaceAll])
  else
    Result := Text;
end;

class function TAtlasVisualizerFormat.IsStructured(const AText: string): Boolean;
var
  Text: string;
begin
  Text := Trim(AText);
  Result := (Text <> '') and ((Text[1] = '(') or (Text[1] = '$') or (Text[1] = ':') or (Text[1] = '{'));
end;

function Printable(AValue: Byte): Char;
begin
  if (AValue >= 32) and (AValue < 127) then
    Result := Char(AValue)
  else
    Result := '.';
end;

class function TAtlasVisualizerFormat.HexPreview(const ABytes: TBytes; ATotal: Int64; AMaxBytes: Integer): string;
var
  Count, Index: Integer;
  Hex, Text: string;
begin
  Count := Min(Length(ABytes), AMaxBytes);
  Hex := '';
  Text := '';
  for Index := 0 to Count - 1 do
  begin
    if Hex <> '' then
      Hex := Hex + ' ';
    Hex := Hex + IntToHex(ABytes[Index], 2);
    Text := Text + Printable(ABytes[Index]);
  end;
  if ATotal > Count then
  begin
    Hex := Hex + ' …';
    Text := Text + '…';
  end;
  Result := Format('%d Bytes', [ATotal]);
  if Hex <> '' then
    Result := Result + Separator + Hex + Separator + Text;
end;

class function TAtlasVisualizerFormat.HexLineCount(ALength: Integer): Integer;
begin
  Result := (ALength + 15) div 16;
end;

class function TAtlasVisualizerFormat.HexLine(const ABytes: TBytes; AOffset: Integer): string;
var
  Index: Integer;
  Hex, Text: string;
begin
  Hex := '';
  Text := '';
  for Index := AOffset to AOffset + 15 do
  begin
    if Index = AOffset + 8 then
      Hex := Hex + ' ';
    if Index < Length(ABytes) then
    begin
      Hex := Hex + IntToHex(ABytes[Index], 2) + ' ';
      Text := Text + Printable(ABytes[Index]);
    end
    else
      Hex := Hex + '   ';
  end;
  Result := IntToHex(AOffset, 8) + '  ' + Hex + ' ' + Text;
end;

class function TAtlasVisualizerFormat.CompactJson(const AText: string): string;
var
  Builder: TStringBuilder;
  Index: Integer;
  InString, Escaped: Boolean;
  C: Char;
begin
  Builder := TStringBuilder.Create(Length(AText));
  try
    InString := False;
    Escaped := False;
    for Index := 1 to Length(AText) do
    begin
      C := AText[Index];
      if InString then
      begin
        Builder.Append(C);
        if Escaped then
          Escaped := False
        else if C = '\' then
          Escaped := True
        else if C = '"' then
          InString := False;
        Continue;
      end;
      if C = '"' then
        InString := True;
      if CharInSet(C, [' ', #9, #10, #13]) then
        Continue;
      Builder.Append(C);
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

procedure AddJsonNodes(AValue: TJSONValue; const ALabel: string; ALevel: Integer;
  var ANodes: TArray<TAtlasVisualizerNode>);
var
  Node: TAtlasVisualizerNode;
  Pair: TJSONPair;
  Index: Integer;
  Prefix: string;
begin
  Node.Level := ALevel;
  Prefix := '';
  if ALabel <> '' then
    Prefix := ALabel + ': ';
  if AValue is TJSONObject then
  begin
    Node.Text := Prefix + Format('{%d}', [TJSONObject(AValue).Count]);
    ANodes := ANodes + [Node];
    for Index := 0 to TJSONObject(AValue).Count - 1 do
    begin
      Pair := TJSONObject(AValue).Pairs[Index];
      AddJsonNodes(Pair.JsonValue, Pair.JsonString.Value, ALevel + 1, ANodes);
    end;
  end
  else if AValue is TJSONArray then
  begin
    Node.Text := Prefix + Format('[%d]', [TJSONArray(AValue).Count]);
    ANodes := ANodes + [Node];
    for Index := 0 to TJSONArray(AValue).Count - 1 do
      AddJsonNodes(TJSONArray(AValue).Items[Index], Format('[%d]', [Index]), ALevel + 1, ANodes);
  end
  else
  begin
    Node.Text := Prefix + AValue.ToJSON;
    ANodes := ANodes + [Node];
  end;
end;

class function TAtlasVisualizerFormat.JsonTree(const AText: string; out ANodes: TArray<TAtlasVisualizerNode>): Boolean;
var
  Value: TJSONValue;
begin
  ANodes := nil;
  Value := TJSONObject.ParseJSONValue(AText);
  Result := Value <> nil;
  if not Result then
    Exit;
  try
    AddJsonNodes(Value, '', 0, ANodes);
  finally
    Value.Free;
  end;
end;

function SwapRedBlue(AValue: Cardinal): Cardinal;
begin
  Result := ((AValue and $FF) shl 16) or (AValue and $FF00) or ((AValue shr 16) and $FF);
end;

class function TAtlasVisualizerFormat.ColorRgb(AValue: Int64; out ARgb: Cardinal): Boolean;
begin
  ARgb := 0;
  Result := (AValue >= 0) and (AValue <= $FFFFFF);
  if Result then
    ARgb := SwapRedBlue(Cardinal(AValue));
end;

class function TAtlasVisualizerFormat.ColorName(AValue: Int64): string;
var
  Rgb: Cardinal;
  Index: Integer;
  Value: Int64;
begin
  Result := '';
  Value := AValue;
  // TColor ist vorzeichenbehaftet: Systemfarben kommen als -16777201 usw.
  if Value < 0 then
    Value := Value + $100000000;
  if Value = ClNone then
    Exit('clNone');
  if Value = ClDefault then
    Exit('clDefault');
  if (Value >= SystemColorBase) and (Value <= SystemColorBase + High(SystemColors)) then
    Exit(SystemColors[Value - SystemColorBase]);
  if not ColorRgb(Value, Rgb) then
    Exit;
  for Index := Low(StandardColors) to High(StandardColors) do
    if StandardColors[Index].Value = Rgb then
      Exit(StandardColors[Index].Name);
  for Index := Low(WebColors) to High(WebColors) do
    if WebColors[Index].Value = Rgb then
      Exit('clWeb' + WebColors[Index].Name);
end;

class function TAtlasVisualizerFormat.ColorText(AValue: Int64): string;
var
  Name: string;
  Rgb: Cardinal;
  Value: Int64;
begin
  Name := ColorName(AValue);
  Value := AValue;
  if Value < 0 then
    Value := Value + $100000000;
  if not ColorRgb(Value, Rgb) then
  begin
    Result := Name;
    if Result = '' then
      Result := '$' + IntToHex(Value, 8);
    Exit;
  end;
  Result := '$' + IntToHex(Rgb, 6);
  if Name <> '' then
    Result := Name + Separator + Result;
end;

class function TAtlasVisualizerFormat.AlphaColorText(AValue: Int64): string;
var
  Value: Cardinal;
  Index: Integer;
begin
  Value := Cardinal(AValue and $FFFFFFFF);
  Result := '$' + IntToHex(Value, 8);
  if Value = 0 then
    Exit('claNull');
  if (Value shr 24) <> $FF then
    Exit;
  for Index := Low(WebColors) to High(WebColors) do
    if WebColors[Index].Value = (Value and $FFFFFF) then
      Exit('cla' + WebColors[Index].Name + Separator + Result);
end;

class function TAtlasVisualizerFormat.GuidText(const AEvalResult: string): string;
var
  Fields, Bytes: TArray<TAtlasDebugField>;
  Text: string;
  D1, D2, D3, Value: Int64;
  Guid: TGUID;
  Index: Integer;
begin
  Result := '';
  if not ParseFields(AEvalResult, Fields) or not FieldValue(Fields, 'D1', Text) or not ParseInteger(Text, D1) or
    not FieldValue(Fields, 'D2', Text) or not ParseInteger(Text, D2) or not FieldValue(Fields, 'D3', Text) or
    not ParseInteger(Text, D3) or not FieldValue(Fields, 'D4', Text) or not ParseFields(Text, Bytes) or
    (Length(Bytes) <> 8) then
    Exit;
  Guid.D1 := Cardinal(D1);
  Guid.D2 := Word(D2);
  Guid.D3 := Word(D3);
  for Index := 0 to 7 do
  begin
    if not ParseInteger(Bytes[Index].Value, Value) then
      Exit;
    Guid.D4[Index] := Byte(Value);
  end;
  Result := GUIDToString(Guid);
end;

function Number(const AText: string): string;
var
  Value: Double;
  Settings: TFormatSettings;
begin
  // Ganze Zahlen wie angezeigt; Gleitkomma ohne überflüssige Stellen.
  Result := Trim(AText);
  Settings := TFormatSettings.Invariant;
  if (Pos('.', Result) > 0) or (Pos('E', UpperCase(Result)) > 0) then
    if TryStrToFloat(Result, Value, Settings) then
      Result := FloatToStr(Value, Settings);
end;

class function TAtlasVisualizerFormat.GeometryText(const ABaseType, AEvalResult: string): string;
var
  Fields: TArray<TAtlasDebugField>;
  A, B, C, D: string;
begin
  Result := '';
  if not ParseFields(AEvalResult, Fields) then
    Exit;
  if SameText(ABaseType, 'TPoint') or SameText(ABaseType, 'TPointF') or SameText(ABaseType, 'TSmallPoint') then
  begin
    if FieldValue(Fields, 'X', A) and FieldValue(Fields, 'Y', B) then
      Result := Format('(%s, %s)', [Number(A), Number(B)]);
  end
  else if SameText(ABaseType, 'TRect') or SameText(ABaseType, 'TRectF') then
  begin
    if FieldValue(Fields, 'Left', A) and FieldValue(Fields, 'Top', B) and FieldValue(Fields, 'Right', C) and
      FieldValue(Fields, 'Bottom', D) then
      Result := Format('(%s, %s)–(%s, %s)', [Number(A), Number(B), Number(C), Number(D)]);
  end
  else if SameText(ABaseType, 'TSize') or SameText(ABaseType, 'TSizeF') then
  begin
    if (FieldValue(Fields, 'cx', A) and FieldValue(Fields, 'cy', B)) or
      (FieldValue(Fields, 'Width', A) and FieldValue(Fields, 'Height', B)) then
      Result := Format('%s × %s', [Number(A), Number(B)]);
  end;
end;

class function TAtlasVisualizerFormat.DibPixels(const ABits: TBytes; AWidth, AHeight, ABitsPerPixel,
  AWidthBytes: Integer; ABottomUp: Boolean; out APixels: TArray<Cardinal>): Boolean;
var
  X, Y, Row, Offset, Step: Integer;
  Alpha: Cardinal;
begin
  APixels := nil;
  Result := (AWidth > 0) and (AHeight > 0) and ((ABitsPerPixel = 24) or (ABitsPerPixel = 32)) and
    (AWidthBytes >= AWidth * (ABitsPerPixel div 8)) and (Int64(AWidthBytes) * AHeight <= Length(ABits));
  if not Result then
    Exit;
  Step := ABitsPerPixel div 8;
  SetLength(APixels, AWidth * AHeight);
  for Y := 0 to AHeight - 1 do
  begin
    if ABottomUp then
      Row := AHeight - 1 - Y
    else
      Row := Y;
    for X := 0 to AWidth - 1 do
    begin
      // DIB: Blau, Grün, Rot (, Alpha).
      Offset := Row * AWidthBytes + X * Step;
      Alpha := $FF;
      if Step = 4 then
        Alpha := ABits[Offset + 3];
      APixels[Y * AWidth + X] := (Alpha shl 24) or (Cardinal(ABits[Offset + 2]) shl 16) or
        (Cardinal(ABits[Offset + 1]) shl 8) or ABits[Offset];
    end;
  end;
end;

class function TAtlasVisualizerFormat.ListText(const AShown: string; ACount: Integer;
  const AItems: TArray<string>): string;
begin
  Result := Format('%s · Count = %d', [AShown, ACount]);
  if Length(AItems) > 0 then
  begin
    Result := Result + Separator + '[' + string.Join(', ', AItems);
    if ACount > Length(AItems) then
      Result := Result + ', …';
    Result := Result + ']';
  end;
end;

class function TAtlasVisualizerFormat.DictionaryText(const AShown: string; ACount: Integer;
  const APairs: TArray<string>): string;
begin
  Result := Format('%s · Count = %d', [AShown, ACount]);
  if Length(APairs) > 0 then
  begin
    Result := Result + Separator + '{' + string.Join(', ', APairs);
    if ACount > Length(APairs) then
      Result := Result + ', …';
    Result := Result + '}';
  end;
end;

{ TAtlasVisualizers }

class function TAtlasVisualizers.SupportedTypes(AKind: TAtlasVisualizerKind): TArray<TAtlasVisualizerType>;

  procedure Add(const AUnit, AName: string; AAllDescendants, AIsGeneric: Boolean);
  begin
    // Mit und ohne Unit: Welche Form die IDE vergleicht, hängt vom Typ ab.
    Result := Result + [Supported(AUnit + '.' + AName, AAllDescendants, AIsGeneric),
      Supported(AName, AAllDescendants, AIsGeneric)];
  end;

const
  Collections = 'System.Generics.Collections';
begin
  Result := nil;
  case AKind of
    TAtlasVisualizerKind.Lists:
      begin
        Add(Collections, 'TList<T>', True, True);
        Add(Collections, 'TObjectList<T>', True, True);
        Add(Collections, 'TStack<T>', True, True);
        Add(Collections, 'TObjectStack<T>', True, True);
        Add(Collections, 'TQueue<T>', True, True);
        Add(Collections, 'TObjectQueue<T>', True, True);
      end;
    TAtlasVisualizerKind.Dictionaries:
      begin
        Add(Collections, 'TDictionary<K,V>', True, True);
        Add(Collections, 'TObjectDictionary<K,V>', True, True);
      end;
    TAtlasVisualizerKind.DataSets:
      Add('Data.DB', 'TDataSet', True, False);
    TAtlasVisualizerKind.Bytes:
      begin
        Add('System.SysUtils', 'TBytes', False, False);
        Add('System', 'TArray<System.Byte>', False, False);
        Add('System.Classes', 'TStream', True, False);
      end;
    TAtlasVisualizerKind.Json:
      Add('System.JSON', 'TJSONValue', True, False);
    TAtlasVisualizerKind.Colors:
      begin
        Add('System.UITypes', 'TColor', False, False);
        Add('Vcl.Graphics', 'TColor', False, False);
        Add('System.UITypes', 'TAlphaColor', False, False);
      end;
    TAtlasVisualizerKind.Guid:
      Add('System', 'TGUID', False, False);
    TAtlasVisualizerKind.Geometry:
      begin
        Add('System.Types', 'TPoint', False, False);
        Add('System.Types', 'TRect', False, False);
        Add('System.Types', 'TSize', False, False);
        Add('System.Types', 'TPointF', False, False);
        Add('System.Types', 'TRectF', False, False);
        Add('System.Types', 'TSizeF', False, False);
      end;
    TAtlasVisualizerKind.Graphics:
      begin
        Add('Vcl.Graphics', 'TGraphic', True, False);
        Add('Vcl.Graphics', 'TPicture', True, False);
      end;
  end;
end;

/// <summary>Letzter Teil eines qualifizierten Namens (ohne Typargumente).</summary>
function StripUnit(const AName: string): string;
var
  Dot: Integer;
begin
  Result := Trim(AName);
  Dot := LastDelimiter('.', Result);
  if Dot > 0 then
    Result := Copy(Result, Dot + 1, MaxInt);
end;

class function TAtlasVisualizers.ShortTypeName(const ATypeName: string): string;
var
  Index, Start: Integer;
  Part: string;
begin
  // Jeden Bezeichner-Abschnitt zwischen <, >, Komma und Leerraum ohne Unit.
  Result := '';
  Start := 1;
  for Index := 1 to Length(ATypeName) + 1 do
    if (Index > Length(ATypeName)) or CharInSet(ATypeName[Index], ['<', '>', ',', ' ']) then
    begin
      Part := Copy(ATypeName, Start, Index - Start);
      if Part <> '' then
        Result := Result + StripUnit(Part);
      if Index <= Length(ATypeName) then
      begin
        if ATypeName[Index] = ',' then
          Result := Result + ','
        else if ATypeName[Index] <> ' ' then
          Result := Result + ATypeName[Index];
      end;
      Start := Index + 1;
    end;
end;

class function TAtlasVisualizers.BaseTypeName(const ATypeName: string): string;
var
  Angle: Integer;
begin
  Result := Trim(ATypeName);
  Angle := Pos('<', Result);
  if Angle > 0 then
    Result := Copy(Result, 1, Angle - 1);
  Result := StripUnit(Result);
end;

class function TAtlasVisualizers.KindOf(const ATypeName: string; out AKind: TAtlasVisualizerKind): Boolean;
var
  Base, Short: string;
begin
  Base := BaseTypeName(ATypeName);
  Short := ShortTypeName(ATypeName);
  Result := True;
  if MatchText(Base, ['TList', 'TObjectList', 'TStack', 'TObjectStack', 'TQueue', 'TObjectQueue']) and
    (Pos('<', ATypeName) > 0) then
    AKind := TAtlasVisualizerKind.Lists
  else if MatchText(Base, ['TDictionary', 'TObjectDictionary']) then
    AKind := TAtlasVisualizerKind.Dictionaries
  else if MatchText(Base, ['TDataSet', 'TClientDataSet', 'TFDQuery', 'TFDTable', 'TFDMemTable',
    'TFDStoredProc', 'TFDDataSet', 'TFDCustomQuery', 'TFDRdbmsDataSet', 'TFDAdaptedDataSet', 'TCustomClientDataSet',
    'TSQLQuery', 'TSQLTable', 'TSQLDataSet', 'TADOQuery', 'TADOTable', 'TADODataSet', 'TIBQuery', 'TIBTable']) then
    AKind := TAtlasVisualizerKind.DataSets
  else if SameText(Base, 'TBytes') or SameText(Short, 'TArray<Byte>') or MatchText(Base, ['TStream',
    'TMemoryStream', 'TCustomMemoryStream', 'TBytesStream', 'TStringStream', 'TFileStream', 'TBufferedFileStream',
    'THandleStream', 'TResourceStream', 'TPointerStream']) then
    AKind := TAtlasVisualizerKind.Bytes
  else if MatchText(Base, ['TJSONValue', 'TJSONObject', 'TJSONArray', 'TJSONString', 'TJSONNumber', 'TJSONBool',
    'TJSONTrue', 'TJSONFalse', 'TJSONNull', 'TJSONAncestor']) then
    AKind := TAtlasVisualizerKind.Json
  else if MatchText(Base, ['TColor', 'TAlphaColor']) then
    AKind := TAtlasVisualizerKind.Colors
  else if SameText(Base, 'TGUID') then
    AKind := TAtlasVisualizerKind.Guid
  else if MatchText(Base, ['TPoint', 'TRect', 'TSize', 'TPointF', 'TRectF', 'TSizeF', 'TSmallPoint']) then
    AKind := TAtlasVisualizerKind.Geometry
  else if MatchText(Base, ['TGraphic', 'TBitmap', 'TPicture', 'TPngImage', 'TJPEGImage', 'TGIFImage', 'TIcon',
    'TMetafile', 'TWICImage']) then
    AKind := TAtlasVisualizerKind.Graphics
  else
    Result := False;
end;

class function TAtlasVisualizers.KindOfChain(const ATypeNames: array of string;
  out AKind: TAtlasVisualizerKind): Boolean;
var
  Name: string;
begin
  for Name in ATypeNames do
    if (Name <> '') and KindOf(Name, AKind) then
      Exit(True);
  Result := False;
end;

class function TAtlasVisualizers.DeclaredType(const ADeclaration: string): string;
var
  Index, Depth, Start: Integer;
  Found: Boolean;
begin
  Result := '';
  // Erster Doppelpunkt außerhalb von Klammern (Parameter) und spitzen Klammern (Typargumente).
  Depth := 0;
  Found := False;
  Index := 1;
  while Index <= Length(ADeclaration) do
  begin
    case ADeclaration[Index] of
      '(', '[', '<':
        Inc(Depth);
      ')', ']', '>':
        if Depth > 0 then
          Dec(Depth);
      ':':
        if Depth = 0 then
        begin
          Found := True;
          Break;
        end;
    end;
    Inc(Index);
  end;
  if not Found then
    Exit;
  Inc(Index);
  while (Index <= Length(ADeclaration)) and (ADeclaration[Index] = ' ') do
    Inc(Index);
  // Name mit Units und Typargumenten; „array of Byte“ und „set of …“ als Ganzes.
  if StartsText('array of ', Copy(ADeclaration, Index, MaxInt)) then
  begin
    Start := Index;
    Inc(Index, Length('array of '));
    while (Index <= Length(ADeclaration)) and (ADeclaration[Index] = ' ') do
      Inc(Index);
  end
  else
    Start := Index;
  Depth := 0;
  while Index <= Length(ADeclaration) do
  begin
    case ADeclaration[Index] of
      'A'..'Z', 'a'..'z', '0'..'9', '_', '.':
        ;
      '<':
        Inc(Depth);
      '>':
        if Depth = 0 then
          Break
        else
          Dec(Depth);
      ',', ' ':
        if Depth = 0 then
          Break;
    else
      if (Depth = 0) and (Ord(ADeclaration[Index]) < 128) then
        Break;
    end;
    Inc(Index);
  end;
  Result := Trim(Copy(ADeclaration, Start, Index - Start));
end;

{ Ersatztexte und Ansichten je Art }

const
  CountProbes: array[0..3] of TProbe = (
    (Pattern: '%0:s.Count'; Evaluation: TAtlasVisualizerEvaluation.Fields),
    (Pattern: '%0:s.FListHelper.FCount'; Evaluation: TAtlasVisualizerEvaluation.Fields),
    (Pattern: '%0:s.FCount'; Evaluation: TAtlasVisualizerEvaluation.Fields),
    (Pattern: '%0:s.Count'; Evaluation: TAtlasVisualizerEvaluation.Properties));
  ListItemProbes: array[0..2] of TProbe = (
    (Pattern: '%0:s.List[%1:d]'; Evaluation: TAtlasVisualizerEvaluation.Fields),
    (Pattern: '%0:s.FItems[%1:d]'; Evaluation: TAtlasVisualizerEvaluation.Fields),
    (Pattern: '%0:s[%1:d]'; Evaluation: TAtlasVisualizerEvaluation.Properties));

/// <summary>Kurzname eines Elements: einfacher Wert wie angezeigt, bei Objekten das erste Namensfeld, mit Aufrufen
/// ToString.</summary>
function ItemText(var AEvaluator: TEvaluator; const AItemExpression, AValue: string): string;
var
  Name, Text: string;
begin
  Result := Trim(AValue);
  if not TAtlasVisualizerFormat.IsStructured(Result) then
    Exit(TAtlasVisualizerFormat.Shorten(Result, 40));
  for Name in AEvaluator.Options.NameFields do
    if AEvaluator.FirstOf(AItemExpression, [Probe('%0:s.' + Name, TAtlasVisualizerEvaluation.Fields),
      Probe('%0:s.' + Name, TAtlasVisualizerEvaluation.Properties)], 0, Text) and
      not TAtlasVisualizerFormat.IsStructured(Text) then
      Exit(TAtlasVisualizerFormat.Shorten(TAtlasVisualizerFormat.Unquote(Text), 40));
  if AEvaluator.FirstOf(AItemExpression, [Probe('%0:s.ToString', TAtlasVisualizerEvaluation.Calls)], 0, Text) then
    Exit(TAtlasVisualizerFormat.Shorten(TAtlasVisualizerFormat.Unquote(Text), 40));
  Result := TAtlasVisualizerFormat.Shorten(Result, 24);
end;

function ListItems(var AEvaluator: TEvaluator; ACount: Int64; AMax: Integer): TArray<string>;
var
  Index: Integer;
  Value: string;
begin
  Result := nil;
  for Index := 0 to Integer(Min(ACount, Int64(AMax))) - 1 do
  begin
    if not AEvaluator.First(ListItemProbes, Index, Value) then
      Break;
    Result := Result + [ItemText(AEvaluator, AEvaluator.LastExpression, Value)];
  end;
end;

function DictionaryPairs(var AEvaluator: TEvaluator; ACount: Int64; AMax: Integer): TArray<string>;
var
  Slot, Slots: Integer;
  Capacity, Hash: Int64;
  Key, Value, Text: string;
begin
  Result := nil;
  if not AEvaluator.Int([Probe('Length(%0:s.FItems)', TAtlasVisualizerEvaluation.Fields)], Capacity) then
    Exit;
  Slots := Integer(Min(Capacity, Int64(MaxDictionarySlots)));
  if AMax > TAtlasVisualizerOptions.PreviewItems then
    Slots := Integer(Min(Capacity, Int64(MaxInt)));
  Slot := 0;
  while (Slot < Slots) and (Length(Result) < Min(ACount, Int64(AMax))) do
  begin
    if AEvaluator.First([Probe('%0:s.FItems[%1:d].HashCode', TAtlasVisualizerEvaluation.Fields)], Slot, Text) and
      TAtlasVisualizerFormat.ParseInteger(Text, Hash) and (Hash <> EmptyHash) and
      AEvaluator.First([Probe('%0:s.FItems[%1:d].Key', TAtlasVisualizerEvaluation.Fields)], Slot, Key) and
      AEvaluator.First([Probe('%0:s.FItems[%1:d].Value', TAtlasVisualizerEvaluation.Fields)], Slot, Value) then
      Result := Result + [ItemText(AEvaluator, Format('%s.FItems[%d].Key', [AEvaluator.Expression, Slot]), Key) +
        #9 + ItemText(AEvaluator, Format('%s.FItems[%d].Value', [AEvaluator.Expression, Slot]), Value)];
    Inc(Slot);
  end;
end;

function PairText(const APair: string): string;
begin
  Result := StringReplace(APair, #9, ': ', []);
end;

type
  TDataSetInfo = record
    State: string;
    RecNo: Int64;
    RecordCount: Int64;
    HasPosition: Boolean;
    Names: TArray<string>;
    Types: TArray<string>;
    Values: TArray<string>;
    OldValues: TArray<string>;
  end;

function ReadDataSet(var AEvaluator: TEvaluator; AMaxFields: Integer; AWithDetails: Boolean): TDataSetInfo;
var
  FieldCount: Int64;
  Index: Integer;
  Field, Text: string;
begin
  Result := Default(TDataSetInfo);
  AEvaluator.First([Probe('%0:s.State', TAtlasVisualizerEvaluation.Fields),
    Probe('%0:s.FState', TAtlasVisualizerEvaluation.Fields)], 0, Result.State);
  Result.HasPosition := AEvaluator.Int([Probe('%0:s.RecNo', TAtlasVisualizerEvaluation.Properties)],
    Result.RecNo) and AEvaluator.Int([Probe('%0:s.RecordCount', TAtlasVisualizerEvaluation.Properties)],
    Result.RecordCount);
  if SameText(Result.State, 'dsInactive') or not AEvaluator.Int([Probe('%0:s.FieldCount',
    TAtlasVisualizerEvaluation.Properties)], FieldCount) then
    Exit;
  for Index := 0 to Integer(Min(FieldCount, Int64(AMaxFields))) - 1 do
  begin
    Field := Format('%s.Fields[%d]', [AEvaluator.Expression, Index]);
    if not AEvaluator.FirstOf(Field, [Probe('%0:s.FieldName', TAtlasVisualizerEvaluation.Properties)], 0, Text) then
      Break;
    Result.Names := Result.Names + [TAtlasVisualizerFormat.Unquote(Text)];
    if not AEvaluator.FirstOf(Field, [Probe('%0:s.DisplayText', TAtlasVisualizerEvaluation.Properties),
      Probe('%0:s.AsString', TAtlasVisualizerEvaluation.Properties)], 0, Text) then
      Text := '?';
    Result.Values := Result.Values + [TAtlasVisualizerFormat.Unquote(Text)];
    if not AWithDetails then
      Continue;
    if not AEvaluator.FirstOf(Field, [Probe('%0:s.DataType', TAtlasVisualizerEvaluation.Properties)], 0, Text) then
      Text := '';
    Result.Types := Result.Types + [Text];
    // Alter Wert nur beim Bearbeiten; sonst ist er gleich dem Wert.
    Text := '';
    if SameText(Result.State, 'dsEdit') and not AEvaluator.FirstOf(Field, [Probe('%0:s.OldValue',
      TAtlasVisualizerEvaluation.Properties)], 0, Text) then
      Text := '?';
    Result.OldValues := Result.OldValues + [TAtlasVisualizerFormat.Unquote(Text)];
  end;
end;

type
  TByteSource = record
    /// <summary>Die Länge ist bekannt.</summary>
    Known: Boolean;
    Total: Int64;
    Address: UInt64;
    Bytes: TBytes;
    HasBytes: Boolean;
  end;

function IsStreamType(const ABase: string): Boolean;
begin
  Result := MatchText(ABase, ['TStream', 'TMemoryStream', 'TCustomMemoryStream', 'TBytesStream', 'TStringStream',
    'TFileStream', 'TBufferedFileStream', 'THandleStream', 'TResourceStream', 'TPointerStream']);
end;

function ReadBytes(var AEvaluator: TEvaluator; const ABase, AEvalResult: string; AMax: Integer): TByteSource;
var
  Text: string;
  Size: Int64;
begin
  Result := Default(TByteSource);
  if IsStreamType(ABase) then
  begin
    if not AEvaluator.Int([Probe('%0:s.FSize', TAtlasVisualizerEvaluation.Fields),
      Probe('%0:s.Size', TAtlasVisualizerEvaluation.Properties)], Size) then
      Exit;
    Result.Known := True;
    Result.Total := Size;
    // Nur Speicherstreams haben einen Puffer im Programm.
    if AEvaluator.First([Probe('%0:s.FMemory', TAtlasVisualizerEvaluation.Fields)], 0, Text) then
      TAtlasVisualizerFormat.ParseAddress(Text, Result.Address);
  end
  else
  begin
    if TAtlasVisualizerFormat.ParseByteList(AEvalResult, Result.Bytes) then
    begin
      Result.HasBytes := True;
      Result.Known := True;
      Result.Total := Length(Result.Bytes);
    end;
    if AEvaluator.Int([Probe('Length(%0:s)', TAtlasVisualizerEvaluation.Fields)], Size) then
    begin
      Result.Known := True;
      Result.Total := Size;
    end;
    if AEvaluator.First([Probe('Pointer(%0:s)', TAtlasVisualizerEvaluation.Fields)], 0, Text) then
      TAtlasVisualizerFormat.ParseAddress(Text, Result.Address);
  end;
  // Ganz bzw. bis AMax aus dem Speicher, wenn die Anzeige der IDE kürzer ist.
  if (Result.Address <> 0) and (Length(Result.Bytes) < Min(Result.Total, Int64(AMax))) and
    AEvaluator.Read(Result.Address, Integer(Min(Result.Total, Int64(AMax))), Result.Bytes) then
    Result.HasBytes := True;
end;

type
  TImageInfo = record
    Width: Int64;
    Height: Int64;
    PixelFormat: string;
    Dib: string;
  end;

function ReadImage(var AEvaluator: TEvaluator; const ABase: string): TImageInfo;
begin
  Result := Default(TImageInfo);
  // Bei TPicture die Grafik darin.
  if SameText(ABase, 'TPicture') then
    AEvaluator.Expression := AEvaluator.Expression + '.FGraphic';
  Result.Dib := AEvaluator.Expression + '.FImage.FDIB.dsBm';
  if not (AEvaluator.Int([Probe(Result.Dib + '.bmWidth', TAtlasVisualizerEvaluation.Fields),
    Probe('%0:s.Width', TAtlasVisualizerEvaluation.Properties)], Result.Width) and
    AEvaluator.Int([Probe(Result.Dib + '.bmHeight', TAtlasVisualizerEvaluation.Fields),
    Probe('%0:s.Height', TAtlasVisualizerEvaluation.Properties)], Result.Height)) then
  begin
    Result.Width := 0;
    Result.Height := 0;
  end;
  Result.Height := Abs(Result.Height);
  AEvaluator.First([Probe('%0:s.FPixelFormat', TAtlasVisualizerEvaluation.Fields),
    Probe('%0:s.PixelFormat', TAtlasVisualizerEvaluation.Properties)], 0, Result.PixelFormat);
end;

function ImagePixels(var AEvaluator: TEvaluator; const AInfo: TImageInfo; out AWidth, AHeight: Integer;
  out APixels: TArray<Cardinal>): Boolean;
var
  Text: string;
  Width, Height, Bits, WidthBytes: Int64;
  Address: UInt64;
  Data: TBytes;
begin
  AWidth := 0;
  AHeight := 0;
  APixels := nil;
  Result := AEvaluator.Int([Probe(AInfo.Dib + '.bmWidth', TAtlasVisualizerEvaluation.Fields)], Width) and
    AEvaluator.Int([Probe(AInfo.Dib + '.bmHeight', TAtlasVisualizerEvaluation.Fields)], Height) and
    AEvaluator.Int([Probe(AInfo.Dib + '.bmBitsPixel', TAtlasVisualizerEvaluation.Fields)], Bits) and
    AEvaluator.Int([Probe(AInfo.Dib + '.bmWidthBytes', TAtlasVisualizerEvaluation.Fields)], WidthBytes) and
    AEvaluator.First([Probe(AInfo.Dib + '.bmBits', TAtlasVisualizerEvaluation.Fields)], 0, Text) and
    TAtlasVisualizerFormat.ParseAddress(Text, Address) and (Width > 0) and (Height <> 0) and
    (Width * Abs(Height) <= AEvaluator.Options.MaxImagePixels) and
    AEvaluator.Read(Address, Integer(WidthBytes * Abs(Height)), Data) and
    TAtlasVisualizerFormat.DibPixels(Data, Integer(Width), Integer(Abs(Height)), Integer(Bits), Integer(WidthBytes),
    Height > 0, APixels);
  if Result then
  begin
    AWidth := Integer(Width);
    AHeight := Integer(Abs(Height));
  end;
end;

type
  TJsonInfo = record
    Text: string;
    HasText: Boolean;
    Count: Int64;
    HasCount: Boolean;
    Keys: TArray<string>;
  end;

function ReadJson(var AEvaluator: TEvaluator; AMaxKeys: Integer): TJsonInfo;
var
  Index: Integer;
  Text: string;
begin
  Result := Default(TJsonInfo);
  Result.HasText := AEvaluator.First([Probe('%0:s.ToJSON', TAtlasVisualizerEvaluation.Calls)], 0, Text);
  if Result.HasText then
  begin
    Result.Text := TAtlasVisualizerFormat.CompactJson(TAtlasVisualizerFormat.Unquote(Text));
    Exit;
  end;
  Result.HasCount := AEvaluator.Int([Probe('%0:s.FMembers.FListHelper.FCount',
    TAtlasVisualizerEvaluation.Fields), Probe('%0:s.FElements.FListHelper.FCount',
    TAtlasVisualizerEvaluation.Fields), Probe('%0:s.Count', TAtlasVisualizerEvaluation.Properties)], Result.Count);
  if not Result.HasCount then
    Exit;
  for Index := 0 to Integer(Min(Result.Count, Int64(AMaxKeys))) - 1 do
  begin
    if not AEvaluator.First([Probe('%0:s.FMembers.FItems[%1:d].FJsonString.FValue',
      TAtlasVisualizerEvaluation.Fields), Probe('%0:s.Pairs[%1:d].JsonString.Value',
      TAtlasVisualizerEvaluation.Calls)], Index, Text) or TAtlasVisualizerFormat.IsStructured(Text) then
      Break;
    Result.Keys := Result.Keys + [TAtlasVisualizerFormat.Unquote(Text)];
  end;
end;

/// <summary>Text einer Farbe; AHasRgb, wenn sie einen festen RGB-Wert hat (nicht bei Systemfarben und clNone).
/// </summary>
function ColorOf(const ABase, AEvalResult: string; out AText: string; out ARgb: Cardinal;
  out AHasRgb: Boolean): Boolean;
var
  Value: Int64;
begin
  AText := '';
  ARgb := 0;
  AHasRgb := False;
  Result := TAtlasVisualizerFormat.ParseInteger(AEvalResult, Value);
  if not Result then
    Exit;
  if SameText(ABase, 'TAlphaColor') then
  begin
    AText := TAtlasVisualizerFormat.AlphaColorText(Value);
    ARgb := Cardinal(Value and $FFFFFF);
    AHasRgb := True;
  end
  else
  begin
    AText := TAtlasVisualizerFormat.ColorText(Value);
    if Value < 0 then
      Value := Value + $100000000;
    AHasRgb := TAtlasVisualizerFormat.ColorRgb(Value, ARgb);
  end;
end;

class function TAtlasVisualizers.Replacement(AKind: TAtlasVisualizerKind; const AExpression, ATypeName,
  AEvalResult: string; const AOptions: TAtlasVisualizerOptions; const AContext: TAtlasVisualizerContext): string;
var
  Evaluator: TEvaluator;
  Count, Index: Int64;
  Base, Shown, Text: string;
  Items: TArray<string>;
  DataSet: TDataSetInfo;
  Source: TByteSource;
  Json: TJsonInfo;
  Image: TImageInfo;
  Rgb: Cardinal;
  HasRgb: Boolean;
begin
  Result := '';
  if not (AKind in AOptions.Kinds) then
    Exit;
  Evaluator := NewEvaluator(AExpression, AOptions, AContext);
  Base := BaseTypeName(ATypeName);
  Shown := ShortTypeName(ATypeName);
  case AKind of
    TAtlasVisualizerKind.Lists:
      if Evaluator.Int(CountProbes, Count) then
        Result := TAtlasVisualizerFormat.ListText(Shown, Integer(Count),
          ListItems(Evaluator, Count, TAtlasVisualizerOptions.PreviewItems));
    TAtlasVisualizerKind.Dictionaries:
      if Evaluator.Int(CountProbes, Count) then
      begin
        Items := DictionaryPairs(Evaluator, Count, TAtlasVisualizerOptions.PreviewItems);
        for Index := 0 to High(Items) do
          Items[Index] := PairText(Items[Index]);
        Result := TAtlasVisualizerFormat.DictionaryText(Shown, Integer(Count), Items);
      end;
    TAtlasVisualizerKind.DataSets:
      begin
        DataSet := ReadDataSet(Evaluator, TAtlasVisualizerOptions.PreviewItems, False);
        if DataSet.State = '' then
          Exit;
        Result := Shown + Separator + DataSet.State;
        if DataSet.HasPosition then
          Result := Result + Separator + Format('%d/%d', [DataSet.RecNo, DataSet.RecordCount]);
        Items := nil;
        for Index := 0 to High(DataSet.Names) do
          Items := Items + [DataSet.Names[Index] + ' = ' + TAtlasVisualizerFormat.Shorten(DataSet.Values[Index], 30)];
        if Length(Items) > 0 then
          Result := Result + Separator + string.Join(', ', Items);
      end;
    TAtlasVisualizerKind.Bytes:
      begin
        Source := ReadBytes(Evaluator, Base, AEvalResult, TAtlasVisualizerOptions.PreviewBytes);
        if Source.Known then
        begin
          Result := TAtlasVisualizerFormat.HexPreview(Source.Bytes, Source.Total, TAtlasVisualizerOptions.PreviewBytes);
          if IsStreamType(Base) then
            Result := Shown + Separator + Result;
        end;
      end;
    TAtlasVisualizerKind.Json:
      begin
        Json := ReadJson(Evaluator, TAtlasVisualizerOptions.PreviewItems);
        if Json.HasText then
          Result := Json.Text
        else if Json.HasCount then
        begin
          Result := Format('%s · Count = %d', [Shown, Json.Count]);
          if Length(Json.Keys) > 0 then
          begin
            Result := Result + Separator + '{' + string.Join(', ', Json.Keys);
            if Json.Count > Length(Json.Keys) then
              Result := Result + ', …';
            Result := Result + '}';
          end;
        end;
      end;
    TAtlasVisualizerKind.Colors:
      if ColorOf(Base, AEvalResult, Text, Rgb, HasRgb) then
        Result := Text;
    TAtlasVisualizerKind.Guid:
      Result := TAtlasVisualizerFormat.GuidText(AEvalResult);
    TAtlasVisualizerKind.Geometry:
      Result := TAtlasVisualizerFormat.GeometryText(Base, AEvalResult);
    TAtlasVisualizerKind.Graphics:
      begin
        Image := ReadImage(Evaluator, Base);
        if (Image.Width > 0) and (Image.Height > 0) then
        begin
          Result := Format('%s · %d × %d', [Shown, Image.Width, Image.Height]);
          if Image.PixelFormat <> '' then
            Result := Result + Separator + Image.PixelFormat;
        end
        else if Image.PixelFormat <> '' then
          Result := Shown + Separator + Image.PixelFormat;
      end;
  end;
  Result := TAtlasVisualizerFormat.Shorten(Result, AOptions.MaxLength);
end;

function Row(const AValues: array of string): TArray<string>;
var
  Index: Integer;
begin
  SetLength(Result, Length(AValues));
  for Index := 0 to High(AValues) do
    Result[Index] := AValues[Index];
end;

class function TAtlasVisualizers.View(AKind: TAtlasVisualizerKind; const AExpression, ATypeName,
  AEvalResult: string; const AOptions: TAtlasVisualizerOptions;
  const AContext: TAtlasVisualizerContext): TAtlasVisualizerView;
var
  Evaluator: TEvaluator;
  Count: Int64;
  Index: Integer;
  Base, Value, Key: string;
  Items: TArray<string>;
  DataSet: TDataSetInfo;
  Source: TByteSource;
  Json: TJsonInfo;
  Image: TImageInfo;
  Tab: Integer;
  HasRgb: Boolean;
begin
  Result := Default(TAtlasVisualizerView);
  Result.Kind := AKind;
  Result.Summary := Replacement(AKind, AExpression, ATypeName, AEvalResult, AOptions, AContext);
  if Result.Summary = '' then
    Result.Summary := TAtlasVisualizerFormat.Shorten(AEvalResult, AOptions.MaxLength);
  Evaluator := NewEvaluator(AExpression, AOptions, AContext);
  Base := BaseTypeName(ATypeName);
  case AKind of
    TAtlasVisualizerKind.Lists:
      if Evaluator.Int(CountProbes, Count) then
      begin
        Result.Mode := TAtlasVisualizerViewMode.Table;
        Result.Columns := [TAtlasVisualizerColumn.Index, TAtlasVisualizerColumn.Value];
        Items := ListItems(Evaluator, Count, TAtlasVisualizerOptions.ViewItems);
        for Index := 0 to High(Items) do
          Result.Rows := Result.Rows + [Row([IntToStr(Index), Items[Index]])];
        Result.Total := Count;
      end;
    TAtlasVisualizerKind.Dictionaries:
      if Evaluator.Int(CountProbes, Count) then
      begin
        Result.Mode := TAtlasVisualizerViewMode.Table;
        Result.Columns := [TAtlasVisualizerColumn.Key, TAtlasVisualizerColumn.Value];
        for Value in DictionaryPairs(Evaluator, Count, TAtlasVisualizerOptions.ViewItems) do
        begin
          Tab := Pos(#9, Value);
          Key := Copy(Value, 1, Tab - 1);
          Result.Rows := Result.Rows + [Row([Key, Copy(Value, Tab + 1, MaxInt)])];
        end;
        Result.Total := Count;
      end;
    TAtlasVisualizerKind.DataSets:
      begin
        DataSet := ReadDataSet(Evaluator, TAtlasVisualizerOptions.ViewItems, True);
        Result.Mode := TAtlasVisualizerViewMode.Table;
        Result.Columns := [TAtlasVisualizerColumn.Field, TAtlasVisualizerColumn.FieldType,
          TAtlasVisualizerColumn.Value, TAtlasVisualizerColumn.OldValue];
        for Index := 0 to High(DataSet.Names) do
          Result.Rows := Result.Rows + [Row([DataSet.Names[Index], DataSet.Types[Index], DataSet.Values[Index],
            DataSet.OldValues[Index]])];
      end;
    TAtlasVisualizerKind.Bytes:
      begin
        Source := ReadBytes(Evaluator, Base, AEvalResult, TAtlasVisualizerOptions.ViewBytes);
        Result.Mode := TAtlasVisualizerViewMode.Hex;
        Result.Bytes := Source.Bytes;
        Result.Total := Source.Total;
      end;
    TAtlasVisualizerKind.Json:
      begin
        Json := ReadJson(Evaluator, TAtlasVisualizerOptions.ViewItems);
        if Json.HasText and TAtlasVisualizerFormat.JsonTree(Json.Text, Result.Nodes) then
          Result.Mode := TAtlasVisualizerViewMode.Tree
        else
        begin
          Result.Mode := TAtlasVisualizerViewMode.Table;
          Result.Columns := [TAtlasVisualizerColumn.Index, TAtlasVisualizerColumn.Key];
          for Index := 0 to High(Json.Keys) do
            Result.Rows := Result.Rows + [Row([IntToStr(Index), Json.Keys[Index]])];
          Result.Total := Json.Count;
        end;
      end;
    TAtlasVisualizerKind.Colors:
      begin
        Result.Mode := TAtlasVisualizerViewMode.Text;
        if ColorOf(Base, AEvalResult, Result.Text, Result.Color, HasRgb) and HasRgb then
          Result.Mode := TAtlasVisualizerViewMode.Color;
      end;
    TAtlasVisualizerKind.Guid, TAtlasVisualizerKind.Geometry:
      begin
        Result.Mode := TAtlasVisualizerViewMode.Text;
        Result.Text := Result.Summary;
      end;
    TAtlasVisualizerKind.Graphics:
      begin
        Image := ReadImage(Evaluator, Base);
        Result.Mode := TAtlasVisualizerViewMode.Text;
        Result.Text := Result.Summary;
        if ImagePixels(Evaluator, Image, Result.Width, Result.Height, Result.Pixels) then
          Result.Mode := TAtlasVisualizerViewMode.Image;
      end;
  end;
  Result.NeedsMore := Evaluator.Skipped;
end;

end.
